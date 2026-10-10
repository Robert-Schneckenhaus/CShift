// What the IR already knows at a place, used before the code is written (Prepare.csh):
//
//   * Known variables: a load of a variable that was stored or loaded before on every way to it (the last access in a
//     dominating block, and no store on the ways from there) is that value. Only for variables whose address is used by
//     nothing but their loads and stores, so that no call can change them. Two loads of `index` around a store into
//     another array are the same value then, and so are the bounds checks of `data[index]` that read and write.
//   * Known conditions: a block whose only predecessor branched on a comparison knows its outcome, and so do the blocks
//     it dominates. The same comparison there is a constant: the bounds check of `data[index] ^= x` is made once.
//   * Checked arithmetic that cannot overflow: `i + 1` where `i < n` (signed) or `i < length` (unsigned, a length is
//     at most int.MaxValue) is known, `i + k + 1` where `i + k < n` is known, `length - c` (a length is never
//     negative), and operations whose operands have small ranges (`(d << 4) + d + 87` with `d = x & 0xffff`) become
//     plain additions and subtractions; their panic blocks go away.
//   * The same computation twice (an add, a cast of the same values) where the first dominates the second: the second
//     is the first's result (CommonValues).
//   * Blocks: a branch on a constant goes to its target, blocks that nothing reaches any more are removed, and a block
//     that only one block branches to (and that comes after it) is joined to that block.

namespace CShift.M68k;

using System;

// a comparison that holds: a Pred b
struct Fact
{
    string Pred;
    string A;
    string B;
}

// ---------------------------------------------------------------------------
// The edges of the blocks
// ---------------------------------------------------------------------------

struct Edges
{
    Dictionary<string, int> Index;
    List<int>[] Succs;
    List<int>[] Preds;
}

Edges BlockEdges(IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    var e = Edges { Index = Dictionary<string, int>.Create(), Succs = new List<int>[n], Preds = new List<int>[n] };
    for (var i = 0; i < n; i += 1)
    {
        e.Index.Set(blocks[i].Label, i);
        e.Succs[i] = List<int>.Create();
        e.Preds[i] = List<int>.Create();
    }
    for (var i = 0; i < n; i += 1)
    {
        foreach (var inst in blocks[i].Insts.ToArray())
        {
            if (inst.Op != "br" && inst.Op != "switch")
                continue;
            foreach (var label in inst.Labels)
            {
                if (e.Index.TryGet(label) is int t && !e.Succs[i].Contains(t))
                {
                    e.Succs[i].Add(t);
                    e.Preds[t].Add(i);
                }
            }
        }
    }
    return e;
}

// the blocks that a way from 'from' to 'to' can pass without passing 'from' again ('from' not included, 'to' only if
// such a way passes it before it ends there: a loop around it)
bool[] Between(Edges e, int from, int to)
{
    int n = e.Succs.Length;
    var forward = new bool[n];
    var work = List<int>.Create();
    foreach (var s in e.Succs[from].ToArray())
    {
        if (s != from && !forward[s])
        {
            forward[s] = true;
            work.Add(s);
        }
    }
    while (work.Count() > 0)
    {
        int b = work.Get(work.Count() - 1);
        work.RemoveAt(work.Count() - 1);
        foreach (var s in e.Succs[b].ToArray())
        {
            if (s != from && !forward[s])
            {
                forward[s] = true;
                work.Add(s);
            }
        }
    }
    var backward = new bool[n];
    foreach (var p in e.Preds[to].ToArray())
    {
        if (p != from && !backward[p])
        {
            backward[p] = true;
            work.Add(p);
        }
    }
    while (work.Count() > 0)
    {
        int b = work.Get(work.Count() - 1);
        work.RemoveAt(work.Count() - 1);
        foreach (var p in e.Preds[b].ToArray())
        {
            if (p != from && !backward[p])
            {
                backward[p] = true;
                work.Add(p);
            }
        }
    }
    var result = new bool[n];
    for (var i = 0; i < n; i += 1)
        result[i] = forward[i] && backward[i];
    return result;
}

// ---------------------------------------------------------------------------
// Known variables
// ---------------------------------------------------------------------------

// the variable that an instruction loads (load) or stores (store), "" if it is none of the plain variables
string AccessedVariable(Gen g, IrInst inst, Dictionary<string, int> plain)
{
    int a = inst.Op == "load" ? 0 : inst.Op == "store" ? 1 : -1;
    if (a < 0 || inst.Args.Length <= a)
        return "";
    var v = g.M.Vals.Get(inst.Args[a]);
    return v.Kind == ValKind.Local && plain.ContainsKey(v.Name) ? v.Name : "";
}

void ForwardLoads(Gen g, IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    // the plain variables: scalar allocas whose address only loads and stores of their size use
    var plain = Dictionary<string, int>.Create();
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca" && IsScalar4(g, inst.OpType) && (inst.Args.Length == 0 || !IsLocal(g, inst.Args[0])))
                plain.Set(inst.Res, g.L.Size(inst.OpType));
        }
    }
    if (plain.Count() == 0)
        return;
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind != ValKind.Local || !plain.ContainsKey(v.Name))
                    continue;
                int size = plain.Get(v.Name);
                bool ok = (inst.Op == "load" && a == 0 && IsScalar4(g, inst.Type) && g.L.Size(inst.Type) == size && !inst.Volatile) ||
                          (inst.Op == "store" && a == 1 && IsScalar4(g, inst.OpType) && g.L.Size(inst.OpType) == size && !inst.Volatile);
                if (!ok)
                    plain.Remove(v.Name);
            }
            if (inst.Callee >= 0 && g.M.Vals.Get(inst.Callee).Kind == ValKind.Local)
                plain.Remove(g.M.Vals.Get(inst.Callee).Name);
        }
    }
    if (plain.Count() == 0)
        return;
    var idom = Dominators(f);
    var e = BlockEdges(f);
    // the variables each block stores
    var stores = new HashSet<string>[n];
    for (var j = 0; j < n; j += 1)
    {
        stores[j] = HashSet<string>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (inst.Op == "store")
            {
                string name = AccessedVariable(g, inst, plain);
                if (name.Length > 0)
                    stores[j].Add(name);
            }
        }
    }
    var replaced = Dictionary<string, int>.Create();   // a load's result -> the value it is
    for (var j = 0; j < n; j += 1)
    {
        if (j > 0 && idom[j] < 0)
            continue; // (not reached)
        var insts = blocks[j].Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Op != "load")
                continue;
            string name = AccessedVariable(g, inst, plain);
            if (name.Length == 0)
                continue;
            int known = KnownValue(g, blocks, e, idom, stores, plain, name, j, k);
            if (known >= 0)
                replaced.Set(inst.Res, known);
        }
    }
    if (replaced.Count() == 0)
        return;
    // a value that is a replaced load itself: what that one is
    foreach (var entry in replaced.Entries())
    {
        int vi = entry.Value;
        for (var guard = 0; guard < 1000; guard += 1)
        {
            var v = g.M.Vals.Get(vi);
            if (v.Kind != ValKind.Local || !replaced.ContainsKey(v.Name))
                break;
            vi = replaced.Get(v.Name);
        }
        replaced.Set(entry.Key, vi);
    }
    for (var j = 0; j < n; j += 1)
    {
        var kept = List<IrInst>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (!(inst.Op == "load" && replaced.ContainsKey(inst.Res)))
                kept.Add(inst);
        }
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
    }
    foreach (var entry in replaced.Entries())
        ReplaceUses(g, f, entry.Key, entry.Value);
}

// The value of variable 'name' before instruction k of block j, -1 if it is not known: the last access before it in
// the block, else that of the nearest dominating block with an access, if no block on the ways from there stores it.
int KnownValue(Gen g, IrBlock[] blocks, Edges e, int[] idom, HashSet<string>[] stores, Dictionary<string, int> plain,
               string name, int j, int k)
{
    var insts = blocks[j].Insts.ToArray();
    for (var i = k - 1; i >= 0; i -= 1)
    {
        if (AccessedVariable(g, insts[i], plain) == name)
            return insts[i].Op == "store" ? insts[i].Args[0] : ResultValue(g, insts[i]);
    }
    int d = idom[j];
    while (d >= 0)
    {
        var dinsts = blocks[d].Insts.ToArray();
        for (var i = dinsts.Length - 1; i >= 0; i -= 1)
        {
            if (AccessedVariable(g, dinsts[i], plain) != name)
                continue;
            var between = Between(e, d, j);
            for (var b = 0; b < between.Length; b += 1)
            {
                if (between[b] && stores[b].Contains(name))
                    return -1;
            }
            return dinsts[i].Op == "store" ? dinsts[i].Args[0] : ResultValue(g, dinsts[i]);
        }
        if (d == 0)
            break;
        d = idom[d];
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Known conditions
// ---------------------------------------------------------------------------

// a value as a key for comparisons: locals by name, integer constants by value; "" for others
string ValueKey(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local)
        return "%" + v.Name;
    if (v.Kind == ValKind.Int)
    {
        int bits = g.T.Kind(v.Type) == IrKind.Int ? g.T.Bits(v.Type) : 32;
        return "#" + Normalize(v.Int, bits > 32 ? 64 : bits, true).ToString();
    }
    if (v.Kind == ValKind.Null || v.Kind == ValKind.Zero)
        return "#0";
    return "";
}

string NegatePred(string p)
{
    switch (p)
    {
    case "eq": return "ne";
    case "ne": return "eq";
    case "slt": return "sge";
    case "sge": return "slt";
    case "sle": return "sgt";
    case "sgt": return "sle";
    case "ult": return "uge";
    case "uge": return "ult";
    case "ule": return "ugt";
    case "ugt": return "ule";
    }
    return "";
}

// a < b is b > a
string SwapPred(string p)
{
    switch (p)
    {
    case "slt": return "sgt";
    case "sgt": return "slt";
    case "sle": return "sge";
    case "sge": return "sle";
    case "ult": return "ugt";
    case "ugt": return "ult";
    case "ule": return "uge";
    case "uge": return "ule";
    }
    return p;
}

// 1 if the comparison holds, 0 if it does not, -1 if the facts do not tell
int Decide(List<Fact> facts, string p, string a, string b)
{
    if (a.Length == 0 || b.Length == 0)
        return -1;
    foreach (var fact in facts)
    {
        string q = "";
        if (fact.A == a && fact.B == b)
            q = fact.Pred;
        else if (fact.A == b && fact.B == a)
            q = SwapPred(fact.Pred);
        else
            continue;
        if (q == p)
            return 1;
        if (NegatePred(q) == p)
            return 0;
    }
    return -1;
}

// x is 'base + k' (k >= 0): an add of a constant or the value of a checked add of a constant. NoWrap: the sum did not
// wrap around (a checked add, or a plain one that was checked); a plain add from unchecked code can.
struct Offset
{
    string Base;
    int64 K;
    bool NoWrap;
}

void KnownConditions(Gen g, IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    var e = BlockEdges(f);
    var idom = Dominators(f);
    // the comparisons, the sums with constants and the values that are never negative
    var cmps = Dictionary<string, IrInst>.Create();
    var sums = Dictionary<string, Offset>.Create();
    var checkedSum = Dictionary<string, Offset>.Create();   // a checked add's result (the aggregate) -> its sum
    var nonNegative = HashSet<string>.Create();
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Res.Length == 0)
                continue;
            if (inst.Op == "icmp" && inst.Args.Length == 2)
                cmps.Set(inst.Res, inst);
            int64 c = 0;
            if (inst.Op == "add" && inst.Args.Length == 2 && ConstInt(g, inst.Args[1], ref c) && c >= 0 && c < 65536 &&
                IsLocal(g, inst.Args[0]))
                sums.Set("%" + inst.Res, Offset { Base = ValueKey(g, inst.Args[0]), K = c, NoWrap = g.NoWrap.Contains(inst.Res) });
            if (IsOverflowCall(g, inst, "llvm.sadd.with.overflow.i32") && ConstInt(g, inst.Args[1], ref c) && c >= 0 &&
                c < 65536 && IsLocal(g, inst.Args[0]))
                checkedSum.Set(inst.Res, Offset { Base = ValueKey(g, inst.Args[0]), K = c, NoWrap = true });
            if (IsLengthCall(g, inst) || inst.Op == "zext")
                nonNegative.Add("%" + inst.Res);
        }
    }
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "extractvalue" && inst.Res.Length > 0 && inst.Cases.Length == 1 && inst.Cases[0] == 0 &&
                IsLocal(g, inst.Args[0]) && checkedSum.TryGet(g.M.Vals.Get(inst.Args[0]).Name) is Offset s)
                sums.Set("%" + inst.Res, s);
        }
    }

    // the facts that each block brings: its only predecessor branched on a comparison
    var own = new List<Fact>[n];
    for (var j = 0; j < n; j += 1)
        own[j] = List<Fact>.Create();
    for (var j = 0; j < n; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        if (insts.Length == 0)
            continue;
        var br = insts[insts.Length - 1];
        if (br.Op != "br" || br.Labels.Length != 2 || br.Labels[0] == br.Labels[1] || !IsLocal(g, br.Args[0]))
            continue;
        var found = cmps.TryGet(g.M.Vals.Get(br.Args[0]).Name);
        if (found is IrInst cmp)
        {
            string a = ValueKey(g, cmp.Args[0]);
            string b = ValueKey(g, cmp.Args[1]);
            if (a.Length == 0 || b.Length == 0)
                continue;
            for (var side = 0; side < 2; side += 1)
            {
                var target = e.Index.TryGet(br.Labels[side]);
                if (target is int t && e.Preds[t].Count() == 1)
                    own[t].Add(Fact { Pred = side == 0 ? cmp.Pred : NegatePred(cmp.Pred), A = a, B = b });
            }
        }
    }

    var ranges = NewRanges(g, f);
    var constants = Dictionary<string, int>.Create();   // a comparison's result -> its constant
    var plainOps = List<string>.Create();               // the checked operations that cannot overflow
    int i1 = g.T.IntType(1);
    for (var j = 0; j < n; j += 1)
    {
        if (j > 0 && idom[j] < 0)
            continue;
        var facts = List<Fact>.Create();
        for (int d = j; d >= 0; d = d == 0 ? -1 : idom[d])
        {
            foreach (var fact in own[d].ToArray())
                facts.Add(fact);
        }
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (inst.Op == "icmp" && inst.Res.Length > 0 && inst.Args.Length == 2)
            {
                int r = Decide(facts, inst.Pred, ValueKey(g, inst.Args[0]), ValueKey(g, inst.Args[1]));
                if (r >= 0)
                    constants.Set(inst.Res, g.M.AddVal(IrVal { Kind = ValKind.Int, Type = i1, Int = r }));
                continue;
            }
            // a branch on a comparison made before (in a dominating block) whose outcome is known here
            if (inst.Op == "br" && inst.Labels.Length == 2 && IsLocal(g, inst.Args[0]))
            {
                var cmp = cmps.TryGet(g.M.Vals.Get(inst.Args[0]).Name);
                if (cmp is IrInst c)
                {
                    int r = Decide(facts, c.Pred, ValueKey(g, c.Args[0]), ValueKey(g, c.Args[1]));
                    if (r >= 0)
                        inst.Args[0] = g.M.AddVal(IrVal { Kind = ValKind.Int, Type = i1, Int = r });
                }
                continue;
            }
            if (CannotOverflow(g, inst, facts, sums, nonNegative) || RangesFit(g, ranges, inst))
                plainOps.Add(inst.Res);
        }
    }
    foreach (var entry in constants.Entries())
    {
        ReplaceUses(g, f, entry.Key, entry.Value);
        g.Skip.Add(entry.Key);
    }
    if (plainOps.Count() > 0)
        PlainArithmetic(g, f, plainOps);
}

// a value that is never negative: a length, a zero-extended value or a constant >= 0
bool IsNonNegative(HashSet<string> nonNegative, string key)
{
    return nonNegative.Contains(key) || (key.StartsWith("#") && !key.StartsWith("#-"));
}

bool IsOverflowCall(Gen g, IrInst inst, string name)
{
    if (inst.Op != "call" || inst.Callee < 0 || inst.Args.Length != 2 || inst.Res.Length == 0)
        return false;
    var c = g.M.Vals.Get(inst.Callee);
    return c.Kind == ValKind.Global && c.Name == name;
}

// whether a checked add or sub of 32 bits cannot overflow, by the facts
bool CannotOverflow(Gen g, IrInst inst, List<Fact> facts, Dictionary<string, Offset> sums, HashSet<string> nonNegative)
{
    int64 c = 0;
    if (IsOverflowCall(g, inst, "llvm.sadd.with.overflow.i32"))
    {
        int x = 0;
        if (ConstInt(g, inst.Args[1], ref c))
            x = inst.Args[0];
        else if (ConstInt(g, inst.Args[0], ref c))
            x = inst.Args[1];
        else
            return false;
        if (c < 0 || c > 65536 || !IsLocal(g, x))
            return false;
        if (c == 0)
            return true;
        string key = ValueKey(g, x);
        // a fact 'y < something' with y = x + k (k >= c - 1): y <= int.MaxValue - 1, so x + c <= int.MaxValue. For
        // 'y < length' (unsigned) y cannot have wrapped around (it would be at least 2^31 then); for a signed fact it
        // must not have.
        foreach (var fact in facts)
        {
            string y = "";
            bool signedFact = false;
            if (fact.Pred == "slt")
            {
                y = fact.A;
                signedFact = true;
            }
            else if (fact.Pred == "sgt")
            {
                y = fact.B;
                signedFact = true;
            }
            else if (fact.Pred == "ult" && IsNonNegative(nonNegative, fact.B))
                y = fact.A;
            else if (fact.Pred == "ugt" && IsNonNegative(nonNegative, fact.A))
                y = fact.B;
            if (y.Length == 0)
                continue;
            if (y == key && c <= 1)
                return true;
            if (sums.TryGet(y) is Offset s && s.Base == key && s.K + 1 >= c && (s.NoWrap || !signedFact))
                return true;
        }
        return false;
    }
    if (IsOverflowCall(g, inst, "llvm.ssub.with.overflow.i32"))
    {
        // length - c: a length is never negative
        if (!ConstInt(g, inst.Args[1], ref c) || c < 0 || c > 65536 || !IsLocal(g, inst.Args[0]))
            return false;
        string key = ValueKey(g, inst.Args[0]);
        if (IsNonNegative(nonNegative, key) || c == 0)
            return true;
        // x - 1 where x > y is known
        foreach (var fact in facts)
        {
            if (c == 1 && ((fact.Pred == "sgt" && fact.A == key) || (fact.Pred == "slt" && fact.B == key)))
                return true;
            if ((fact.Pred == "sge" && fact.A == key && fact.B == "#0") || (fact.Pred == "sle" && fact.B == key && fact.A == "#0"))
                return true;
        }
        return false;
    }
    return false;
}

// The checked operations that cannot overflow become plain ones: the call becomes an add or sub (its value), the
// overflow flag false.
void PlainArithmetic(Gen g, IrFunc f, List<string> calls)
{
    var set = HashSet<string>.Create();
    foreach (var name in calls)
        set.Add(name);
    int i1 = g.T.IntType(1);
    int no = g.M.AddVal(IrVal { Kind = ValKind.Int, Type = i1, Int = 0 });
    var uses = LocalUses(g, f);
    var blocks = f.Blocks.ToArray();
    var flags = List<string>.Create();
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        // the extracts of each call: value and flag
        var valueOf = Dictionary<string, string>.Create();
        var flagOf = Dictionary<string, string>.Create();
        foreach (var inst in insts)
        {
            if (inst.Op == "extractvalue" && inst.Cases.Length == 1 && IsLocal(g, inst.Args[0]) &&
                set.Contains(g.M.Vals.Get(inst.Args[0]).Name))
            {
                string call = g.M.Vals.Get(inst.Args[0]).Name;
                if (inst.Cases[0] == 0 && !valueOf.ContainsKey(call))
                    valueOf.Set(call, inst.Res);
                else if (inst.Cases[0] == 1 && !flagOf.ContainsKey(call))
                    flagOf.Set(call, inst.Res);
            }
        }
        if (valueOf.Count() == 0 && flagOf.Count() == 0)
            continue;
        var kept = List<IrInst>.Create();
        foreach (var inst in insts)
        {
            // (its only uses: the two extracts in this block)
            if (inst.Op == "call" && set.Contains(inst.Res) && valueOf.ContainsKey(inst.Res) && flagOf.ContainsKey(inst.Res) &&
                uses.GetOrDefault(inst.Res, 0) == 2)
            {
                var callee = g.M.Vals.Get(inst.Callee);
                int t = g.M.Vals.Get(inst.Args[0]).Type;
                g.NoWrap.Add(valueOf.Get(inst.Res));
                kept.Add(IrInst { Op = callee.Name.Contains("add") ? "add" : "sub", Res = valueOf.Get(inst.Res), Type = t,
                                  OpType = t, Args = [inst.Args[0], inst.Args[1]], Pred = "", Labels = new string[0],
                                  Cases = new int64[0], Callee = -1, Volatile = false });
                flags.Add(flagOf.Get(inst.Res));
                set.Remove(inst.Res); // (done; its extracts below are left out)
                set.Add("done:" + inst.Res);
                continue;
            }
            if (inst.Op == "extractvalue" && IsLocal(g, inst.Args[0]) && set.Contains("done:" + g.M.Vals.Get(inst.Args[0]).Name))
                continue;
            kept.Add(inst);
        }
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
    }
    foreach (var flag in flags)
        ReplaceUses(g, f, flag, no);
}

// ---------------------------------------------------------------------------
// Ranges: the smallest and largest value a 32-bit value can have, from how it is computed
// ---------------------------------------------------------------------------

struct Range
{
    bool Known;
    int64 Lo;
    int64 Hi;
}

struct Ranges
{
    Dictionary<string, IrInst> Def;          // a value -> the instruction that computes it
    Dictionary<string, List<int>> Stored;    // a plain variable -> the values stored into it
    Dictionary<string, Range> Done;
    HashSet<string> Busy;                    // (being computed: a cycle through a variable is not known)
}

Ranges NewRanges(Gen g, IrFunc f)
{
    var r = Ranges { Def = Dictionary<string, IrInst>.Create(), Stored = Dictionary<string, List<int>>.Create(),
                     Done = Dictionary<string, Range>.Create(), Busy = HashSet<string>.Create() };
    var plain = HashSet<string>.Create();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Res.Length > 0 && !g.Skip.Contains(inst.Res))
                r.Def.Set(inst.Res, inst);
            if (inst.Op == "alloca" && IsScalar4(g, inst.OpType) && (inst.Args.Length == 0 || !IsLocal(g, inst.Args[0])))
                plain.Add(inst.Res);
        }
    }
    // the variables whose address is used by nothing but loads and stores, and what is stored into them
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind != ValKind.Local || !plain.Contains(v.Name))
                    continue;
                if (inst.Op == "store" && a == 1)
                {
                    if (!r.Stored.ContainsKey(v.Name))
                        r.Stored.Set(v.Name, List<int>.Create());
                    r.Stored.Get(v.Name).Add(inst.Args[0]);
                }
                else if (!(inst.Op == "load" && a == 0))
                    plain.Remove(v.Name);
            }
        }
    }
    foreach (var name in r.Stored.Keys())
    {
        if (!plain.Contains(name))
            r.Stored.Remove(name);
    }
    return r;
}

Range Unknown()
{
    return Range { Known = false, Lo = 0, Hi = 0 };
}

Range Between32(int64 lo, int64 hi)
{
    if (lo < -2147483648 || hi > 2147483647 || lo > hi)
        return Unknown();
    return Range { Known = true, Lo = lo, Hi = hi };
}

Range RangeOf(Gen g, Ranges r, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Int)
    {
        int bits = g.T.Kind(v.Type) == IrKind.Int ? g.T.Bits(v.Type) : 32;
        if (bits > 32)
            return Unknown();
        int64 c = Normalize(v.Int, bits, true);
        return Range { Known = true, Lo = c, Hi = c };
    }
    if (v.Kind != ValKind.Local)
        return Unknown();
    var done = r.Done.TryGet(v.Name);
    if (done is Range known)
        return known;
    if (r.Busy.Contains(v.Name))
        return Unknown();
    r.Busy.Add(v.Name);
    var result = Unknown();
    var def = r.Def.TryGet(v.Name);
    if (def is IrInst inst)
        result = RangeOfInst(g, r, inst);
    r.Busy.Remove(v.Name);
    r.Done.Set(v.Name, result);
    return result;
}

Range RangeOfInst(Gen g, Ranges r, IrInst inst)
{
    string op = inst.Op;
    int64 c = 0;
    if (op == "zext" && g.T.Kind(inst.OpType) == IrKind.Int && g.T.Bits(inst.OpType) < 32)
    {
        var x = RangeOf(g, r, inst.Args[0]);
        int bits = g.T.Bits(inst.OpType);
        if (x.Known && x.Lo >= 0)
            return x;
        return Range { Known = true, Lo = 0, Hi = ((int64)1 << bits) - 1 };
    }
    if (op == "sext" && g.T.Kind(inst.OpType) == IrKind.Int && g.T.Bits(inst.OpType) < 32)
    {
        int bits = g.T.Bits(inst.OpType);
        return Range { Known = true, Lo = -((int64)1 << (bits - 1)), Hi = ((int64)1 << (bits - 1)) - 1 };
    }
    if (g.T.Kind(inst.Type) != IrKind.Int || g.T.Bits(inst.Type) != 32)
        return Unknown();
    if (IsLengthCall(g, inst))
        return Range { Known = true, Lo = 0, Hi = 2147483647 };
    if (op == "and" && inst.Args.Length == 2)
    {
        for (var side = 0; side < 2; side += 1)
        {
            if (ConstInt(g, inst.Args[side], ref c) && Normalize(c, 32, true) >= 0)
                return Range { Known = true, Lo = 0, Hi = Normalize(c, 32, true) };
        }
        var x = RangeOf(g, r, inst.Args[0]);
        var y = RangeOf(g, r, inst.Args[1]);
        if (x.Known && x.Lo >= 0)
            return Range { Known = true, Lo = 0, Hi = x.Hi };
        if (y.Known && y.Lo >= 0)
            return Range { Known = true, Lo = 0, Hi = y.Hi };
        return Unknown();
    }
    if ((op == "lshr" || op == "ashr" || op == "shl") && inst.Args.Length == 2 && ConstInt(g, inst.Args[1], ref c) && c >= 0 &&
        c < 32)
    {
        var x = RangeOf(g, r, inst.Args[0]);
        if (op == "lshr" && !(x.Known && x.Lo >= 0))
            return c == 0 ? Unknown() : Range { Known = true, Lo = 0, Hi = 4294967295 >> (int)c };
        if (!x.Known)
            return Unknown();
        if (op == "shl")
            return x.Lo >= 0 ? Between32(x.Lo << (int)c, x.Hi << (int)c) : Unknown();
        return Range { Known = true, Lo = x.Lo >> (int)c, Hi = x.Hi >> (int)c };
    }
    if ((op == "add" || op == "sub") && inst.Args.Length == 2)
    {
        var x = RangeOf(g, r, inst.Args[0]);
        var y = RangeOf(g, r, inst.Args[1]);
        if (!x.Known || !y.Known)
            return Unknown();
        return op == "add" ? Between32(x.Lo + y.Lo, x.Hi + y.Hi) : Between32(x.Lo - y.Hi, x.Hi - y.Lo);
    }
    if (op == "extractvalue" && inst.Cases.Length == 1 && inst.Cases[0] == 0 && IsLocal(g, inst.Args[0]))
    {
        // the value of a checked add/sub: where it is used, it did not overflow
        var call = r.Def.TryGet(g.M.Vals.Get(inst.Args[0]).Name);
        if (call is IrInst ci && (IsOverflowCall(g, ci, "llvm.sadd.with.overflow.i32") ||
                                  IsOverflowCall(g, ci, "llvm.ssub.with.overflow.i32")))
        {
            var x = RangeOf(g, r, ci.Args[0]);
            var y = RangeOf(g, r, ci.Args[1]);
            if (!x.Known || !y.Known)
                return Unknown();
            return g.M.Vals.Get(ci.Callee).Name.Contains("add") ? Between32(x.Lo + y.Lo, x.Hi + y.Hi) :
                                                                   Between32(x.Lo - y.Hi, x.Hi - y.Lo);
        }
        return Unknown();
    }
    if (op == "load" && IsLocal(g, inst.Args[0]))
    {
        // a variable: what is stored into it
        var stored = r.Stored.TryGet(g.M.Vals.Get(inst.Args[0]).Name);
        if (stored is List<int> values)
            return Union(g, r, values.ToArray());
        return Unknown();
    }
    if (op == "phi")
        return Union(g, r, inst.Args);
    return Unknown();
}

Range Union(Gen g, Ranges r, int[] values)
{
    if (values.Length == 0)
        return Unknown();
    int64 lo = 0;
    int64 hi = 0;
    for (var i = 0; i < values.Length; i += 1)
    {
        var x = RangeOf(g, r, values[i]);
        if (!x.Known)
            return Unknown();
        if (i == 0 || x.Lo < lo)
            lo = x.Lo;
        if (i == 0 || x.Hi > hi)
            hi = x.Hi;
    }
    return Range { Known = true, Lo = lo, Hi = hi };
}

// a checked add/sub of 32 bits whose operands' ranges keep it in 32 bits
bool RangesFit(Gen g, Ranges r, IrInst inst)
{
    bool add = IsOverflowCall(g, inst, "llvm.sadd.with.overflow.i32");
    if (!add && !IsOverflowCall(g, inst, "llvm.ssub.with.overflow.i32"))
        return false;
    var x = RangeOf(g, r, inst.Args[0]);
    var y = RangeOf(g, r, inst.Args[1]);
    if (!x.Known || !y.Known)
        return false;
    return (add ? Between32(x.Lo + y.Lo, x.Hi + y.Hi) : Between32(x.Lo - y.Hi, x.Hi - y.Lo)).Known;
}

// ---------------------------------------------------------------------------
// The same computation twice
// ---------------------------------------------------------------------------

// A pure computation (arithmetic, a cast) of the same operands as one that dominates it is that one's result.
void CommonValues(Gen g, IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    var idom = Dominators(f);
    var keyAt = Dictionary<string, List<int[]>>.Create();   // key -> { block, index, value }
    var replaced = Dictionary<string, int>.Create();
    for (var j = 0; j < blocks.Length; j += 1)
    {
        if (j > 0 && idom[j] < 0)
            continue;
        var insts = blocks[j].Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Res.Length == 0 || g.Skip.Contains(inst.Res) || !IsCommonOp(inst.Op))
                continue;
            string key = inst.Op + " " + inst.Pred + " " + inst.Type.ToString() + " " + inst.OpType.ToString();
            bool ok = true;
            foreach (var a in inst.Args)
            {
                string ak = ValueKey(g, a);
                if (ak.Length == 0)
                    ok = false;
                var v = g.M.Vals.Get(a);
                if (v.Kind == ValKind.Local && replaced.TryGet(v.Name) is int rv)
                    ak = ValueKey(g, rv);
                key = key + " " + ak;
            }
            if (!ok)
                continue;
            int by = -1;
            var found = keyAt.TryGet(key);
            if (found is List<int[]> list)
            {
                foreach (var at in list.ToArray())
                {
                    if (by < 0 && (at[0] == j ? at[1] < k : Dominates(idom, at[0], j)))
                        by = at[2];
                }
            }
            if (by >= 0)
                replaced.Set(inst.Res, by);
            else
            {
                if (!keyAt.ContainsKey(key))
                    keyAt.Set(key, List<int[]>.Create());
                keyAt.Get(key).Add([j, k, ResultValue(g, inst)]);
            }
        }
    }
    if (replaced.Count() == 0)
        return;
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var kept = List<IrInst>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (!(inst.Res.Length > 0 && replaced.ContainsKey(inst.Res)))
                kept.Add(inst);
        }
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
    }
    foreach (var entry in replaced.Entries())
        ReplaceUses(g, f, entry.Key, entry.Value);
}

bool IsCommonOp(string op)
{
    switch (op)
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
    case "zext":
    case "sext":
    case "trunc":
        return true;
    }
    return false; // (not icmp: a comparison with one use is written together with its branch)
}

// ---------------------------------------------------------------------------
// Branches on constants, blocks that nothing reaches
// ---------------------------------------------------------------------------

// A branch on a constant goes to its target; the blocks that cannot be reached any more are removed (and the phis
// forget them).
void SimplifyBranches(Gen g, IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    bool changed = false;
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        if (insts.Length == 0)
            continue;
        var br = insts[insts.Length - 1];
        int64 c = 0;
        if (br.Op != "br" || br.Labels.Length != 2 || !ConstInt(g, br.Args[0], ref c))
            continue;
        insts[insts.Length - 1] = Branch(Normalize(c, 1, false) != 0 ? br.Labels[0] : br.Labels[1]);
        var kept = List<IrInst>.Create();
        foreach (var inst in insts)
            kept.Add(inst);
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
        changed = true;
    }
    if (!changed)
        return;
    var e = BlockEdges(f);
    blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    var reached = new bool[n];
    var work = List<int>.Create();
    if (n > 0)
    {
        reached[0] = true;
        work.Add(0);
    }
    while (work.Count() > 0)
    {
        int b = work.Get(work.Count() - 1);
        work.RemoveAt(work.Count() - 1);
        foreach (var s in e.Succs[b].ToArray())
        {
            if (!reached[s])
            {
                reached[s] = true;
                work.Add(s);
            }
        }
    }
    var result = List<IrBlock>.Create();
    for (var j = 0; j < n; j += 1)
    {
        if (!reached[j])
            continue;
        // phis: only the incoming values of predecessors that still branch here
        var kept = List<IrInst>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (inst.Op != "phi")
            {
                kept.Add(inst);
                continue;
            }
            var args = List<int>.Create();
            var labels = List<string>.Create();
            for (var a = 0; a < inst.Labels.Length; a += 1)
            {
                if (e.Index.TryGet(inst.Labels[a]) is int p && reached[p] && e.Succs[p].Contains(j))
                {
                    args.Add(inst.Args[a]);
                    labels.Add(inst.Labels[a]);
                }
            }
            kept.Add(IrInst { Op = inst.Op, Res = inst.Res, Type = inst.Type, OpType = inst.OpType, Args = args.ToArray(),
                              Pred = inst.Pred, Labels = labels.ToArray(), Cases = inst.Cases, Callee = inst.Callee,
                              Volatile = inst.Volatile });
        }
        result.Add(IrBlock { Label = blocks[j].Label, Insts = kept });
    }
    f.Blocks.Clear();
    foreach (var b in result)
        f.Blocks.Add(b);
    JoinBlocks(g, f);
}

// A block that ends in 'br label %next', where %next comes after it and only it branches to %next: %next's
// instructions are appended (its phis have one incoming value: that value), and the phis after it name the block.
void JoinBlocks(Gen g, IrFunc f)
{
    for (var guard = 0; guard < 100000; guard += 1)
    {
        var blocks = f.Blocks.ToArray();
        var e = BlockEdges(f);
        int from = -1;
        int to = -1;
        for (var j = 0; j < blocks.Length && from < 0; j += 1)
        {
            var insts = blocks[j].Insts.ToArray();
            if (insts.Length == 0)
                continue;
            var br = insts[insts.Length - 1];
            if (br.Op != "br" || br.Labels.Length != 1)
                continue;
            var target = e.Index.TryGet(br.Labels[0]);
            if (target is int t && t > j && e.Preds[t].Count() == 1)
            {
                from = j;
                to = t;
            }
        }
        if (from < 0)
            return;
        var kept = List<IrInst>.Create();
        var fromInsts = blocks[from].Insts.ToArray();
        for (var k = 0; k < fromInsts.Length - 1; k += 1)
            kept.Add(fromInsts[k]);
        var phiValues = Dictionary<string, int>.Create();
        foreach (var inst in blocks[to].Insts.ToArray())
        {
            if (inst.Op == "phi")
            {
                if (inst.Args.Length == 1)
                    phiValues.Set(inst.Res, inst.Args[0]);
                else
                    return; // (cannot happen: one predecessor)
                continue;
            }
            kept.Add(inst);
        }
        string fromLabel = blocks[from].Label;
        string toLabel = blocks[to].Label;
        f.Blocks.Set(from, IrBlock { Label = fromLabel, Insts = kept });
        f.Blocks.RemoveAt(to);
        foreach (var entry in phiValues.Entries())
            ReplaceUses(g, f, entry.Key, entry.Value);
        // the phis of the blocks after %next: from %next is from the joined block now
        foreach (var b in f.Blocks.ToArray())
        {
            foreach (var inst in b.Insts.ToArray())
            {
                if (inst.Op != "phi")
                    continue;
                for (var a = 0; a < inst.Labels.Length; a += 1)
                {
                    if (inst.Labels[a] == toLabel)
                        inst.Labels[a] = fromLabel;
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// The order of the computations in a block
// ---------------------------------------------------------------------------

// A pure computation (or a load, if nothing writes memory before its use) that only one later instruction of its block
// uses moves right before that instruction, with the computation of the first operand last: the value then goes
// through d0 (Regalloc.csh, ForwardedValues) instead of a register of its own. 'x = load; s = d >> 8; x ^ s' becomes
// 's = d >> 8; x = load; x ^ s'.
void OrderOperands(Gen g, IrFunc f)
{
    var uses = LocalUses(g, f);
    var blocks = f.Blocks.ToArray();
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        int n = insts.Length;
        // the index of each result's instruction and of its only user in the block
        var at = Dictionary<string, int>.Create();
        for (var k = 0; k < n; k += 1)
        {
            if (insts[k].Res.Length > 0)
                at.Set(insts[k].Res, k);
        }
        var user = new int[n];
        for (var k = 0; k < n; k += 1)
            user[k] = -1;
        for (var k = 0; k < n; k += 1)
        {
            var inst = insts[k];
            if (inst.Op == "phi")
                continue;
            foreach (var a in inst.Args)
            {
                var v = g.M.Vals.Get(a);
                if (v.Kind == ValKind.Local && at.TryGet(v.Name) is int d && d < k)
                    user[d] = user[d] == -1 ? k : -2; // (-2: more than one use here)
            }
        }
        // which instructions move: single use later in the block; loads only when nothing between writes memory and
        // the user stays where it is
        var moves = new bool[n];
        for (var k = 0; k < n; k += 1)
        {
            var inst = insts[k];
            int u = user[k];
            if (u < 0 || inst.Res.Length == 0 || g.Skip.Contains(inst.Res) || uses.GetOrDefault(inst.Res, 0) != 1)
                continue;
            if (insts[u].Op == "phi")
                continue;
            if (IsCommonOp(inst.Op))
                moves[k] = true;
        }
        for (var k = 0; k < n; k += 1)
        {
            var inst = insts[k];
            int u = user[k];
            if (u < 0 || inst.Op != "load" || inst.Volatile || g.T.IsAggregate(inst.Type) || g.Skip.Contains(inst.Res) ||
                uses.GetOrDefault(inst.Res, 0) != 1 || insts[u].Op == "phi")
                continue;
            // it ends up right before the computation that its users lead to (the first that does not move): nothing
            // up to there may write memory
            int root = u;
            while (moves[root] && user[root] >= 0)
                root = user[root];
            bool clear = true;
            for (var m = k + 1; m < root && clear; m += 1)
                clear = !WritesMemory(insts[m]);
            moves[k] = clear;
        }
        bool any = false;
        for (var k = 0; k < n && !any; k += 1)
            any = moves[k];
        if (!any)
            continue;
        var order = List<IrInst>.Create();
        var done = new bool[n];
        for (var k = 0; k < n; k += 1)
        {
            if (!moves[k])
                EmitWithOperands(g, insts, at, user, moves, done, order, k);
        }
        // (an instruction that moves but whose user was already written cannot happen: users come later)
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = order });
    }
}

// writes instruction k, after the moved computations of its operands (the first operand's last)
void EmitWithOperands(Gen g, IrInst[] insts, Dictionary<string, int> at, int[] user, bool[] moves, bool[] done,
                      List<IrInst> order, int k)
{
    if (done[k])
        return;
    done[k] = true;
    var inst = insts[k];
    if (inst.Op != "phi")
    {
        for (var a = inst.Args.Length - 1; a >= 0; a -= 1)
        {
            var v = g.M.Vals.Get(inst.Args[a]);
            if (v.Kind == ValKind.Local && at.TryGet(v.Name) is int d && moves[d] && user[d] == k)
                EmitWithOperands(g, insts, at, user, moves, done, order, d);
        }
    }
    order.Add(inst);
}

// whether an instruction may write memory (a load must not move past it)
bool WritesMemory(IrInst inst)
{
    return inst.Op == "store" || inst.Op == "call" || inst.Op == "atomicrmw" || inst.Op == "cmpxchg" || inst.Op == "fence" ||
           inst.Volatile;
}

// ---------------------------------------------------------------------------
// Truncations
// ---------------------------------------------------------------------------

// A trunc changes nothing in a 68000 register (an 8- or 16-bit value is its low bits; what reads it as such reads only
// those): the arithmetic, comparisons, casts and stores that use it take the wider value itself. Uses where the wider
// type would matter (calls, returns, phis, selects, aggregates, addresses) keep the trunc.
void FreeTruncations(Gen g, IrFunc f)
{
    var source = Dictionary<string, int>.Create();   // a trunc's result -> its operand
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "trunc" && inst.Res.Length > 0 && !g.Skip.Contains(inst.Res) && IsScalar4(g, inst.Type) &&
                IsScalar4(g, inst.OpType) && g.T.Kind(inst.OpType) == IrKind.Int)
                source.Set(inst.Res, inst.Args[0]);
        }
    }
    if (source.Count() == 0)
        return;
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Res.Length > 0 && g.Skip.Contains(inst.Res))
                continue;
            bool lowBits = IsArithmetic32(g, inst) && inst.Op != "lshr" && inst.Op != "ashr" && inst.Op != "sdiv" &&
                           inst.Op != "udiv" && inst.Op != "srem" && inst.Op != "urem";
            lowBits = lowBits || inst.Op == "icmp" || IsIntCast(inst.Op);
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind != ValKind.Local || !source.ContainsKey(v.Name))
                    continue;
                // a store: only its value (not its address); a shift: only what is shifted (the count is read whole)
                if ((lowBits && !(inst.Op == "shl" && a == 1)) || (inst.Op == "store" && a == 0 && IsScalar4(g, inst.OpType)))
                    inst.Args[a] = source.Get(v.Name);
            }
        }
    }
}
