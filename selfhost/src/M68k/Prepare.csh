// Before a function is written: simple improvements of its IR.
//
//   * Constant folding: comparisons of two constants, and/or/xor of constants (the division checks of CShift compare
//     the divisor with -1 even when it is a constant) - the uses get the constant, the instruction is skipped.
//   * Variables written once: a scalar variable stored once (a parameter's copy, mostly, or a local variable that is
//     never assigned again) and otherwise only read, where the store comes before every load (it dominates them), is
//     replaced by the stored value.
//   * Lengths: the length of an array or string (__cs_len) is computed once per value, right after the value: a block
//     never changes its length, so every bounds check of the same array uses the same length (also in loops).
//   * Conditions: '&&' and '||' in a condition become branches (no bool is made: the block of the phi that joins them
//     goes away), and a branch on '!c' branches on c the other way round.
//   * What is known (Facts.csh): loads of variables whose value is known, computations made twice, comparisons whose
//     outcome is known, checked arithmetic that cannot overflow, branches on constants, unreachable and joinable blocks.
//   * Address folding: a getelementptr whose only uses are loads and stores (one, or the load and the store of
//     'a[i] ^= x') is not computed on its own: each access uses the 68000's addressing modes, (d16,An) or (d8,An,Dn.l).

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
    g.NoWrap.Clear();
    PromoteSingleStores(g, f);
    InlineCalls(g, f);
    PromoteSingleStores(g, f); // (the variables of the inlined functions)
    ForwardLoads(g, f);
    ShareLengths(g, f);
    FoldConstants(g, f); // (constant shift counts and masks for the ranges)
    CommonValues(g, f);
    KnownConditions(g, f);
    CommonValues(g, f);  // (the checked operations that became plain ones)
    KnownConditions(g, f);
    SimplifyBranches(g, f);
    FoldConstants(g, f);
    SimplifyBranches(g, f);
    ThreadConditions(g, f);
    FreeTruncations(g, f);
    RemoveDeadCode(g, f);
    OrderOperands(g, f);
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
    var checkedConst = Dictionary<string, int[]>.Create(); // a checked add/sub of constants -> { result, overflow }
    int i1 = g.T.IntType(1);
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "extractvalue" && inst.Res.Length > 0 && inst.Args.Length == 1 && inst.Cases.Length == 1 &&
                IsLocal(g, inst.Args[0]))
            {
                var folded = checkedConst.TryGet(g.M.Vals.Get(inst.Args[0]).Name);
                if (folded is int[] parts && inst.Cases[0] >= 0 && inst.Cases[0] <= 1)
                {
                    known.Set(inst.Res, parts[(int)inst.Cases[0]]);
                    g.Skip.Add(inst.Res);
                    continue;
                }
            }
            if (inst.Op == "call" && inst.Res.Length > 0 && inst.Args.Length == 2 && inst.Callee >= 0)
            {
                // llvm.[su](add|sub).with.overflow of two constants: the result and the flag are constants
                for (var a = 0; a < 2; a += 1)
                {
                    var v = g.M.Vals.Get(inst.Args[a]);
                    if (v.Kind == ValKind.Local && known.TryGet(v.Name) is int ci)
                        inst.Args[a] = ci;
                }
                var callee = g.M.Vals.Get(inst.Callee);
                int ot = g.M.Vals.Get(inst.Args[0]).Type;
                int64 ox = 0;
                int64 oy = 0;
                if (callee.Kind == ValKind.Global && callee.Name.StartsWith("llvm.") && callee.Name.Contains(".with.overflow.") &&
                    !callee.Name.Contains("mul") && g.T.Kind(ot) == IrKind.Int && g.T.Bits(ot) <= 32 &&
                    ConstInt(g, inst.Args[0], ref ox) && ConstInt(g, inst.Args[1], ref oy))
                {
                    int obits = g.T.Bits(ot);
                    bool osigned = callee.Name.StartsWith("llvm.s");
                    int64 ox2 = Normalize(ox, obits, osigned);
                    int64 oy2 = Normalize(oy, obits, osigned);
                    int64 sum = callee.Name.Contains("add") ? ox2 + oy2 : ox2 - oy2;
                    bool overflow = Normalize(sum, obits, osigned) != sum;
                    int value = g.M.AddVal(IrVal { Kind = ValKind.Int, Type = ot, Int = Normalize(sum, obits, false) });
                    int flag = g.M.AddVal(IrVal { Kind = ValKind.Int, Type = i1, Int = overflow ? 1 : 0 });
                    checkedConst.Set(inst.Res, [value, flag]);
                    g.Skip.Add(inst.Res);
                }
                continue;
            }
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
            if (inst.Op == "inttoptr" && inst.Res.Length > 0 && inst.Args.Length == 1)
            {
                // a constant address (a custom chip register, ...): loads and stores use it as an absolute address
                int64 address = 0;
                if (ConstInt(g, inst.Args[0], ref address))
                {
                    known.Set(inst.Res, g.M.AddVal(IrVal { Kind = ValKind.Int, Type = inst.Type, Int = Normalize(address, 32, false) }));
                    g.Skip.Add(inst.Res);
                }
                continue;
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

void PromoteSingleStores(Gen g, IrFunc f)
{
    if (f.Blocks.Count() == 0)
        return;
    var blocks = f.Blocks.ToArray();
    // the candidates: allocas of one scalar
    var state = Dictionary<string, int>.Create();   // alloca -> 0 not stored yet, 1 stored once, -1 not promotable
    var stored = Dictionary<string, int>.Create();  // alloca -> the stored value
    var storeType = Dictionary<string, int>.Create();
    var storeAt = Dictionary<string, int[]>.Create(); // alloca -> { block, instruction } of the store
    var loadsOf = List<string>.Create();             // the loads: the variable, and where they are
    var loadAt = List<int[]>.Create();
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca" && (inst.Args.Length == 0 || !IsLocal(g, inst.Args[0])) && IsScalar4(g, inst.OpType))
                state.Set(inst.Res, 0);
        }
    }
    if (state.Count() == 0)
        return;
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Callee >= 0)
                Disqualify(g, state, inst.Callee);
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind != ValKind.Local || !state.ContainsKey(v.Name))
                    continue;
                int st = state.Get(v.Name);
                if (st < 0)
                    continue;
                if (inst.Op == "store" && a == 1)
                {
                    // once (before every load: checked below)
                    if (st == 0 && g.L.Size(inst.OpType) == 4)
                    {
                        state.Set(v.Name, 1);
                        stored.Set(v.Name, inst.Args[0]);
                        storeType.Set(v.Name, inst.OpType);
                        storeAt.Set(v.Name, [j, k]);
                    }
                    else
                        state.Set(v.Name, -1);
                }
                else if (inst.Op == "load" && a == 0)
                {
                    // read after the store, as what was stored
                    if (st != 1 || inst.Type != storeType.Get(v.Name))
                        state.Set(v.Name, -1);
                    else
                    {
                        loadsOf.Add(v.Name);
                        loadAt.Add([j, k]);
                    }
                }
                else
                    state.Set(v.Name, -1);
            }
        }
    }
    // the store must dominate every load: earlier in the same block, or in a block that dominates the load's block
    var idom = Dominators(f);
    for (var i = 0; i < loadsOf.Count(); i += 1)
    {
        string name = loadsOf.Get(i);
        if (state.GetOrDefault(name, -1) != 1)
            continue;
        var s = storeAt.Get(name);
        var l = loadAt.Get(i);
        bool before = s[0] == l[0] ? s[1] < l[1] : Dominates(idom, s[0], l[0]);
        if (!before)
            state.Set(name, -1);
    }
    // the loads become the stored value
    var value = Dictionary<string, int>.Create();
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op != "load")
                continue;
            var v = g.M.Vals.Get(inst.Args[0]);
            if (v.Kind == ValKind.Local && state.GetOrDefault(v.Name, -1) == 1)
                value.Set(inst.Res, stored.Get(v.Name));
        }
    }
    if (value.Count() == 0)
        return;
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var kept = List<IrInst>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (inst.Op == "alloca" && state.GetOrDefault(inst.Res, -1) == 1)
                continue;
            if (inst.Op == "store" && IsLocal(g, inst.Args[1]) && state.GetOrDefault(g.M.Vals.Get(inst.Args[1]).Name, -1) == 1)
                continue;
            if (inst.Op == "load" && value.ContainsKey(inst.Res))
                continue;
            for (var a = 0; a < inst.Args.Length; a += 1)
                inst.Args[a] = Promoted(g, value, inst.Args[a]);
            var copy = inst;
            if (inst.Callee >= 0)
                copy.Callee = Promoted(g, value, inst.Callee);
            kept.Add(copy);
        }
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
    }
}

// a value, or what was stored in the variable it was loaded from (through loads of such values)
int Promoted(Gen g, Dictionary<string, int> value, int vi)
{
    int at = vi;
    for (var guard = 0; guard < 1000; guard += 1)
    {
        var v = g.M.Vals.Get(at);
        if (v.Kind != ValKind.Local)
            return at;
        var next = value.TryGet(v.Name);
        int n = next is int found ? found : -1;
        if (n < 0)
            return at;
        at = n;
    }
    return at;
}

// The immediate dominator of every block (Cooper, Harvey and Kennedy, "A Simple, Fast Dominance Algorithm"): -1 for
// the entry block and for the blocks that cannot be reached.
int[] Dominators(IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    var index = Dictionary<string, int>.Create();
    for (var i = 0; i < n; i += 1)
        index.Set(blocks[i].Label, i);
    var succs = new List<int>[n];
    var preds = new List<int>[n];
    for (var i = 0; i < n; i += 1)
    {
        succs[i] = List<int>.Create();
        preds[i] = List<int>.Create();
    }
    for (var i = 0; i < n; i += 1)
    {
        foreach (var inst in blocks[i].Insts.ToArray())
        {
            if (inst.Op != "br" && inst.Op != "switch")
                continue;
            foreach (var label in inst.Labels)
            {
                if (index.TryGet(label) is int t && !succs[i].Contains(t))
                {
                    succs[i].Add(t);
                    preds[t].Add(i);
                }
            }
        }
    }
    // the reverse postorder of a depth-first search from the entry
    var order = new int[n];   // block -> its number in reverse postorder (-1: not reached)
    var post = List<int>.Create();
    var visited = new bool[n];
    var stack = List<int>.Create();
    var next = new int[n];    // the next successor to visit
    for (var i = 0; i < n; i += 1)
        order[i] = -1;
    if (n > 0)
    {
        stack.Add(0);
        visited[0] = true;
    }
    while (stack.Count() > 0)
    {
        int b = stack.Get(stack.Count() - 1);
        if (next[b] < succs[b].Count())
        {
            int s = succs[b].Get(next[b]);
            next[b] += 1;
            if (!visited[s])
            {
                visited[s] = true;
                stack.Add(s);
            }
        }
        else
        {
            stack.RemoveAt(stack.Count() - 1);
            post.Add(b);
        }
    }
    int reached = post.Count();
    var rpo = new int[reached];
    for (var i = 0; i < reached; i += 1)
    {
        rpo[i] = post.Get(reached - 1 - i);
        order[rpo[i]] = i;
    }
    var idom = new int[n];
    for (var i = 0; i < n; i += 1)
        idom[i] = -1;
    if (n == 0)
        return idom;
    idom[0] = 0;
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (var r = 1; r < reached; r += 1)
        {
            int b = rpo[r];
            int found = -1;
            foreach (var p in preds[b].ToArray())
            {
                if (idom[p] < 0)
                    continue;
                if (found < 0)
                    found = p;
                else
                {
                    // the nearest common dominator of p and found
                    int x = p;
                    int y = found;
                    while (x != y)
                    {
                        while (order[x] > order[y])
                            x = idom[x];
                        while (order[y] > order[x])
                            y = idom[y];
                    }
                    found = x;
                }
            }
            if (found >= 0 && idom[b] != found)
            {
                idom[b] = found;
                changed = true;
            }
        }
    }
    idom[0] = -1;
    return idom;
}

// whether block a dominates block b (a block dominates itself)
bool Dominates(int[] idom, int a, int b)
{
    int x = b;
    for (var guard = 0; guard <= idom.Length; guard += 1)
    {
        if (x == a)
            return true;
        if (x <= 0)
            return false; // the entry, or a block that cannot be reached
        x = idom[x];
    }
    return false;
}

// The length of an array or string (__cs_len), computed once per value instead of at every bounds check:
//   1. a call that an earlier one of the same value dominates becomes that one's result (the program read the length
//      there already);
//   2. the calls in a loop that the value comes from outside of become one right after the value - if it is surely a
//      whole block there: a parameter, a loaded value, a phi or what a function returned (not the raw memory of an
//      allocation, whose length is written after it: an inlined __cs_alloc). A block never changes its length, and that
//      of null is 0.
void ShareLengths(Gen g, IrFunc f)
{
    var blocks = f.Blocks.ToArray();
    bool any = false;
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
            any = any || IsLengthCall(g, inst);
    }
    if (!any)
        return;
    var idom = Dominators(f);
    var depth = LoopDepth(f);
    var replaced = Dictionary<string, int>.Create();   // a call's result -> the value that replaces it

    // 1. calls dominated by an earlier call of the same value
    var keptName = List<string>.Create();   // the calls that stay: the value, where, the result
    var keptAt = List<int[]>.Create();
    var keptRes = List<int>.Create();
    var resultOf = Dictionary<string, int>.Create();
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (!IsLengthCall(g, inst))
                continue;
            string name = g.M.Vals.Get(inst.Args[0]).Name;
            int by = -1;
            for (var i = 0; i < keptName.Count() && by < 0; i += 1)
            {
                var at = keptAt.Get(i);
                if (keptName.Get(i) == name && (at[0] == j ? at[1] < k : Dominates(idom, at[0], j)))
                    by = keptRes.Get(i);
            }
            if (by >= 0)
                replaced.Set(inst.Res, by);
            else
            {
                keptName.Add(name);
                keptAt.Add([j, k]);
                keptRes.Add(ResultValue(g, inst));
            }
        }
    }

    // 2. the definitions of the values that are whole blocks where they are defined
    var defBlock = Dictionary<string, int>.Create();
    var defAfter = Dictionary<string, int>.Create();   // -1: at the start of the block (after its phis and allocas)
    foreach (var p in f.Params)
    {
        defBlock.Set(p.Name, 0);
        defAfter.Set(p.Name, -1);
    }
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var insts = blocks[j].Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Res.Length == 0)
                continue;
            if (inst.Op == "phi")
            {
                defBlock.Set(inst.Res, j);
                defAfter.Set(inst.Res, -1);
            }
            else if (inst.Op == "load" || (inst.Op == "call" && !IsRawAllocation(g, inst)))
            {
                defBlock.Set(inst.Res, j);
                defAfter.Set(inst.Res, k);
            }
        }
    }
    var shared = Dictionary<string, int>.Create();   // value -> its length, computed after it
    var argOf = Dictionary<string, int>.Create();
    int callee = -1;
    int lengthType = 0;
    for (var i = 0; i < keptName.Count(); i += 1)
    {
        string name = keptName.Get(i);
        int j = keptAt.Get(i)[0];
        if (!defBlock.ContainsKey(name) || depth[j] <= depth[defBlock.Get(name)])
            continue;
        var call = blocks[j].Insts.Get(keptAt.Get(i)[1]);
        if (!shared.ContainsKey(name))
        {
            shared.Set(name, g.M.AddVal(IrVal { Kind = ValKind.Local, Type = call.Type, Name = name + ".len" }));
            argOf.Set(name, call.Args[0]);
            callee = call.Callee;
            lengthType = call.Type;
        }
        replaced.Set(call.Res, shared.Get(name));
    }
    if (replaced.Count() == 0)
        return;
    for (var j = 0; j < blocks.Length; j += 1)
    {
        var kept = List<IrInst>.Create();
        var insts = blocks[j].Insts.ToArray();
        int start = 0;
        while (start < insts.Length && (insts[start].Op == "phi" || insts[start].Op == "alloca"))
            start += 1;
        for (var k = 0; k < insts.Length; k += 1)
        {
            if (k == start)
                AddLengths(g, kept, shared, argOf, defBlock, defAfter, j, -1, callee, lengthType);
            var inst = insts[k];
            if (inst.Res.Length > 0 && replaced.ContainsKey(inst.Res))
                continue;
            kept.Add(inst);
            if (k >= start)
                AddLengths(g, kept, shared, argOf, defBlock, defAfter, j, k, callee, lengthType);
        }
        f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
    }
    foreach (var entry in replaced.Entries())
        ReplaceUses(g, f, entry.Key, entry.Value);
}

// A block that only joins the parts of '&&' or '||' - a phi of i1 and a branch on it - is left out: a predecessor
// whose part is a constant branches straight to where that constant leads, one that ends in 'br label %join' branches
// on its value (a compare that the code generator then writes with its branch). A branch on 'xor i1 %c, true' (a '!'
// used only there) branches on %c with its targets swapped.
void ThreadConditions(Gen g, IrFunc f)
{
    bool changed = true;
    for (var guard = 0; changed && guard < 1000; guard += 1)
    {
        changed = false;
        var uses = LocalUses(g, f);
        var blocks = f.Blocks.ToArray();
        var index = Dictionary<string, int>.Create();
        for (var i = 0; i < blocks.Length; i += 1)
            index.Set(blocks[i].Label, i);
        // '!c' before a branch
        for (var j = 0; j < blocks.Length; j += 1)
        {
            var insts = blocks[j].Insts.ToArray();
            int n = insts.Length;
            if (n < 2)
                continue;
            var br = insts[n - 1];
            var not = insts[n - 2];
            if (br.Op != "br" || br.Labels.Length != 2 || not.Op != "xor" || not.Res.Length == 0 || g.Skip.Contains(not.Res) ||
                g.T.Bits(not.Type) != 1 || !IsLocal(g, br.Args[0]) || g.M.Vals.Get(br.Args[0]).Name != not.Res ||
                uses.GetOrDefault(not.Res, 0) != 1)
                continue;
            int c = -1;
            if (IsTrue(g, not.Args[1]))
                c = not.Args[0];
            else if (IsTrue(g, not.Args[0]))
                c = not.Args[1];
            if (c < 0)
                continue;
            var kept = List<IrInst>.Create();
            for (var k = 0; k < n - 2; k += 1)
                kept.Add(insts[k]);
            kept.Add(IrInst { Op = "br", Res = "", Type = 0, OpType = br.OpType, Args = [c], Pred = "",
                              Labels = [br.Labels[1], br.Labels[0]], Cases = new int64[0], Callee = -1, Volatile = false });
            f.Blocks.Set(j, IrBlock { Label = blocks[j].Label, Insts = kept });
            changed = true;
        }
        if (changed)
            continue;
        // the join of '&&' / '||'
        for (var j = 1; j < blocks.Length && !changed; j += 1)
        {
            var insts = blocks[j].Insts.ToArray();
            if (insts.Length != 2 || insts[0].Op != "phi" || insts[1].Op != "br" || insts[1].Labels.Length != 2)
                continue;
            var phi = insts[0];
            var br = insts[1];
            if (g.T.Bits(phi.Type) != 1 || !IsLocal(g, br.Args[0]) || g.M.Vals.Get(br.Args[0]).Name != phi.Res ||
                uses.GetOrDefault(phi.Res, 0) != 1)
                continue;
            string join = blocks[j].Label;
            string yes = br.Labels[0];
            string no = br.Labels[1];
            if (yes == join || no == join || HasPhiFrom(f, yes, join) || HasPhiFrom(f, no, join))
                continue;
            bool can = true;
            for (var a = 0; a < phi.Args.Length && can; a += 1)
            {
                int p = index.GetOrDefault(phi.Labels[a], -1);
                if (p < 0 || p == j)
                {
                    can = false;
                    continue;
                }
                var pinsts = blocks[p].Insts.ToArray();
                var term = pinsts[pinsts.Length - 1];
                bool constant = g.M.Vals.Get(phi.Args[a]).Kind == ValKind.Int;
                if (term.Op != "br" || (!constant && term.Labels.Length != 1))
                    can = false;
            }
            if (!can)
                continue;
            for (var a = 0; a < phi.Args.Length; a += 1)
            {
                int p = index.Get(phi.Labels[a]);
                var pinsts = blocks[p].Insts.ToArray();
                var term = pinsts[pinsts.Length - 1];
                var v = g.M.Vals.Get(phi.Args[a]);
                IrInst next;
                if (v.Kind == ValKind.Int)
                {
                    var labels = new string[term.Labels.Length];
                    for (var l = 0; l < labels.Length; l += 1)
                        labels[l] = term.Labels[l] == join ? (v.Int != 0 ? yes : no) : term.Labels[l];
                    next = IrInst { Op = "br", Res = "", Type = 0, OpType = term.OpType, Args = term.Args, Pred = "",
                                    Labels = labels, Cases = new int64[0], Callee = -1, Volatile = false };
                }
                else
                    next = IrInst { Op = "br", Res = "", Type = 0, OpType = phi.Type, Args = [phi.Args[a]], Pred = "",
                                    Labels = [yes, no], Cases = new int64[0], Callee = -1, Volatile = false };
                var kept = List<IrInst>.Create();
                for (var k = 0; k < pinsts.Length - 1; k += 1)
                    kept.Add(pinsts[k]);
                kept.Add(next);
                f.Blocks.Set(p, IrBlock { Label = blocks[p].Label, Insts = kept });
            }
            f.Blocks.RemoveAt(j);
            changed = true;
        }
    }
}

bool IsTrue(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    return v.Kind == ValKind.Int && v.Int != 0;
}

// whether a block has a phi that takes a value from the block 'from'
bool HasPhiFrom(IrFunc f, string label, string from)
{
    foreach (var b in f.Blocks.ToArray())
    {
        if (b.Label != label)
            continue;
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op != "phi")
                continue;
            foreach (var l in inst.Labels)
            {
                if (l == from)
                    return true;
            }
        }
    }
    return false;
}

// how often each local value is used (the skipped instructions not counted)
Dictionary<string, int> LocalUses(Gen g, IrFunc f)
{
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
    return uses;
}

// the value an instruction defines (a new value that names its result)
int ResultValue(Gen g, IrInst inst)
{
    return g.M.AddVal(IrVal { Kind = ValKind.Local, Type = inst.Type, Name = inst.Res });
}

// a call that returns raw memory: what it points to is filled in after it (the header of a block)
bool IsRawAllocation(Gen g, IrInst inst)
{
    if (inst.Callee < 0)
        return true;
    var c = g.M.Vals.Get(inst.Callee);
    return c.Kind != ValKind.Global || c.Name == "calloc" || c.Name == "malloc" || c.Name == "realloc";
}

// the shared lengths of the values defined at this place (after instruction k of block j; k = -1: its start)
void AddLengths(Gen g, List<IrInst> kept, Dictionary<string, int> shared, Dictionary<string, int> argOf,
                Dictionary<string, int> defBlock, Dictionary<string, int> defAfter, int j, int k, int callee, int lengthType)
{
    foreach (var entry in shared.Entries())
    {
        if (defBlock.Get(entry.Key) != j || defAfter.Get(entry.Key) != k)
            continue;
        kept.Add(IrInst { Op = "call", Res = g.M.Vals.Get(entry.Value).Name, Type = lengthType, OpType = lengthType,
                          Args = [argOf.Get(entry.Key)], Pred = "", Labels = new string[0], Cases = new int64[0],
                          Callee = callee, Volatile = false });
    }
}

bool IsLengthCall(Gen g, IrInst inst)
{
    if (inst.Op != "call" || inst.Callee < 0 || inst.Args.Length != 1 || inst.Res.Length == 0)
        return false;
    var c = g.M.Vals.Get(inst.Callee);
    return c.Kind == ValKind.Global && c.Name == "__cs_len" && IsLocal(g, inst.Args[0]);
}

void Disqualify(Gen g, Dictionary<string, int> state, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local && state.ContainsKey(v.Name))
        state.Set(v.Name, -1);
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
    var accesses = Dictionary<string, int>.Create();   // the uses as the address of a scalar load or store
    var allocas = HashSet<string>.Create();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca")
                allocas.Add(inst.Res);
            if ((inst.Op == "load" || inst.Op == "store") && IsScalar4(g, inst.Op == "load" ? inst.Type : inst.OpType))
            {
                var ptr = g.M.Vals.Get(inst.Args[inst.Op == "load" ? 0 : 1]);
                if (ptr.Kind == ValKind.Local)
                    accesses.Set(ptr.Name, accesses.GetOrDefault(ptr.Name, 0) + 1);
            }
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
    // the geps of the function (a gep's single use may be in a later block: its operands are values that do not change)
    var geps = List<IrInst>.Create();
    var gepAt = Dictionary<string, int>.Create();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "getelementptr" && !g.Skip.Contains(inst.Res))
            {
                gepAt.Set(inst.Res, geps.Count());
                geps.Add(inst);
            }
        }
    }
    var insts = geps.ToArray();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op != "load" && inst.Op != "store")
                continue;
            int t = inst.Op == "load" ? inst.Type : inst.OpType;
            if (!IsScalar4(g, t))
                continue;
            int pi = inst.Op == "load" ? inst.Args[0] : inst.Args[1];
            var p = g.M.Vals.Get(pi);
            // (all uses of the address are loads and stores: each one uses the addressing mode, as in 'a[i] ^= x')
            if (p.Kind != ValKind.Local || uses.GetOrDefault(p.Name, 0) != accesses.GetOrDefault(p.Name, 0))
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
    // an index of 32 bits that is not scaled: straight from its register
    var iv = g.M.Vals.Get(fold.Index);
    if (fold.IndexBits == 32 && fold.Stride == 1 && iv.Kind == ValKind.Local && g.Home.TryGet(iv.Name) is string ir &&
        (ir.StartsWith("%d") || ir.StartsWith("%a")))
        return "(" + fold.Offset.ToString() + "," + baseReg + "," + ir + ".l)";
    Load32(g, fold.Index, "%d1");
    if (fold.IndexBits < 32)
        Extend(g, "%d1", fold.IndexBits, true);
    ScaleD1(g, fold.Stride);
    return "(" + fold.Offset.ToString() + "," + baseReg + ",%d1.l)";
}
