// Which methods leave 'this' unchanged. A method that does not write the bytes of its struct - no assignment to a field
// (or to a field of an embedded struct or an element of a Fixed field), no 'ref' or '&' of one, and only calls of such
// methods on them - can be called on a read-only value (a 'const ref' parameter or a field of one, a variable a lambda
// captured): directly, without a copy (EmitMethodCallOn). Calling one that changes it there is an error, which names
// the reason (ReadOnlyChangeError).
//
// What a field refers to is not part of the struct: '_state[0].Count += 1' writes the shared storage of a List, not the
// List, and 'Items[i] = x' and 'Items.Add(x)' call methods that do the same.
//
// The answer is per method and struct type (generic structs per instance), from the syntax and the types of the
// fields. A name is a field unless a parameter or a local variable of the method hides it there (pattern variables
// are not counted: such a name still counts as the field). A method without a body counts as a change. Lambdas work on
// a copy of 'this' and are left out. Methods that call each other are assumed to keep 'this' while they are being
// decided (a write anywhere in the cycle still shows); a result that relied on that for a method further up is decided
// again later instead of being remembered.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;

const int KeepsYes = 1;
const int KeepsNo = 2;
const int KeepsBusy = 3;     // ... + the depth: being decided

struct KeepScan
{
    int Owner;          // the struct type of 'this'
    int Depth;          // the depth of the method being decided
    int Lowest;         // the lowest depth of a method being decided that the result relied on
    List<string> Locals; // the parameters and local variables in scope
    string Why;         // what changes 'this' (the first change found): "assigns 'Count'"
    string RootLocal;   // not 'this' but this local variable (of type Owner) is asked about (LocalStaysUnchanged)
}

// Whether the local variable 'name' (of type t) stays unchanged in the statements list[from..]: it is not assigned,
// not passed with 'ref', its address is not taken, and the methods called on it (or on its fields) keep them. Another
// variable of the same name counts as a change.
bool LocalStaysUnchanged(const ref Compiler cg, string name, int t, Stmt[] list, int from)
{
    var scan = KeepScan { Owner = t, Depth = 0, Lowest = 1000000, Locals = List<string>.Create(), Why = "", RootLocal = name };
    for (var i = from; i < list.Length; i += 1)
    {
        if (!StmtKeepsThis(cg, ref scan, list[i]))
            return false;
    }
    return true;
}

// Whether the method 'entry' (an index in Compiler.Funcs) of the struct type 'owner' leaves 'this' unchanged.
bool MethodKeepsThis(const ref Compiler cg, int entry, int owner)
{
    int lowest = 1000000;
    return KeepsThisAt(cg, entry, owner, 0, ref lowest);
}

// What a method that does not keep 'this' does to it ("assigns 'Count'"); see MethodKeepsThis.
string MethodChangeReason(const ref Compiler cg, int entry, int owner)
{
    if (MethodKeepsThis(cg, entry, owner))
        return "";
    return cg.KeepsWhy.GetOrDefault(entry.ToString() + ":" + owner.ToString(), "changes it");
}

// The error for calling the method 'name' that changes the read-only value it is called on.
string ReadOnlyChangeError(const ref Compiler cg, string name, int entry, int owner)
{
    return ReadOnlyError(cg, name, owner, MethodChangeReason(cg, entry, owner));
}

string ReadOnlyError(const ref Compiler cg, string name, int type, string why)
{
    return "'" + name + "' changes the read-only '" + cg.Types.Name(type) + "' it is called on (a 'const ref' parameter or " +
           "a variable a lambda captured): it " + why + ". Call it on a copy ('var copy = ...;') or make the parameter 'ref'";
}

bool KeepsThisAt(const ref Compiler cg, int entry, int owner, int depth, ref int lowest)
{
    string key = entry.ToString() + ":" + owner.ToString();
    if (cg.KeepsThis.TryGet(key) is int state)
    {
        if (state == KeepsYes)
            return true;
        if (state == KeepsNo)
            return false;
        int busy = state - KeepsBusy; // a method that is being decided calls itself
        if (busy < lowest)
            lowest = busy;
        return true;
    }
    var d = cg.Funcs.Get(entry).Decl;
    if (d.IsStatic)
        return true;
    if (d.Body.Kind != StmtKind.Block)
    {
        cg.KeepsThis.Set(key, KeepsNo);
        cg.KeepsWhy.Set(key, "has no body that shows what it does");
        return false;
    }
    cg.KeepsThis.Set(key, KeepsBusy + depth);
    var scan = KeepScan { Owner = owner, Depth = depth + 1, Lowest = 1000000, Locals = List<string>.Create(), Why = "", RootLocal = "" };
    foreach (var p in d.Params)
        scan.Locals.Add(p.Name);
    bool keeps = StmtKeepsThis(cg, ref scan, d.Body);
    if (!keeps)
    {
        cg.KeepsThis.Set(key, KeepsNo); // a write found does not depend on any assumption
        cg.KeepsWhy.Set(key, scan.Why.Length > 0 ? scan.Why : "changes it");
    }
    else if (scan.Lowest >= depth)
        cg.KeepsThis.Set(key, KeepsYes);
    else
        cg.KeepsThis.Remove(key);       // relied on a method further up that is still being decided
    if (keeps && scan.Lowest < depth && scan.Lowest < lowest)
        lowest = scan.Lowest;
    return keeps;
}

// Records the first change found; returns false (the method does not keep 'this').
bool Changes(ref KeepScan scan, string why)
{
    if (scan.Why.Length == 0)
        scan.Why = why;
    return false;
}

// Whether all the methods a call may resolve to keep 'this'.
bool CandidatesKeepThis(const ref Compiler cg, ref KeepScan scan, Candidate[] cands)
{
    foreach (var c in cands)
    {
        int low = scan.Lowest;
        bool keeps = KeepsThisAt(cg, c.Entry, c.Owner, scan.Depth, ref low);
        scan.Lowest = low;
        if (!keeps)
        {
            string name = cg.Funcs.Get(c.Entry).Decl.Name;
            string inner = cg.KeepsWhy.GetOrDefault(c.Entry.ToString() + ":" + c.Owner.ToString(), "changes it");
            // one step of the chain is enough to point at the cause
            return Changes(ref scan, "calls '" + name + "', which " + (inner.Contains(", which ") ? "changes it" : inner));
        }
    }
    return true;
}

bool IsKeepLocal(const ref KeepScan scan, string name)
{
    for (var i = scan.Locals.Count() - 1; i >= 0; i -= 1)
    {
        if (scan.Locals.Get(i) == name)
            return true;
    }
    return false;
}

void DropKeepLocals(ref KeepScan scan, int mark)
{
    while (scan.Locals.Count() > mark)
        scan.Locals.RemoveAt(scan.Locals.Count() - 1);
}

// The source text of a part of 'this' for the reason of a change: Count, Pos.X, Pair[...].
string ThisPartText(const ref Compiler cg, Expr e)
{
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.This:
        return "this";
    case ExprKind.Name:
        return tree.GetName(e).Name;
    case ExprKind.Member:
        return ThisPartText(cg, tree.GetMember(e).Object) + "." + tree.GetMember(e).Name;
    case ExprKind.Index:
        return ThisPartText(cg, tree.GetIndex(e).Object) + "[...]";
    case ExprKind.Unchecked:
        return ThisPartText(cg, tree.GetUnchecked(e).Operand);
    default:
        return "...";
    }
}

// The type of an expression that is a part of 'this' itself - this, a field, a field of an embedded struct, an element
// of a Fixed field - or -1 for anything else (a local variable, what a field refers to, a value).
int ThisPartType(const ref Compiler cg, const ref KeepScan scan, Expr e)
{
    var tree = cg.Tree;
    var types = cg.Types;
    switch (e.Kind)
    {
    case ExprKind.This:
        return scan.RootLocal.Length > 0 ? -1 : scan.Owner;
    case ExprKind.Name:
    {
        string name = tree.GetName(e).Name;
        if (scan.RootLocal.Length > 0)
            return name == scan.RootLocal ? scan.Owner : -1;
        if (IsKeepLocal(scan, name))
            return -1;
        var p = FindField(cg, scan.Owner, name);
        return p.Found ? p.Type : -1;
    }
    case ExprKind.Member:
    {
        var m = tree.GetMember(e);
        if (m.ViaArrow)
            return -1;
        int t = ThisPartType(cg, scan, m.Object);
        if (t < 0 || !types.IsStruct(t))
            return -1;
        var p = FindField(cg, t, m.Name);
        return p.Found ? p.Type : -1;
    }
    case ExprKind.Index:
    {
        int t = ThisPartType(cg, scan, tree.GetIndex(e).Object);
        if (t < 0 || !types.IsFixed(t))
            return -1;
        return types.Elem(t);
    }
    case ExprKind.Unchecked:
        return ThisPartType(cg, scan, tree.GetUnchecked(e).Operand);
    default:
        return -1;
    }
}

// Whether calling the method 'name' on a value of type t (a part of 'this') keeps it.
bool CallOnKeepsThis(const ref Compiler cg, ref KeepScan scan, int t, string name)
{
    var types = cg.Types;
    if (types.IsStruct(t))
    {
        var cands = MethodCandidates(cg, t, name);
        if (cands.Length > 0)
            return CandidatesKeepThis(cg, ref scan, cands);
        var field = FindField(cg, t, name);
        if (field.Found && IsCallableType(cg, field.Type))
            return true; // a field with a function type, called like a method
        return Changes(ref scan, "calls '" + name + "', which the compiler does not know");
    }
    if (IsUnionType(cg, t))
    {
        // the method of the member the union holds
        foreach (var member in GetUnionInfo(cg, t).Members)
        {
            if (types.IsStruct(member) && !CandidatesKeepThis(cg, ref scan, MethodCandidates(cg, member, name)))
                return false;
        }
        return true;
    }
    return true; // the methods of strings, arrays, numbers, ... work on a value
}

// Whether calling the method 'name' on a read-only value of type t would change it, and why: "" if it would not (the
// union case of ReadOnlyChangeError: the methods of all members are asked).
string UnionChangeReason(const ref Compiler cg, int union, string name)
{
    var scan = KeepScan { Owner = union, Depth = 0, Lowest = 1000000, Locals = List<string>.Create(), Why = "", RootLocal = "" };
    if (CallOnKeepsThis(cg, ref scan, union, name))
        return "";
    return scan.Why.Length > 0 ? scan.Why : "changes it";
}

bool StmtKeepsThis(const ref Compiler cg, ref KeepScan scan, Stmt s)
{
    var tree = cg.Tree;
    switch (s.Kind)
    {
    case StmtKind.None:
    case StmtKind.Break:
    case StmtKind.Continue:
    case StmtKind.Empty:
        return true;
    case StmtKind.Block:
    {
        int mark = scan.Locals.Count();
        foreach (var inner in tree.GetBlock(s).Stmts)
        {
            if (!StmtKeepsThis(cg, ref scan, inner))
                return false;
        }
        DropKeepLocals(ref scan, mark);
        return true;
    }
    case StmtKind.VarDecl:
    {
        var d = tree.GetVarDecl(s);
        if (!ExprKeepsThis(cg, ref scan, d.Init))
            return false;
        if (scan.RootLocal.Length > 0 && d.Name == scan.RootLocal)
            return Changes(ref scan, "declares another '" + d.Name + "'");
        scan.Locals.Add(d.Name);
        return true;
    }
    case StmtKind.Expr:
        return ExprKeepsThis(cg, ref scan, tree.GetExprStmt(s).Expr);
    case StmtKind.If:
    {
        var n = tree.GetIf(s);
        return ExprKeepsThis(cg, ref scan, n.Cond) && NestedKeepsThis(cg, ref scan, n.Then) && NestedKeepsThis(cg, ref scan, n.Else);
    }
    case StmtKind.While:
        return ExprKeepsThis(cg, ref scan, tree.GetWhile(s).Cond) && NestedKeepsThis(cg, ref scan, tree.GetWhile(s).Body);
    case StmtKind.DoWhile:
        return NestedKeepsThis(cg, ref scan, tree.GetDoWhile(s).Body) && ExprKeepsThis(cg, ref scan, tree.GetDoWhile(s).Cond);
    case StmtKind.For:
    {
        var n = tree.GetFor(s);
        int mark = scan.Locals.Count();
        if (!StmtKeepsThis(cg, ref scan, n.Init) || !ExprKeepsThis(cg, ref scan, n.Cond) || !NestedKeepsThis(cg, ref scan, n.Body))
            return false;
        foreach (var it in n.Iterators)
        {
            if (!ExprKeepsThis(cg, ref scan, it))
                return false;
        }
        DropKeepLocals(ref scan, mark);
        return true;
    }
    case StmtKind.Foreach:
    {
        // the loop works on a copy of the collection (EmitForeach)
        var n = tree.GetForeach(s);
        if (!ExprKeepsThis(cg, ref scan, n.Iterable))
            return false;
        if (scan.RootLocal.Length > 0 && n.Name == scan.RootLocal)
            return Changes(ref scan, "declares another '" + n.Name + "'");
        int mark = scan.Locals.Count();
        scan.Locals.Add(n.Name);
        if (!NestedKeepsThis(cg, ref scan, n.Body))
            return false;
        DropKeepLocals(ref scan, mark);
        return true;
    }
    case StmtKind.Switch:
    {
        var n = tree.GetSwitch(s);
        if (!ExprKeepsThis(cg, ref scan, n.Subject))
            return false;
        foreach (var section in n.Sections)
        {
            foreach (var label in section.Labels)
            {
                if (!ExprKeepsThis(cg, ref scan, label.Value))
                    return false;
            }
            int mark = scan.Locals.Count();
            foreach (var inner in section.Body)
            {
                if (!StmtKeepsThis(cg, ref scan, inner))
                    return false;
            }
            DropKeepLocals(ref scan, mark);
        }
        return true;
    }
    case StmtKind.Return:
        return ExprKeepsThis(cg, ref scan, tree.GetReturn(s).Value);
    case StmtKind.UsingBlock:
    {
        int mark = scan.Locals.Count();
        if (!StmtKeepsThis(cg, ref scan, tree.GetUsingBlock(s).Decl) || !NestedKeepsThis(cg, ref scan, tree.GetUsingBlock(s).Body))
            return false;
        DropKeepLocals(ref scan, mark);
        return true;
    }
    default:
        return Changes(ref scan, "has a statement the compiler does not follow");
    }
}

// The body of an 'if' or a loop: a variable it declares ends with it.
bool NestedKeepsThis(const ref Compiler cg, ref KeepScan scan, Stmt s)
{
    int mark = scan.Locals.Count();
    if (!StmtKeepsThis(cg, ref scan, s))
        return false;
    DropKeepLocals(ref scan, mark);
    return true;
}

bool ExprsKeepThis(const ref Compiler cg, ref KeepScan scan, Expr[] list)
{
    foreach (var e in list)
    {
        if (!ExprKeepsThis(cg, ref scan, e))
            return false;
    }
    return true;
}

bool ExprKeepsThis(const ref Compiler cg, ref KeepScan scan, Expr e)
{
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.None:
    case ExprKind.IntLit:
    case ExprKind.FloatLit:
    case ExprKind.CharLit:
    case ExprKind.StringLit:
    case ExprKind.BoolLit:
    case ExprKind.NullLit:
    case ExprKind.This:
    case ExprKind.Name:
    case ExprKind.SizeOf:
    case ExprKind.Default:
    case ExprKind.NewObject:
    case ExprKind.Embed:
    case ExprKind.EmbedFilenames:
    case ExprKind.EmbedLines:
    case ExprKind.Lambda:      // works on a copy of 'this'
        return true;
    case ExprKind.Member:
        return ExprKeepsThis(cg, ref scan, tree.GetMember(e).Object);
    case ExprKind.Call:
        return CallKeepsThis(cg, ref scan, tree.GetCall(e));
    case ExprKind.Index:
    {
        var n = tree.GetIndex(e);
        if (!ExprKeepsThis(cg, ref scan, n.Object) || !ExprKeepsThis(cg, ref scan, n.Index))
            return false;
        int t = ThisPartType(cg, scan, n.Object);
        return t < 0 || !cg.Types.IsStruct(t) || CallOnKeepsThis(cg, ref scan, t, "Get"); // obj[i] is obj.Get(i)
    }
    case ExprKind.Slice:
    {
        var n = tree.GetSlice(e);
        return ExprKeepsThis(cg, ref scan, n.Object) && ExprKeepsThis(cg, ref scan, n.Start) && ExprKeepsThis(cg, ref scan, n.End);
    }
    case ExprKind.Unary:
    {
        var u = tree.GetUnary(e);
        if (u.Op == UnOp.AddrOf && ThisPartType(cg, scan, u.Operand) >= 0)
            return Changes(ref scan, "takes the address of '" + ThisPartText(cg, u.Operand) + "'");
        return ExprKeepsThis(cg, ref scan, u.Operand);
    }
    case ExprKind.Binary:
        return ExprKeepsThis(cg, ref scan, tree.GetBinary(e).Lhs) && ExprKeepsThis(cg, ref scan, tree.GetBinary(e).Rhs);
    case ExprKind.Assign:
        return AssignKeepsThis(cg, ref scan, tree.GetAssign(e));
    case ExprKind.Conditional:
    {
        var c = tree.GetCond(e);
        return ExprKeepsThis(cg, ref scan, c.Cond) && ExprKeepsThis(cg, ref scan, c.Then) && ExprKeepsThis(cg, ref scan, c.Else);
    }
    case ExprKind.Cast:
        return ExprKeepsThis(cg, ref scan, tree.GetCast(e).Operand);
    case ExprKind.NewArray:
    {
        var a = tree.GetNewArray(e);
        return ExprKeepsThis(cg, ref scan, a.Size) && ExprsKeepThis(cg, ref scan, a.Init);
    }
    case ExprKind.StructInit:
    {
        foreach (var f in tree.GetStructInit(e).Fields)
        {
            if (!ExprKeepsThis(cg, ref scan, f.Value))
                return false;
        }
        return true;
    }
    case ExprKind.Collection:
        return ExprsKeepThis(cg, ref scan, tree.GetCollection(e).Items);
    case ExprKind.Is:
        return ExprKeepsThis(cg, ref scan, tree.GetIs(e).Operand);
    case ExprKind.Try:
        return ExprKeepsThis(cg, ref scan, tree.GetTry(e).Operand);
    case ExprKind.ErrorLit:
        return ExprKeepsThis(cg, ref scan, tree.GetErrorLit(e).Message) && ExprKeepsThis(cg, ref scan, tree.GetErrorLit(e).Code);
    case ExprKind.Unchecked:
        return ExprKeepsThis(cg, ref scan, tree.GetUnchecked(e).Operand);
    case ExprKind.RefArg:
    {
        var operand = tree.GetRefArg(e).Operand;
        if (ThisPartType(cg, scan, operand) >= 0)
            return Changes(ref scan, "passes '" + ThisPartText(cg, operand) + "' with 'ref'");
        return ExprKeepsThis(cg, ref scan, operand);
    }
    case ExprKind.Start:
        return ExprKeepsThis(cg, ref scan, tree.GetStart(e).Operand);
    default:
        return Changes(ref scan, "has an expression the compiler does not follow");
    }
}

bool AssignKeepsThis(const ref Compiler cg, ref KeepScan scan, AssignExpr a)
{
    var tree = cg.Tree;
    if (!ExprKeepsThis(cg, ref scan, a.Value))
        return false;
    if (a.Target.Kind == ExprKind.Index)
    {
        // obj[i] = v is obj.Set(i, v); obj[i] += v reads with Get as well
        var n = tree.GetIndex(a.Target);
        int t = ThisPartType(cg, scan, n.Object);
        if (t >= 0 && cg.Types.IsStruct(t))
            return ExprKeepsThis(cg, ref scan, n.Index) && CallOnKeepsThis(cg, ref scan, t, "Set") &&
                   (!a.HasOp || CallOnKeepsThis(cg, ref scan, t, "Get"));
    }
    if (ThisPartType(cg, scan, a.Target) >= 0)
        return Changes(ref scan, "assigns '" + ThisPartText(cg, a.Target) + "'");
    return ExprKeepsThis(cg, ref scan, a.Target);
}

bool CallKeepsThis(const ref Compiler cg, ref KeepScan scan, CallExpr c)
{
    var tree = cg.Tree;
    if (!ExprsKeepThis(cg, ref scan, c.Args))
        return false;
    if (c.Callee.Kind == ExprKind.Name)
    {
        // Method(...) on 'this', unless a variable or a field with a function type has the name (EmitNameCall); else a
        // function
        string name = tree.GetName(c.Callee).Name;
        if (IsKeepLocal(scan, name) || scan.RootLocal.Length > 0)
            return true; // a variable with a function type, or (for a local variable) any function
        var field = FindField(cg, scan.Owner, name);
        if (field.Found && IsCallableType(cg, field.Type))
            return true;
        return CandidatesKeepThis(cg, ref scan, MethodCandidates(cg, scan.Owner, name));
    }
    if (c.Callee.Kind == ExprKind.Member)
    {
        var m = tree.GetMember(c.Callee);
        if (!ExprKeepsThis(cg, ref scan, m.Object))
            return false;
        int t = m.ViaArrow ? -1 : ThisPartType(cg, scan, m.Object);
        return t < 0 || CallOnKeepsThis(cg, ref scan, t, m.Name);
    }
    return ExprKeepsThis(cg, ref scan, c.Callee);
}
