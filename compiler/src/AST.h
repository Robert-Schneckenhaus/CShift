#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "Common.h"

// ---------------------------------------------------------------------------
// Type references (syntax only, resolved to Type* during code generation)
// ---------------------------------------------------------------------------

struct TypeRef;
using TypeRefPtr = std::unique_ptr<TypeRef>;

struct TypeRef
{
    enum Kind
    {
        Named,   // a.b.C<args>
        Pointer, // elem*
        Array    // elem[]
    };

    Kind kind = Named;
    SourceLoc loc;
    std::vector<std::string> path;
    std::vector<TypeRefPtr> args;
    TypeRefPtr elem;

    std::string toString() const;
};

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

enum class ExprKind
{
    IntLit, FloatLit, CharLit, StringLit, BoolLit, NullLit,
    Name, Member, Call, Index, Unary, Binary, Assign, Conditional, Cast,
    NewArray, NewObject, StructInit, Is, Try, ErrorLit, SizeOf, Default, This, Unchecked, RefArg, Start
};

enum class BinOp
{
    Add, Sub, Mul, Div, Rem,
    BitAnd, BitOr, BitXor, Shl, Shr,
    LogAnd, LogOr,
    Eq, Ne, Lt, Gt, Le, Ge
};

enum class UnOp { Neg, Plus, Not, BitNot, Deref, AddrOf };

struct Expr
{
    Expr(ExprKind k, SourceLoc l) : kind(k), loc(l) {}
    virtual ~Expr() = default;
    ExprKind kind;
    SourceLoc loc;
};
using ExprPtr = std::unique_ptr<Expr>;

struct IntLitExpr : Expr
{
    IntLitExpr(SourceLoc l) : Expr(ExprKind::IntLit, l) {}
    uint64_t value = 0;
    bool isUnsigned = false;
    bool isLong = false;
};

struct FloatLitExpr : Expr
{
    FloatLitExpr(SourceLoc l) : Expr(ExprKind::FloatLit, l) {}
    double value = 0;
    bool isFloat32 = false;
};

struct CharLitExpr : Expr
{
    CharLitExpr(SourceLoc l) : Expr(ExprKind::CharLit, l) {}
    uint8_t value = 0;
};

struct StringLitExpr : Expr
{
    StringLitExpr(SourceLoc l) : Expr(ExprKind::StringLit, l) {}
    std::string value;
};

struct BoolLitExpr : Expr
{
    BoolLitExpr(SourceLoc l) : Expr(ExprKind::BoolLit, l) {}
    bool value = false;
};

struct NullLitExpr : Expr
{
    NullLitExpr(SourceLoc l) : Expr(ExprKind::NullLit, l) {}
};

struct NameExpr : Expr
{
    NameExpr(SourceLoc l) : Expr(ExprKind::Name, l) {}
    std::string name;
    std::vector<TypeRefPtr> typeArgs;
};

struct MemberExpr : Expr
{
    MemberExpr(SourceLoc l) : Expr(ExprKind::Member, l) {}
    ExprPtr object;
    std::string name;
    std::vector<TypeRefPtr> typeArgs;
    bool viaArrow = false; // p->x
};

struct CallExpr : Expr
{
    CallExpr(SourceLoc l) : Expr(ExprKind::Call, l) {}
    ExprPtr callee;
    std::vector<ExprPtr> args;
};

struct IndexExpr : Expr
{
    IndexExpr(SourceLoc l) : Expr(ExprKind::Index, l) {}
    ExprPtr object;
    ExprPtr index;
};

struct UnaryExpr : Expr
{
    UnaryExpr(SourceLoc l) : Expr(ExprKind::Unary, l) {}
    UnOp op = UnOp::Neg;
    ExprPtr operand;
};

struct BinaryExpr : Expr
{
    BinaryExpr(SourceLoc l) : Expr(ExprKind::Binary, l) {}
    BinOp op = BinOp::Add;
    ExprPtr lhs;
    ExprPtr rhs;
};

struct AssignExpr : Expr
{
    AssignExpr(SourceLoc l) : Expr(ExprKind::Assign, l) {}
    std::optional<BinOp> op; // set for compound assignments (+=, ...)
    ExprPtr target;
    ExprPtr value;
};

struct CondExpr : Expr
{
    CondExpr(SourceLoc l) : Expr(ExprKind::Conditional, l) {}
    ExprPtr cond;
    ExprPtr thenExpr;
    ExprPtr elseExpr;
};

struct CastExpr : Expr
{
    CastExpr(SourceLoc l) : Expr(ExprKind::Cast, l) {}
    TypeRefPtr type;
    ExprPtr operand;
};

struct NewArrayExpr : Expr
{
    NewArrayExpr(SourceLoc l) : Expr(ExprKind::NewArray, l) {}
    TypeRefPtr elemType;
    ExprPtr size;              // null if only an initializer list is given
    std::vector<ExprPtr> init; // element initializers
    bool hasInit = false;
};

struct NewObjectExpr : Expr
{
    NewObjectExpr(SourceLoc l) : Expr(ExprKind::NewObject, l) {}
    TypeRefPtr type;
};

struct FieldInit
{
    SourceLoc loc;
    std::string name;
    ExprPtr value;
};

struct StructInitExpr : Expr
{
    StructInitExpr(SourceLoc l) : Expr(ExprKind::StructInit, l) {}
    TypeRefPtr type;
    std::vector<FieldInit> fields;
};

struct IsExpr : Expr
{
    IsExpr(SourceLoc l) : Expr(ExprKind::Is, l) {}
    ExprPtr operand;
    TypeRefPtr type;
    std::string bindName; // empty if no binding
};

struct TryExpr : Expr
{
    TryExpr(SourceLoc l) : Expr(ExprKind::Try, l) {}
    ExprPtr operand;
};

struct ErrorLitExpr : Expr
{
    ErrorLitExpr(SourceLoc l) : Expr(ExprKind::ErrorLit, l) {}
    ExprPtr message;
    ExprPtr code; // optional
};

// default(T): the zero value of any type (0, false, null, empty Optional, all fields zero)
struct DefaultExpr : Expr
{
    DefaultExpr(SourceLoc l) : Expr(ExprKind::Default, l) {}
    TypeRefPtr type;
};

struct SizeOfExpr : Expr
{
    SizeOfExpr(SourceLoc l) : Expr(ExprKind::SizeOf, l) {}
    TypeRefPtr type;
};

struct ThisExpr : Expr
{
    ThisExpr(SourceLoc l) : Expr(ExprKind::This, l) {}
};

struct UncheckedExpr : Expr
{
    UncheckedExpr(SourceLoc l) : Expr(ExprKind::Unchecked, l) {}
    ExprPtr operand;
};

struct RefArgExpr : Expr
{
    RefArgExpr(SourceLoc l) : Expr(ExprKind::RefArg, l) {}
    ExprPtr operand;
};

// 'start f(args)': the only way to call a 'thread' function (a plain call to one is a compile-time error).
// 'operand' must be a Call whose callee resolves to a 'thread' function.
struct StartExpr : Expr
{
    StartExpr(SourceLoc l) : Expr(ExprKind::Start, l) {}
    ExprPtr operand;
};

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

enum class StmtKind
{
    Block, VarDecl, Expr, If, While, DoWhile, For, Foreach, Switch,
    Break, Continue, Return, UsingBlock, Empty
};

struct Stmt
{
    Stmt(StmtKind k, SourceLoc l) : kind(k), loc(l) {}
    virtual ~Stmt() = default;
    StmtKind kind;
    SourceLoc loc;
};
using StmtPtr = std::unique_ptr<Stmt>;

struct BlockStmt : Stmt
{
    BlockStmt(SourceLoc l) : Stmt(StmtKind::Block, l) {}
    std::vector<StmtPtr> stmts;
    bool isUnsafe = false;
    bool isUnchecked = false;
};

struct VarDeclStmt : Stmt
{
    VarDeclStmt(SourceLoc l) : Stmt(StmtKind::VarDecl, l) {}
    TypeRefPtr type; // null means 'var'
    std::string name;
    ExprPtr init;    // may be null (never for constants)
    bool isUsing = false;
    bool isConst = false; // const int X = 5;  (a read-only variable with a constant initializer)
};

struct ExprStmt : Stmt
{
    ExprStmt(SourceLoc l) : Stmt(StmtKind::Expr, l) {}
    ExprPtr expr;
};

struct IfStmt : Stmt
{
    IfStmt(SourceLoc l) : Stmt(StmtKind::If, l) {}
    ExprPtr cond;
    StmtPtr thenStmt;
    StmtPtr elseStmt;
};

struct WhileStmt : Stmt
{
    WhileStmt(SourceLoc l) : Stmt(StmtKind::While, l) {}
    ExprPtr cond;
    StmtPtr body;
};

struct DoWhileStmt : Stmt
{
    DoWhileStmt(SourceLoc l) : Stmt(StmtKind::DoWhile, l) {}
    StmtPtr body;
    ExprPtr cond;
};

struct ForStmt : Stmt
{
    ForStmt(SourceLoc l) : Stmt(StmtKind::For, l) {}
    StmtPtr init; // may be null
    ExprPtr cond; // may be null
    std::vector<ExprPtr> iterators;
    StmtPtr body;
};

struct ForeachStmt : Stmt
{
    ForeachStmt(SourceLoc l) : Stmt(StmtKind::Foreach, l) {}
    TypeRefPtr type; // null means 'var'
    std::string name;
    ExprPtr iterable;
    StmtPtr body;
};

struct CaseLabel
{
    SourceLoc loc;
    bool isDefault = false;
    ExprPtr value;        // constant case
    TypeRefPtr patType;   // pattern case: 'case T name:'
    std::string patName;
};

struct SwitchSection
{
    SourceLoc loc;
    std::vector<CaseLabel> labels;
    std::vector<StmtPtr> body;
};

struct SwitchStmt : Stmt
{
    SwitchStmt(SourceLoc l) : Stmt(StmtKind::Switch, l) {}
    ExprPtr subject;
    std::vector<SwitchSection> sections;
};

struct BreakStmt : Stmt
{
    BreakStmt(SourceLoc l) : Stmt(StmtKind::Break, l) {}
};

struct ContinueStmt : Stmt
{
    ContinueStmt(SourceLoc l) : Stmt(StmtKind::Continue, l) {}
};

struct ReturnStmt : Stmt
{
    ReturnStmt(SourceLoc l) : Stmt(StmtKind::Return, l) {}
    ExprPtr value; // may be null
};

struct UsingBlockStmt : Stmt
{
    UsingBlockStmt(SourceLoc l) : Stmt(StmtKind::UsingBlock, l) {}
    std::unique_ptr<VarDeclStmt> decl;
    StmtPtr body;
};

struct EmptyStmt : Stmt
{
    EmptyStmt(SourceLoc l) : Stmt(StmtKind::Empty, l) {}
};

// ---------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------

struct FileContext
{
    int fileId = 0;
    std::string ns; // file-scoped namespace, empty = global
    std::vector<std::string> usings;
    bool isPrelude = false;
};

enum class RefKind { None, Ref, ConstRef };

struct Param
{
    SourceLoc loc;
    TypeRefPtr type;
    std::string name;
    RefKind refKind = RefKind::None;
    // FFI marshalling (set for imported C functions):
    bool nullable = false; // a ref/const ref/string parameter that also accepts null (a C pointer that may be NULL)
    bool cstring = false;  // string parameter that is passed as a NUL-terminated char* (const char*)
};

struct Constraint
{
    std::string param;
    std::vector<TypeRefPtr> bounds;
};

struct StructDecl;

struct FuncDecl
{
    SourceLoc loc;
    std::string name;
    std::vector<std::string> typeParams;
    std::vector<Param> params;
    TypeRefPtr ret;
    std::unique_ptr<BlockStmt> body; // null for extern functions and interface methods
    std::vector<Constraint> constraints;
    bool isExtern = false;
    bool isStatic = false;
    bool isVariadic = false;
    bool isThread = false; // 'thread' function: calling it spawns an OS thread (see Types.h / CodeGenThread.cpp)
    // FFI (imported C functions):
    std::string symbol;         // C symbol to call if it differs from the name (e.g. a generated shim)
    bool retCString = false;    // returns a const char* that is copied into a string
    bool retOut = false;        // the C symbol returns the value through an extra trailing pointer parameter
    FileContext* file = nullptr;
    StructDecl* owner = nullptr; // set for struct methods
};

struct FieldDecl
{
    SourceLoc loc;
    TypeRefPtr type;
    std::string name;
    int64_t offset = -1; // byte offset for structs with an explicit (C) layout
};

struct StructDecl
{
    SourceLoc loc;
    std::string name;
    std::vector<std::string> typeParams;
    std::vector<TypeRefPtr> bases; // optional base struct first, then interfaces
    std::vector<Constraint> constraints;
    std::vector<FieldDecl> fields;
    std::vector<std::unique_ptr<FuncDecl>> methods;
    // Structs imported from C headers have an exact layout: fields at fixed offsets, padding in between.
    bool explicitLayout = false;
    uint64_t layoutSize = 0;
    uint64_t layoutAlign = 1;
    bool opaque = false; // incomplete C type: only usable through pointers
    FileContext* file = nullptr;
};

struct InterfaceDecl
{
    SourceLoc loc;
    std::string name;
    std::vector<std::string> typeParams;
    std::vector<std::unique_ptr<FuncDecl>> methods;
    FileContext* file = nullptr;
};

struct EnumMember
{
    SourceLoc loc;
    std::string name;
    ExprPtr value; // optional
};

struct EnumDecl
{
    SourceLoc loc;
    std::string name;
    TypeRefPtr base;
    std::vector<EnumMember> members;
    FileContext* file = nullptr;
};

// const double PI = 3.14159;   (top level, initializer must be a constant expression of literals)
struct ConstDecl
{
    SourceLoc loc;
    TypeRefPtr type;
    std::string name;
    ExprPtr init;
    FileContext* file = nullptr;
};

// A global variable:   int Counter = 0;   string Name;   List<string> Names = List<string>.Create();
// (top level; the initializer is any expression, evaluated before Main in the order of the declarations)
struct GlobalDecl
{
    SourceLoc loc;
    TypeRefPtr type;
    std::string name;
    ExprPtr init; // may be null: the variable starts zeroed
    FileContext* file = nullptr;
};

// using Name from "header.h";   -- imports the declarations of a C header as namespace Name
struct ImportDecl
{
    SourceLoc loc;
    std::string name;
    std::string header;
};

struct CompilationUnit
{
    FileContext file;
    std::vector<ImportDecl> imports;
    std::vector<std::unique_ptr<ConstDecl>> consts;
    std::vector<std::unique_ptr<GlobalDecl>> globals;
    std::vector<std::unique_ptr<StructDecl>> structs;
    std::vector<std::unique_ptr<InterfaceDecl>> interfaces;
    std::vector<std::unique_ptr<EnumDecl>> enums;
    std::vector<std::unique_ptr<FuncDecl>> funcs;
    std::vector<std::string> links; // link "name";
};

inline std::string TypeRef::toString() const
{
    switch (kind)
    {
    case Pointer: return elem->toString() + "*";
    case Array: return elem->toString() + "[]";
    case Named:
    {
        std::string s;
        for (size_t i = 0; i < path.size(); i += 1)
            s += (i ? "." : "") + path[i];
        if (!args.empty())
        {
            s += "<";
            for (size_t i = 0; i < args.size(); i += 1)
                s += (i ? ", " : "") + args[i]->toString();
            s += ">";
        }
        return s;
    }
    }
    return "?";
}
