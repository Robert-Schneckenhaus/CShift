#include "Parser.h"

namespace
{
bool isPrimitiveTypeName(const std::string& n)
{
    static const char* names[] = {"int",   "uint",  "float",  "double", "int8",   "int16", "int32",
                                  "int64", "uint8", "uint16", "uint32", "uint64", "float32", "float64",
                                  "bool",  "char",  "string", "void"};
    for (const char* p : names)
        if (n == p)
            return true;
    return false;
}
} // namespace

Parser::Parser(std::vector<Token> tokens, Diagnostics& diag) : tokens(std::move(tokens)), diag(diag) {}

// ---------------------------------------------------------------------------
// Token helpers
// ---------------------------------------------------------------------------

const Token& Parser::peekTok(size_t ahead) const
{
    size_t i = pos + ahead;
    return i < tokens.size() ? tokens[i] : tokens.back();
}

bool Parser::match(Tok kind)
{
    if (check(kind))
    {
        advance();
        return true;
    }
    return false;
}

const Token& Parser::advance()
{
    const Token& t = tokens[pos];
    if (pos + 1 < tokens.size())
        pos += 1;
    return t;
}

void Parser::errorHere(const std::string& message)
{
    fail(cur().loc, message);
}

const Token& Parser::expect(Tok kind, const char* what)
{
    if (!check(kind))
    {
        // Identifiers and keywords carry their text.
        std::string found = tokenName(cur().kind);
        if (!cur().text.empty() && cur().kind != Tok::StringLit)
            found = "'" + cur().text + "'";
        errorHere(std::string("expected ") + what + ", found " + found);
    }
    return advance();
}

std::string Parser::expectIdent(const char* what)
{
    return expect(Tok::Ident, what).text;
}

bool Parser::adjacent(const Token& a, const Token& b) const
{
    return a.loc.file == b.loc.file && a.loc.line == b.loc.line && a.loc.col + 1 == b.loc.col;
}

// ---------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------

std::unique_ptr<CompilationUnit> Parser::parseUnit(bool isPrelude)
{
    auto u = std::make_unique<CompilationUnit>();
    u->file.fileId = tokens.empty() ? 0 : tokens[0].loc.file;
    u->file.isPrelude = isPrelude;
    unit = u.get();

    while (!check(Tok::Eof))
    {
        size_t before = pos;
        try
        {
            parseTopLevel(*u);
        }
        catch (const CompileError& e)
        {
            diag.error(e);
            synchronizeTopLevel();
            if (pos == before)
                advance();
        }
    }
    return u;
}

void Parser::synchronizeTopLevel()
{
    // Skip to the next token that starts in column 1 (top-level declarations).
    while (!check(Tok::Eof))
    {
        if (cur().loc.col == 1 && !check(Tok::RBrace))
            return;
        advance();
    }
}

std::string Parser::parseQualifiedName()
{
    std::string name = expectIdent("name");
    while (check(Tok::Dot) && peekTok().kind == Tok::Ident)
    {
        advance();
        name += "." + advance().text;
    }
    return name;
}

void Parser::parseTopLevel(CompilationUnit& u)
{
    if (check(Tok::KwNamespace))
    {
        SourceLoc loc = advance().loc;
        if (!u.file.ns.empty())
            fail(loc, "only one file-scoped namespace is allowed per file");
        u.file.ns = parseQualifiedName();
        expect(Tok::Semi, "';' after namespace");
    }
    else if (check(Tok::KwUsing))
    {
        advance();
        u.file.usings.push_back(parseQualifiedName());
        expect(Tok::Semi, "';' after using");
    }
    else if (checkIdent("link") && peekTok().kind == Tok::StringLit)
    {
        advance();
        u.links.push_back(advance().text);
        match(Tok::Semi);
    }
    else if (check(Tok::KwStruct))
    {
        u.structs.push_back(parseStruct(u));
    }
    else if (check(Tok::KwInterface))
    {
        u.interfaces.push_back(parseInterface(u));
    }
    else if (check(Tok::KwEnum))
    {
        u.enums.push_back(parseEnum(u));
    }
    else if (check(Tok::KwExtern))
    {
        advance();
        const Token& abi = expect(Tok::StringLit, "ABI string, e.g. extern \"C\"");
        if (abi.text != "C")
            fail(abi.loc, "only extern \"C\" is supported");
        u.funcs.push_back(parseFunction(u, true, false));
    }
    else if (check(Tok::Ident))
    {
        u.funcs.push_back(parseFunction(u, false, false));
    }
    else
    {
        errorHere(std::string("unexpected ") + tokenName(cur().kind) + " at top level");
    }
}

void Parser::parseTypeParams(std::vector<std::string>& out)
{
    expect(Tok::Lt, "'<'");
    do
    {
        out.push_back(expectIdent("type parameter name"));
    } while (match(Tok::Comma));
    expect(Tok::Gt, "'>'");
}

void Parser::parseConstraints(std::vector<Constraint>& out)
{
    while (match(Tok::KwWhere))
    {
        Constraint c;
        c.param = expectIdent("type parameter name");
        expect(Tok::Colon, "':'");
        do
        {
            c.bounds.push_back(parseType());
        } while (match(Tok::Comma));
        out.push_back(std::move(c));
    }
}

std::unique_ptr<StructDecl> Parser::parseStruct(CompilationUnit& u)
{
    auto decl = std::make_unique<StructDecl>();
    decl->file = &u.file;
    decl->loc = expect(Tok::KwStruct, "'struct'").loc;
    decl->name = expectIdent("struct name");
    if (check(Tok::Lt))
        parseTypeParams(decl->typeParams);
    if (match(Tok::Colon))
    {
        do
        {
            decl->bases.push_back(parseType());
        } while (match(Tok::Comma));
    }
    parseConstraints(decl->constraints);
    expect(Tok::LBrace, "'{'");

    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        bool isStatic = match(Tok::KwStatic);
        SourceLoc memberLoc = cur().loc;
        TypeRefPtr type = parseType();
        std::string name = expectIdent("member name");

        if (check(Tok::LParen) || check(Tok::Lt))
        {
            auto fn = std::make_unique<FuncDecl>();
            fn->loc = memberLoc;
            fn->name = name;
            fn->ret = std::move(type);
            fn->isStatic = isStatic;
            fn->owner = decl.get();
            fn->file = &u.file;
            parseFunctionRest(*fn, u);
            decl->methods.push_back(std::move(fn));
        }
        else
        {
            if (isStatic)
                fail(memberLoc, "static fields are not supported");
            FieldDecl f;
            f.loc = memberLoc;
            f.type = std::move(type);
            f.name = name;
            decl->fields.push_back(std::move(f));
            expect(Tok::Semi, "';' after field");
        }
    }
    expect(Tok::RBrace, "'}'");
    return decl;
}

std::unique_ptr<InterfaceDecl> Parser::parseInterface(CompilationUnit& u)
{
    auto decl = std::make_unique<InterfaceDecl>();
    decl->file = &u.file;
    decl->loc = expect(Tok::KwInterface, "'interface'").loc;
    decl->name = expectIdent("interface name");
    if (check(Tok::Lt))
        parseTypeParams(decl->typeParams);
    expect(Tok::LBrace, "'{'");
    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        auto fn = std::make_unique<FuncDecl>();
        fn->loc = cur().loc;
        fn->ret = parseType();
        fn->name = expectIdent("method name");
        fn->file = &u.file;
        parseFunctionRest(*fn, u);
        if (fn->body)
            fail(fn->loc, "interface methods cannot have a body");
        decl->methods.push_back(std::move(fn));
    }
    expect(Tok::RBrace, "'}'");
    return decl;
}

std::unique_ptr<EnumDecl> Parser::parseEnum(CompilationUnit& u)
{
    auto decl = std::make_unique<EnumDecl>();
    decl->file = &u.file;
    decl->loc = expect(Tok::KwEnum, "'enum'").loc;
    decl->name = expectIdent("enum name");
    if (!match(Tok::Colon))
        fail(decl->loc, "enums require an explicit integer base type, e.g. 'enum " + decl->name + " : uint8'");
    decl->base = parseType();
    expect(Tok::LBrace, "'{'");
    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        EnumMember m;
        m.loc = cur().loc;
        m.name = expectIdent("enum member name");
        if (match(Tok::Assign))
            m.value = parseExpr();
        decl->members.push_back(std::move(m));
        if (!match(Tok::Comma))
            break;
    }
    expect(Tok::RBrace, "'}'");
    return decl;
}

std::unique_ptr<FuncDecl> Parser::parseFunction(CompilationUnit& u, bool isExtern, bool isStatic)
{
    auto fn = std::make_unique<FuncDecl>();
    fn->file = &u.file;
    fn->isExtern = isExtern;
    fn->isStatic = isStatic;
    fn->ret = parseType();
    fn->loc = cur().loc;
    fn->name = expectIdent("function name");
    parseFunctionRest(*fn, u);
    return fn;
}

void Parser::parseParams(FuncDecl& fn)
{
    expect(Tok::LParen, "'('");
    if (!check(Tok::RParen))
    {
        do
        {
            if (match(Tok::Ellipsis))
            {
                fn.isVariadic = true;
                break;
            }
            Param p;
            p.loc = cur().loc;
            if (match(Tok::KwConst))
            {
                expect(Tok::KwRef, "'ref' after 'const'");
                p.refKind = RefKind::ConstRef;
            }
            else if (match(Tok::KwRef))
            {
                p.refKind = RefKind::Ref;
            }
            p.type = parseType();
            if (check(Tok::Ident))
                p.name = advance().text;
            fn.params.push_back(std::move(p));
        } while (match(Tok::Comma));
    }
    expect(Tok::RParen, "')'");
}

void Parser::parseFunctionRest(FuncDecl& fn, CompilationUnit& u)
{
    (void)u;
    if (check(Tok::Lt))
        parseTypeParams(fn.typeParams);
    parseParams(fn);
    parseConstraints(fn.constraints);
    if (check(Tok::LBrace))
        fn.body = parseBlock();
    else
        expect(Tok::Semi, "';' or function body");
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

TypeRefPtr Parser::parseNamedType()
{
    auto t = std::make_unique<TypeRef>();
    t->kind = TypeRef::Named;
    t->loc = cur().loc;
    t->path.push_back(expectIdent("type name"));
    while (check(Tok::Dot) && peekTok().kind == Tok::Ident)
    {
        advance();
        t->path.push_back(advance().text);
    }
    if (check(Tok::Lt))
    {
        advance();
        do
        {
            t->args.push_back(parseType());
        } while (match(Tok::Comma));
        expect(Tok::Gt, "'>'");
    }
    return t;
}

TypeRefPtr Parser::parseType()
{
    TypeRefPtr t = parseNamedType();
    while (true)
    {
        if (check(Tok::Star))
        {
            auto p = std::make_unique<TypeRef>();
            p->kind = TypeRef::Pointer;
            p->loc = cur().loc;
            advance();
            p->elem = std::move(t);
            t = std::move(p);
        }
        else if (check(Tok::LBracket) && peekTok().kind == Tok::RBracket)
        {
            auto a = std::make_unique<TypeRef>();
            a->kind = TypeRef::Array;
            a->loc = cur().loc;
            advance();
            advance();
            a->elem = std::move(t);
            t = std::move(a);
        }
        else
            break;
    }
    return t;
}

TypeRefPtr Parser::tryParseType()
{
    size_t save = pos;
    try
    {
        return parseType();
    }
    catch (const CompileError&)
    {
        pos = save;
        return nullptr;
    }
}

bool Parser::tryParseTypeArgs(std::vector<TypeRefPtr>& out)
{
    size_t save = pos;
    try
    {
        expect(Tok::Lt, "'<'");
        do
        {
            out.push_back(parseType());
        } while (match(Tok::Comma));
        expect(Tok::Gt, "'>'");
        return true;
    }
    catch (const CompileError&)
    {
        pos = save;
        out.clear();
        return false;
    }
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

std::unique_ptr<BlockStmt> Parser::parseBlock()
{
    auto block = std::make_unique<BlockStmt>(cur().loc);
    expect(Tok::LBrace, "'{'");
    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        size_t before = pos;
        try
        {
            block->stmts.push_back(parseStatement());
        }
        catch (const CompileError& e)
        {
            diag.error(e);
            synchronizeStatement();
            if (pos == before)
                advance();
        }
    }
    expect(Tok::RBrace, "'}'");
    return block;
}

void Parser::synchronizeStatement()
{
    while (!check(Tok::Eof))
    {
        if (check(Tok::Semi))
        {
            advance();
            return;
        }
        if (check(Tok::RBrace))
            return;
        advance();
    }
}

StmtPtr Parser::parseStatement()
{
    SourceLoc loc = cur().loc;
    switch (cur().kind)
    {
    case Tok::LBrace: return parseBlock();
    case Tok::Semi:
        advance();
        return std::make_unique<EmptyStmt>(loc);
    case Tok::KwIf: return parseIf();
    case Tok::KwWhile: return parseWhile();
    case Tok::KwDo: return parseDoWhile();
    case Tok::KwFor: return parseFor();
    case Tok::KwForeach: return parseForeach();
    case Tok::KwSwitch: return parseSwitch();
    case Tok::KwUsing: return parseUsing();
    case Tok::KwBreak:
        advance();
        expect(Tok::Semi, "';'");
        return std::make_unique<BreakStmt>(loc);
    case Tok::KwContinue:
        advance();
        expect(Tok::Semi, "';'");
        return std::make_unique<ContinueStmt>(loc);
    case Tok::KwReturn:
    {
        advance();
        auto r = std::make_unique<ReturnStmt>(loc);
        if (!check(Tok::Semi))
            r->value = parseExpr();
        expect(Tok::Semi, "';'");
        return r;
    }
    case Tok::KwUnsafe:
        if (peekTok().kind == Tok::LBrace)
        {
            advance();
            auto b = parseBlock();
            b->isUnsafe = true;
            return b;
        }
        break;
    case Tok::KwUnchecked:
        if (peekTok().kind == Tok::LBrace)
        {
            advance();
            auto b = parseBlock();
            b->isUnchecked = true;
            return b;
        }
        break;
    default: break;
    }
    return parseSimpleStatement(true);
}

std::unique_ptr<VarDeclStmt> Parser::tryParseVarDecl()
{
    if (!check(Tok::Ident))
        return nullptr;
    size_t save = pos;
    SourceLoc loc = cur().loc;
    TypeRefPtr t = tryParseType();
    if (t && check(Tok::Ident) && (peekTok().kind == Tok::Assign || peekTok().kind == Tok::Semi))
    {
        auto d = std::make_unique<VarDeclStmt>(loc);
        d->name = advance().text;
        if (match(Tok::Assign))
            d->init = parseExpr();
        bool isVar = t->kind == TypeRef::Named && t->path.size() == 1 && t->path[0] == "var" && t->args.empty();
        if (!isVar)
            d->type = std::move(t);
        return d;
    }
    pos = save;
    return nullptr;
}

StmtPtr Parser::parseSimpleStatement(bool expectSemi)
{
    SourceLoc loc = cur().loc;
    if (auto decl = tryParseVarDecl())
    {
        if (expectSemi)
            expect(Tok::Semi, "';' after declaration");
        return decl;
    }
    auto s = std::make_unique<ExprStmt>(loc);
    s->expr = parseExpr();
    if (expectSemi)
        expect(Tok::Semi, "';' after expression");
    return s;
}

StmtPtr Parser::parseIf()
{
    auto s = std::make_unique<IfStmt>(advance().loc);
    expect(Tok::LParen, "'(' after 'if'");
    s->cond = parseExpr();
    expect(Tok::RParen, "')'");
    s->thenStmt = parseStatement();
    if (match(Tok::KwElse))
        s->elseStmt = parseStatement();
    return s;
}

StmtPtr Parser::parseWhile()
{
    auto s = std::make_unique<WhileStmt>(advance().loc);
    expect(Tok::LParen, "'(' after 'while'");
    s->cond = parseExpr();
    expect(Tok::RParen, "')'");
    s->body = parseStatement();
    return s;
}

StmtPtr Parser::parseDoWhile()
{
    auto s = std::make_unique<DoWhileStmt>(advance().loc);
    s->body = parseStatement();
    expect(Tok::KwWhile, "'while' after do-body");
    expect(Tok::LParen, "'('");
    s->cond = parseExpr();
    expect(Tok::RParen, "')'");
    expect(Tok::Semi, "';'");
    return s;
}

StmtPtr Parser::parseFor()
{
    auto s = std::make_unique<ForStmt>(advance().loc);
    expect(Tok::LParen, "'(' after 'for'");
    if (!check(Tok::Semi))
        s->init = parseSimpleStatement(false);
    expect(Tok::Semi, "';'");
    if (!check(Tok::Semi))
        s->cond = parseExpr();
    expect(Tok::Semi, "';'");
    if (!check(Tok::RParen))
    {
        do
        {
            s->iterators.push_back(parseExpr());
        } while (match(Tok::Comma));
    }
    expect(Tok::RParen, "')'");
    s->body = parseStatement();
    return s;
}

StmtPtr Parser::parseForeach()
{
    auto s = std::make_unique<ForeachStmt>(advance().loc);
    expect(Tok::LParen, "'(' after 'foreach'");
    TypeRefPtr t = parseType();
    bool isVar = t->kind == TypeRef::Named && t->path.size() == 1 && t->path[0] == "var" && t->args.empty();
    if (!isVar)
        s->type = std::move(t);
    s->name = expectIdent("loop variable name");
    expect(Tok::KwIn, "'in'");
    s->iterable = parseExpr();
    expect(Tok::RParen, "')'");
    s->body = parseStatement();
    return s;
}

StmtPtr Parser::parseSwitch()
{
    auto s = std::make_unique<SwitchStmt>(advance().loc);
    expect(Tok::LParen, "'(' after 'switch'");
    s->subject = parseExpr();
    expect(Tok::RParen, "')'");
    expect(Tok::LBrace, "'{'");

    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        SwitchSection section;
        section.loc = cur().loc;
        while (check(Tok::KwCase) || check(Tok::KwDefault))
        {
            CaseLabel label;
            label.loc = cur().loc;
            if (match(Tok::KwDefault))
            {
                label.isDefault = true;
            }
            else
            {
                advance(); // case
                size_t save = pos;
                TypeRefPtr t = tryParseType();
                if (t && check(Tok::Ident) && peekTok().kind == Tok::Colon)
                {
                    label.patType = std::move(t);
                    label.patName = advance().text;
                }
                else
                {
                    pos = save;
                    label.value = parseExpr();
                }
            }
            expect(Tok::Colon, "':' after case label");
            section.labels.push_back(std::move(label));
        }
        if (section.labels.empty())
            errorHere("expected 'case' or 'default' in switch");

        while (!check(Tok::KwCase) && !check(Tok::KwDefault) && !check(Tok::RBrace) && !check(Tok::Eof))
        {
            size_t before = pos;
            try
            {
                section.body.push_back(parseStatement());
            }
            catch (const CompileError& e)
            {
                diag.error(e);
                synchronizeStatement();
                if (pos == before)
                    advance();
            }
        }
        s->sections.push_back(std::move(section));
    }
    expect(Tok::RBrace, "'}'");
    return s;
}

StmtPtr Parser::parseUsing()
{
    SourceLoc loc = advance().loc; // using
    if (match(Tok::LParen))
    {
        auto s = std::make_unique<UsingBlockStmt>(loc);
        auto decl = std::make_unique<VarDeclStmt>(cur().loc);
        decl->isUsing = true;
        TypeRefPtr t = parseType();
        bool isVar = t->kind == TypeRef::Named && t->path.size() == 1 && t->path[0] == "var" && t->args.empty();
        if (!isVar)
            decl->type = std::move(t);
        decl->name = expectIdent("variable name");
        expect(Tok::Assign, "'='");
        decl->init = parseExpr();
        expect(Tok::RParen, "')'");
        s->decl = std::move(decl);
        s->body = parseStatement();
        return s;
    }

    // using name = expr;   or   using Type name = expr;
    auto decl = std::make_unique<VarDeclStmt>(loc);
    decl->isUsing = true;
    if (check(Tok::Ident) && peekTok().kind == Tok::Assign)
    {
        decl->name = advance().text;
    }
    else
    {
        TypeRefPtr t = parseType();
        bool isVar = t->kind == TypeRef::Named && t->path.size() == 1 && t->path[0] == "var" && t->args.empty();
        if (!isVar)
            decl->type = std::move(t);
        decl->name = expectIdent("variable name");
    }
    expect(Tok::Assign, "'=' in using declaration");
    decl->init = parseExpr();
    expect(Tok::Semi, "';'");
    return decl;
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

ExprPtr Parser::parseExpr()
{
    return parseAssignment();
}

bool Parser::assignOpAt(std::optional<BinOp>& op, int& count) const
{
    count = 1;
    op.reset();
    switch (cur().kind)
    {
    case Tok::Assign: return true;
    case Tok::PlusAssign: op = BinOp::Add; return true;
    case Tok::MinusAssign: op = BinOp::Sub; return true;
    case Tok::StarAssign: op = BinOp::Mul; return true;
    case Tok::SlashAssign: op = BinOp::Div; return true;
    case Tok::PercentAssign: op = BinOp::Rem; return true;
    case Tok::AmpAssign: op = BinOp::BitAnd; return true;
    case Tok::PipeAssign: op = BinOp::BitOr; return true;
    case Tok::CaretAssign: op = BinOp::BitXor; return true;
    case Tok::ShlAssign: op = BinOp::Shl; return true;
    case Tok::Gt:
        if (peekTok().kind == Tok::GtEq && adjacent(cur(), peekTok()))
        {
            op = BinOp::Shr;
            count = 2;
            return true;
        }
        return false;
    default: return false;
    }
}

ExprPtr Parser::parseAssignment()
{
    ExprPtr lhs = parseConditional();
    std::optional<BinOp> op;
    int count;
    if (assignOpAt(op, count))
    {
        SourceLoc loc = cur().loc;
        pos += count;
        auto a = std::make_unique<AssignExpr>(loc);
        a->op = op;
        a->target = std::move(lhs);
        a->value = parseAssignment();
        return a;
    }
    return lhs;
}

ExprPtr Parser::parseConditional()
{
    ExprPtr cond = parseBinary(1);
    if (check(Tok::Question))
    {
        auto c = std::make_unique<CondExpr>(advance().loc);
        c->cond = std::move(cond);
        c->thenExpr = parseAssignment();
        expect(Tok::Colon, "':' in conditional expression");
        c->elseExpr = parseAssignment();
        return c;
    }
    return cond;
}

bool Parser::binaryOpAt(BinOpInfo& out) const
{
    const Token& t = cur();
    auto set = [&](BinOp op, int prec, int count = 1) {
        out = BinOpInfo{op, prec, count, false};
        return true;
    };
    switch (t.kind)
    {
    case Tok::PipePipe: return set(BinOp::LogOr, 1);
    case Tok::AmpAmp: return set(BinOp::LogAnd, 2);
    case Tok::Pipe: return set(BinOp::BitOr, 3);
    case Tok::Caret: return set(BinOp::BitXor, 4);
    case Tok::Amp: return set(BinOp::BitAnd, 5);
    case Tok::EqEq: return set(BinOp::Eq, 6);
    case Tok::NotEq: return set(BinOp::Ne, 6);
    case Tok::Lt: return set(BinOp::Lt, 7);
    case Tok::LtEq: return set(BinOp::Le, 7);
    case Tok::GtEq: return set(BinOp::Ge, 7);
    case Tok::Gt:
    {
        const Token& n = peekTok();
        if (n.kind == Tok::Gt && adjacent(t, n))
            return set(BinOp::Shr, 8, 2);
        if (n.kind == Tok::GtEq && adjacent(t, n))
            return false; // '>>=' is an assignment
        return set(BinOp::Gt, 7);
    }
    case Tok::KwIs:
        out = BinOpInfo{BinOp::Eq, 7, 1, true};
        return true;
    case Tok::Shl: return set(BinOp::Shl, 8);
    case Tok::Plus: return set(BinOp::Add, 9);
    case Tok::Minus: return set(BinOp::Sub, 9);
    case Tok::Star: return set(BinOp::Mul, 10);
    case Tok::Slash: return set(BinOp::Div, 10);
    case Tok::Percent: return set(BinOp::Rem, 10);
    default: return false;
    }
}

ExprPtr Parser::parseBinary(int minPrec)
{
    ExprPtr lhs = parseUnary();
    while (true)
    {
        BinOpInfo info;
        if (!binaryOpAt(info) || info.prec < minPrec)
            break;
        SourceLoc loc = cur().loc;
        pos += info.tokenCount;

        if (info.isIs)
        {
            auto is = std::make_unique<IsExpr>(loc);
            is->operand = std::move(lhs);
            is->type = parseType();
            if (check(Tok::Ident))
                is->bindName = advance().text;
            lhs = std::move(is);
            continue;
        }

        auto b = std::make_unique<BinaryExpr>(loc);
        b->op = info.op;
        b->lhs = std::move(lhs);
        b->rhs = parseBinary(info.prec + 1);
        lhs = std::move(b);
    }
    return lhs;
}

ExprPtr Parser::parseUnary()
{
    SourceLoc loc = cur().loc;
    auto unary = [&](UnOp op) {
        advance();
        auto u = std::make_unique<UnaryExpr>(loc);
        u->op = op;
        u->operand = parseUnary();
        return u;
    };

    switch (cur().kind)
    {
    case Tok::Minus: return unary(UnOp::Neg);
    case Tok::Plus: return unary(UnOp::Plus);
    case Tok::Bang: return unary(UnOp::Not);
    case Tok::Tilde: return unary(UnOp::BitNot);
    case Tok::Star: return unary(UnOp::Deref);
    case Tok::Amp: return unary(UnOp::AddrOf);
    case Tok::KwTry:
    {
        advance();
        auto t = std::make_unique<TryExpr>(loc);
        t->operand = parseUnary();
        return t;
    }
    case Tok::KwRef:
    {
        advance();
        auto r = std::make_unique<RefArgExpr>(loc);
        r->operand = parseUnary();
        return r;
    }
    case Tok::KwUnchecked:
    {
        advance();
        expect(Tok::LParen, "'(' after 'unchecked'");
        auto u = std::make_unique<UncheckedExpr>(loc);
        u->operand = parseExpr();
        expect(Tok::RParen, "')'");
        return parsePostfix(std::move(u));
    }
    default: break;
    }
    return parsePostfix(parsePrimary());
}

void Parser::parseArgs(std::vector<ExprPtr>& out)
{
    expect(Tok::LParen, "'('");
    if (!check(Tok::RParen))
    {
        do
        {
            out.push_back(parseExpr());
        } while (match(Tok::Comma));
    }
    expect(Tok::RParen, "')'");
}

bool Parser::looksLikeStructInit() const
{
    if (!check(Tok::LBrace))
        return false;
    const Token& a = peekTok(1);
    if (a.kind == Tok::RBrace)
        return true;
    return a.kind == Tok::Ident && peekTok(2).kind == Tok::Assign;
}

TypeRefPtr Parser::exprToTypeRef(Expr& expr)
{
    auto t = std::make_unique<TypeRef>();
    t->kind = TypeRef::Named;
    t->loc = expr.loc;
    std::vector<std::string> reversed;
    Expr* e = &expr;
    bool first = true;
    while (true)
    {
        if (e->kind == ExprKind::Name)
        {
            auto* n = static_cast<NameExpr*>(e);
            reversed.push_back(n->name);
            if (first)
                t->args = std::move(n->typeArgs);
            break;
        }
        if (e->kind == ExprKind::Member)
        {
            auto* m = static_cast<MemberExpr*>(e);
            reversed.push_back(m->name);
            if (first)
                t->args = std::move(m->typeArgs);
            e = m->object.get();
            first = false;
            continue;
        }
        fail(expr.loc, "invalid struct initializer type");
    }
    t->path.assign(reversed.rbegin(), reversed.rend());
    return t;
}

void Parser::parseStructInitBody(StructInitExpr& init)
{
    expect(Tok::LBrace, "'{'");
    while (!check(Tok::RBrace) && !check(Tok::Eof))
    {
        FieldInit f;
        f.loc = cur().loc;
        f.name = expectIdent("field name");
        expect(Tok::Assign, "'=' in initializer");
        f.value = parseExpr();
        init.fields.push_back(std::move(f));
        if (!match(Tok::Comma))
            break;
    }
    expect(Tok::RBrace, "'}'");
}

ExprPtr Parser::parsePostfix(ExprPtr expr)
{
    while (true)
    {
        SourceLoc loc = cur().loc;
        if (check(Tok::Dot) || check(Tok::Arrow))
        {
            bool arrow = check(Tok::Arrow);
            advance();
            auto m = std::make_unique<MemberExpr>(loc);
            m->object = std::move(expr);
            m->viaArrow = arrow;
            m->name = expectIdent("member name");
            if (check(Tok::Lt))
            {
                size_t save = pos;
                std::vector<TypeRefPtr> args;
                if (tryParseTypeArgs(args) && (check(Tok::LParen) || check(Tok::Dot) || check(Tok::LBrace)))
                    m->typeArgs = std::move(args);
                else
                    pos = save;
            }
            expr = std::move(m);
        }
        else if (check(Tok::LParen))
        {
            auto c = std::make_unique<CallExpr>(loc);
            c->callee = std::move(expr);
            parseArgs(c->args);
            expr = std::move(c);
        }
        else if (check(Tok::LBracket))
        {
            advance();
            auto i = std::make_unique<IndexExpr>(loc);
            i->object = std::move(expr);
            i->index = parseExpr();
            expect(Tok::RBracket, "']'");
            expr = std::move(i);
        }
        else if (check(Tok::LBrace) && (expr->kind == ExprKind::Name || expr->kind == ExprKind::Member) &&
                 looksLikeStructInit())
        {
            auto init = std::make_unique<StructInitExpr>(expr->loc);
            init->type = exprToTypeRef(*expr);
            parseStructInitBody(*init);
            expr = std::move(init);
        }
        else
        {
            break;
        }
    }
    return expr;
}

bool Parser::castFollows(const TypeRef& type) const
{
    switch (cur().kind)
    {
    case Tok::Ident: case Tok::IntLit: case Tok::FloatLit: case Tok::CharLit: case Tok::StringLit:
    case Tok::LParen: case Tok::Bang: case Tok::Tilde: case Tok::KwNew: case Tok::KwThis:
    case Tok::KwSizeof: case Tok::KwNull: case Tok::KwTrue: case Tok::KwFalse: case Tok::KwTry:
    case Tok::KwUnchecked:
        return true;
    case Tok::Minus: case Tok::Plus: case Tok::Star: case Tok::Amp:
        // "(int)-x" is a cast; "(a) - b" is a subtraction.
        return type.kind != TypeRef::Named || (type.path.size() == 1 && type.args.empty() &&
                                                isPrimitiveTypeName(type.path[0]));
    default:
        return false;
    }
}

ExprPtr Parser::parseParenOrCast()
{
    SourceLoc loc = cur().loc;
    size_t save = pos;
    advance(); // (

    TypeRefPtr t = tryParseType();
    if (t && check(Tok::RParen))
    {
        advance();
        if (castFollows(*t))
        {
            auto c = std::make_unique<CastExpr>(loc);
            c->type = std::move(t);
            c->operand = parseUnary();
            return c;
        }
    }
    pos = save + 1;
    ExprPtr e = parseExpr();
    expect(Tok::RParen, "')'");
    return e;
}

ExprPtr Parser::parseNew()
{
    SourceLoc loc = advance().loc; // new
    TypeRefPtr type = parseNamedType();

    if (check(Tok::LBracket))
    {
        advance();
        auto n = std::make_unique<NewArrayExpr>(loc);
        n->elemType = std::move(type);
        if (!check(Tok::RBracket))
            n->size = parseExpr();
        expect(Tok::RBracket, "']'");
        // Further "[]" pairs make the element type an array: new int[3][] is an array of int[].
        while (check(Tok::LBracket) && peekTok().kind == Tok::RBracket)
        {
            auto a = std::make_unique<TypeRef>();
            a->kind = TypeRef::Array;
            a->loc = cur().loc;
            advance();
            advance();
            a->elem = std::move(n->elemType);
            n->elemType = std::move(a);
        }
        if (check(Tok::LBrace))
        {
            advance();
            n->hasInit = true;
            while (!check(Tok::RBrace) && !check(Tok::Eof))
            {
                n->init.push_back(parseExpr());
                if (!match(Tok::Comma))
                    break;
            }
            expect(Tok::RBrace, "'}'");
        }
        if (!n->size && !n->hasInit)
            fail(loc, "array creation needs a size or an initializer list");
        return n;
    }
    if (check(Tok::LBrace))
    {
        auto init = std::make_unique<StructInitExpr>(loc);
        init->type = std::move(type);
        parseStructInitBody(*init);
        return init;
    }
    auto n = std::make_unique<NewObjectExpr>(loc);
    n->type = std::move(type);
    expect(Tok::LParen, "'(' after type in 'new' expression");
    expect(Tok::RParen, "')': structs have no constructors, use an initializer instead");
    return n;
}

ExprPtr Parser::parsePrimary()
{
    const Token& t = cur();
    SourceLoc loc = t.loc;

    switch (t.kind)
    {
    case Tok::IntLit:
    {
        auto e = std::make_unique<IntLitExpr>(loc);
        e->value = t.intValue;
        e->isUnsigned = t.isUnsigned;
        e->isLong = t.isLong;
        advance();
        return e;
    }
    case Tok::FloatLit:
    {
        auto e = std::make_unique<FloatLitExpr>(loc);
        e->value = t.floatValue;
        e->isFloat32 = t.isFloat32;
        advance();
        return e;
    }
    case Tok::CharLit:
    {
        auto e = std::make_unique<CharLitExpr>(loc);
        e->value = (uint8_t)t.intValue;
        advance();
        return e;
    }
    case Tok::StringLit:
    {
        auto e = std::make_unique<StringLitExpr>(loc);
        e->value = t.text;
        advance();
        return e;
    }
    case Tok::KwTrue:
    case Tok::KwFalse:
    {
        auto e = std::make_unique<BoolLitExpr>(loc);
        e->value = t.kind == Tok::KwTrue;
        advance();
        return e;
    }
    case Tok::KwNull:
        advance();
        return std::make_unique<NullLitExpr>(loc);
    case Tok::KwThis:
        advance();
        return std::make_unique<ThisExpr>(loc);
    case Tok::KwSizeof:
    {
        advance();
        expect(Tok::LParen, "'(' after 'sizeof'");
        auto e = std::make_unique<SizeOfExpr>(loc);
        e->type = parseType();
        expect(Tok::RParen, "')'");
        return e;
    }
    case Tok::KwNew: return parseNew();
    case Tok::LParen: return parseParenOrCast();
    case Tok::Ident:
    {
        if (t.text == "error" && peekTok().kind == Tok::LParen)
        {
            advance();
            advance();
            auto e = std::make_unique<ErrorLitExpr>(loc);
            e->message = parseExpr();
            if (match(Tok::Comma))
                e->code = parseExpr();
            expect(Tok::RParen, "')'");
            return e;
        }

        auto n = std::make_unique<NameExpr>(loc);
        n->name = t.text;
        advance();
        if (check(Tok::Lt))
        {
            size_t save = pos;
            std::vector<TypeRefPtr> args;
            if (tryParseTypeArgs(args) && (check(Tok::LParen) || check(Tok::Dot) || check(Tok::LBrace)))
                n->typeArgs = std::move(args);
            else
                pos = save;
        }
        return n;
    }
    default:
        errorHere(std::string("unexpected ") + tokenName(t.kind) + " in expression");
    }
}
