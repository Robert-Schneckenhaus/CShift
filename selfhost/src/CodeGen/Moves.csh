// Moves: the last use of a local variable gives its reference away instead of copying it. Where a value is stored -
// returned, assigned ('y = x;'), the initializer of a variable ('var y = x;'), a field value of a struct initializer or
// an item of a collection expression in such a place - a variable that is not read afterwards is moved: its value is
// loaded as an owned value and its slot is cleared (the release at the end of its scope then does nothing). That saves
// a retain and a release per value: 'return list;', 'return Foo { Items = items, Name = name };'.
//
// Which uses are the last ones is decided from the syntax before a function is compiled (FindMoves), conservatively:
// the variable is declared in a block on the way to the statement ('var x = ...;' or with a type) or is a parameter;
// its name appears exactly once in the statement and in none of the statements after it, in every block up to the one
// that declares it; no loop lies in between; its address (&x) is taken nowhere. Names are compared as text, so another
// variable with the same name counts as a use too. Code generation moves only variables that own their reference (not
// 'ref' or 'const ref' parameters, 'using' variables or constants), see MoveLocal.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;

struct MoveScan
{
    HashSet<int> Moves;     // the Name nodes that are moves
    List<Stmt[]> Lists;     // the statement lists on the way to the current statement (the function body first)
    List<int> At;           // the index of the current statement in each of them
    List<bool> ViaLoop;     // whether the list is the body of a loop (reached again by the loop)
    string[] Params;
    Stmt Body;
}

// The Name nodes of a function body (or a lambda's) that are moves.
HashSet<int> FindMoves(const ref Compiler cg, Param[] ps, Stmt body)
{
    var names = new string[ps.Length];
    for (var i = 0; i < ps.Length; i += 1)
        names[i] = ps[i].Name;
    var scan = MoveScan { Moves = HashSet<int>.Create(), Lists = List<Stmt[]>.Create(), At = List<int>.Create(),
                          ViaLoop = List<bool>.Create(), Params = names, Body = body };
    if (body.Kind == StmtKind.Block)
        ScanMoveList(cg, scan, cg.Tree.GetBlock(body).Stmts, false);
    return scan.Moves;
}

// x => x: the body of a lambda is its result.
HashSet<int> FindLambdaBodyMoves(const ref Compiler cg, Param[] ps, Expr result)
{
    var moves = HashSet<int>.Create();
    if (result.Kind != ExprKind.Name)
        return moves;
    string name = cg.Tree.GetName(result).Name;
    foreach (var p in ps)
    {
        if (p.Name == name)
            moves.Add(result.Index);
    }
    return moves;
}

void ScanMoveList(const ref Compiler cg, MoveScan scan, Stmt[] list, bool viaLoop)
{
    scan.Lists.Add(list);
    scan.At.Add(-1);
    scan.ViaLoop.Add(viaLoop);
    int level = scan.Lists.Count() - 1;
    for (var i = 0; i < list.Length; i += 1)
    {
        scan.At.Set(level, i);
        ScanMoveStmt(cg, scan, list[i]);
    }
    scan.Lists.RemoveAt(level);
    scan.At.RemoveAt(level);
    scan.ViaLoop.RemoveAt(level);
}

// A statement that is not a block, as a list of one (the body of an 'if' or a loop without braces).
void ScanMoveNested(const ref Compiler cg, MoveScan scan, Stmt s, bool viaLoop)
{
    if (s.Kind == StmtKind.None)
        return;
    if (s.Kind == StmtKind.Block)
    {
        ScanMoveList(cg, scan, cg.Tree.GetBlock(s).Stmts, viaLoop);
        return;
    }
    var one = new Stmt[1];
    one[0] = s;
    ScanMoveList(cg, scan, one, viaLoop);
}

void ScanMoveStmt(const ref Compiler cg, MoveScan scan, Stmt s)
{
    var tree = cg.Tree;
    switch (s.Kind)
    {
    case StmtKind.Block:
        ScanMoveList(cg, scan, tree.GetBlock(s).Stmts, false);
        break;
    case StmtKind.VarDecl:
    {
        var d = tree.GetVarDecl(s);
        if (!d.IsConst && !d.IsUsing)
            MoveCandidates(cg, scan, d.Init);
        break;
    }
    case StmtKind.Expr:
    {
        Expr e = tree.GetExprStmt(s).Expr;
        if (e.Kind == ExprKind.Assign && !tree.GetAssign(e).HasOp)
            MoveCandidates(cg, scan, tree.GetAssign(e).Value);
        break;
    }
    case StmtKind.Return:
        MoveCandidates(cg, scan, tree.GetReturn(s).Value);
        break;
    case StmtKind.If:
        ScanMoveNested(cg, scan, tree.GetIf(s).Then, false);
        ScanMoveNested(cg, scan, tree.GetIf(s).Else, false);
        break;
    case StmtKind.While:
        ScanMoveNested(cg, scan, tree.GetWhile(s).Body, true);
        break;
    case StmtKind.DoWhile:
        ScanMoveNested(cg, scan, tree.GetDoWhile(s).Body, true);
        break;
    case StmtKind.For:
        ScanMoveNested(cg, scan, tree.GetFor(s).Body, true);
        break;
    case StmtKind.Foreach:
        ScanMoveNested(cg, scan, tree.GetForeach(s).Body, true);
        break;
    case StmtKind.Switch:
        foreach (var section in tree.GetSwitch(s).Sections)
            ScanMoveList(cg, scan, section.Body, false);
        break;
    case StmtKind.UsingBlock:
        ScanMoveNested(cg, scan, tree.GetUsingBlock(s).Body, false);
        break;
    default:
        break;
    }
}

// The places in a stored value where a variable can be moved: the value itself, the field values of a struct
// initializer and the items of a collection expression (not spread ones), nested.
void MoveCandidates(const ref Compiler cg, MoveScan scan, Expr v)
{
    var tree = cg.Tree;
    if (v.Kind == ExprKind.Name)
        TryMove(cg, scan, v);
    else if (v.Kind == ExprKind.StructInit)
    {
        foreach (var f in tree.GetStructInit(v).Fields)
            MoveCandidates(cg, scan, f.Value);
    }
    else if (v.Kind == ExprKind.Collection)
    {
        var c = tree.GetCollection(v);
        for (var i = 0; i < c.Items.Length; i += 1)
        {
            if (!c.Spread[i])
                MoveCandidates(cg, scan, c.Items[i]);
        }
    }
}

void TryMove(const ref Compiler cg, MoveScan scan, Expr nameExpr)
{
    string name = cg.Tree.GetName(nameExpr).Name;
    int top = scan.Lists.Count() - 1;
    Stmt here = scan.Lists.Get(top)[scan.At.Get(top)];
    // the name once in the statement, no 'try' in it (an early return would clean up in the middle of it), and its
    // address taken nowhere
    if (MentionsInStmt(cg, here, name, 0) != 1 || MentionsInStmt(cg, here, name, 2) != 0 || MentionsInStmt(cg, scan.Body, name, 1) != 0)
        return;
    for (var level = top; level >= 0; level -= 1)
    {
        var list = scan.Lists.Get(level);
        int at = scan.At.Get(level);
        for (var i = at + 1; i < list.Length; i += 1)
        {
            if (MentionsInStmt(cg, list[i], name, 0) != 0)
                return; // read again (or a variable with the same name)
        }
        bool declaredHere = false;
        for (var i = 0; i < at; i += 1)
        {
            if (list[i].Kind == StmtKind.VarDecl && cg.Tree.GetVarDecl(list[i]).Name == name)
                declaredHere = true;
        }
        if (!declaredHere && level == 0)
        {
            declaredHere = false;
            foreach (var p in scan.Params)
            {
                if (p == name)
                    declaredHere = true;
            }
        }
        if (declaredHere)
        {
            // a loop between the declaration and the statement reaches the variable again
            for (var j = level + 1; j <= top; j += 1)
            {
                if (scan.ViaLoop.Get(j))
                    return;
            }
            scan.Moves.Add(nameExpr.Index);
            return;
        }
        if (scan.ViaLoop.Get(level))
            return; // declared further out, with this loop in between
    }
}

// How often the name appears in a statement (declarations of the name count too). Mode 1 counts only where its address
// is taken (&x, &x.f, &x[i]), mode 2 the 'try' expressions instead. A kind of statement or expression that is not
// known counts as many.
int MentionsInStmt(const ref Compiler cg, Stmt s, string name, int mode)
{
    var tree = cg.Tree;
    int declared = mode == 0 ? 1 : 0;
    switch (s.Kind)
    {
    case StmtKind.None:
    case StmtKind.Break:
    case StmtKind.Continue:
    case StmtKind.Empty:
        return 0;
    case StmtKind.Block:
    {
        int n = 0;
        foreach (var inner in tree.GetBlock(s).Stmts)
            n += MentionsInStmt(cg, inner, name, mode);
        return n;
    }
    case StmtKind.VarDecl:
    {
        var d = tree.GetVarDecl(s);
        return (d.Name == name ? declared : 0) + MentionsIn(cg, d.Init, name, mode, false);
    }
    case StmtKind.Expr:
        return MentionsIn(cg, tree.GetExprStmt(s).Expr, name, mode, false);
    case StmtKind.If:
    {
        var n = tree.GetIf(s);
        return MentionsIn(cg, n.Cond, name, mode, false) + MentionsInStmt(cg, n.Then, name, mode) +
               MentionsInStmt(cg, n.Else, name, mode);
    }
    case StmtKind.While:
        return MentionsIn(cg, tree.GetWhile(s).Cond, name, mode, false) + MentionsInStmt(cg, tree.GetWhile(s).Body, name, mode);
    case StmtKind.DoWhile:
        return MentionsInStmt(cg, tree.GetDoWhile(s).Body, name, mode) + MentionsIn(cg, tree.GetDoWhile(s).Cond, name, mode, false);
    case StmtKind.For:
    {
        var n = tree.GetFor(s);
        int count = MentionsInStmt(cg, n.Init, name, mode) + MentionsIn(cg, n.Cond, name, mode, false) +
                    MentionsInStmt(cg, n.Body, name, mode);
        foreach (var it in n.Iterators)
            count += MentionsIn(cg, it, name, mode, false);
        return count;
    }
    case StmtKind.Foreach:
    {
        var n = tree.GetForeach(s);
        return (n.Name == name ? declared : 0) + MentionsIn(cg, n.Iterable, name, mode, false) + MentionsInStmt(cg, n.Body, name, mode);
    }
    case StmtKind.Switch:
    {
        var n = tree.GetSwitch(s);
        int count = MentionsIn(cg, n.Subject, name, mode, false);
        foreach (var section in n.Sections)
        {
            foreach (var label in section.Labels)
                count += MentionsIn(cg, label.Value, name, mode, false) + (label.PatName == name ? declared : 0);
            foreach (var inner in section.Body)
                count += MentionsInStmt(cg, inner, name, mode);
        }
        return count;
    }
    case StmtKind.Return:
        return MentionsIn(cg, tree.GetReturn(s).Value, name, mode, false);
    case StmtKind.UsingBlock:
        return MentionsInStmt(cg, tree.GetUsingBlock(s).Decl, name, mode) + MentionsInStmt(cg, tree.GetUsingBlock(s).Body, name, mode);
    default:
        return 1000;
    }
}

// How often the name appears in an expression (see MentionsInStmt); 'underAddress': inside the operand of '&'.
int MentionsIn(const ref Compiler cg, Expr e, string name, int mode, bool underAddress)
{
    var tree = cg.Tree;
    int declared = mode == 0 ? 1 : 0;
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
    case ExprKind.SizeOf:
    case ExprKind.Default:
    case ExprKind.NewObject:
    case ExprKind.Embed:
    case ExprKind.EmbedFilenames:
    case ExprKind.EmbedLines:
        return 0;
    case ExprKind.Name:
        return tree.GetName(e).Name == name && (mode == 0 || (mode == 1 && underAddress)) ? 1 : 0;
    case ExprKind.Member:
        return MentionsIn(cg, tree.GetMember(e).Object, name, mode, underAddress);
    case ExprKind.Call:
    {
        var c = tree.GetCall(e);
        int n = MentionsIn(cg, c.Callee, name, mode, false);
        foreach (var arg in c.Args)
            n += MentionsIn(cg, arg, name, mode, false);
        return n;
    }
    case ExprKind.Index:
        return MentionsIn(cg, tree.GetIndex(e).Object, name, mode, underAddress) + MentionsIn(cg, tree.GetIndex(e).Index, name, mode, false);
    case ExprKind.Slice:
    {
        var s = tree.GetSlice(e);
        return MentionsIn(cg, s.Object, name, mode, underAddress) + MentionsIn(cg, s.Start, name, mode, false) +
               MentionsIn(cg, s.End, name, mode, false);
    }
    case ExprKind.Unary:
    {
        var u = tree.GetUnary(e);
        return MentionsIn(cg, u.Operand, name, mode, underAddress || u.Op == UnOp.AddrOf);
    }
    case ExprKind.Binary:
        return MentionsIn(cg, tree.GetBinary(e).Lhs, name, mode, false) + MentionsIn(cg, tree.GetBinary(e).Rhs, name, mode, false);
    case ExprKind.Assign:
        return MentionsIn(cg, tree.GetAssign(e).Target, name, mode, false) + MentionsIn(cg, tree.GetAssign(e).Value, name, mode, false);
    case ExprKind.Conditional:
    {
        var c = tree.GetCond(e);
        return MentionsIn(cg, c.Cond, name, mode, false) + MentionsIn(cg, c.Then, name, mode, false) +
               MentionsIn(cg, c.Else, name, mode, false);
    }
    case ExprKind.Cast:
        return MentionsIn(cg, tree.GetCast(e).Operand, name, mode, underAddress);
    case ExprKind.NewArray:
    {
        var a = tree.GetNewArray(e);
        int n = MentionsIn(cg, a.Size, name, mode, false);
        foreach (var item in a.Init)
            n += MentionsIn(cg, item, name, mode, false);
        return n;
    }
    case ExprKind.StructInit:
    {
        int n = 0;
        foreach (var f in tree.GetStructInit(e).Fields)
            n += MentionsIn(cg, f.Value, name, mode, false);
        return n;
    }
    case ExprKind.Collection:
    {
        int n = 0;
        foreach (var item in tree.GetCollection(e).Items)
            n += MentionsIn(cg, item, name, mode, false);
        return n;
    }
    case ExprKind.Is:
    {
        var i = tree.GetIs(e);
        return MentionsIn(cg, i.Operand, name, mode, false) + (i.BindName == name ? declared : 0);
    }
    case ExprKind.Try:
        return (mode == 2 ? 1 : 0) + MentionsIn(cg, tree.GetTry(e).Operand, name, mode, false);
    case ExprKind.ErrorLit:
        return MentionsIn(cg, tree.GetErrorLit(e).Message, name, mode, false) + MentionsIn(cg, tree.GetErrorLit(e).Code, name, mode, false);
    case ExprKind.Unchecked:
        return MentionsIn(cg, tree.GetUnchecked(e).Operand, name, mode, underAddress);
    case ExprKind.RefArg:
        return MentionsIn(cg, tree.GetRefArg(e).Operand, name, mode, underAddress);
    case ExprKind.Start:
        return MentionsIn(cg, tree.GetStart(e).Operand, name, mode, false);
    case ExprKind.Lambda:
    {
        var l = tree.GetLambda(e);
        int n = MentionsIn(cg, l.Body, name, mode, false) + MentionsInStmt(cg, l.Block, name, mode);
        foreach (var p in l.Params)
        {
            if (p.Name == name)
                n += declared;
        }
        return n;
    }
    default:
        return 1000;
    }
}

// A use of a local variable that FindMoves chose: its value as an owned value, and its slot cleared - if the variable
// owns its reference. Value { } (none) otherwise.
Value MoveLocal(const ref Compiler cg, Expr e)
{
    if (!cg.Fn[0].HasMoves || !cg.Fn[0].Moves.Contains(e.Index))
        return Value { };
    int local = FindLocal(cg, cg.Tree.GetName(e).Name);
    if (local < 0)
        return Value { };
    var v = cg.Fn[0].Vars.Get(local);
    if (v.IsRef || v.IsConst || v.IsConstant || v.Disposable || !v.OwnsArc || !NeedsArc(cg, v.Type) || v.Slot.Length == 0)
        return Value { };
    string llvm = LlvmType(cg, v.Type);
    string value = cg.Ir.Load(llvm, v.Slot);
    if (cg.Fn[0].InReturn)
        cg.Fn[0].ReturnMoves.Add(v.Slot); // the function ends here: its cleanup skips the variable (EmitScopeCleanup)
    else
        cg.Ir.Store(llvm, ZeroValue(cg, v.Type), v.Slot);
    return Rvalue(v.Type, value, true);
}
