// A peephole optimizer for the assembly of one function (Gen.csh writes simple, regular code): copies through
// a0/a1 become direct moves, stores that are loaded again right away keep the register, arguments are pushed
// directly, branches over branches are inverted. It only changes a pattern when the scratch registers it removes
// (d0/d1/a0/a1) are not read afterwards.

namespace CShift.M68k;

using System;

string Peephole(string text)
{
    var lines = List<string>.Create();
    foreach (var l in text.Split('\n'))
    {
        if (l.Length > 0)
            lines.Add(l.ToString());
    }
    for (var pass = 0; pass < 4; pass += 1)
    {
        if (!PeepholePass(lines))
            break;
    }
    var sb = StringBuilder.Create();
    foreach (var l in lines.ToArray())
    {
        sb.Append(l);
        sb.Append('\n');
    }
    return sb.ToString();
}

bool IsInstrLine(string line)
{
    return line.StartsWith("\t") && !line.StartsWith("\t.");
}

string Mnemonic(string line)
{
    if (!IsInstrLine(line))
        return "";
    int tab = line.IndexOf('\t', 1);
    return tab < 0 ? line.Substring(1).ToString() : line.Substring(1, tab - 1).ToString();
}

string[] Operands(string line)
{
    int tab = line.IndexOf('\t', 1);
    if (tab < 0)
        return new string[0];
    return SplitOperands(line.Substring(tab + 1).ToString());
}

string Instr(string mnemonic, string operands)
{
    return "\t" + mnemonic + "\t" + operands;
}

bool Mentions(string operand, string reg)
{
    return operand.Contains(reg);
}

string Negate(string cond)
{
    switch (cond)
    {
    case "eq": return "ne";
    case "ne": return "eq";
    case "lt": return "ge";
    case "ge": return "lt";
    case "le": return "gt";
    case "gt": return "le";
    case "cs": return "cc";
    case "cc": return "cs";
    case "ls": return "hi";
    case "hi": return "ls";
    case "mi": return "pl";
    case "pl": return "mi";
    case "vs": return "vc";
    case "vc": return "vs";
    default: return "";
    }
}

// Is the register (d0, d1, a0 or a1: "%d0") not read before it is written again, after line 'from'?
bool DeadAfter(List<string> lines, int from, string reg)
{
    for (var i = from; i < lines.Count(); i += 1)
    {
        string line = lines.Get(i);
        if (!line.StartsWith("\t"))
            return false; // a label: other code may come here
        if (line.StartsWith("\t."))
            continue;
        string mn = Mnemonic(line);
        var ops = Operands(line);
        if (mn == "jsr")
        {
            if (ops.Length > 0 && (Mentions(ops[0], reg) || ops[0].StartsWith("__cs68k_")))
                return false; // the register helpers take d0/d1
            return true;      // the called function does not keep the scratch registers
        }
        if (mn == "rts" || mn == "jmp" || mn == "bra" || mn.StartsWith("db") || (mn.StartsWith("b") && mn.Length <= 3))
            return false;
        if (ops.Length == 0)
            continue;
        for (var k = 0; k < ops.Length - 1; k += 1)
        {
            if (Mentions(ops[k], reg))
                return false;
        }
        string last = ops[ops.Length - 1];
        if (last == reg)
        {
            // (move.w/move.b write only part of a data register; to an address register, move.w writes all of it)
            bool fullWrite = mn == "move.l" || mn == "moveq" || mn == "lea" || (reg.StartsWith("%a") && mn == "move.w");
            if (ops.Length == 2 && fullWrite)
                return true;
            return false;
        }
        if (Mentions(last, reg))
            return false;
    }
    return false;
}

// "(d,%a6)" -> the same place plus 'plus' bytes; "" if the operand is not of that form
string OffsetOperand(string operand, int plus)
{
    if (!operand.StartsWith("(") || !operand.EndsWith(",%a6)"))
        return "";
    string d = operand.Substring(1, operand.Length - 6).ToString();
    var n = TryAsmNumber(d);
    if (n is int64 v)
        return "(" + (v + (int64)plus).ToString() + ",%a6)";
    return "";
}

// "(%aX)" -> 0, "(n,%aX)" -> n; -99999 for any other use of the register
int RegisterOffset(string operand, string reg)
{
    if (operand == "(" + reg + ")")
        return 0;
    string tail = "," + reg + ")";
    if (operand.StartsWith("(") && operand.EndsWith(tail))
    {
        var n = TryAsmNumber(operand.Substring(1, operand.Length - 1 - tail.Length).ToString());
        if (n is int64 v && v >= -32768 && v <= 32767)
            return (int)v;
    }
    return -99999;
}

bool PeepholePass(List<string> lines)
{
    bool changed = false;
    int i = 0;
    while (i < lines.Count())
    {
        string line = lines.Get(i);
        string mn = Mnemonic(line);
        if (mn.Length == 0)
        {
            i += 1;
            continue;
        }
        var ops = Operands(line);

        // lea (d,%a6),%aX / lea (c,%aX),%aX -> lea (d+c,%a6),%aX
        if (mn == "lea" && ops.Length == 2 && ops[1].StartsWith("%a") && OffsetOperand(ops[0], 0).Length > 0 && i + 1 < lines.Count())
        {
            string next = lines.Get(i + 1);
            var ops2 = Operands(next);
            if (Mnemonic(next) == "lea" && ops2.Length == 2 && ops2[1] == ops[1])
            {
                int at = RegisterOffset(ops2[0], ops[1]);
                if (at != -99999)
                {
                    lines.Set(i, Instr("lea", OffsetOperand(ops[0], at) + "," + ops[1]));
                    lines.RemoveAt(i + 1);
                    changed = true;
                    continue;
                }
            }
        }

        // lea (d,%a6),%a0 / op ...(n,%a0)... -> op ...(d+n,%a6)... (a0 not needed afterwards; same for a1)
        // move.l %aN,%a0 / op ...(n,%a0)... -> op ...(n,%aN)...
        if ((mn == "lea" || mn == "move.l") && ops.Length == 2 && (ops[1] == "%a0" || ops[1] == "%a1") && i + 1 < lines.Count())
        {
            string scratch = ops[1];
            bool fromFrame = mn == "lea" && OffsetOperand(ops[0], 0).Length > 0;
            bool fromReg = mn == "move.l" && ops[0].StartsWith("%a") && ops[0] != "%a0" && ops[0] != "%a1" && ops[0] != "%sp";
            string next = lines.Get(i + 1);
            string mn2 = Mnemonic(next);
            var ops2 = Operands(next);
            if ((fromFrame || fromReg) && mn2.Length > 0 && !mn2.StartsWith("lea") && mn2 != "jsr" && mn2 != "jmp" && ops2.Length >= 1 &&
                DeadAfter(lines, i + 2, scratch))
            {
                var rewritten = new string[ops2.Length];
                bool ok = true;
                int uses = 0;
                for (var k = 0; k < ops2.Length && ok; k += 1)
                {
                    string o = ops2[k];
                    if (!Mentions(o, scratch))
                    {
                        rewritten[k] = o;
                        continue;
                    }
                    int at = RegisterOffset(o, scratch);
                    if (at == -99999)
                    {
                        ok = false;
                        break;
                    }
                    uses += 1;
                    rewritten[k] = fromFrame ? OffsetOperand(ops[0], at) : "(" + at.ToString() + "," + ops[0] + ")";
                }
                if (ok && uses > 0)
                {
                    lines.RemoveAt(i);
                    lines.Set(i, Instr(mn2, string.Join(",", rewritten)));
                    changed = true;
                    continue;
                }
            }
        }

        // lea (0,%aN),%aN
        if (mn == "lea" && ops.Length == 2 && ops[0] == "(0," + ops[1] + ")")
        {
            lines.RemoveAt(i);
            changed = true;
            continue;
        }

        // lea (s,%a6),%a0 / lea (d,%a6),%a1 (either order) / move.l (%a0)+,(%a1)+ ... -> move.l (s,%a6),(d,%a6) ...
        if (mn == "lea" && ops.Length == 2 && (ops[1] == "%a0" || ops[1] == "%a1") && i + 2 < lines.Count())
        {
            string second = lines.Get(i + 1);
            var ops2 = Operands(second);
            if (Mnemonic(second) == "lea" && ops2.Length == 2 && (ops2[1] == "%a0" || ops2[1] == "%a1") && ops2[1] != ops[1])
            {
                string src = ops[1] == "%a0" ? ops[0] : ops2[0];
                string dst = ops[1] == "%a1" ? ops[0] : ops2[0];
                int count = 0;
                while (i + 2 + count < lines.Count() && lines.Get(i + 2 + count) == "\tmove.l\t(%a0)+,(%a1)+" && count < 4)
                    count += 1;
                int end = i + 2 + count;
                if (count > 0 && OffsetOperand(src, 0).Length > 0 && OffsetOperand(dst, 0).Length > 0 &&
                    DeadAfter(lines, end, "%a0") && DeadAfter(lines, end, "%a1"))
                {
                    for (var k = 0; k < count + 2; k += 1)
                        lines.RemoveAt(i);
                    for (var k = count - 1; k >= 0; k -= 1)
                        lines.Insert(i, Instr("move.l", OffsetOperand(src, 4 * k) + "," + OffsetOperand(dst, 4 * k)));
                    changed = true;
                    continue;
                }
            }
        }

        // suba.l #n,%sp / move.l %sp,%a1 / lea (s,%a6),%a0 / move.l (%a0)+,(%a1)+ x n/4 -> push the longs
        if (mn == "suba.l" && ops.Length == 2 && ops[1] == "%sp" && ops[0].StartsWith("#") && i + 3 < lines.Count() &&
            lines.Get(i + 1) == "\tmove.l\t%sp,%a1")
        {
            var n = TryAsmNumber(ops[0].Substring(1).ToString());
            string third = lines.Get(i + 2);
            var ops3 = Operands(third);
            if (n is int64 bytes && bytes % 4 == 0 && bytes > 0 && bytes <= 16 && Mnemonic(third) == "lea" && ops3.Length == 2 &&
                ops3[1] == "%a0" && OffsetOperand(ops3[0], 0).Length > 0)
            {
                int count = (int)(bytes / 4);
                bool all = i + 3 + count <= lines.Count();
                for (var k = 0; all && k < count; k += 1)
                    all = lines.Get(i + 3 + k) == "\tmove.l\t(%a0)+,(%a1)+";
                int end = i + 3 + count;
                if (all && DeadAfter(lines, end, "%a0") && DeadAfter(lines, end, "%a1"))
                {
                    for (var k = 0; k < count + 3; k += 1)
                        lines.RemoveAt(i);
                    for (var k = 0; k < count; k += 1)
                        lines.Insert(i, Instr("move.l", OffsetOperand(ops3[0], 4 * k) + ",-(%sp)"));
                    changed = true;
                    continue;
                }
            }
        }

        if (i + 1 < lines.Count())
        {
            string next = lines.Get(i + 1);
            string mn2 = Mnemonic(next);
            var ops2 = Operands(next);

            // move.l %dX,M / move.l M,%dX -> the second is not needed
            if (mn == "move.l" && mn2 == "move.l" && ops.Length == 2 && ops2.Length == 2 && ops[0].StartsWith("%d") &&
                ops2[1] == ops[0] && ops2[0] == ops[1] && !Mentions(ops[1], ops[0]) && ops[1].StartsWith("("))
            {
                lines.RemoveAt(i + 1);
                changed = true;
                continue;
            }

            // move.l M,%d0 / move.l %d0,D -> move.l M,D (d0 not needed afterwards)
            if (mn == "move.l" && mn2 == "move.l" && ops.Length == 2 && ops2.Length == 2 && (ops[1] == "%d0" || ops[1] == "%d1") &&
                ops2[0] == ops[1] && !Mentions(ops2[1], ops[1]) && !ops2[1].StartsWith("%a") && DeadAfter(lines, i + 2, ops[1]))
            {
                lines.RemoveAt(i);
                lines.Set(i, Instr("move.l", ops[0] + "," + ops2[1]));
                changed = true;
                continue;
            }

            // move.l M,%d0 / move.l %d0,%aN -> move.l M,%aN (movea)
            if (mn == "move.l" && mn2 == "move.l" && ops.Length == 2 && ops2.Length == 2 && ops[1] == "%d0" && ops2[0] == "%d0" &&
                ops2[1].StartsWith("%a") && !ops[0].StartsWith("#") && DeadAfter(lines, i + 2, "%d0"))
            {
                lines.RemoveAt(i);
                lines.Set(i, Instr("move.l", ops[0] + "," + ops2[1]));
                changed = true;
                continue;
            }

            // moveq #0,%dX / cmp.l %dX,%dY -> tst.l %dY
            if (mn == "moveq" && ops.Length == 2 && ops[0] == "#0" && mn2.StartsWith("cmp.") && ops2.Length == 2 && ops2[0] == ops[1] &&
                ops2[1].StartsWith("%d") && DeadAfter(lines, i + 2, ops[1]))
            {
                lines.RemoveAt(i);
                lines.Set(i, Instr("tst" + mn2.Substring(3).ToString(), ops2[1]));
                changed = true;
                continue;
            }

            // bra L / L:
            if (mn == "bra" && ops.Length == 1 && next == ops[0] + ":")
            {
                lines.RemoveAt(i);
                changed = true;
                continue;
            }

            // bCC L1 / bra L2 / L1: -> b!CC L2 / L1:
            if (mn.Length == 3 && mn.StartsWith("b") && mn != "bra" && mn != "bsr" && mn2 == "bra" && ops.Length == 1 && ops2.Length == 1 &&
                i + 2 < lines.Count() && lines.Get(i + 2) == ops[0] + ":")
            {
                string negated = Negate(mn.Substring(1).ToString());
                if (negated.Length > 0)
                {
                    lines.Set(i, Instr("b" + negated, ops2[0]));
                    lines.RemoveAt(i + 1);
                    changed = true;
                    continue;
                }
            }
        }

        // lea (n,%sp),%sp -> addq.l #n,%sp
        if (mn == "lea" && ops.Length == 2 && ops[1] == "%sp" && ops[0].StartsWith("(") && ops[0].EndsWith(",%sp)"))
        {
            var n = TryAsmNumber(ops[0].Substring(1, ops[0].Length - 6).ToString());
            if (n is int64 v && v >= 1 && v <= 8)
            {
                lines.Set(i, Instr("addq.l", "#" + v.ToString() + ",%sp"));
                changed = true;
            }
        }
        i += 1;
    }
    return changed;
}
