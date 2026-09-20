#pragma once

#include "AST.h"
#include "Lexer.h"

class Parser
{
public:
    Parser(std::vector<Token> tokens, Diagnostics& diag);
    std::unique_ptr<CompilationUnit> parseUnit(bool isPrelude);
    TypeRefPtr parseStandaloneType();

private:
    // Token helpers
    const Token& cur() const { return tokens[pos]; }
    const Token& peekTok(size_t ahead = 1) const;
    bool check(Tok kind) const { return cur().kind == kind; }
    bool checkIdent(const char* text) const { return cur().kind == Tok::Ident && cur().text == text; }
    bool match(Tok kind);
    const Token& advance();
    const Token& expect(Tok kind, const char* what);
    std::string expectIdent(const char* what);
    bool adjacent(const Token& a, const Token& b) const;
    [[noreturn]] void errorHere(const std::string& message);

    // Declarations
    void parseTopLevel(CompilationUnit& unit);
    std::string parseQualifiedName();
    std::unique_ptr<StructDecl> parseStruct(CompilationUnit& unit);
    std::unique_ptr<InterfaceDecl> parseInterface(CompilationUnit& unit);
    std::unique_ptr<EnumDecl> parseEnum(CompilationUnit& unit);
    std::unique_ptr<FuncDecl> parseFunction(CompilationUnit& unit, bool isExtern, bool isStatic);
    void parseFunctionRest(FuncDecl& fn, CompilationUnit& unit);
    void parseTypeParams(std::vector<std::string>& out);
    void parseConstraints(std::vector<Constraint>& out);
    void parseParams(FuncDecl& fn);

    // Types
    TypeRefPtr parseType();
    TypeRefPtr parseNamedType();
    TypeRefPtr tryParseType();
    bool tryParseTypeArgs(std::vector<TypeRefPtr>& out);

    // Statements
    StmtPtr parseStatement();
    std::unique_ptr<BlockStmt> parseBlock();
    StmtPtr parseSimpleStatement(bool expectSemi);
    std::unique_ptr<VarDeclStmt> tryParseVarDecl();
    StmtPtr parseIf();
    StmtPtr parseWhile();
    StmtPtr parseDoWhile();
    StmtPtr parseFor();
    StmtPtr parseForeach();
    StmtPtr parseSwitch();
    StmtPtr parseUsing();
    void synchronizeStatement();
    void synchronizeTopLevel();

    // Expressions
    ExprPtr parseExpr();
    ExprPtr parseAssignment();
    ExprPtr parseConditional();
    ExprPtr parseBinary(int minPrec);
    ExprPtr parseUnary();
    ExprPtr parsePostfix(ExprPtr expr);
    ExprPtr parsePrimary();
    ExprPtr parseNew();
    ExprPtr parseParenOrCast();
    void parseArgs(std::vector<ExprPtr>& out);
    void parseStructInitBody(StructInitExpr& init);
    bool looksLikeStructInit() const;
    bool castFollows(const TypeRef& type) const;
    TypeRefPtr exprToTypeRef(Expr& expr);

    struct BinOpInfo
    {
        BinOp op;
        int prec;
        int tokenCount;
        bool isIs;
    };
    bool binaryOpAt(BinOpInfo& out) const;
    bool assignOpAt(std::optional<BinOp>& op, int& tokenCount) const;

    std::vector<Token> tokens;
    size_t pos = 0;
    Diagnostics& diag;
    CompilationUnit* unit = nullptr;
};
