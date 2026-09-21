// Text dump of the syntax tree. The format is the same as in the C++ compiler (cshiftc --dump-ast), so that the two
// parsers can be compared. One node per line, children indented by two spaces and prefixed with their role:
//
//     Call@5:9
//       callee: Name@5:9 name=foo
//       args[0]: IntLit@5:13 value=42

namespace CShift.Syntax;

using System;

struct AstDumper
{
    Ast Tree;
    StringBuilder Out;

    static AstDumper Create(Ast tree)
    {
        return AstDumper { Tree = tree, Out = StringBuilder.Create() };
    }

    // ---- helpers ----

    static string At(SourceLoc loc)
    {
        return "@" + loc.Line.ToString() + ":" + loc.Col.ToString();
    }

    void Line(int indent, string role, string text)
    {
        for (var i = 0; i < indent; i += 1)
            Out.Append("  ");
        if (role.Length > 0)
            Out.Append(role + ": ");
        Out.Append(text);
        Out.Append('\n');
    }

    string TypeText(TypeRef t)
    {
        return Tree.TypeToString(t);
    }

    string TypeAttr(string name, TypeRef t)
    {
        if (t.IsNull())
            return "";
        return " " + name + "=" + TypeText(t);
    }

    string TypeList(TypeRef[] types)
    {
        var sb = StringBuilder.Create();
        sb.Append('[');
        for (var i = 0; i < types.Length; i += 1)
        {
            if (i > 0)
                sb.Append(',');
            sb.Append(TypeText(types[i]));
        }
        sb.Append(']');
        return sb.ToString();
    }

    static string NameList(string[] names)
    {
        var sb = StringBuilder.Create();
        sb.Append('[');
        for (var i = 0; i < names.Length; i += 1)
        {
            if (i > 0)
                sb.Append(',');
            sb.Append(names[i]);
        }
        sb.Append(']');
        return sb.ToString();
    }

    static string Flag(bool value, string name)
    {
        return value ? " " + name : "";
    }

    // ---- expressions ----

    void DumpExpr(int indent, string role, Expr e)
    {
        if (e.IsNull())
            return;
        string head = ExprKindName(e.Kind) + At(e.Loc);
        switch (e.Kind)
        {
        case ExprKind.IntLit:
        {
            var n = Tree.GetIntLit(e);
            Line(indent, role, head + " value=" + n.Value.ToString() + Flag(n.IsUnsigned, "u") + Flag(n.IsLong, "l"));
            break;
        }
        case ExprKind.FloatLit:
        {
            var n = Tree.GetFloatLit(e);
            Line(indent, role, head + " bits=" + DoubleBits(n.Value) + Flag(n.IsFloat32, "f"));
            break;
        }
        case ExprKind.CharLit:
        {
            var n = Tree.GetCharLit(e);
            Line(indent, role, head + " value=" + n.Value.ToString());
            break;
        }
        case ExprKind.StringLit:
        {
            var n = Tree.GetStringLit(e);
            Line(indent, role, head + " value=\"" + EscapeText(n.Value) + "\"");
            break;
        }
        case ExprKind.BoolLit:
        {
            var n = Tree.GetBoolLit(e);
            Line(indent, role, head + " value=" + (n.Value ? "true" : "false"));
            break;
        }
        case ExprKind.NullLit:
        case ExprKind.This:
            Line(indent, role, head);
            break;
        case ExprKind.Name:
        {
            var n = Tree.GetName(e);
            Line(indent, role, head + " name=" + n.Name + (n.TypeArgs.Length > 0 ? " typeArgs=" + TypeList(n.TypeArgs) : ""));
            break;
        }
        case ExprKind.Member:
        {
            var n = Tree.GetMember(e);
            Line(indent, role, head + " name=" + n.Name + Flag(n.ViaArrow, "arrow") +
                               (n.TypeArgs.Length > 0 ? " typeArgs=" + TypeList(n.TypeArgs) : ""));
            DumpExpr(indent + 1, "object", n.Object);
            break;
        }
        case ExprKind.Call:
        {
            var n = Tree.GetCall(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "callee", n.Callee);
            for (var i = 0; i < n.Args.Length; i += 1)
                DumpExpr(indent + 1, "args[" + i.ToString() + "]", n.Args[i]);
            break;
        }
        case ExprKind.Index:
        {
            var n = Tree.GetIndex(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "object", n.Object);
            DumpExpr(indent + 1, "index", n.Index);
            break;
        }
        case ExprKind.Unary:
        {
            var n = Tree.GetUnary(e);
            Line(indent, role, head + " op=" + ((int)n.Op).ToString());
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        case ExprKind.Binary:
        {
            var n = Tree.GetBinary(e);
            Line(indent, role, head + " op=" + ((int)n.Op).ToString());
            DumpExpr(indent + 1, "lhs", n.Lhs);
            DumpExpr(indent + 1, "rhs", n.Rhs);
            break;
        }
        case ExprKind.Assign:
        {
            var n = Tree.GetAssign(e);
            Line(indent, role, head + (n.HasOp ? " op=" + ((int)n.Op).ToString() : ""));
            DumpExpr(indent + 1, "target", n.Target);
            DumpExpr(indent + 1, "value", n.Value);
            break;
        }
        case ExprKind.Conditional:
        {
            var n = Tree.GetCond(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "cond", n.Cond);
            DumpExpr(indent + 1, "then", n.Then);
            DumpExpr(indent + 1, "else", n.Else);
            break;
        }
        case ExprKind.Cast:
        {
            var n = Tree.GetCast(e);
            Line(indent, role, head + TypeAttr("type", n.Type));
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        case ExprKind.NewArray:
        {
            var n = Tree.GetNewArray(e);
            Line(indent, role, head + TypeAttr("elem", n.ElemType) + Flag(n.HasInit, "hasInit"));
            DumpExpr(indent + 1, "size", n.Size);
            for (var i = 0; i < n.Init.Length; i += 1)
                DumpExpr(indent + 1, "init[" + i.ToString() + "]", n.Init[i]);
            break;
        }
        case ExprKind.NewObject:
        {
            var n = Tree.GetNewObject(e);
            Line(indent, role, head + TypeAttr("type", n.Type));
            break;
        }
        case ExprKind.StructInit:
        {
            var n = Tree.GetStructInit(e);
            Line(indent, role, head + TypeAttr("type", n.Type));
            for (var i = 0; i < n.Fields.Length; i += 1)
            {
                var f = n.Fields[i];
                Line(indent + 1, "", "field" + At(f.Loc) + " name=" + f.Name);
                DumpExpr(indent + 2, "value", f.Value);
            }
            break;
        }
        case ExprKind.Is:
        {
            var n = Tree.GetIs(e);
            Line(indent, role, head + TypeAttr("type", n.Type) + (n.BindName.Length > 0 ? " bind=" + n.BindName : ""));
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        case ExprKind.Try:
        {
            var n = Tree.GetTry(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        case ExprKind.ErrorLit:
        {
            var n = Tree.GetErrorLit(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "message", n.Message);
            DumpExpr(indent + 1, "code", n.Code);
            break;
        }
        case ExprKind.SizeOf:
        {
            var n = Tree.GetSizeOf(e);
            Line(indent, role, head + TypeAttr("type", n.Type));
            break;
        }
        case ExprKind.Default:
        {
            var n = Tree.GetDefault(e);
            Line(indent, role, head + TypeAttr("type", n.Type));
            break;
        }
        case ExprKind.Unchecked:
        {
            var n = Tree.GetUnchecked(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        case ExprKind.RefArg:
        {
            var n = Tree.GetRefArg(e);
            Line(indent, role, head);
            DumpExpr(indent + 1, "operand", n.Operand);
            break;
        }
        default:
            Line(indent, role, head);
            break;
        }
    }

    static string ExprKindName(ExprKind kind)
    {
        switch (kind)
        {
        case ExprKind.IntLit: return "IntLit";
        case ExprKind.FloatLit: return "FloatLit";
        case ExprKind.CharLit: return "CharLit";
        case ExprKind.StringLit: return "StringLit";
        case ExprKind.BoolLit: return "BoolLit";
        case ExprKind.NullLit: return "NullLit";
        case ExprKind.Name: return "Name";
        case ExprKind.Member: return "Member";
        case ExprKind.Call: return "Call";
        case ExprKind.Index: return "Index";
        case ExprKind.Unary: return "Unary";
        case ExprKind.Binary: return "Binary";
        case ExprKind.Assign: return "Assign";
        case ExprKind.Conditional: return "Conditional";
        case ExprKind.Cast: return "Cast";
        case ExprKind.NewArray: return "NewArray";
        case ExprKind.NewObject: return "NewObject";
        case ExprKind.StructInit: return "StructInit";
        case ExprKind.Is: return "Is";
        case ExprKind.Try: return "Try";
        case ExprKind.ErrorLit: return "ErrorLit";
        case ExprKind.SizeOf: return "SizeOf";
        case ExprKind.Default: return "Default";
        case ExprKind.This: return "This";
        case ExprKind.Unchecked: return "Unchecked";
        case ExprKind.RefArg: return "RefArg";
        default: return "?";
        }
    }

    // ---- statements ----

    void DumpStmt(int indent, string role, Stmt s)
    {
        if (s.IsNull())
            return;
        string at = At(s.Loc);
        switch (s.Kind)
        {
        case StmtKind.Block:
        {
            var n = Tree.GetBlock(s);
            Line(indent, role, "Block" + at + Flag(n.IsUnsafe, "unsafe") + Flag(n.IsUnchecked, "unchecked"));
            for (var i = 0; i < n.Stmts.Length; i += 1)
                DumpStmt(indent + 1, "stmts[" + i.ToString() + "]", n.Stmts[i]);
            break;
        }
        case StmtKind.VarDecl:
        {
            var n = Tree.GetVarDecl(s);
            Line(indent, role, "VarDecl" + at + " name=" + n.Name + TypeAttr("type", n.Type) + Flag(n.IsUsing, "using"));
            DumpExpr(indent + 1, "init", n.Init);
            break;
        }
        case StmtKind.Expr:
        {
            var n = Tree.GetExprStmt(s);
            Line(indent, role, "ExprStmt" + at);
            DumpExpr(indent + 1, "expr", n.Expr);
            break;
        }
        case StmtKind.If:
        {
            var n = Tree.GetIf(s);
            Line(indent, role, "If" + at);
            DumpExpr(indent + 1, "cond", n.Cond);
            DumpStmt(indent + 1, "then", n.Then);
            DumpStmt(indent + 1, "else", n.Else);
            break;
        }
        case StmtKind.While:
        {
            var n = Tree.GetWhile(s);
            Line(indent, role, "While" + at);
            DumpExpr(indent + 1, "cond", n.Cond);
            DumpStmt(indent + 1, "body", n.Body);
            break;
        }
        case StmtKind.DoWhile:
        {
            var n = Tree.GetDoWhile(s);
            Line(indent, role, "DoWhile" + at);
            DumpStmt(indent + 1, "body", n.Body);
            DumpExpr(indent + 1, "cond", n.Cond);
            break;
        }
        case StmtKind.For:
        {
            var n = Tree.GetFor(s);
            Line(indent, role, "For" + at);
            DumpStmt(indent + 1, "init", n.Init);
            DumpExpr(indent + 1, "cond", n.Cond);
            for (var i = 0; i < n.Iterators.Length; i += 1)
                DumpExpr(indent + 1, "iterators[" + i.ToString() + "]", n.Iterators[i]);
            DumpStmt(indent + 1, "body", n.Body);
            break;
        }
        case StmtKind.Foreach:
        {
            var n = Tree.GetForeach(s);
            Line(indent, role, "Foreach" + at + " name=" + n.Name + TypeAttr("type", n.Type));
            DumpExpr(indent + 1, "iterable", n.Iterable);
            DumpStmt(indent + 1, "body", n.Body);
            break;
        }
        case StmtKind.Switch:
        {
            var n = Tree.GetSwitch(s);
            Line(indent, role, "Switch" + at);
            DumpExpr(indent + 1, "subject", n.Subject);
            for (var i = 0; i < n.Sections.Length; i += 1)
            {
                var section = n.Sections[i];
                Line(indent + 1, "", "section" + At(section.Loc));
                for (var k = 0; k < section.Labels.Length; k += 1)
                {
                    var label = section.Labels[k];
                    Line(indent + 2, "", "label" + At(label.Loc) + Flag(label.IsDefault, "default") +
                                         TypeAttr("patType", label.PatType) + (label.PatName != null && label.PatName.Length > 0 ? " patName=" + label.PatName : ""));
                    DumpExpr(indent + 3, "value", label.Value);
                }
                for (var k = 0; k < section.Body.Length; k += 1)
                    DumpStmt(indent + 2, "body[" + k.ToString() + "]", section.Body[k]);
            }
            break;
        }
        case StmtKind.Break:
            Line(indent, role, "Break" + at);
            break;
        case StmtKind.Continue:
            Line(indent, role, "Continue" + at);
            break;
        case StmtKind.Return:
        {
            var n = Tree.GetReturn(s);
            Line(indent, role, "Return" + at);
            DumpExpr(indent + 1, "value", n.Value);
            break;
        }
        case StmtKind.UsingBlock:
        {
            var n = Tree.GetUsingBlock(s);
            Line(indent, role, "UsingBlock" + at);
            DumpStmt(indent + 1, "decl", n.Decl);
            DumpStmt(indent + 1, "body", n.Body);
            break;
        }
        case StmtKind.Empty:
            Line(indent, role, "Empty" + at);
            break;
        default:
            Line(indent, role, "?" + at);
            break;
        }
    }

    // ---- declarations ----

    void DumpConstraints(int indent, Constraint[] constraints)
    {
        for (var i = 0; i < constraints.Length; i += 1)
            Line(indent, "", "Constraint param=" + constraints[i].Param + " bounds=" + TypeList(constraints[i].Bounds));
    }

    void DumpFunc(int indent, string role, FuncDecl f)
    {
        Line(indent, role, "Func" + At(f.Loc) + " name=" + f.Name + TypeAttr("ret", f.Ret) + Flag(f.IsStatic, "static") +
                           Flag(f.IsExtern, "extern") + Flag(f.IsVariadic, "variadic") +
                           (f.TypeParams.Length > 0 ? " typeParams=" + NameList(f.TypeParams) : ""));
        for (var i = 0; i < f.Params.Length; i += 1)
        {
            var p = f.Params[i];
            Line(indent + 1, "", "Param" + At(p.Loc) + " name=" + p.Name + TypeAttr("type", p.Type) +
                                 (p.Ref != RefKind.None ? " ref=" + ((int)p.Ref).ToString() : ""));
        }
        DumpConstraints(indent + 1, f.Constraints);
        DumpStmt(indent + 1, "body", f.Body);
    }

    void DumpUnit(CompilationUnit unit)
    {
        var usings = unit.File.Usings.ToArray();
        var links = unit.Links.ToArray();
        Line(0, "", "Unit ns=" + unit.File.Ns + " usings=" + NameList(usings) + " links=" + NameList(links));

        for (var i = 0; i < unit.Imports.Count(); i += 1)
        {
            var d = unit.Imports.Get(i);
            Line(1, "", "Import" + At(d.Loc) + " name=" + d.Name + " header=\"" + EscapeText(d.Header) + "\"");
        }
        for (var i = 0; i < unit.Consts.Count(); i += 1)
        {
            var d = unit.Consts.Get(i);
            Line(1, "", "Const" + At(d.Loc) + " name=" + d.Name + TypeAttr("type", d.Type));
            DumpExpr(2, "init", d.Init);
        }
        for (var i = 0; i < unit.Structs.Count(); i += 1)
        {
            var d = unit.Structs.Get(i);
            Line(1, "", "Struct" + At(d.Loc) + " name=" + d.Name + (d.TypeParams.Length > 0 ? " typeParams=" + NameList(d.TypeParams) : "") +
                        (d.Bases.Length > 0 ? " bases=" + TypeList(d.Bases) : ""));
            DumpConstraints(2, d.Constraints);
            for (var k = 0; k < d.Fields.Length; k += 1)
            {
                var f = d.Fields[k];
                Line(2, "", "Field" + At(f.Loc) + " name=" + f.Name + TypeAttr("type", f.Type));
            }
            for (var k = 0; k < d.Methods.Length; k += 1)
                DumpFunc(2, "", d.Methods[k]);
        }
        for (var i = 0; i < unit.Interfaces.Count(); i += 1)
        {
            var d = unit.Interfaces.Get(i);
            Line(1, "", "Interface" + At(d.Loc) + " name=" + d.Name + (d.TypeParams.Length > 0 ? " typeParams=" + NameList(d.TypeParams) : ""));
            for (var k = 0; k < d.Methods.Length; k += 1)
                DumpFunc(2, "", d.Methods[k]);
        }
        for (var i = 0; i < unit.Enums.Count(); i += 1)
        {
            var d = unit.Enums.Get(i);
            Line(1, "", "Enum" + At(d.Loc) + " name=" + d.Name + TypeAttr("base", d.Base));
            for (var k = 0; k < d.Members.Length; k += 1)
            {
                var m = d.Members[k];
                Line(2, "", "Member" + At(m.Loc) + " name=" + m.Name);
                DumpExpr(3, "value", m.Value);
            }
        }
        for (var i = 0; i < unit.Funcs.Count(); i += 1)
            DumpFunc(1, "", unit.Funcs.Get(i));
    }
}
