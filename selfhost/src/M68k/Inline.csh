// Inlining of small functions (before the other preparations of a function): the call's block is split at the call,
// a copy of the callee's blocks (values and labels renamed) goes in between; its returns branch to the rest of the
// block, where a phi takes the result (under the call's name). The folding and the register allocation then work
// across what used to be a call: no arguments on the stack, no frame, no saved registers.

namespace CShift.M68k;

using System;

const int InlineLimit = 40;     // the most instructions a function may have to be inlined
const int InlineBudget = 40;    // inlined calls per function

void InlineCalls(Gen g, IrFunc f)
{
    int budget = InlineBudget;
    bool changed = true;
    while (changed && budget > 0)
    {
        changed = false;
        for (var bi = 0; bi < f.Blocks.Count() && !changed; bi += 1)
        {
            var insts = f.Blocks.Get(bi).Insts.ToArray();
            for (var k = 0; k < insts.Length; k += 1)
            {
                var inst = insts[k];
                if (inst.Op != "call" || inst.Callee < 0)
                    continue;
                var callee = g.M.Vals.Get(inst.Callee);
                if (callee.Kind != ValKind.Global || callee.Name == f.Name)
                    continue;
                var fi = g.M.FuncIndex.TryGet(callee.Name);
                int index = fi is int found ? found : -1;
                if (index < 0)
                    continue;
                var fn = g.M.Funcs.Get(index);
                if (!Inlinable(g, fn) || fn.Params.Length != inst.Args.Length)
                    continue;
                InlineAt(g, f, bi, k, fn);
                changed = true;
                budget -= 1;
                break;
            }
        }
    }
}

bool Inlinable(Gen g, IrFunc fn)
{
    if (!fn.Defined || fn.Varargs || fn.Blocks.Count() == 0)
        return false;
    if (fn.Name == "__cs_len")
        return false; // written inline by the code generator (better than its IR)
    if (fn.Ret != g.T.Void && g.T.IsAggregate(fn.Ret))
        return false;
    int count = 0;
    bool returns = false;
    foreach (var b in fn.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            count += 1;
            if (inst.Op == "ret")
                returns = true;
            if (count > InlineLimit)
                return false;
            if (inst.Op == "call" && inst.Callee >= 0)
            {
                var c = g.M.Vals.Get(inst.Callee);
                if (c.Kind == ValKind.Global && c.Name == fn.Name)
                    return false; // recursive
            }
        }
    }
    return returns; // (a function that never returns stays a call)
}

struct InlineCopy
{
    Dictionary<string, int> Values;   // callee value name -> caller value
    string Tag;
}

int RemapValue(Gen g, InlineCopy copy, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind != ValKind.Local)
        return vi;
    var found = copy.Values.TryGet(v.Name);
    if (found is int mapped)
        return mapped;
    int fresh = g.M.AddVal(IrVal { Kind = ValKind.Local, Type = v.Type, Name = v.Name + "." + copy.Tag });
    copy.Values.Set(v.Name, fresh);
    return fresh;
}

void InlineAt(Gen g, IrFunc f, int bi, int k, IrFunc fn)
{
    string tag = "in" + g.NewLabel().Substring(2).ToString();
    var block = f.Blocks.Get(bi);
    var insts = block.Insts.ToArray();
    var call = insts[k];
    string contLabel = block.Label + "." + tag + "r"; // (never a copied label: those end in the tag)

    // the rest of the block
    var cont = List<IrInst>.Create();
    for (var i = k + 1; i < insts.Length; i += 1)
        cont.Add(insts[i]);
    // its successors now come from the rest: their phis name it
    var last = insts[insts.Length - 1];
    foreach (var label in last.Labels)
    {
        for (var j = 0; j < f.Blocks.Count(); j += 1)
        {
            if (f.Blocks.Get(j).Label != label)
                continue;
            foreach (var phi in f.Blocks.Get(j).Insts.ToArray())
            {
                if (phi.Op != "phi")
                    continue;
                for (var a = 0; a < phi.Labels.Length; a += 1)
                {
                    if (phi.Labels[a] == block.Label)
                        phi.Labels[a] = contLabel;
                }
            }
        }
    }

    // the copy of the callee
    var copy = InlineCopy { Values = Dictionary<string, int>.Create(), Tag = tag };
    for (var p = 0; p < fn.Params.Length; p += 1)
        copy.Values.Set(fn.Params[p].Name, call.Args[p]);
    var retValues = List<int>.Create();
    var retLabels = List<string>.Create();
    var copied = List<IrBlock>.Create();
    string entry = "";
    foreach (var cb in fn.Blocks.ToArray())
    {
        string label = cb.Label + "." + tag;
        if (entry.Length == 0)
            entry = label;
        var list = List<IrInst>.Create();
        foreach (var ci in cb.Insts.ToArray())
        {
            if (ci.Op == "ret")
            {
                if (ci.Args.Length > 0)
                {
                    retValues.Add(RemapValue(g, copy, ci.Args[0]));
                    retLabels.Add(label);
                }
                list.Add(Branch(contLabel));
                continue;
            }
            var args = new int[ci.Args.Length];
            for (var a = 0; a < args.Length; a += 1)
                args[a] = RemapValue(g, copy, ci.Args[a]);
            var labels = new string[ci.Labels.Length];
            for (var a = 0; a < labels.Length; a += 1)
                labels[a] = ci.Labels[a] + "." + tag;
            list.Add(IrInst { Op = ci.Op, Res = ci.Res.Length > 0 ? ci.Res + "." + tag : "", Type = ci.Type, OpType = ci.OpType,
                              Args = args, Pred = ci.Pred, Labels = labels, Cases = ci.Cases,
                              Callee = ci.Callee >= 0 ? RemapValue(g, copy, ci.Callee) : -1, Volatile = ci.Volatile });
        }
        copied.Add(IrBlock { Label = label, Insts = list });
    }

    // the result: with one return its value itself, else a phi at the start of the rest, under the call's name
    if (call.Res.Length > 0 && retValues.Count() == 1 && !CalledThrough(g, f, call.Res))
    {
        ReplaceUses(g, f, call.Res, retValues.Get(0));
        foreach (var cb in copied.ToArray())
            ReplaceUses(g, cb, call.Res, retValues.Get(0));
        for (var i = 0; i < cont.Count(); i += 1)
            ReplaceArgs(g, cont.Get(i), call.Res, retValues.Get(0));
    }
    else if (call.Res.Length > 0)
    {
        cont.Insert(0, IrInst { Op = "phi", Res = call.Res, Type = call.Type, OpType = call.Type, Args = retValues.ToArray(),
                                Pred = "", Labels = retLabels.ToArray(), Cases = new int64[0], Callee = -1, Volatile = false });
    }

    // the block up to the call, then a branch into the copy
    var head = List<IrInst>.Create();
    for (var i = 0; i < k; i += 1)
        head.Add(insts[i]);
    head.Add(Branch(entry));
    f.Blocks.Set(bi, IrBlock { Label = block.Label, Insts = head });
    int at = bi + 1;
    foreach (var cb in copied.ToArray())
    {
        f.Blocks.Insert(at, cb);
        at += 1;
    }
    f.Blocks.Insert(at, IrBlock { Label = contLabel, Insts = cont });
}

// whether a call goes through the local value name (a callee is not replaced)
bool CalledThrough(Gen g, IrFunc f, string name)
{
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Callee >= 0)
            {
                var v = g.M.Vals.Get(inst.Callee);
                if (v.Kind == ValKind.Local && v.Name == name)
                    return true;
            }
        }
    }
    return false;
}

// every use of the local value name becomes the value vi
void ReplaceUses(Gen g, IrFunc f, string name, int vi)
{
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
            ReplaceArgs(g, inst, name, vi);
    }
}

void ReplaceUses(Gen g, IrBlock b, string name, int vi)
{
    foreach (var inst in b.Insts.ToArray())
        ReplaceArgs(g, inst, name, vi);
}

void ReplaceArgs(Gen g, IrInst inst, string name, int vi)
{
    for (var a = 0; a < inst.Args.Length; a += 1)
    {
        var v = g.M.Vals.Get(inst.Args[a]);
        if (v.Kind == ValKind.Local && v.Name == name)
            inst.Args[a] = vi;
    }
}

IrInst Branch(string label)
{
    return IrInst { Op = "br", Res = "", Type = 0, OpType = 0, Args = new int[0], Pred = "", Labels = [label], Cases = new int64[0],
                    Callee = -1, Volatile = false };
}
