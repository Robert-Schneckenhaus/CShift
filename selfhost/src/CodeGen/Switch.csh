// The switch statement (port of CodeGen::emitSwitch): constant labels compare with '==', pattern labels
// ('case T name:') test the payload of an Error<T> or Optional<T>. A section must not fall through into the next one.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

void EmitSwitch(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetSwitch(s);
    PushScope(cg);
    Value subj = EmitRValue(cg, n.Subject);
    int st = subj.Type;
    string subjVal = subj.V;
    if (NeedsArc(cg, st))
    {
        // Keep an owned copy alive for the whole switch.
        string slot = ir.Alloca(LlvmType(cg, st), "switch.subject");
        string owned = Consume(cg, subj);
        ir.Store(LlvmType(cg, st), owned, slot);
        DeclareVar(cg, "$switch", st, slot);
        subjVal = owned;
    }
    FlushTemps(cg, 0, true);
    // a union is matched through memory (its tag and its payload)
    string unionSlot = "";
    if (IsUnionType(cg, st))
    {
        unionSlot = ir.Alloca(LlvmType(cg, st), "switch.union");
        ir.Store(LlvmType(cg, st), subjVal, unionSlot);
    }

    string endLabel = ir.NewLabel("switch.end");
    var bodies = new string[n.Sections.Length];
    for (var i = 0; i < bodies.Length; i += 1)
        bodies[i] = ir.NewLabel("case");
    string defaultLabel = "";

    for (var i = 0; i < n.Sections.Length; i += 1)
    {
        foreach (var label in n.Sections[i].Labels)
        {
            if (label.IsDefault)
            {
                if (defaultLabel.Length > 0)
                    Fail(cg, label.Loc, "the switch already has a 'default' label");
                defaultLabel = bodies[i];
                continue;
            }
            string cond;
            if (!label.PatType.IsNull())
            {
                bool isError = false;
                int pt = ResultPatternType(cg, st, label.PatType, label.Loc, ref isError);
                if (isError)
                    cond = ir.Bin("xor", "i1", ir.ExtractValue(LlvmType(cg, st), subjVal, "0"), "true"); // "case error e:"
                else if (IsUnionType(cg, st))
                {
                    int index = UnionMemberIndex(cg, st, pt);
                    if (index < 0)
                        Fail(cg, label.Loc, "'" + types.Name(pt) + "' is not a member of union '" + types.Name(st) + "'");
                    cond = ir.ICmp("eq", "i32", UnionTag(cg, st, unionSlot), (index + 1).ToString());
                }
                else if (types.IsResultLike(st) && types.Elem(st) == pt)
                    cond = ir.ExtractValue(LlvmType(cg, st), subjVal, "0");
                else
                {
                    Fail(cg, label.Loc, "pattern type '" + types.Name(pt) + "' does not match the switch subject of type '" + types.Name(st) + "'");
                    cond = "true";
                }
            }
            else
            {
                Value lv = EmitRValue(cg, label.Value);
                cond = EmitCompare(cg, BinOp.Eq, Rvalue(st, subjVal, false), lv, label.Loc).V;
                FlushTemps(cg, 0, true);
            }
            string next = ir.NewLabel("case.test");
            ir.CondBr(cond, bodies[i], next);
            ir.SetBlock(next);
        }
    }
    ir.Br(defaultLabel.Length > 0 ? defaultLabel : endLabel);

    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = "", ScopeDepth = ScopeCount(cg) });
    for (var i = 0; i < n.Sections.Length; i += 1)
    {
        var sec = n.Sections[i];
        ir.SetBlock(bodies[i]);
        PushScope(cg);
        foreach (var label in sec.Labels)
        {
            if (label.PatType.IsNull() || label.PatName.Length == 0)
                continue;
            bool isError = false;
            int pt = ResultPatternType(cg, st, label.PatType, label.Loc, ref isError);
            string slot = ir.Alloca(LlvmType(cg, pt), label.PatName);
            string payload = IsUnionType(cg, st) ? ir.Load(LlvmType(cg, pt), UnionPayload(cg, st, unionSlot))
                           : pt == st ? subjVal : ir.ExtractValue(LlvmType(cg, st), subjVal, "1");
            EmitRetain(cg, pt, payload);
            ir.Store(LlvmType(cg, pt), payload, slot);
            DeclareVar(cg, label.PatName, pt, slot);
            break;
        }
        foreach (var stmt in sec.Body)
            EmitStmt(cg, stmt);
        if (ir.Reachable())
            Fail(cg, sec.Loc, "control cannot fall through from one case label to another (missing 'break')");
        // The section's block may still be open here (e.g. a nested switch/try where every branch returns leaves its
        // own end label open but unreachable). It must be terminated before the next SetBlock call.
        if (ir.BlockOpen())
            ir.Unreachable();
        PopScope(cg, true);
    }
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);

    ir.SetBlock(endLabel);
    PopScope(cg, true);
}
