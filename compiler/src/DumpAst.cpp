// Text dump of the syntax tree (see Dump.h). The format is shared with selfhost/src/Syntax/AstDump.csh.

#include <cstring>

#include "Dump.h"

namespace
{
std::string escapeText(const std::string& s)
{
    std::string out;
    for (unsigned char c : s)
    {
        if (c == '\\')
            out += "\\\\";
        else if (c == '"')
            out += "\\\"";
        else if (c >= 32 && c < 127)
            out += (char)c;
        else
        {
            static const char digits[] = "0123456789abcdef";
            out += "\\x";
            out += digits[(c >> 4) & 15];
            out += digits[c & 15];
        }
    }
    return out;
}

std::string doubleBits(double value)
{
    uint64_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    std::string s;
    for (int shift = 60; shift >= 0; shift -= 4)
        s += "0123456789abcdef"[(bits >> shift) & 15];
    return s;
}

class Dumper
{
public:
    explicit Dumper(std::ostream& out) : out(out) {}

    void unit(const CompilationUnit& u)
    {
        line(0, "", "Unit ns=" + u.file.ns + " usings=" + names(u.file.usings) + " links=" + names(u.links));
        for (const auto& d : u.imports)
            line(1, "", "Import" + at(d.loc) + " name=" + d.name + " header=\"" + escapeText(d.header) + "\"");
        for (const auto& d : u.consts)
        {
            line(1, "", "Const" + at(d->loc) + " name=" + d->name + typeAttr("type", d->type.get()));
            expr(2, "init", d->init.get());
        }
        for (const auto& d : u.globals)
        {
            line(1, "", "Global" + at(d->loc) + " name=" + d->name + typeAttr("type", d->type.get()));
            if (d->init)
                expr(2, "init", d->init.get());
        }
        for (const auto& d : u.structs)
        {
            line(1, "", "Struct" + at(d->loc) + " name=" + d->name +
                            (d->typeParams.empty() ? "" : " typeParams=" + names(d->typeParams)) +
                            (d->bases.empty() ? "" : " bases=" + typeList(d->bases)));
            constraints(2, d->constraints);
            for (const auto& f : d->fields)
                line(2, "", "Field" + at(f.loc) + " name=" + f.name + typeAttr("type", f.type.get()));
            for (const auto& m : d->methods)
                func(2, "", *m);
        }
        for (const auto& d : u.interfaces)
        {
            line(1, "", "Interface" + at(d->loc) + " name=" + d->name +
                            (d->typeParams.empty() ? "" : " typeParams=" + names(d->typeParams)));
            for (const auto& m : d->methods)
                func(2, "", *m);
        }
        for (const auto& d : u.enums)
        {
            line(1, "", "Enum" + at(d->loc) + " name=" + d->name + typeAttr("base", d->base.get()));
            for (const auto& m : d->members)
            {
                line(2, "", "Member" + at(m.loc) + " name=" + m.name);
                expr(3, "value", m.value.get());
            }
        }
        for (const auto& f : u.funcs)
            func(1, "", *f);
    }

private:
    std::ostream& out;

    static std::string at(SourceLoc loc) { return "@" + std::to_string(loc.line) + ":" + std::to_string(loc.col); }

    void line(int indent, const std::string& role, const std::string& text)
    {
        for (int i = 0; i < indent; i += 1)
            out << "  ";
        if (!role.empty())
            out << role << ": ";
        out << text << "\n";
    }

    static std::string flag(bool value, const char* name) { return value ? std::string(" ") + name : std::string(); }

    static std::string names(const std::vector<std::string>& v)
    {
        std::string s = "[";
        for (size_t i = 0; i < v.size(); i += 1)
            s += (i ? "," : "") + v[i];
        return s + "]";
    }

    static std::string typeAttr(const char* name, const TypeRef* t)
    {
        if (!t)
            return "";
        return std::string(" ") + name + "=" + t->toString();
    }

    static std::string typeList(const std::vector<TypeRefPtr>& types)
    {
        std::string s = "[";
        for (size_t i = 0; i < types.size(); i += 1)
            s += (i ? "," : "") + types[i]->toString();
        return s + "]";
    }

    void constraints(int indent, const std::vector<Constraint>& list)
    {
        for (const auto& c : list)
            line(indent, "", "Constraint param=" + c.param + " bounds=" + typeList(c.bounds));
    }

    void func(int indent, const std::string& role, const FuncDecl& f)
    {
        line(indent, role, "Func" + at(f.loc) + " name=" + f.name + typeAttr("ret", f.ret.get()) + flag(f.isStatic, "static") +
                               flag(f.isExtern, "extern") + flag(f.isVariadic, "variadic") +
                               (f.typeParams.empty() ? "" : " typeParams=" + names(f.typeParams)));
        for (const auto& p : f.params)
            line(indent + 1, "", "Param" + at(p.loc) + " name=" + p.name + typeAttr("type", p.type.get()) +
                                     (p.refKind != RefKind::None ? " ref=" + std::to_string((int)p.refKind) : ""));
        constraints(indent + 1, f.constraints);
        if (f.body)
            stmt(indent + 1, "body", f.body.get());
    }

    void expr(int indent, const std::string& role, const Expr* e)
    {
        if (!e)
            return;
        std::string loc = at(e->loc);
        switch (e->kind)
        {
        case ExprKind::IntLit:
        {
            auto* n = static_cast<const IntLitExpr*>(e);
            line(indent, role, "IntLit" + loc + " value=" + std::to_string(n->value) + flag(n->isUnsigned, "u") + flag(n->isLong, "l"));
            break;
        }
        case ExprKind::FloatLit:
        {
            auto* n = static_cast<const FloatLitExpr*>(e);
            line(indent, role, "FloatLit" + loc + " bits=" + doubleBits(n->value) + flag(n->isFloat32, "f"));
            break;
        }
        case ExprKind::CharLit:
            line(indent, role, "CharLit" + loc + " value=" + std::to_string((int)static_cast<const CharLitExpr*>(e)->value));
            break;
        case ExprKind::StringLit:
            line(indent, role, "StringLit" + loc + " value=\"" + escapeText(static_cast<const StringLitExpr*>(e)->value) + "\"");
            break;
        case ExprKind::BoolLit:
            line(indent, role, "BoolLit" + loc + " value=" + (static_cast<const BoolLitExpr*>(e)->value ? "true" : "false"));
            break;
        case ExprKind::NullLit: line(indent, role, "NullLit" + loc); break;
        case ExprKind::This: line(indent, role, "This" + loc); break;
        case ExprKind::Name:
        {
            auto* n = static_cast<const NameExpr*>(e);
            line(indent, role, "Name" + loc + " name=" + n->name + (n->typeArgs.empty() ? "" : " typeArgs=" + typeList(n->typeArgs)));
            break;
        }
        case ExprKind::Member:
        {
            auto* n = static_cast<const MemberExpr*>(e);
            line(indent, role, "Member" + loc + " name=" + n->name + flag(n->viaArrow, "arrow") +
                                   (n->typeArgs.empty() ? "" : " typeArgs=" + typeList(n->typeArgs)));
            expr(indent + 1, "object", n->object.get());
            break;
        }
        case ExprKind::Call:
        {
            auto* n = static_cast<const CallExpr*>(e);
            line(indent, role, "Call" + loc);
            expr(indent + 1, "callee", n->callee.get());
            for (size_t i = 0; i < n->args.size(); i += 1)
                expr(indent + 1, "args[" + std::to_string(i) + "]", n->args[i].get());
            break;
        }
        case ExprKind::Index:
        {
            auto* n = static_cast<const IndexExpr*>(e);
            line(indent, role, "Index" + loc);
            expr(indent + 1, "object", n->object.get());
            expr(indent + 1, "index", n->index.get());
            break;
        }
        case ExprKind::Unary:
        {
            auto* n = static_cast<const UnaryExpr*>(e);
            line(indent, role, "Unary" + loc + " op=" + std::to_string((int)n->op));
            expr(indent + 1, "operand", n->operand.get());
            break;
        }
        case ExprKind::Binary:
        {
            auto* n = static_cast<const BinaryExpr*>(e);
            line(indent, role, "Binary" + loc + " op=" + std::to_string((int)n->op));
            expr(indent + 1, "lhs", n->lhs.get());
            expr(indent + 1, "rhs", n->rhs.get());
            break;
        }
        case ExprKind::Assign:
        {
            auto* n = static_cast<const AssignExpr*>(e);
            line(indent, role, "Assign" + loc + (n->op ? " op=" + std::to_string((int)*n->op) : ""));
            expr(indent + 1, "target", n->target.get());
            expr(indent + 1, "value", n->value.get());
            break;
        }
        case ExprKind::Conditional:
        {
            auto* n = static_cast<const CondExpr*>(e);
            line(indent, role, "Conditional" + loc);
            expr(indent + 1, "cond", n->cond.get());
            expr(indent + 1, "then", n->thenExpr.get());
            expr(indent + 1, "else", n->elseExpr.get());
            break;
        }
        case ExprKind::Cast:
        {
            auto* n = static_cast<const CastExpr*>(e);
            line(indent, role, "Cast" + loc + typeAttr("type", n->type.get()));
            expr(indent + 1, "operand", n->operand.get());
            break;
        }
        case ExprKind::NewArray:
        {
            auto* n = static_cast<const NewArrayExpr*>(e);
            line(indent, role, "NewArray" + loc + typeAttr("elem", n->elemType.get()) + flag(n->hasInit, "hasInit"));
            expr(indent + 1, "size", n->size.get());
            for (size_t i = 0; i < n->init.size(); i += 1)
                expr(indent + 1, "init[" + std::to_string(i) + "]", n->init[i].get());
            break;
        }
        case ExprKind::NewObject:
            line(indent, role, "NewObject" + loc + typeAttr("type", static_cast<const NewObjectExpr*>(e)->type.get()));
            break;
        case ExprKind::StructInit:
        {
            auto* n = static_cast<const StructInitExpr*>(e);
            line(indent, role, "StructInit" + loc + typeAttr("type", n->type.get()));
            for (const auto& f : n->fields)
            {
                line(indent + 1, "", "field" + at(f.loc) + " name=" + f.name);
                expr(indent + 2, "value", f.value.get());
            }
            break;
        }
        case ExprKind::Is:
        {
            auto* n = static_cast<const IsExpr*>(e);
            line(indent, role, "Is" + loc + typeAttr("type", n->type.get()) + (n->bindName.empty() ? "" : " bind=" + n->bindName));
            expr(indent + 1, "operand", n->operand.get());
            break;
        }
        case ExprKind::Try:
            line(indent, role, "Try" + loc);
            expr(indent + 1, "operand", static_cast<const TryExpr*>(e)->operand.get());
            break;
        case ExprKind::ErrorLit:
        {
            auto* n = static_cast<const ErrorLitExpr*>(e);
            line(indent, role, "ErrorLit" + loc);
            expr(indent + 1, "message", n->message.get());
            expr(indent + 1, "code", n->code.get());
            break;
        }
        case ExprKind::SizeOf:
            line(indent, role, "SizeOf" + loc + typeAttr("type", static_cast<const SizeOfExpr*>(e)->type.get()));
            break;
        case ExprKind::Default:
            line(indent, role, "Default" + loc + typeAttr("type", static_cast<const DefaultExpr*>(e)->type.get()));
            break;
        case ExprKind::Unchecked:
            line(indent, role, "Unchecked" + loc);
            expr(indent + 1, "operand", static_cast<const UncheckedExpr*>(e)->operand.get());
            break;
        case ExprKind::RefArg:
            line(indent, role, "RefArg" + loc);
            expr(indent + 1, "operand", static_cast<const RefArgExpr*>(e)->operand.get());
            break;
        }
    }

    void stmt(int indent, const std::string& role, const Stmt* s)
    {
        if (!s)
            return;
        std::string loc = at(s->loc);
        switch (s->kind)
        {
        case StmtKind::Block:
        {
            auto* n = static_cast<const BlockStmt*>(s);
            line(indent, role, "Block" + loc + flag(n->isUnsafe, "unsafe") + flag(n->isUnchecked, "unchecked"));
            for (size_t i = 0; i < n->stmts.size(); i += 1)
                stmt(indent + 1, "stmts[" + std::to_string(i) + "]", n->stmts[i].get());
            break;
        }
        case StmtKind::VarDecl:
        {
            auto* n = static_cast<const VarDeclStmt*>(s);
            line(indent, role, "VarDecl" + loc + " name=" + n->name + typeAttr("type", n->type.get()) + flag(n->isUsing, "using") + flag(n->isConst, "const"));
            expr(indent + 1, "init", n->init.get());
            break;
        }
        case StmtKind::Expr:
            line(indent, role, "ExprStmt" + loc);
            expr(indent + 1, "expr", static_cast<const ExprStmt*>(s)->expr.get());
            break;
        case StmtKind::If:
        {
            auto* n = static_cast<const IfStmt*>(s);
            line(indent, role, "If" + loc);
            expr(indent + 1, "cond", n->cond.get());
            stmt(indent + 1, "then", n->thenStmt.get());
            stmt(indent + 1, "else", n->elseStmt.get());
            break;
        }
        case StmtKind::While:
        {
            auto* n = static_cast<const WhileStmt*>(s);
            line(indent, role, "While" + loc);
            expr(indent + 1, "cond", n->cond.get());
            stmt(indent + 1, "body", n->body.get());
            break;
        }
        case StmtKind::DoWhile:
        {
            auto* n = static_cast<const DoWhileStmt*>(s);
            line(indent, role, "DoWhile" + loc);
            stmt(indent + 1, "body", n->body.get());
            expr(indent + 1, "cond", n->cond.get());
            break;
        }
        case StmtKind::For:
        {
            auto* n = static_cast<const ForStmt*>(s);
            line(indent, role, "For" + loc);
            stmt(indent + 1, "init", n->init.get());
            expr(indent + 1, "cond", n->cond.get());
            for (size_t i = 0; i < n->iterators.size(); i += 1)
                expr(indent + 1, "iterators[" + std::to_string(i) + "]", n->iterators[i].get());
            stmt(indent + 1, "body", n->body.get());
            break;
        }
        case StmtKind::Foreach:
        {
            auto* n = static_cast<const ForeachStmt*>(s);
            line(indent, role, "Foreach" + loc + " name=" + n->name + typeAttr("type", n->type.get()));
            expr(indent + 1, "iterable", n->iterable.get());
            stmt(indent + 1, "body", n->body.get());
            break;
        }
        case StmtKind::Switch:
        {
            auto* n = static_cast<const SwitchStmt*>(s);
            line(indent, role, "Switch" + loc);
            expr(indent + 1, "subject", n->subject.get());
            for (const auto& section : n->sections)
            {
                line(indent + 1, "", "section" + at(section.loc));
                for (const auto& label : section.labels)
                {
                    line(indent + 2, "", "label" + at(label.loc) + flag(label.isDefault, "default") +
                                             typeAttr("patType", label.patType.get()) +
                                             (label.patName.empty() ? "" : " patName=" + label.patName));
                    expr(indent + 3, "value", label.value.get());
                }
                for (size_t k = 0; k < section.body.size(); k += 1)
                    stmt(indent + 2, "body[" + std::to_string(k) + "]", section.body[k].get());
            }
            break;
        }
        case StmtKind::Break: line(indent, role, "Break" + loc); break;
        case StmtKind::Continue: line(indent, role, "Continue" + loc); break;
        case StmtKind::Return:
            line(indent, role, "Return" + loc);
            expr(indent + 1, "value", static_cast<const ReturnStmt*>(s)->value.get());
            break;
        case StmtKind::UsingBlock:
        {
            auto* n = static_cast<const UsingBlockStmt*>(s);
            line(indent, role, "UsingBlock" + loc);
            stmt(indent + 1, "decl", n->decl.get());
            stmt(indent + 1, "body", n->body.get());
            break;
        }
        case StmtKind::Empty: line(indent, role, "Empty" + loc); break;
        }
    }
};
} // namespace

void dumpUnit(const CompilationUnit& unit, std::ostream& out)
{
    Dumper(out).unit(unit);
}
