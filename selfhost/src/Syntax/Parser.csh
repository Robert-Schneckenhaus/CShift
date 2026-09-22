// The parser: a recursive descent parser with a little backtracking (for generics, casts and declarations).
//
// It is a port of compiler/src/Parser.cpp. The C++ parser throws CompileError; here every parse function returns an
// Error<T> and propagates failures with 'try'. Backtracking restores Pos. The position of an error travels in the
// error code (SourceLoc.Pack).

namespace CShift.Syntax;

using System;

struct BinOpInfo
{
    bool Valid;
    BinOp Op;
    int Prec;
    int TokenCount;
    bool IsIs;
}

struct AssignOpInfo
{
    bool Valid;
    bool HasOp;
    BinOp Op;
    int Count;
}

struct TypeArgsResult
{
    bool Ok;
    TypeRef[] Args;
}

struct Parser
{
    Token[] Tokens;
    int Pos;
    Diagnostics Diag;
    Ast Tree;
    CompilationUnit Unit;
    int FileId;

    static Parser Create(List<Token> tokens, Diagnostics diag, Ast tree)
    {
        var p = Parser { Tokens = tokens.ToArray(), Pos = 0, Diag = diag, Tree = tree };
        p.FileId = p.Tokens.Length == 0 ? 0 : p.Tokens[0].Loc.File;
        return p;
    }

    // ---- token helpers ----

    Token Cur()
    {
        return Tokens[Pos];
    }

    TokenKind Kind()
    {
        return Tokens[Pos].Kind;
    }

    Token PeekTok(int ahead)
    {
        int i = Pos + ahead;
        if (i < Tokens.Length)
            return Tokens[i];
        return Tokens[Tokens.Length - 1];
    }

    TokenKind PeekKind(int ahead)
    {
        return PeekTok(ahead).Kind;
    }

    bool Check(TokenKind kind)
    {
        return Tokens[Pos].Kind == kind;
    }

    bool CheckIdent(string text)
    {
        return Tokens[Pos].Kind == TokenKind.Ident && Tokens[Pos].Text == text;
    }

    bool Match(TokenKind kind)
    {
        if (Check(kind))
        {
            Advance();
            return true;
        }
        return false;
    }

    Token Advance()
    {
        Token t = Tokens[Pos];
        if (Pos + 1 < Tokens.Length)
            Pos += 1;
        return t;
    }

    Error<Token> Expect(TokenKind kind, string what)
    {
        if (!Check(kind))
        {
            // Identifiers and keywords carry their text.
            Token c = Cur();
            string found = TokenName(c.Kind);
            if (c.Text.Length > 0 && c.Kind != TokenKind.StringLit)
                found = "'" + c.Text + "'";
            return error("expected " + what + ", found " + found, c.Loc.Pack());
        }
        return Advance();
    }

    Error<string> ExpectIdent(string what)
    {
        Token t = try Expect(TokenKind.Ident, what);
        return t.Text;
    }

    bool Adjacent(Token a, Token b)
    {
        return a.Loc.File == b.Loc.File && a.Loc.Line == b.Loc.Line && a.Loc.Col + 1 == b.Loc.Col;
    }

    static bool IsPrimitiveTypeName(string n)
    {
        return n == "int" || n == "uint" || n == "float" || n == "double" || n == "int8" || n == "int16" ||
               n == "int32" || n == "int64" || n == "uint8" || n == "uint16" || n == "uint32" || n == "uint64" ||
               n == "float32" || n == "float64" || n == "bool" || n == "char" || n == "string" || n == "void" ||
               n == "nint" || n == "nuint";
    }

    // ---- declarations ----

    // Parses the complete token stream as a single type (used for the type strings of .ffi files).
    Error<TypeRef> ParseStandaloneType()
    {
        TypeRef t = try ParseType();
        try Expect(TokenKind.Eof, "end of type");
        return t;
    }

    CompilationUnit ParseUnit(bool isPrelude)
    {
        Unit = CompilationUnit.Create(FileId, isPrelude);
        while (!Check(TokenKind.Eof))
        {
            int before = Pos;
            var r = ParseTopLevel();
            if (!r)
            {
                Diag.Report(FileId, r.Message, r.Code);
                SynchronizeTopLevel();
                if (Pos == before)
                    Advance();
            }
        }
        return Unit;
    }

    // Skips to the next token that starts in column 1 (top-level declarations).
    void SynchronizeTopLevel()
    {
        while (!Check(TokenKind.Eof))
        {
            if (Cur().Loc.Col == 1 && !Check(TokenKind.RBrace))
                return;
            Advance();
        }
    }

    Error<string> ParseQualifiedName()
    {
        string name = try ExpectIdent("name");
        while (Check(TokenKind.Dot) && PeekKind(1) == TokenKind.Ident)
        {
            Advance();
            name += "." + Advance().Text;
        }
        return name;
    }

    Error<void> ParseTopLevel()
    {
        if (Check(TokenKind.KwNamespace))
        {
            SourceLoc loc = Advance().Loc;
            if (Unit.File.Ns.Length > 0)
                return error("only one file-scoped namespace is allowed per file", loc.Pack());
            Unit.File.Ns = try ParseQualifiedName();
            try Expect(TokenKind.Semi, "';' after namespace");
        }
        else if (Check(TokenKind.KwUsing))
        {
            SourceLoc loc = Advance().Loc;
            string name = try ParseQualifiedName();
            if (CheckIdent("from"))
            {
                // using Sqlite3 from "sqlite3.h";  -- imports a C header as namespace Sqlite3
                Advance();
                Token header = try Expect(TokenKind.StringLit, "header path in quotes after 'from'");
                Unit.Imports.Add(ImportDecl { Loc = loc, Name = name, Header = header.Text });
            }
            else
            {
                Unit.File.Usings.Add(name);
            }
            try Expect(TokenKind.Semi, "';' after using");
        }
        else if (CheckIdent("link") && PeekKind(1) == TokenKind.StringLit)
        {
            Advance();
            Unit.Links.Add(Advance().Text);
            Match(TokenKind.Semi);
        }
        else if (Check(TokenKind.KwConst))
        {
            Advance();
            var c = ConstDecl { };
            c.Type = try ParseType();
            c.Loc = Cur().Loc;
            c.Name = try ExpectIdent("constant name");
            try Expect(TokenKind.Assign, "'=' (a constant must be initialized, e.g. const int X = 5;)");
            c.Init = try ParseExpr();
            try Expect(TokenKind.Semi, "';' after constant");
            Unit.Consts.Add(c);
        }
        else if (Check(TokenKind.KwStruct))
        {
            StructDecl s = try ParseStruct();
            Unit.Structs.Add(s);
        }
        else if (Check(TokenKind.KwInterface))
        {
            InterfaceDecl i = try ParseInterface();
            Unit.Interfaces.Add(i);
        }
        else if (Check(TokenKind.KwEnum))
        {
            EnumDecl e = try ParseEnum();
            Unit.Enums.Add(e);
        }
        else if (Check(TokenKind.KwExtern))
        {
            Advance();
            Token abi = try Expect(TokenKind.StringLit, "ABI string, e.g. extern \"C\"");
            if (abi.Text != "C")
                return error("only extern \"C\" is supported", abi.Loc.Pack());
            FuncDecl f = try ParseFunction(true, false);
            Unit.Funcs.Add(f);
        }
        else if (Check(TokenKind.Ident))
        {
            // "Type Name;" or "Type Name = value;" is a global variable, "Type Name(" a function.
            int start = Pos;
            bool isGlobal = false;
            var probe = ParseType();
            if (probe)
                isGlobal = Check(TokenKind.Ident) && (PeekKind(1) == TokenKind.Semi || PeekKind(1) == TokenKind.Assign);
            Pos = start;
            if (isGlobal)
            {
                var g = GlobalDecl { };
                g.Type = try ParseType();
                g.Loc = Cur().Loc;
                g.Name = try ExpectIdent("variable name");
                if (Match(TokenKind.Assign))
                    g.Init = try ParseExpr();
                try Expect(TokenKind.Semi, "';' after variable declaration");
                Unit.Globals.Add(g);
            }
            else
            {
                FuncDecl f = try ParseFunction(false, false);
                Unit.Funcs.Add(f);
            }
        }
        else
        {
            return error("unexpected " + TokenName(Kind()) + " at top level", Cur().Loc.Pack());
        }
    }

    Error<string[]> ParseTypeParams()
    {
        try Expect(TokenKind.Lt, "'<'");
        var names = List<string>.Create();
        do
        {
            names.Add(try ExpectIdent("type parameter name"));
        } while (Match(TokenKind.Comma));
        try Expect(TokenKind.Gt, "'>'");
        return names.ToArray();
    }

    Error<Constraint[]> ParseConstraints()
    {
        var list = List<Constraint>.Create();
        while (Match(TokenKind.KwWhere))
        {
            var c = Constraint { };
            c.Param = try ExpectIdent("type parameter name");
            try Expect(TokenKind.Colon, "':'");
            var bounds = List<TypeRef>.Create();
            do
            {
                bounds.Add(try ParseType());
            } while (Match(TokenKind.Comma));
            c.Bounds = bounds.ToArray();
            list.Add(c);
        }
        return list.ToArray();
    }

    Error<StructDecl> ParseStruct()
    {
        var decl = StructDecl { };
        decl.LayoutAlign = 1;
        Token kw = try Expect(TokenKind.KwStruct, "'struct'");
        decl.Loc = kw.Loc;
        decl.Name = try ExpectIdent("struct name");
        decl.TypeParams = new string[0];
        if (Check(TokenKind.Lt))
            decl.TypeParams = try ParseTypeParams();
        var bases = List<TypeRef>.Create();
        if (Match(TokenKind.Colon))
        {
            do
            {
                bases.Add(try ParseType());
            } while (Match(TokenKind.Comma));
        }
        decl.Bases = bases.ToArray();
        decl.Constraints = try ParseConstraints();
        try Expect(TokenKind.LBrace, "'{'");

        var fields = List<FieldDecl>.Create();
        var methods = List<FuncDecl>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            bool isStatic = Match(TokenKind.KwStatic);
            SourceLoc memberLoc = Cur().Loc;
            TypeRef type = try ParseType();
            string name = try ExpectIdent("member name");

            if (Check(TokenKind.LParen) || Check(TokenKind.Lt))
            {
                var fn = FuncDecl { Loc = memberLoc, Name = name, Ret = type, IsStatic = isStatic, Owner = Unit.Structs.Count() };
                try ParseFunctionRest(ref fn);
                methods.Add(fn);
            }
            else
            {
                if (isStatic)
                    return error("static fields are not supported", memberLoc.Pack());
                fields.Add(FieldDecl { Loc = memberLoc, Type = type, Name = name, Offset = -1 });
                try Expect(TokenKind.Semi, "';' after field");
            }
        }
        try Expect(TokenKind.RBrace, "'}'");
        decl.Fields = fields.ToArray();
        decl.Methods = methods.ToArray();
        return decl;
    }

    Error<InterfaceDecl> ParseInterface()
    {
        var decl = InterfaceDecl { };
        Token kw = try Expect(TokenKind.KwInterface, "'interface'");
        decl.Loc = kw.Loc;
        decl.Name = try ExpectIdent("interface name");
        decl.TypeParams = new string[0];
        if (Check(TokenKind.Lt))
            decl.TypeParams = try ParseTypeParams();
        try Expect(TokenKind.LBrace, "'{'");
        var methods = List<FuncDecl>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            var fn = FuncDecl { Loc = Cur().Loc, Owner = -1 };
            fn.Ret = try ParseType();
            fn.Name = try ExpectIdent("method name");
            try ParseFunctionRest(ref fn);
            if (!fn.Body.IsNull())
                return error("interface methods cannot have a body", fn.Loc.Pack());
            methods.Add(fn);
        }
        try Expect(TokenKind.RBrace, "'}'");
        decl.Methods = methods.ToArray();
        return decl;
    }

    Error<EnumDecl> ParseEnum()
    {
        var decl = EnumDecl { };
        Token kw = try Expect(TokenKind.KwEnum, "'enum'");
        decl.Loc = kw.Loc;
        decl.Name = try ExpectIdent("enum name");
        if (!Match(TokenKind.Colon))
            return error("enums require an explicit integer base type, e.g. 'enum " + decl.Name + " : uint8'", decl.Loc.Pack());
        decl.Base = try ParseType();
        try Expect(TokenKind.LBrace, "'{'");
        var members = List<EnumMember>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            var m = EnumMember { Loc = Cur().Loc };
            m.Name = try ExpectIdent("enum member name");
            if (Match(TokenKind.Assign))
                m.Value = try ParseExpr();
            members.Add(m);
            if (!Match(TokenKind.Comma))
                break;
        }
        try Expect(TokenKind.RBrace, "'}'");
        decl.Members = members.ToArray();
        return decl;
    }

    Error<FuncDecl> ParseFunction(bool isExtern, bool isStatic)
    {
        var fn = FuncDecl { IsExtern = isExtern, IsStatic = isStatic, Owner = -1 };
        fn.Ret = try ParseType();
        fn.Loc = Cur().Loc;
        fn.Name = try ExpectIdent("function name");
        try ParseFunctionRest(ref fn);
        return fn;
    }

    Error<void> ParseParams(ref FuncDecl fn)
    {
        try Expect(TokenKind.LParen, "'('");
        var list = List<Param>.Create();
        if (!Check(TokenKind.RParen))
        {
            do
            {
                if (Match(TokenKind.Ellipsis))
                {
                    fn.IsVariadic = true;
                    break;
                }
                var p = Param { Loc = Cur().Loc };
                if (Match(TokenKind.KwConst))
                {
                    try Expect(TokenKind.KwRef, "'ref' after 'const'");
                    p.Ref = RefKind.ConstRef;
                }
                else if (Match(TokenKind.KwRef))
                {
                    p.Ref = RefKind.Ref;
                }
                p.Type = try ParseType();
                p.Name = "";
                if (Check(TokenKind.Ident))
                    p.Name = Advance().Text;
                list.Add(p);
            } while (Match(TokenKind.Comma));
        }
        try Expect(TokenKind.RParen, "')'");
        fn.Params = list.ToArray();
    }

    Error<void> ParseFunctionRest(ref FuncDecl fn)
    {
        fn.TypeParams = new string[0];
        if (Check(TokenKind.Lt))
            fn.TypeParams = try ParseTypeParams();
        try ParseParams(ref fn);
        fn.Constraints = try ParseConstraints();
        if (Check(TokenKind.LBrace))
            fn.Body = try ParseBlock();
        else
            try Expect(TokenKind.Semi, "';' or function body");
    }

    // ---- types ----

    TypeRef NewType(TypeRefKind kind, SourceLoc loc, string[] path, TypeRef[] args, TypeRef elem)
    {
        return Tree.AddType(TypeRefNode { Kind = kind, Loc = loc, Path = path, Args = args, Elem = elem });
    }

    Error<TypeRef> ParseNamedType()
    {
        SourceLoc loc = Cur().Loc;
        var path = List<string>.Create();
        path.Add(try ExpectIdent("type name"));
        while (Check(TokenKind.Dot) && PeekKind(1) == TokenKind.Ident)
        {
            Advance();
            path.Add(Advance().Text);
        }
        var args = List<TypeRef>.Create();
        if (Check(TokenKind.Lt))
        {
            Advance();
            do
            {
                args.Add(try ParseType());
            } while (Match(TokenKind.Comma));
            try Expect(TokenKind.Gt, "'>'");
        }
        return NewType(TypeRefKind.Named, loc, path.ToArray(), args.ToArray(), TypeRef { });
    }

    Error<TypeRef> ParseType()
    {
        TypeRef t = try ParseNamedType();
        while (true)
        {
            if (Check(TokenKind.Star))
            {
                SourceLoc loc = Cur().Loc;
                Advance();
                t = NewType(TypeRefKind.Pointer, loc, new string[0], new TypeRef[0], t);
            }
            else if (Check(TokenKind.LBracket) && PeekKind(1) == TokenKind.RBracket)
            {
                SourceLoc loc = Cur().Loc;
                Advance();
                Advance();
                t = NewType(TypeRefKind.Array, loc, new string[0], new TypeRef[0], t);
            }
            else
            {
                break;
            }
        }
        return t;
    }

    // Like ParseType, but a failure restores the position and yields "no type".
    TypeRef TryParseType()
    {
        int save = Pos;
        var r = ParseType();
        if (r is TypeRef t)
            return t;
        Pos = save;
        return TypeRef { };
    }

    TypeArgsResult TryParseTypeArgs()
    {
        int save = Pos;
        var r = ParseTypeArgsList();
        if (r is TypeRef[] args)
            return TypeArgsResult { Ok = true, Args = args };
        Pos = save;
        return TypeArgsResult { Ok = false, Args = new TypeRef[0] };
    }

    Error<TypeRef[]> ParseTypeArgsList()
    {
        try Expect(TokenKind.Lt, "'<'");
        var list = List<TypeRef>.Create();
        do
        {
            list.Add(try ParseType());
        } while (Match(TokenKind.Comma));
        try Expect(TokenKind.Gt, "'>'");
        return list.ToArray();
    }

    bool IsVarType(TypeRef t)
    {
        var node = Tree.GetType(t);
        return node.Kind == TypeRefKind.Named && node.Path.Length == 1 && node.Path[0] == "var" && node.Args.Length == 0;
    }

    // ---- statements ----

    Error<Stmt> ParseBlock()
    {
        SourceLoc loc = Cur().Loc;
        try Expect(TokenKind.LBrace, "'{'");
        var stmts = List<Stmt>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            int before = Pos;
            var r = ParseStatement();
            if (r is Stmt s)
            {
                stmts.Add(s);
            }
            else
            {
                Diag.Report(FileId, r.Message, r.Code);
                SynchronizeStatement();
                if (Pos == before)
                    Advance();
            }
        }
        try Expect(TokenKind.RBrace, "'}'");
        return Tree.AddBlock(loc, BlockStmt { Stmts = stmts.ToArray() });
    }

    // A block that is marked unsafe or unchecked: the marker is set after the block was parsed.
    Error<Stmt> ParseMarkedBlock(bool isUnsafe)
    {
        Advance(); // unsafe / unchecked
        Stmt b = try ParseBlock();
        var node = Tree.GetBlock(b);
        if (isUnsafe)
            node.IsUnsafe = true;
        else
            node.IsUnchecked = true;
        Tree.Blocks.Set(b.Index, node);
        return b;
    }

    void SynchronizeStatement()
    {
        while (!Check(TokenKind.Eof))
        {
            if (Check(TokenKind.Semi))
            {
                Advance();
                return;
            }
            if (Check(TokenKind.RBrace))
                return;
            Advance();
        }
    }

    Error<Stmt> ParseStatement()
    {
        SourceLoc loc = Cur().Loc;
        switch (Kind())
        {
        case TokenKind.LBrace:
            return ParseBlock();
        case TokenKind.Semi:
            Advance();
            return Tree.AddEmpty(loc);
        case TokenKind.KwIf:
            return ParseIf();
        case TokenKind.KwWhile:
            return ParseWhile();
        case TokenKind.KwDo:
            return ParseDoWhile();
        case TokenKind.KwFor:
            return ParseFor();
        case TokenKind.KwForeach:
            return ParseForeach();
        case TokenKind.KwSwitch:
            return ParseSwitch();
        case TokenKind.KwUsing:
            return ParseUsing();
        case TokenKind.KwConst:
        {
            // const int X = 5;  (a local constant)
            Advance();
            var d = VarDeclStmt { IsConst = true };
            TypeRef t = try ParseType();
            if (IsVarType(t))
                return error("a constant needs an explicit type, e.g. const int X = 5;", loc.Pack());
            d.Type = t;
            d.Name = try ExpectIdent("constant name");
            try Expect(TokenKind.Assign, "'=' (a constant must be initialized, e.g. const int X = 5;)");
            d.Init = try ParseExpr();
            try Expect(TokenKind.Semi, "';' after constant");
            return Tree.AddVarDecl(loc, d);
        }
        case TokenKind.KwBreak:
            Advance();
            try Expect(TokenKind.Semi, "';'");
            return Tree.AddBreak(loc);
        case TokenKind.KwContinue:
            Advance();
            try Expect(TokenKind.Semi, "';'");
            return Tree.AddContinue(loc);
        case TokenKind.KwReturn:
        {
            Advance();
            var r = ReturnStmt { };
            if (!Check(TokenKind.Semi))
                r.Value = try ParseExpr();
            try Expect(TokenKind.Semi, "';'");
            return Tree.AddReturn(loc, r);
        }
        case TokenKind.KwUnsafe:
            if (PeekKind(1) == TokenKind.LBrace)
                return ParseMarkedBlock(true);
            break;
        case TokenKind.KwUnchecked:
            if (PeekKind(1) == TokenKind.LBrace)
                return ParseMarkedBlock(false);
            break;
        default:
            break;
        }
        return ParseSimpleStatement(true);
    }

    // 'Type name = expr;' or 'Type name;'. Yields no statement (and restores the position) if this is not a declaration.
    Stmt TryParseVarDecl()
    {
        if (!Check(TokenKind.Ident))
            return Stmt { };
        int save = Pos;
        SourceLoc loc = Cur().Loc;
        TypeRef t = TryParseType();
        if (!t.IsNull() && Check(TokenKind.Ident) && (PeekKind(1) == TokenKind.Assign || PeekKind(1) == TokenKind.Semi))
        {
            var d = VarDeclStmt { };
            d.Name = Advance().Text;
            if (Match(TokenKind.Assign))
            {
                var init = ParseExpr();
                if (init is Expr e)
                {
                    d.Init = e;
                }
                else
                {
                    // The failure must surface as an error of the enclosing statement: mark it for the caller.
                    PendingError = init.Message;
                    PendingErrorCode = init.Code;
                    HasPendingError = true;
                    return Stmt { };
                }
            }
            if (!IsVarType(t))
                d.Type = t;
            return Tree.AddVarDecl(loc, d);
        }
        Pos = save;
        return Stmt { };
    }

    // An error inside the initializer of a declaration (TryParseVarDecl cannot return an Error itself).
    string PendingError;
    int PendingErrorCode;
    bool HasPendingError;

    Error<Stmt> ParseSimpleStatement(bool expectSemi)
    {
        SourceLoc loc = Cur().Loc;
        HasPendingError = false;
        Stmt decl = TryParseVarDecl();
        if (HasPendingError)
        {
            HasPendingError = false;
            return error(PendingError, PendingErrorCode);
        }
        if (!decl.IsNull())
        {
            if (expectSemi)
                try Expect(TokenKind.Semi, "';' after declaration");
            return decl;
        }
        var s = ExprStmt { };
        s.Expr = try ParseExpr();
        if (expectSemi)
            try Expect(TokenKind.Semi, "';' after expression");
        return Tree.AddExprStmt(loc, s);
    }

    Error<Stmt> ParseIf()
    {
        SourceLoc loc = Advance().Loc;
        var s = IfStmt { };
        try Expect(TokenKind.LParen, "'(' after 'if'");
        s.Cond = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        s.Then = try ParseStatement();
        if (Match(TokenKind.KwElse))
            s.Else = try ParseStatement();
        return Tree.AddIf(loc, s);
    }

    Error<Stmt> ParseWhile()
    {
        SourceLoc loc = Advance().Loc;
        var s = WhileStmt { };
        try Expect(TokenKind.LParen, "'(' after 'while'");
        s.Cond = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        s.Body = try ParseStatement();
        return Tree.AddWhile(loc, s);
    }

    Error<Stmt> ParseDoWhile()
    {
        SourceLoc loc = Advance().Loc;
        var s = DoWhileStmt { };
        s.Body = try ParseStatement();
        try Expect(TokenKind.KwWhile, "'while' after do-body");
        try Expect(TokenKind.LParen, "'('");
        s.Cond = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        try Expect(TokenKind.Semi, "';'");
        return Tree.AddDoWhile(loc, s);
    }

    Error<Stmt> ParseFor()
    {
        SourceLoc loc = Advance().Loc;
        var s = ForStmt { };
        try Expect(TokenKind.LParen, "'(' after 'for'");
        if (!Check(TokenKind.Semi))
            s.Init = try ParseSimpleStatement(false);
        try Expect(TokenKind.Semi, "';'");
        if (!Check(TokenKind.Semi))
            s.Cond = try ParseExpr();
        try Expect(TokenKind.Semi, "';'");
        var iterators = List<Expr>.Create();
        if (!Check(TokenKind.RParen))
        {
            do
            {
                iterators.Add(try ParseExpr());
            } while (Match(TokenKind.Comma));
        }
        s.Iterators = iterators.ToArray();
        try Expect(TokenKind.RParen, "')'");
        s.Body = try ParseStatement();
        return Tree.AddFor(loc, s);
    }

    Error<Stmt> ParseForeach()
    {
        SourceLoc loc = Advance().Loc;
        var s = ForeachStmt { };
        try Expect(TokenKind.LParen, "'(' after 'foreach'");
        TypeRef t = try ParseType();
        if (!IsVarType(t))
            s.Type = t;
        s.Name = try ExpectIdent("loop variable name");
        try Expect(TokenKind.KwIn, "'in'");
        s.Iterable = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        s.Body = try ParseStatement();
        return Tree.AddForeach(loc, s);
    }

    Error<Stmt> ParseSwitch()
    {
        SourceLoc loc = Advance().Loc;
        var s = SwitchStmt { };
        try Expect(TokenKind.LParen, "'(' after 'switch'");
        s.Subject = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        try Expect(TokenKind.LBrace, "'{'");

        var sections = List<SwitchSection>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            var section = SwitchSection { Loc = Cur().Loc };
            var labels = List<CaseLabel>.Create();
            while (Check(TokenKind.KwCase) || Check(TokenKind.KwDefault))
            {
                var label = CaseLabel { Loc = Cur().Loc };
                if (Match(TokenKind.KwDefault))
                {
                    label.IsDefault = true;
                }
                else
                {
                    Advance(); // case
                    int save = Pos;
                    TypeRef t = TryParseType();
                    if (!t.IsNull() && Check(TokenKind.Ident) && PeekKind(1) == TokenKind.Colon)
                    {
                        label.PatType = t;
                        label.PatName = Advance().Text;
                    }
                    else
                    {
                        Pos = save;
                        label.Value = try ParseExpr();
                    }
                }
                try Expect(TokenKind.Colon, "':' after case label");
                labels.Add(label);
            }
            if (labels.Count() == 0)
                return error("expected 'case' or 'default' in switch", Cur().Loc.Pack());
            section.Labels = labels.ToArray();

            var body = List<Stmt>.Create();
            while (!Check(TokenKind.KwCase) && !Check(TokenKind.KwDefault) && !Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
            {
                int before = Pos;
                var r = ParseStatement();
                if (r is Stmt st)
                {
                    body.Add(st);
                }
                else
                {
                    Diag.Report(FileId, r.Message, r.Code);
                    SynchronizeStatement();
                    if (Pos == before)
                        Advance();
                }
            }
            section.Body = body.ToArray();
            sections.Add(section);
        }
        try Expect(TokenKind.RBrace, "'}'");
        s.Sections = sections.ToArray();
        return Tree.AddSwitch(loc, s);
    }

    Error<Stmt> ParseUsing()
    {
        SourceLoc loc = Advance().Loc; // using
        if (Match(TokenKind.LParen))
        {
            var decl = VarDeclStmt { IsUsing = true };
            SourceLoc declLoc = Cur().Loc;
            TypeRef t = try ParseType();
            if (!IsVarType(t))
                decl.Type = t;
            decl.Name = try ExpectIdent("variable name");
            try Expect(TokenKind.Assign, "'='");
            decl.Init = try ParseExpr();
            try Expect(TokenKind.RParen, "')'");
            var s = UsingBlockStmt { };
            s.Decl = Tree.AddVarDecl(declLoc, decl);
            s.Body = try ParseStatement();
            return Tree.AddUsingBlock(loc, s);
        }

        // using name = expr;   or   using Type name = expr;
        var d = VarDeclStmt { IsUsing = true };
        if (Check(TokenKind.Ident) && PeekKind(1) == TokenKind.Assign)
        {
            d.Name = Advance().Text;
        }
        else
        {
            TypeRef t = try ParseType();
            if (!IsVarType(t))
                d.Type = t;
            d.Name = try ExpectIdent("variable name");
        }
        try Expect(TokenKind.Assign, "'=' in using declaration");
        d.Init = try ParseExpr();
        try Expect(TokenKind.Semi, "';'");
        return Tree.AddVarDecl(loc, d);
    }

    // ---- expressions ----

    Error<Expr> ParseExpr()
    {
        return ParseAssignment();
    }

    AssignOpInfo AssignOpAt()
    {
        var info = AssignOpInfo { Valid = true, HasOp = true, Count = 1 };
        switch (Kind())
        {
        case TokenKind.Assign:
            info.HasOp = false;
            return info;
        case TokenKind.PlusAssign:
            info.Op = BinOp.Add;
            return info;
        case TokenKind.MinusAssign:
            info.Op = BinOp.Sub;
            return info;
        case TokenKind.StarAssign:
            info.Op = BinOp.Mul;
            return info;
        case TokenKind.SlashAssign:
            info.Op = BinOp.Div;
            return info;
        case TokenKind.PercentAssign:
            info.Op = BinOp.Rem;
            return info;
        case TokenKind.AmpAssign:
            info.Op = BinOp.BitAnd;
            return info;
        case TokenKind.PipeAssign:
            info.Op = BinOp.BitOr;
            return info;
        case TokenKind.CaretAssign:
            info.Op = BinOp.BitXor;
            return info;
        case TokenKind.ShlAssign:
            info.Op = BinOp.Shl;
            return info;
        case TokenKind.Gt:
            if (PeekKind(1) == TokenKind.GtEq && Adjacent(Cur(), PeekTok(1)))
            {
                info.Op = BinOp.Shr;
                info.Count = 2;
                return info;
            }
            return AssignOpInfo { };
        default:
            return AssignOpInfo { };
        }
    }

    Error<Expr> ParseAssignment()
    {
        Expr lhs = try ParseConditional();
        var info = AssignOpAt();
        if (info.Valid)
        {
            SourceLoc loc = Cur().Loc;
            Pos += info.Count;
            var a = AssignExpr { HasOp = info.HasOp, Op = info.Op, Target = lhs };
            a.Value = try ParseAssignment();
            return Tree.AddAssign(loc, a);
        }
        return lhs;
    }

    Error<Expr> ParseConditional()
    {
        Expr cond = try ParseBinary(1);
        if (Check(TokenKind.Question))
        {
            SourceLoc loc = Advance().Loc;
            var c = CondExpr { Cond = cond };
            c.Then = try ParseAssignment();
            try Expect(TokenKind.Colon, "':' in conditional expression");
            c.Else = try ParseAssignment();
            return Tree.AddCond(loc, c);
        }
        return cond;
    }

    static BinOpInfo Op(BinOp op, int prec, int count)
    {
        return BinOpInfo { Valid = true, Op = op, Prec = prec, TokenCount = count, IsIs = false };
    }

    BinOpInfo BinaryOpAt()
    {
        switch (Kind())
        {
        case TokenKind.PipePipe: return Op(BinOp.LogOr, 1, 1);
        case TokenKind.AmpAmp: return Op(BinOp.LogAnd, 2, 1);
        case TokenKind.Pipe: return Op(BinOp.BitOr, 3, 1);
        case TokenKind.Caret: return Op(BinOp.BitXor, 4, 1);
        case TokenKind.Amp: return Op(BinOp.BitAnd, 5, 1);
        case TokenKind.EqEq: return Op(BinOp.Eq, 6, 1);
        case TokenKind.NotEq: return Op(BinOp.Ne, 6, 1);
        case TokenKind.Lt: return Op(BinOp.Lt, 7, 1);
        case TokenKind.LtEq: return Op(BinOp.Le, 7, 1);
        case TokenKind.GtEq: return Op(BinOp.Ge, 7, 1);
        case TokenKind.Gt:
        {
            Token t = Cur();
            Token n = PeekTok(1);
            if (n.Kind == TokenKind.Gt && Adjacent(t, n))
                return Op(BinOp.Shr, 8, 2);
            if (n.Kind == TokenKind.GtEq && Adjacent(t, n))
                return BinOpInfo { }; // '>>=' is an assignment
            return Op(BinOp.Gt, 7, 1);
        }
        case TokenKind.KwIs:
            return BinOpInfo { Valid = true, Op = BinOp.Eq, Prec = 7, TokenCount = 1, IsIs = true };
        case TokenKind.Shl: return Op(BinOp.Shl, 8, 1);
        case TokenKind.Plus: return Op(BinOp.Add, 9, 1);
        case TokenKind.Minus: return Op(BinOp.Sub, 9, 1);
        case TokenKind.Star: return Op(BinOp.Mul, 10, 1);
        case TokenKind.Slash: return Op(BinOp.Div, 10, 1);
        case TokenKind.Percent: return Op(BinOp.Rem, 10, 1);
        default:
            return BinOpInfo { };
        }
    }

    Error<Expr> ParseBinary(int minPrec)
    {
        Expr lhs = try ParseUnary();
        while (true)
        {
            var info = BinaryOpAt();
            if (!info.Valid || info.Prec < minPrec)
                break;
            SourceLoc loc = Cur().Loc;
            Pos += info.TokenCount;

            if (info.IsIs)
            {
                var isNode = IsExpr { Operand = lhs };
                isNode.Type = try ParseType();
                isNode.BindName = "";
                if (Check(TokenKind.Ident))
                    isNode.BindName = Advance().Text;
                lhs = Tree.AddIs(loc, isNode);
                continue;
            }

            var b = BinaryExpr { Op = info.Op, Lhs = lhs };
            b.Rhs = try ParseBinary(info.Prec + 1);
            lhs = Tree.AddBinary(loc, b);
        }
        return lhs;
    }

    Error<Expr> ParseUnaryOp(UnOp op, SourceLoc loc)
    {
        Advance();
        var u = UnaryExpr { Op = op };
        u.Operand = try ParseUnary();
        return Tree.AddUnary(loc, u);
    }

    Error<Expr> ParseUnary()
    {
        SourceLoc loc = Cur().Loc;
        switch (Kind())
        {
        case TokenKind.Minus: return ParseUnaryOp(UnOp.Neg, loc);
        case TokenKind.Plus: return ParseUnaryOp(UnOp.Plus, loc);
        case TokenKind.Bang: return ParseUnaryOp(UnOp.Not, loc);
        case TokenKind.Tilde: return ParseUnaryOp(UnOp.BitNot, loc);
        case TokenKind.Star: return ParseUnaryOp(UnOp.Deref, loc);
        case TokenKind.Amp: return ParseUnaryOp(UnOp.AddrOf, loc);
        case TokenKind.KwTry:
        {
            Advance();
            var t = TryExpr { };
            t.Operand = try ParseUnary();
            return Tree.AddTry(loc, t);
        }
        case TokenKind.KwRef:
        {
            Advance();
            var r = RefArgExpr { };
            r.Operand = try ParseUnary();
            return Tree.AddRefArg(loc, r);
        }
        case TokenKind.KwUnchecked:
        {
            Advance();
            try Expect(TokenKind.LParen, "'(' after 'unchecked'");
            var u = UncheckedExpr { };
            u.Operand = try ParseExpr();
            try Expect(TokenKind.RParen, "')'");
            return ParsePostfix(Tree.AddUnchecked(loc, u));
        }
        default:
            break;
        }
        Expr primary = try ParsePrimary();
        return ParsePostfix(primary);
    }

    Error<Expr[]> ParseArgs()
    {
        try Expect(TokenKind.LParen, "'('");
        var list = List<Expr>.Create();
        if (!Check(TokenKind.RParen))
        {
            do
            {
                list.Add(try ParseExpr());
            } while (Match(TokenKind.Comma));
        }
        try Expect(TokenKind.RParen, "')'");
        return list.ToArray();
    }

    bool LooksLikeStructInit()
    {
        if (!Check(TokenKind.LBrace))
            return false;
        Token a = PeekTok(1);
        if (a.Kind == TokenKind.RBrace)
            return true;
        return a.Kind == TokenKind.Ident && PeekKind(2) == TokenKind.Assign;
    }

    // The type of a struct initializer 'Name<T> { ... }' is written like an expression: convert it back.
    Error<TypeRef> ExprToTypeRef(Expr expr)
    {
        var reversed = List<string>.Create();
        TypeRef[] args = new TypeRef[0];
        Expr e = expr;
        bool first = true;
        while (true)
        {
            if (e.Kind == ExprKind.Name)
            {
                var n = Tree.GetName(e);
                reversed.Add(n.Name);
                if (first)
                    args = n.TypeArgs;
                break;
            }
            if (e.Kind == ExprKind.Member)
            {
                var m = Tree.GetMember(e);
                reversed.Add(m.Name);
                if (first)
                    args = m.TypeArgs;
                e = m.Object;
                first = false;
                continue;
            }
            return error("invalid struct initializer type", expr.Loc.Pack());
        }
        var path = new string[reversed.Count()];
        for (var i = 0; i < path.Length; i += 1)
            path[i] = reversed.Get(path.Length - 1 - i);
        return NewType(TypeRefKind.Named, expr.Loc, path, args, TypeRef { });
    }

    Error<FieldInit[]> ParseStructInitBody()
    {
        try Expect(TokenKind.LBrace, "'{'");
        var fields = List<FieldInit>.Create();
        while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
        {
            var f = FieldInit { Loc = Cur().Loc };
            f.Name = try ExpectIdent("field name");
            try Expect(TokenKind.Assign, "'=' in initializer");
            f.Value = try ParseExpr();
            fields.Add(f);
            if (!Match(TokenKind.Comma))
                break;
        }
        try Expect(TokenKind.RBrace, "'}'");
        return fields.ToArray();
    }

    // Type arguments after a name in an expression (Foo<int>(...)): only if they are followed by a call, a member
    // access, an initializer or the end of the argument.
    TypeArgsResult TryExprTypeArgs()
    {
        int save = Pos;
        var r = TryParseTypeArgs();
        if (r.Ok && (Check(TokenKind.LParen) || Check(TokenKind.Dot) || Check(TokenKind.LBrace) || Check(TokenKind.Semi) ||
                     Check(TokenKind.Comma) || Check(TokenKind.RParen)))
            return r;
        Pos = save;
        return TypeArgsResult { Ok = false, Args = new TypeRef[0] };
    }

    Error<Expr> ParsePostfix(Expr expr0)
    {
        Expr expr = expr0;
        while (true)
        {
            SourceLoc loc = Cur().Loc;
            if (Check(TokenKind.Dot) || Check(TokenKind.Arrow))
            {
                bool arrow = Check(TokenKind.Arrow);
                Advance();
                var m = MemberExpr { Object = expr, ViaArrow = arrow };
                m.Name = try ExpectIdent("member name");
                m.TypeArgs = new TypeRef[0];
                if (Check(TokenKind.Lt))
                {
                    var r = TryExprTypeArgs();
                    if (r.Ok)
                        m.TypeArgs = r.Args;
                }
                expr = Tree.AddMember(loc, m);
            }
            else if (Check(TokenKind.LParen))
            {
                var c = CallExpr { Callee = expr };
                c.Args = try ParseArgs();
                expr = Tree.AddCall(loc, c);
            }
            else if (Check(TokenKind.LBracket))
            {
                Advance();
                var i = IndexExpr { Object = expr };
                i.Index = try ParseExpr();
                try Expect(TokenKind.RBracket, "']'");
                expr = Tree.AddIndex(loc, i);
            }
            else if (Check(TokenKind.LBrace) && (expr.Kind == ExprKind.Name || expr.Kind == ExprKind.Member) && LooksLikeStructInit())
            {
                var init = StructInitExpr { };
                init.Type = try ExprToTypeRef(expr);
                init.Fields = try ParseStructInitBody();
                expr = Tree.AddStructInit(expr.Loc, init);
            }
            else
            {
                break;
            }
        }
        return expr;
    }

    bool CastFollows(TypeRef type)
    {
        switch (Kind())
        {
        case TokenKind.Ident:
        case TokenKind.IntLit:
        case TokenKind.FloatLit:
        case TokenKind.CharLit:
        case TokenKind.StringLit:
        case TokenKind.LParen:
        case TokenKind.Bang:
        case TokenKind.Tilde:
        case TokenKind.KwNew:
        case TokenKind.KwThis:
        case TokenKind.KwSizeof:
        case TokenKind.KwNull:
        case TokenKind.KwTrue:
        case TokenKind.KwFalse:
        case TokenKind.KwTry:
        case TokenKind.KwUnchecked:
            return true;
        case TokenKind.Minus:
        case TokenKind.Plus:
        case TokenKind.Star:
        case TokenKind.Amp:
        {
            // "(int)-x" is a cast; "(a) - b" is a subtraction.
            var node = Tree.GetType(type);
            return node.Kind != TypeRefKind.Named || (node.Path.Length == 1 && node.Args.Length == 0 && IsPrimitiveTypeName(node.Path[0]));
        }
        default:
            return false;
        }
    }

    Error<Expr> ParseParenOrCast()
    {
        SourceLoc loc = Cur().Loc;
        int save = Pos;
        Advance(); // (

        TypeRef t = TryParseType();
        if (!t.IsNull() && Check(TokenKind.RParen))
        {
            Advance();
            if (CastFollows(t))
            {
                var c = CastExpr { Type = t };
                c.Operand = try ParseUnary();
                return Tree.AddCast(loc, c);
            }
        }
        Pos = save + 1;
        Expr e = try ParseExpr();
        try Expect(TokenKind.RParen, "')'");
        return e;
    }

    Error<Expr> ParseNew()
    {
        SourceLoc loc = Advance().Loc; // new
        TypeRef type = try ParseNamedType();

        if (Check(TokenKind.LBracket))
        {
            Advance();
            var n = NewArrayExpr { ElemType = type };
            if (!Check(TokenKind.RBracket))
                n.Size = try ParseExpr();
            try Expect(TokenKind.RBracket, "']'");
            // Further "[]" pairs make the element type an array: new int[3][] is an array of int[].
            while (Check(TokenKind.LBracket) && PeekKind(1) == TokenKind.RBracket)
            {
                SourceLoc aloc = Cur().Loc;
                Advance();
                Advance();
                n.ElemType = NewType(TypeRefKind.Array, aloc, new string[0], new TypeRef[0], n.ElemType);
            }
            var init = List<Expr>.Create();
            if (Check(TokenKind.LBrace))
            {
                Advance();
                n.HasInit = true;
                while (!Check(TokenKind.RBrace) && !Check(TokenKind.Eof))
                {
                    init.Add(try ParseExpr());
                    if (!Match(TokenKind.Comma))
                        break;
                }
                try Expect(TokenKind.RBrace, "'}'");
            }
            n.Init = init.ToArray();
            if (n.Size.IsNull() && !n.HasInit)
                return error("array creation needs a size or an initializer list", loc.Pack());
            return Tree.AddNewArray(loc, n);
        }
        if (Check(TokenKind.LBrace))
        {
            var si = StructInitExpr { Type = type };
            si.Fields = try ParseStructInitBody();
            return Tree.AddStructInit(loc, si);
        }
        var no = NewObjectExpr { Type = type };
        try Expect(TokenKind.LParen, "'(' after type in 'new' expression");
        try Expect(TokenKind.RParen, "')': structs have no constructors, use an initializer instead");
        return Tree.AddNewObject(loc, no);
    }

    Error<Expr> ParsePrimary()
    {
        Token t = Cur();
        SourceLoc loc = t.Loc;

        switch (t.Kind)
        {
        case TokenKind.IntLit:
        {
            Advance();
            return Tree.AddIntLit(loc, IntLitExpr { Value = t.IntValue, IsUnsigned = t.IsUnsigned, IsLong = t.IsLong });
        }
        case TokenKind.FloatLit:
        {
            Advance();
            return Tree.AddFloatLit(loc, FloatLitExpr { Value = t.FloatValue, IsFloat32 = t.IsFloat32 });
        }
        case TokenKind.CharLit:
        {
            Advance();
            return Tree.AddCharLit(loc, CharLitExpr { Value = (int)(t.IntValue & 255) });
        }
        case TokenKind.StringLit:
        {
            Advance();
            return Tree.AddStringLit(loc, StringLitExpr { Value = t.Text });
        }
        case TokenKind.KwTrue:
        case TokenKind.KwFalse:
        {
            Advance();
            return Tree.AddBoolLit(loc, BoolLitExpr { Value = t.Kind == TokenKind.KwTrue });
        }
        case TokenKind.KwNull:
            Advance();
            return Tree.AddNullLit(loc);
        case TokenKind.KwThis:
            Advance();
            return Tree.AddThis(loc);
        case TokenKind.KwSizeof:
        {
            Advance();
            try Expect(TokenKind.LParen, "'(' after 'sizeof'");
            var e = SizeOfExpr { };
            e.Type = try ParseType();
            try Expect(TokenKind.RParen, "')'");
            return Tree.AddSizeOf(loc, e);
        }
        case TokenKind.KwDefault:
        {
            Advance();
            try Expect(TokenKind.LParen, "'(' after 'default'");
            var e = DefaultExpr { };
            e.Type = try ParseType();
            try Expect(TokenKind.RParen, "')'");
            return Tree.AddDefault(loc, e);
        }
        case TokenKind.KwNew:
            return ParseNew();
        case TokenKind.LParen:
            return ParseParenOrCast();
        case TokenKind.Ident:
        {
            if (t.Text == "error" && PeekKind(1) == TokenKind.LParen)
            {
                Advance();
                Advance();
                var e = ErrorLitExpr { };
                e.Message = try ParseExpr();
                if (Match(TokenKind.Comma))
                    e.Code = try ParseExpr();
                try Expect(TokenKind.RParen, "')'");
                return Tree.AddErrorLit(loc, e);
            }

            var n = NameExpr { Name = t.Text };
            n.TypeArgs = new TypeRef[0];
            Advance();
            if (Check(TokenKind.Lt))
            {
                var r = TryExprTypeArgs();
                if (r.Ok)
                    n.TypeArgs = r.Args;
            }
            return Tree.AddName(loc, n);
        }
        default:
            return error("unexpected " + TokenName(t.Kind) + " in expression", t.Loc.Pack());
        }
    }
}
