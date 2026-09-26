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
    // for the exhaustiveness check (CheckExhaustive): the members and values the labels cover
    var coveredMembers = List<int>.Create();   // union members (their index)
    var coveredValues = List<string>.Create(); // enum values, and the codes of an Error<T, E> (as IR constants)
    bool failureCovered = false;               // Error<T, E>: 'case error e' or 'case E code'

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
                if (isError || IsErrorEnum(cg, pt))
                {
                    cond = ir.Bin("xor", "i1", ir.ExtractValue(LlvmType(cg, st), subjVal, "0"), "true"); // "case error e:", "case E code:"
                    failureCovered = true;
                }
                else if (IsUnionType(cg, st))
                {
                    int index = UnionMemberIndex(cg, st, pt);
                    if (index < 0)
                        Fail(cg, label.Loc, "'" + types.Name(pt) + "' is not a member of union '" + types.Name(st) + "'");
                    cond = ir.ICmp("eq", "i32", UnionTag(cg, st, unionSlot), (index + 1).ToString());
                    coveredMembers.Add(index);
                }
                else if (types.IsResultLike(st) && types.Elem(st) == pt)
                    cond = ir.ExtractValue(LlvmType(cg, st), subjVal, "0");
                else
                {
                    Fail(cg, label.Loc, "pattern type '" + types.Name(pt) + "' does not match the switch subject of type '" + types.Name(st) + "'");
                    cond = "true";
                }
            }
            else if (types.IsError(st) && types.Code(st) != 0)
            {
                // "case E.Member:" on an Error<T, E>: failed with that code
                Value lv = ConvertValue(cg, EmitRValue(cg, label.Value), types.Code(st), label.Loc);
                coveredValues.Add(lv.V);
                string failed = ir.Bin("xor", "i1", ir.ExtractValue(LlvmType(cg, st), subjVal, "0"), "true");
                string same = ir.ICmp("eq", "i32", ir.ExtractValue(LlvmType(cg, st), subjVal, "3"), lv.V);
                cond = ir.Bin("and", "i1", failed, same);
                FlushTemps(cg, 0, true);
            }
            else
            {
                Value lv = EmitRValue(cg, label.Value);
                if (types.IsEnum(st))
                    coveredValues.Add(ConvertValue(cg, lv, st, label.Loc).V);
                cond = EmitCompare(cg, BinOp.Eq, Rvalue(st, subjVal, false), lv, label.Loc).V;
                FlushTemps(cg, 0, true);
            }
            string next = ir.NewLabel("case.test");
            ir.CondBr(cond, bodies[i], next);
            ir.SetBlock(next);
        }
    }
    if (defaultLabel.Length == 0)
        CheckExhaustive(cg, st, coveredMembers, coveredValues, failureCovered, s.Loc);
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
                           : pt == st ? subjVal
                           : IsErrorEnum(cg, pt) ? ir.ExtractValue(LlvmType(cg, st), subjVal, "3") // "case E code:"
                           : ir.ExtractValue(LlvmType(cg, st), subjVal, "1");
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

// A switch without 'default:' over a union, an enum or the codes of an Error<T, E> must name every case: a new member
// then shows every switch that has to handle it. (A switch over an Error<T, E> without code labels is not checked.)
void CheckExhaustive(Compiler cg, int st, List<int> members, List<string> values, bool failureCovered, SourceLoc loc)
{
    var types = cg.Types;
    var missing = List<string>.Create();
    string what = "";
    if (IsUnionType(cg, st))
    {
        var info = GetUnionInfo(cg, st);
        for (var i = 0; i < info.Members.Length; i += 1)
        {
            if (!members.Contains(i))
                missing.Add(types.Name(info.Members[i]));
        }
        what = "union '" + types.Name(st) + "'";
    }
    else if (types.IsEnum(st) || (types.IsError(st) && types.Code(st) != 0 && values.Count() > 0 && !failureCovered))
    {
        int enumType = types.IsEnum(st) ? st : types.Code(st);
        var info = GetEnumInfo(cg, enumType);
        for (var i = 0; i < info.Values.Length; i += 1)
        {
            string v = info.Values[i].ToString();
            string u = unchecked((uint64)info.Values[i]).ToString();
            if (!values.Contains(v) && !values.Contains(u) && !missing.Contains(info.Names[i]))
                missing.Add(info.Names[i]);
        }
        what = types.IsEnum(st) ? "enum '" + types.Name(st) + "'" : "the error codes of '" + types.Name(st) + "'";
    }
    if (missing.Count() == 0)
        return;
    string names = "";
    for (var i = 0; i < missing.Count(); i += 1)
        names += (i > 0 ? ", " : "") + "'" + missing.Get(i) + "'";
    Fail(cg, loc, "the switch over " + what + " does not handle " + names + "; add the case" + (missing.Count() > 1 ? "s" : "") +
                  " or 'default:'");
}

