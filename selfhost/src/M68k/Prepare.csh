// Before a function is written: simple improvements of its IR.
//
//   * Constant folding: comparisons of two constants, and/or/xor of constants (the division checks of CShift compare
//     the divisor with -1 even when it is a constant) - the uses get the constant, the instruction is skipped.
//   * Address folding: a getelementptr whose only use is the load or store right after it (in its block) is not
//     computed on its own: the access uses the 68000's addressing modes, (d16,An) or (d8,An,Dn.l).

namespace CShift.M68k;

using System;

struct AddrFold
{
    int Base;       // the pointer value
    int Index;      // the variable index (-1: none)
    int IndexBits;  // its width (sign-extended to 32 bits)
    int Stride;     // bytes per index step
    int64 Offset;   // the constant part
}

void PrepareFunction(Gen g, IrFunc f)
{
    g.Folds.Clear();
    g.Skip.Clear();
    FoldConstants(g, f);
    RemoveDeadCode(g, f);
    FoldAddresses(g, f);
}

bool ConstInt(Gen g, int vi, ref int64 value)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Int || v.Kind == ValKind.Null || v.Kind == ValKind.Zero)
    {
        value = v.Kind == ValKind.Int ? v.Int : 0;
        return true;
    }
    return false;
}

// value truncated to 'bits' and extended (signed or not) to 64 bits
int64 Normalize(int64 value, int bits, bool signed)
{
    if (bits >= 64)
        return value;
    unchecked
    {
        int64 mask = ((int64)1 << bits) - 1;
        int64 v = value & mask;
        if (signed && (v >> (bits - 1)) != 0)
            v = v - ((int64)1 << bits);
        return v;
    }
}

void FoldConstants(Gen g, IrFunc f)
{
    var known = Dictionary<string, int>.Create(); // result -> the value index of its constant
    int i1 = g.T.IntType(1);
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            // uses of folded values get the constant
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind == ValKind.Local)
                {
                    var c = known.TryGet(v.Name);
                    if (c is int ci)
                        inst.Args[a] = ci;
                }
            }
            if (inst.Res.Length == 0 || inst.Args.Length != 2)
                continue;
            int64 x = 0;
            int64 y = 0;
            bool cx = ConstInt(g, inst.Args[0], ref x);
            bool cy = ConstInt(g, inst.Args[1], ref y);
            if ((inst.Op == "and" || inst.Op == "or") && (cx != cy) && g.T.Kind(inst.OpType) == IrKind.Int)
            {
                // x and 0 = 0; for i1: x or 1 = 1
                int64 c = cx ? x : y;
                int width = g.T.Bits(inst.OpType);
                bool zero = inst.Op == "and" && Normalize(c, width, false) == 0;
                bool one = inst.Op == "or" && width == 1 && Normalize(c, 1, false) == 1;
                if (zero || one)
                {
                    known.Set(inst.Res, g.M.AddVal(IrVal { Kind = ValKind.Int, Type = inst.OpType, Int = zero ? 0 : 1 }));
                    g.Skip.Add(inst.Res);
                }
                continue;
            }
            if (!cx || !cy)
                continue;
            int t = inst.OpType;
            if (g.T.Kind(t) != IrKind.Int && g.T.Kind(t) != IrKind.Ptr)
                continue;
            int bits = g.T.Kind(t) == IrKind.Ptr ? 32 : g.T.Bits(t);
            if (bits > 32)
                continue;
            int64 result;
            if (inst.Op == "icmp")
            {
                string p = inst.Pred;
                bool signed = p.StartsWith("s");
                int64 a = Normalize(x, bits, signed || p == "eq" || p == "ne");
                int64 c = Normalize(y, bits, signed || p == "eq" || p == "ne");
                bool r = p == "eq" ? a == c : p == "ne" ? a != c : (p == "slt" || p == "ult") ? a < c :
                         (p == "sle" || p == "ule") ? a <= c : (p == "sgt" || p == "ugt") ? a > c : a >= c;
                result = r ? 1 : 0;
            }
            else if (inst.Op == "and")
                result = x & y;
            else if (inst.Op == "or")
                result = x | y;
            else if (inst.Op == "xor")
                result = x ^ y;
            else
                continue;
            int type = inst.Op == "icmp" ? i1 : t;
            known.Set(inst.Res, g.M.AddVal(IrVal { Kind = ValKind.Int, Type = type, Int = Normalize(result, inst.Op == "icmp" ? 1 : bits, false) }));
            g.Skip.Add(inst.Res);
        }
    }
}

// Instructions without side effects whose results nobody uses (after the folding) are not written.
void RemoveDeadCode(Gen g, IrFunc f)
{
    bool changed = true;
    while (changed)
    {
        changed = false;
        var uses = Dictionary<string, int>.Create();
        foreach (var b in f.Blocks.ToArray())
        {
            foreach (var inst in b.Insts.ToArray())
            {
                if (inst.Res.Length > 0 && g.Skip.Contains(inst.Res))
                    continue;
                foreach (var a in inst.Args)
                {
                    var v = g.M.Vals.Get(a);
                    if (v.Kind == ValKind.Local)
                        uses.Set(v.Name, uses.GetOrDefault(v.Name, 0) + 1);
                }
                if (inst.Callee >= 0 && g.M.Vals.Get(inst.Callee).Kind == ValKind.Local)
                    uses.Set(g.M.Vals.Get(inst.Callee).Name, uses.GetOrDefault(g.M.Vals.Get(inst.Callee).Name, 0) + 1);
            }
        }
        foreach (var b in f.Blocks.ToArray())
        {
            foreach (var inst in b.Insts.ToArray())
            {
                if (inst.Res.Length == 0 || g.Skip.Contains(inst.Res) || uses.ContainsKey(inst.Res) || !IsPure(inst))
                    continue;
                g.Skip.Add(inst.Res);
                changed = true;
            }
        }
    }
}

bool IsPure(IrInst inst)
{
    switch (inst.Op)
    {
    case "add":
    case "sub":
    case "mul":
    case "and":
    case "or":
    case "xor":
    case "shl":
    case "lshr":
    case "ashr":
    case "icmp":
    case "fcmp":
    case "zext":
    case "sext":
    case "trunc":
    case "ptrtoint":
    case "inttoptr":
    case "bitcast":
    case "getelementptr":
    case "select":
    case "extractvalue":
    case "insertvalue":
        return true;
    case "load":
        return !inst.Volatile;
    default:
        return false;
    }
}

void FoldAddresses(Gen g, IrFunc f)
{
    var uses = Dictionary<string, int>.Create();
    var allocas = HashSet<string>.Create();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca")
                allocas.Add(inst.Res);
            foreach (var a in inst.Args)
            {
                var v = g.M.Vals.Get(a);
                if (v.Kind == ValKind.Local)
                    uses.Set(v.Name, uses.GetOrDefault(v.Name, 0) + 1);
            }
            if (inst.Callee >= 0 && g.M.Vals.Get(inst.Callee).Kind == ValKind.Local)
                uses.Set(g.M.Vals.Get(inst.Callee).Name, uses.GetOrDefault(g.M.Vals.Get(inst.Callee).Name, 0) + 1);
        }
    }
    foreach (var b in f.Blocks.ToArray())
    {
        var insts = b.Insts.ToArray();
        var gepAt = Dictionary<string, int>.Create(); // gep results of this block -> index
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Op == "getelementptr")
            {
                gepAt.Set(inst.Res, k);
                continue;
            }
            if (inst.Op != "load" && inst.Op != "store")
                continue;
            int t = inst.Op == "load" ? inst.Type : inst.OpType;
            if (!IsScalar4(g, t))
                continue;
            int pi = inst.Op == "load" ? inst.Args[0] : inst.Args[1];
            var p = g.M.Vals.Get(pi);
            if (p.Kind != ValKind.Local || uses.GetOrDefault(p.Name, 0) != 1)
                continue;
            var at = gepAt.TryGet(p.Name);
            int gk = at is int found ? found : -1;
            if (gk < 0)
                continue;
            var fold = AddrFold { Base = -1, Index = -1, IndexBits = 32, Stride = 1, Offset = 0 };
            if (!GepParts(g, insts[gk], ref fold))
                continue;
            // a constant gep below it (the header of an array): merged
            var baseVal = g.M.Vals.Get(fold.Base);
            string inner = "";
            if (baseVal.Kind == ValKind.Local && uses.GetOrDefault(baseVal.Name, 0) == 1)
            {
                var bat = gepAt.TryGet(baseVal.Name);
                if (bat is int bk)
                {
                    var innerFold = AddrFold { Base = -1, Index = -1, IndexBits = 32, Stride = 1, Offset = 0 };
                    if (GepParts(g, insts[bk], ref innerFold) && innerFold.Index < 0)
                    {
                        fold.Base = innerFold.Base;
                        fold.Offset += innerFold.Offset;
                        inner = baseVal.Name;
                    }
                }
            }
            // the base must be a pointer value (not the address of a variable of the frame)
            var finalBase = g.M.Vals.Get(fold.Base);
            if (finalBase.Kind == ValKind.Local && allocas.Contains(finalBase.Name))
                continue;
            if (finalBase.Kind != ValKind.Local && finalBase.Kind != ValKind.Global)
                continue;
            if (fold.Index >= 0 ? (fold.Offset < -128 || fold.Offset > 127) : (fold.Offset < -32768 || fold.Offset > 32767))
                continue;
            g.Folds.Set(p.Name, fold);
            g.Skip.Add(p.Name);
            if (inner.Length > 0)
                g.Skip.Add(inner);
        }
    }
}

// The parts of a getelementptr: base, constant offset and at most one variable index. False if it has more.
bool GepParts(Gen g, IrInst inst, ref AddrFold fold)
{
    fold.Base = inst.Args[0];
    int t = inst.OpType;
    for (var k = 1; k < inst.Args.Length; k += 1)
    {
        int idx = inst.Args[k];
        int stride;
        if (k == 1)
            stride = g.L.Stride(t);
        else if (g.T.Kind(t) == IrKind.Struct)
        {
            int field = (int)g.M.Vals.Get(idx).Int;
            fold.Offset += (int64)g.L.FieldOffset(t, field);
            t = g.T.Info(t).Fields[field];
            continue;
        }
        else
        {
            t = g.T.Info(t).Elem;
            stride = g.L.Stride(t);
        }
        var iv = g.M.Vals.Get(idx);
        if (iv.Kind != ValKind.Local)
        {
            var c = EvalConst(g, idx);
            if (!c.Ok || c.Sym.Length > 0)
                return false;
            int bits = g.T.Bits(iv.Type);
            fold.Offset += Normalize(c.Off, bits > 0 && bits < 64 ? bits : 64, true) * (int64)stride;
            continue;
        }
        if (fold.Index >= 0 || g.T.Bits(iv.Type) > 32)
            return false;
        fold.Index = idx;
        fold.IndexBits = g.T.Bits(iv.Type);
        fold.Stride = stride;
    }
    return true;
}

// The operand of a folded access: the base in an address register (its own, or a0), the scaled index in d1.
string FoldedOperand(Gen g, AddrFold fold)
{
    string baseReg = "%a0";
    var bv = g.M.Vals.Get(fold.Base);
    if (bv.Kind == ValKind.Local)
    {
        var home = g.Home.TryGet(bv.Name);
        if (home is string reg && reg.StartsWith("%a"))
            baseReg = reg;
    }
    if (baseReg == "%a0")
        LoadAddr(g, fold.Base, "%a0");
    if (fold.Index < 0)
        return fold.Offset == 0 ? "(" + baseReg + ")" : "(" + fold.Offset.ToString() + "," + baseReg + ")";
    Load32(g, fold.Index, "%d1");
    if (fold.IndexBits < 32)
        Extend(g, "%d1", fold.IndexBits, true);
    ScaleD1(g, fold.Stride);
    return "(" + fold.Offset.ToString() + "," + baseReg + ",%d1.l)";
}
