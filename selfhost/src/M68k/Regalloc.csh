// Register allocation of the 68000 backend (linear scan): the scalar values of a function (up to 32 bits) and its
// scalar variables (allocas whose address is only loaded from and stored to) get the registers d4-d7 and a2-a5 for
// their whole lifetime, if they fit; the others stay in their stack slots. There is no spill code: a value lives either
// in a register or in its slot, everywhere.
//
//   1. Liveness: a data flow analysis over the blocks (a load of a variable uses it, a store defines it; the arguments
//      of a phi are used at the end of the predecessor).
//   2. Intervals: the blocks in their order, every instruction numbered; a value's interval covers every point where it
//      is live (without holes: from its first to its last point).
//   3. Linear scan in the order of the interval starts: a free register of the preferred kind (address registers for
//      pointers), else the one of the active value that is worth least, if the new one is worth more. The worth: the
//      uses and definitions, weighted by the loop nesting (8 per level).

namespace CShift.M68k;

using System;

struct LiveInterval
{
    string Name;
    int Start;
    int End;
    int Weight;
    bool Pointer;
}

void AllocateRegisters(Gen g, IrFunc f)
{
    g.Home.Clear();
    g.Saved.Clear();
    g.Saved.Add("%d2-%d3");
    var blocks = f.Blocks.ToArray();
    int n = blocks.Length;
    var index = Dictionary<string, int>.Create();
    for (var i = 0; i < n; i += 1)
        index.Set(blocks[i].Label, i);

    // ---- the candidates ----
    var allocaSize = Dictionary<string, int>.Create();
    var isPointer = Dictionary<string, bool>.Create();
    var excluded = HashSet<string>.Create();
    foreach (var p in f.Params)
        excluded.Add(p.Name);
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca")
            {
                if (IsScalar4(g, inst.OpType) && (inst.Args.Length == 0 || !IsLocal(g, inst.Args[0])))
                {
                    allocaSize.Set(inst.Res, g.L.Size(inst.OpType));
                    isPointer.Set(inst.Res, g.T.Kind(inst.OpType) == IrKind.Ptr);
                }
                else
                    excluded.Add(inst.Res);
            }
            else if (inst.Res.Length > 0)
            {
                if (IsScalar4(g, inst.Type))
                    isPointer.Set(inst.Res, g.T.Kind(inst.Type) == IrKind.Ptr);
                else
                    excluded.Add(inst.Res);
            }
        }
    }
    // a variable whose address is used otherwise stays in memory
    foreach (var b in blocks)
    {
        foreach (var inst in b.Insts.ToArray())
        {
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind != ValKind.Local)
                    continue;
                var size = allocaSize.TryGet(v.Name);
                if (size is int s)
                {
                    bool plain = (inst.Op == "load" && a == 0 && g.L.Size(inst.Type) == s && IsScalar4(g, inst.Type)) ||
                                 (inst.Op == "store" && a == 1 && g.L.Size(inst.OpType) == s && IsScalar4(g, inst.OpType));
                    if (!plain)
                        excluded.Add(v.Name);
                }
            }
        }
    }

    // ---- loop nesting (for the weights): a branch back to an earlier block ----
    var depth = new int[n];
    var succs = new List<int>[n];
    for (var j = 0; j < n; j += 1)
    {
        succs[j] = List<int>.Create();
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            if (inst.Op != "br" && inst.Op != "switch")
                continue;
            foreach (var label in inst.Labels)
            {
                var target = index.TryGet(label);
                if (target is int i)
                {
                    if (!succs[j].Contains(i))
                        succs[j].Add(i);
                    if (i <= j)
                    {
                        for (var k = i; k <= j; k += 1)
                            depth[k] += 1;
                    }
                }
            }
        }
    }

    // ---- positions, uses and definitions per block ----
    var blockStart = new int[n];
    var blockEnd = new int[n];
    var gen = new HashSet<string>[n];
    var kill = new HashSet<string>[n];
    var phiDefs = new HashSet<string>[n];
    var phiUses = new List<string>[n];   // values that phis of other blocks take from this block (used at its end)
    var weight = Dictionary<string, int>.Create();
    var uses = Dictionary<string, int>.Create();
    var defPos = Dictionary<string, int>.Create();
    var defBlock = Dictionary<string, int>.Create();
    var loads = List<IrInst>.Create();          // loads of variables, with their positions
    var loadPos = List<int>.Create();
    var stores = List<IrInst>.Create();
    var storePos = List<int>.Create();
    var storeBlock = List<int>.Create();
    var lo = Dictionary<string, int>.Create();
    var hi = Dictionary<string, int>.Create();
    int pos = 0;
    for (var j = 0; j < n; j += 1)
    {
        gen[j] = HashSet<string>.Create();
        kill[j] = HashSet<string>.Create();
        phiDefs[j] = HashSet<string>.Create();
        phiUses[j] = List<string>.Create();
    }
    for (var j = 0; j < n; j += 1)
    {
        int d = depth[j] > 3 ? 3 : depth[j];
        int w = d == 0 ? 1 : (d == 1 ? 8 : (d == 2 ? 64 : 512));
        blockStart[j] = pos;
        pos += 1;
        foreach (var inst in blocks[j].Insts.ToArray())
        {
            pos += 1;
            if (inst.Op == "phi")
            {
                if (IsCandidate(inst.Res, isPointer, excluded))
                {
                    phiDefs[j].Add(inst.Res);
                    kill[j].Add(inst.Res);
                    Touch(inst.Res, blockStart[j], w, weight, lo, hi);
                }
                for (var a = 0; a < inst.Args.Length; a += 1)
                {
                    var v = g.M.Vals.Get(inst.Args[a]);
                    if (v.Kind == ValKind.Local)
                        uses.Set(v.Name, uses.GetOrDefault(v.Name, 0) + 1);
                    var from = index.TryGet(inst.Labels[a]);
                    if (v.Kind == ValKind.Local && IsCandidate(v.Name, isPointer, excluded) && from is int pj)
                        phiUses[pj].Add(v.Name);
                }
                continue;
            }
            // uses first (a store's value; a load's variable), then the definition
            if (inst.Op == "load" && IsLocal(g, inst.Args[0]) && allocaSize.ContainsKey(g.M.Vals.Get(inst.Args[0]).Name))
            {
                loads.Add(inst);
                loadPos.Add(pos);
            }
            if (inst.Op == "store" && IsLocal(g, inst.Args[1]) && allocaSize.ContainsKey(g.M.Vals.Get(inst.Args[1]).Name))
            {
                stores.Add(inst);
                storePos.Add(pos);
                storeBlock.Add(j);
            }
            for (var a = 0; a < inst.Args.Length; a += 1)
            {
                var v = g.M.Vals.Get(inst.Args[a]);
                if (v.Kind == ValKind.Local)
                    uses.Set(v.Name, uses.GetOrDefault(v.Name, 0) + 1);
                if (v.Kind != ValKind.Local || !IsCandidate(v.Name, isPointer, excluded))
                    continue;
                if (inst.Op == "store" && a == 1 && allocaSize.ContainsKey(v.Name))
                    continue; // the variable is written, not read
                if (!kill[j].Contains(v.Name))
                    gen[j].Add(v.Name);
                Touch(v.Name, pos, w, weight, lo, hi);
            }
            if (inst.Op == "store" && inst.Args.Length > 1)
            {
                var target = g.M.Vals.Get(inst.Args[1]);
                if (target.Kind == ValKind.Local && allocaSize.ContainsKey(target.Name) && IsCandidate(target.Name, isPointer, excluded))
                {
                    kill[j].Add(target.Name);
                    Touch(target.Name, pos, w, weight, lo, hi);
                }
            }
            if (inst.Res.Length > 0 && inst.Op != "alloca" && IsCandidate(inst.Res, isPointer, excluded))
            {
                defPos.Set(inst.Res, pos);
                defBlock.Set(inst.Res, j);
                kill[j].Add(inst.Res);
                Touch(inst.Res, pos, w, weight, lo, hi);
            }
        }
        pos += 1;
        blockEnd[j] = pos;
        pos += 1;
        foreach (var u in phiUses[j].ToArray())
            Touch(u, blockEnd[j], w, weight, lo, hi);
    }

    // ---- liveness: live-in = gen + (live-out - kill); live-out = the live-ins of the successors (without their
    //      phis) + the phi arguments from this block ----
    var liveIn = new HashSet<string>[n];
    var liveOut = new HashSet<string>[n];
    for (var j = 0; j < n; j += 1)
    {
        liveIn[j] = HashSet<string>.Create();
        liveOut[j] = HashSet<string>.Create();
    }
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (var j = n - 1; j >= 0; j -= 1)
        {
            foreach (var s in succs[j].ToArray())
            {
                foreach (var v in liveIn[s].ToArray())
                {
                    if (!phiDefs[s].Contains(v) && !liveOut[j].Contains(v))
                    {
                        liveOut[j].Add(v);
                        changed = true;
                    }
                }
            }
            foreach (var v in phiUses[j].ToArray())
            {
                if (!liveOut[j].Contains(v))
                {
                    liveOut[j].Add(v);
                    changed = true;
                }
            }
            foreach (var v in gen[j].ToArray())
            {
                if (!liveIn[j].Contains(v))
                {
                    liveIn[j].Add(v);
                    changed = true;
                }
            }
            foreach (var v in liveOut[j].ToArray())
            {
                if (!kill[j].Contains(v) && !liveIn[j].Contains(v))
                {
                    liveIn[j].Add(v);
                    changed = true;
                }
            }
        }
    }
    for (var j = 0; j < n; j += 1)
    {
        foreach (var v in liveIn[j].ToArray())
            Touch(v, blockStart[j], 0, weight, lo, hi);
        foreach (var v in liveOut[j].ToArray())
            Touch(v, blockEnd[j], 0, weight, lo, hi);
    }

    // ---- values that share their variable's register ----
    var nonLocal = HashSet<string>.Create();
    for (var j = 0; j < n; j += 1)
    {
        foreach (var v in liveIn[j].ToArray())
            nonLocal.Add(v);
        foreach (var v in liveOut[j].ToArray())
            nonLocal.Add(v);
    }
    var aliasOf = Dictionary<string, string>.Create();
    var aliasEnd = Dictionary<string, int>.Create();   // the last use of a load that shares its variable's register
    // a load whose value is used in its block before the variable is written again: the variable's register
    for (var i = 0; i < loads.Count(); i += 1)
    {
        var ld = loads.Get(i);
        string t = ld.Res;
        string variable = g.M.Vals.Get(ld.Args[0]).Name;
        if (!IsCandidate(t, isPointer, excluded) || !IsCandidate(variable, isPointer, excluded) || nonLocal.Contains(t) || !hi.ContainsKey(t))
            continue;
        int from = loadPos.Get(i);
        int until = hi.Get(t);
        bool written = false;
        for (var k = 0; k < stores.Count() && !written; k += 1)
        {
            int sp = storePos.Get(k);
            if (sp > from && sp <= until && g.M.Vals.Get(stores.Get(k).Args[1]).Name == variable)
                written = true;
        }
        if (written)
            continue;
        Touch(variable, until, 0, weight, lo, hi);
        weight.Set(variable, weight.GetOrDefault(variable, 0) + weight.GetOrDefault(t, 0));
        aliasOf.Set(t, variable);
        aliasEnd.Set(t, until);
        lo.Remove(t);
        hi.Remove(t);
    }
    // a value that is only stored into a variable, which is not read in between: computed in the variable's register
    for (var k = 0; k < stores.Count(); k += 1)
    {
        var st = stores.Get(k);
        var val = g.M.Vals.Get(st.Args[0]);
        string variable = g.M.Vals.Get(st.Args[1]).Name;
        if (val.Kind != ValKind.Local || !IsCandidate(val.Name, isPointer, excluded) || !IsCandidate(variable, isPointer, excluded))
            continue;
        string x = val.Name;
        if (aliasOf.ContainsKey(x) || nonLocal.Contains(x) || uses.GetOrDefault(x, 0) != 1 || !defPos.ContainsKey(x) ||
            defBlock.Get(x) != storeBlock.Get(k) || !lo.ContainsKey(x))
            continue;
        int d = defPos.Get(x);
        int sp = storePos.Get(k);
        bool read = false;
        for (var i = 0; i < loads.Count() && !read; i += 1)
        {
            int lp = loadPos.Get(i);
            var ld = loads.Get(i);
            if (g.M.Vals.Get(ld.Args[0]).Name != variable)
                continue;
            // a load in between, or an earlier load whose shared value is still used after the definition
            if (lp > d && lp < sp)
                read = true;
            var ali = aliasOf.TryGet(ld.Res);
            if (ali is string av && av == variable && lp <= d)
            {
                if (aliasEnd.GetOrDefault(ld.Res, 0) > d)
                    read = true;
            }
        }
        for (var i = 0; i < stores.Count() && !read; i += 1)
        {
            int op = storePos.Get(i);
            if (op > d && op < sp && g.M.Vals.Get(stores.Get(i).Args[1]).Name == variable)
                read = true;
        }
        if (read)
            continue;
        Touch(variable, d, 0, weight, lo, hi);
        weight.Set(variable, weight.GetOrDefault(variable, 0) + weight.GetOrDefault(x, 0));
        aliasOf.Set(x, variable);
        lo.Remove(x);
        hi.Remove(x);
    }

    // ---- linear scan ----
    var intervals = List<LiveInterval>.Create();
    foreach (var entry in lo.Entries())
    {
        string name = entry.Key;
        intervals.Add(LiveInterval { Name = name, Start = entry.Value, End = hi.Get(name), Weight = weight.GetOrDefault(name, 0),
                                     Pointer = isPointer.GetOrDefault(name, false) });
    }
    var sorted = intervals.ToArray();
    for (var i = 1; i < sorted.Length; i += 1)
    {
        var x = sorted[i];
        int k = i - 1;
        while (k >= 0 && (sorted[k].Start > x.Start || (sorted[k].Start == x.Start && sorted[k].Name.CompareTo(x.Name) > 0)))
        {
            sorted[k + 1] = sorted[k];
            k -= 1;
        }
        sorted[k + 1] = x;
    }
    string[] regs = ["%d4", "%d5", "%d6", "%d7", "%a2", "%a3", "%a4", "%a5"];
    var owner = new int[8];     // the interval in each register (-1: free)
    var used = new bool[8];
    for (var r = 0; r < 8; r += 1)
        owner[r] = -1;
    var assigned = new int[sorted.Length];
    for (var i = 0; i < sorted.Length; i += 1)
    {
        assigned[i] = -1;
        var cur = sorted[i];
        if (cur.Weight < 2)
            continue; // not worth a register
        // registers whose value is over
        for (var r = 0; r < 8; r += 1)
        {
            if (owner[r] >= 0 && sorted[owner[r]].End < cur.Start)
                owner[r] = -1;
        }
        int pick = FreeRegister(owner, cur.Pointer);
        if (pick < 0)
        {
            // the active value that is worth least (per point of its interval) gives its register up
            int worst = -1;
            for (var r = 0; r < 8; r += 1)
            {
                if (worst < 0 || Worth(sorted[owner[r]]) < Worth(sorted[owner[worst]]))
                    worst = r;
            }
            if (worst >= 0 && Worth(sorted[owner[worst]]) < Worth(cur))
            {
                assigned[owner[worst]] = -1;
                pick = worst;
            }
        }
        if (pick >= 0)
        {
            owner[pick] = i;
            assigned[i] = pick;
        }
    }
    for (var i = 0; i < sorted.Length; i += 1)
    {
        if (assigned[i] >= 0)
        {
            g.Home.Set(sorted[i].Name, regs[assigned[i]]);
            used[assigned[i]] = true;
        }
    }
    foreach (var entry in aliasOf.Entries())
    {
        var home = g.Home.TryGet(entry.Value);
        if (home is string reg)
            g.Home.Set(entry.Key, reg);
    }
    for (var r = 0; r < 8; r += 1)
    {
        if (used[r])
            g.Saved.Add(regs[r]);
    }
}

bool IsCandidate(string name, Dictionary<string, bool> isPointer, HashSet<string> excluded)
{
    return isPointer.ContainsKey(name) && !excluded.Contains(name);
}

void Touch(string name, int at, int w, Dictionary<string, int> weight, Dictionary<string, int> lo, Dictionary<string, int> hi)
{
    var l = lo.TryGet(name);
    if (!(l is int low) || at < low)
        lo.Set(name, at);
    var h = hi.TryGet(name);
    if (!(h is int high) || at > high)
        hi.Set(name, at);
    if (w > 0)
        weight.Set(name, weight.GetOrDefault(name, 0) + w);
}

// the weight per length of the interval (short, much used values first), scaled to keep integers
int Worth(LiveInterval iv)
{
    int length = iv.End - iv.Start + 1;
    return iv.Weight * 256 / (length < 1 ? 1 : length) + iv.Weight;
}

// a free register: address registers for pointers, data registers for the rest (then the other kind)
int FreeRegister(int[] owner, bool pointer)
{
    int first = pointer ? 4 : 0;
    int second = pointer ? 0 : 4;
    for (var r = first; r < first + 4; r += 1)
    {
        if (owner[r] < 0)
            return r;
    }
    for (var r = second; r < second + 4; r += 1)
    {
        if (owner[r] < 0)
            return r;
    }
    return -1;
}
