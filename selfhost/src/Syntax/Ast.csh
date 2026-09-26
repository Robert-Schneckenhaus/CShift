// The syntax tree.
//
// CShift has no classes, so the tree is stored in "arenas": one List per kind of node, all of them held by the
// struct Ast. A node is referred to by a small handle (Expr, Stmt, TypeRef) that says which kind it is and where it
// is stored. Handles are plain values: they can be copied and compared freely, and the default value (all zeros) is
// "no node". The struct Ast is a handle to shared storage, so it can be passed around by value.
//
//     var call = ast.GetCall(e);          // e.Kind == ExprKind.Call
//     foreach (var arg in call.Args) ...

namespace CShift.Syntax;

using System;

enum BinOp : int32
{
    Add, Sub, Mul, Div, Rem,
    BitAnd, BitOr, BitXor, Shl, Shr,
    LogAnd, LogOr,
    Eq, Ne, Lt, Gt, Le, Ge
}

enum UnOp : int32 { Neg, Plus, Not, BitNot, Deref, AddrOf }

enum RefKind : int32 { None, Ref, ConstRef }

// ---------------------------------------------------------------------------
// Handles
// ---------------------------------------------------------------------------

enum ExprKind : int32
{
    None, // the default value: no expression
    IntLit, FloatLit, CharLit, StringLit, BoolLit, NullLit,
    Name, Member, Call, Index, Unary, Binary, Assign, Conditional, Cast,
    NewArray, NewObject, StructInit, Is, Try, ErrorLit, SizeOf, Default, This, Unchecked, RefArg, Start,
    Lambda, // only in the self-hosted compiler
    Slice,  // a[i..j]
    Collection // [a, b, ..c]
}

struct Expr
{
    ExprKind Kind;
    int Index; // position in the list of nodes of this kind
    SourceLoc Loc;

    bool IsNull()
    {
        return Kind == ExprKind.None;
    }
}

enum StmtKind : int32
{
    None,
    Block, VarDecl, Expr, If, While, DoWhile, For, Foreach, Switch,
    Break, Continue, Return, UsingBlock, Empty
}

struct Stmt
{
    StmtKind Kind;
    int Index;
    SourceLoc Loc;

    bool IsNull()
    {
        return Kind == StmtKind.None;
    }
}

// A type as written in the source. Id is the position in Ast.Types plus one; 0 means "no type" (for 'var').
struct TypeRef
{
    int Id;

    bool IsNull()
    {
        return Id == 0;
    }
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum TypeRefKind : int32 { Named, Pointer, Array }

struct TypeRefNode
{
    TypeRefKind Kind;
    SourceLoc Loc;
    string[] Path;   // Named: a.b.C
    TypeRef[] Args;  // Named: type arguments
    TypeRef Elem;    // Pointer, Array
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

struct IntLitExpr
{
    uint64 Value;
    bool IsUnsigned;
    bool IsLong;
}

struct FloatLitExpr
{
    double Value;
    bool IsFloat32;
}

struct CharLitExpr
{
    int Value;
}

struct StringLitExpr
{
    string Value;
}

struct BoolLitExpr
{
    bool Value;
}

struct NameExpr
{
    string Name;
    TypeRef[] TypeArgs;
}

struct MemberExpr
{
    Expr Object;
    string Name;
    TypeRef[] TypeArgs;
    bool ViaArrow; // p->x
}

struct CallExpr
{
    Expr Callee;
    Expr[] Args;
}

struct IndexExpr
{
    Expr Object;
    Expr Index;
    bool FromEnd;  // a[^n]: the n-th element from the end
}

// [a, b, ..c]: a collection expression; its type comes from where it is used (T[], Slice<T>, List<T>, ...).
struct CollectionExpr
{
    Expr[] Items;
    bool[] Spread;     // ..c: the elements of c
}

// a[start..end], a[..end], a[start..], a[..]; ^n counts from the end. The result is a view (Slice<T>, StringSlice).
struct SliceExpr
{
    Expr Object;
    Expr Start;        // none: 0
    Expr End;          // none: the length
    bool StartFromEnd;
    bool EndFromEnd;
}

struct UnaryExpr
{
    UnOp Op;
    Expr Operand;
}

struct BinaryExpr
{
    BinOp Op;
    Expr Lhs;
    Expr Rhs;
}

struct AssignExpr
{
    bool HasOp; // compound assignment (+=, ...)
    BinOp Op;
    Expr Target;
    Expr Value;
}

struct CondExpr
{
    Expr Cond;
    Expr Then;
    Expr Else;
}

struct CastExpr
{
    TypeRef Type;
    Expr Operand;
}

struct NewArrayExpr
{
    TypeRef ElemType;
    Expr Size;      // none if only an initializer list is given
    Expr[] Init;    // element initializers
    bool HasInit;
}

struct NewObjectExpr
{
    TypeRef Type;
}

struct FieldInit
{
    SourceLoc Loc;
    string Name;
    Expr Value;
}

struct StructInitExpr
{
    TypeRef Type;
    FieldInit[] Fields;
}

struct IsExpr
{
    Expr Operand;
    TypeRef Type;
    string BindName; // empty if there is no binding
    bool Negated;    // 'x is not T'
}

struct TryExpr
{
    Expr Operand;
}

struct ErrorLitExpr
{
    Expr Message;
    Expr Code; // optional
}

struct SizeOfExpr
{
    TypeRef Type;
}

// default(T): the zero value of any type
struct DefaultExpr
{
    TypeRef Type;
}

struct UncheckedExpr
{
    Expr Operand;
}

struct RefArgExpr
{
    Expr Operand;
}

// 'start f(...)': spawns the 'thread' function f on its own OS thread.
// x => x + 1, (int a, int b) => { return a + b; }, () => Work(): the parameter types may be left out (they come
// from the Action/Func type the lambda is converted to). Either Body or Block is set.
struct LambdaExpr
{
    Param[] Params;
    Expr Body;
    Stmt Block;
}

struct StartExpr
{
    Expr Operand;
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

struct BlockStmt
{
    Stmt[] Stmts;
    bool IsUnsafe;
    bool IsUnchecked;
}

struct VarDeclStmt
{
    TypeRef Type; // none means 'var'
    string Name;
    Expr Init;    // optional (never for constants)
    bool IsUsing;
    bool IsConst; // const int X = 5;  (a read-only variable with a constant initializer)
}

struct ExprStmt
{
    Expr Expr;
}

struct IfStmt
{
    Expr Cond;
    Stmt Then;
    Stmt Else; // optional
}

struct WhileStmt
{
    Expr Cond;
    Stmt Body;
}

struct DoWhileStmt
{
    Stmt Body;
    Expr Cond;
}

struct ForStmt
{
    Stmt Init;       // optional
    Expr Cond;       // optional
    Expr[] Iterators;
    Stmt Body;
}

struct ForeachStmt
{
    TypeRef Type; // none means 'var'
    string Name;
    Expr Iterable;
    Stmt Body;
}

struct CaseLabel
{
    SourceLoc Loc;
    bool IsDefault;
    Expr Value;       // constant case
    TypeRef PatType;  // pattern case: 'case T name:'
    string PatName;
}

struct SwitchSection
{
    SourceLoc Loc;
    CaseLabel[] Labels;
    Stmt[] Body;
}

struct SwitchStmt
{
    Expr Subject;
    SwitchSection[] Sections;
}

struct ReturnStmt
{
    Expr Value; // optional
}

struct UsingBlockStmt
{
    Stmt Decl;  // a VarDecl
    Stmt Body;
}

// ---------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------

struct FileContext
{
    int FileId;
    string Ns;              // file-scoped namespace, empty = global
    List<string> Usings;
    bool IsPrelude;
}

struct Param
{
    SourceLoc Loc;
    TypeRef Type;
    string Name;
    RefKind Ref;
    // FFI marshalling (set for imported C functions)
    bool Nullable;
    bool CString;
}

struct Constraint
{
    string Param;
    TypeRef[] Bounds;
}

struct FuncDecl
{
    SourceLoc Loc;
    string Name;
    string[] TypeParams;
    Param[] Params;
    TypeRef Ret;
    Stmt Body;            // a Block; none for extern functions and interface methods
    Constraint[] Constraints;
    bool IsExtern;
    bool IsStatic;
    bool IsVariadic;
    bool IsThread;        // 'thread' function: only callable through 'start', runs on its own OS thread
    // FFI (imported C functions)
    string Symbol;
    bool RetCString;
    bool RetOut;
    int Owner;            // struct methods: index of the struct in CompilationUnit.Structs, otherwise -1
}

struct FieldDecl
{
    SourceLoc Loc;
    TypeRef Type;
    string Name;
    int64 Offset;         // byte offset for structs with an explicit (C) layout, otherwise -1
}

struct StructDecl
{
    SourceLoc Loc;
    string Name;
    string[] TypeParams;
    TypeRef[] Bases;      // optional base struct first, then interfaces
    Constraint[] Constraints;
    FieldDecl[] Fields;
    FuncDecl[] Methods;
    bool ExplicitLayout;
    uint64 LayoutSize;
    uint64 LayoutAlign;
    bool Opaque;
}

struct InterfaceDecl
{
    SourceLoc Loc;
    string Name;
    string[] TypeParams;
    FuncDecl[] Methods;
}

struct EnumMember
{
    SourceLoc Loc;
    string Name;
    Expr Value;           // optional
}

struct EnumDecl
{
    SourceLoc Loc;
    string Name;
    TypeRef Base;       // null for an error enum (always int32)
    EnumMember[] Members;
    bool IsError;       // 'error Name { ... }': the codes of Error<T, Name>
}

// const double PI = 3.14159;
struct ConstDecl
{
    SourceLoc Loc;
    TypeRef Type;
    string Name;
    Expr Init;
}

// A global variable:   int Counter = 0;   string Name;   List<string> Names = List<string>.Create();
struct GlobalDecl
{
    SourceLoc Loc;
    TypeRef Type;
    string Name;
    Expr Init;      // none: the variable starts zeroed
}

// using Name from "header.h";
struct ImportDecl
{
    SourceLoc Loc;
    string Name;
    string Header;
}

// union Shape : IShape { Circle, Rect }: one of the member types, stored inline with a tag (only in the self-hosted
// compiler).
struct UnionDecl
{
    SourceLoc Loc;
    string Name;
    TypeRef[] Members;
    TypeRef[] Interfaces;
}

struct CompilationUnit
{
    FileContext File;
    List<ImportDecl> Imports;
    List<ConstDecl> Consts;
    List<GlobalDecl> Globals;
    List<StructDecl> Structs;
    List<InterfaceDecl> Interfaces;
    List<EnumDecl> Enums;
    List<UnionDecl> Unions;
    List<FuncDecl> Funcs;
    List<string> Links; // link "name";

    static CompilationUnit Create(int fileId, bool isPrelude)
    {
        var unit = CompilationUnit { };
        unit.File = FileContext { FileId = fileId, Ns = "", Usings = List<string>.Create(), IsPrelude = isPrelude };
        unit.Imports = List<ImportDecl>.Create();
        unit.Consts = List<ConstDecl>.Create();
        unit.Globals = List<GlobalDecl>.Create();
        unit.Structs = List<StructDecl>.Create();
        unit.Interfaces = List<InterfaceDecl>.Create();
        unit.Enums = List<EnumDecl>.Create();
        unit.Unions = List<UnionDecl>.Create();
        unit.Funcs = List<FuncDecl>.Create();
        unit.Links = List<string>.Create();
        return unit;
    }
}

// ---------------------------------------------------------------------------
// The arenas
// ---------------------------------------------------------------------------

struct Ast
{
    List<TypeRefNode> Types;
    List<IntLitExpr> IntLits;
    List<FloatLitExpr> FloatLits;
    List<CharLitExpr> CharLits;
    List<StringLitExpr> StringLits;
    List<BoolLitExpr> BoolLits;
    List<NameExpr> Names;
    List<MemberExpr> Members;
    List<CallExpr> Calls;
    List<IndexExpr> Indexes;
    List<SliceExpr> Slices;
    List<CollectionExpr> Collections;
    List<UnaryExpr> Unaries;
    List<BinaryExpr> Binaries;
    List<AssignExpr> Assigns;
    List<CondExpr> Conds;
    List<CastExpr> Casts;
    List<NewArrayExpr> NewArrays;
    List<NewObjectExpr> NewObjects;
    List<StructInitExpr> StructInits;
    List<IsExpr> Iss;
    List<TryExpr> Trys;
    List<ErrorLitExpr> ErrorLits;
    List<SizeOfExpr> SizeOfs;
    List<DefaultExpr> Defaults;
    List<UncheckedExpr> Uncheckeds;
    List<RefArgExpr> RefArgs;
    List<StartExpr> Starts;
    List<LambdaExpr> Lambdas;

    List<BlockStmt> Blocks;
    List<VarDeclStmt> VarDecls;
    List<ExprStmt> ExprStmts;
    List<IfStmt> Ifs;
    List<WhileStmt> Whiles;
    List<DoWhileStmt> DoWhiles;
    List<ForStmt> Fors;
    List<ForeachStmt> Foreachs;
    List<SwitchStmt> Switches;
    List<ReturnStmt> Returns;
    List<UsingBlockStmt> UsingBlocks;

    static Ast Create()
    {
        var a = Ast { };
        a.Types = List<TypeRefNode>.Create();
        a.IntLits = List<IntLitExpr>.Create();
        a.FloatLits = List<FloatLitExpr>.Create();
        a.CharLits = List<CharLitExpr>.Create();
        a.StringLits = List<StringLitExpr>.Create();
        a.BoolLits = List<BoolLitExpr>.Create();
        a.Names = List<NameExpr>.Create();
        a.Members = List<MemberExpr>.Create();
        a.Calls = List<CallExpr>.Create();
        a.Indexes = List<IndexExpr>.Create();
        a.Slices = List<SliceExpr>.Create();
        a.Collections = List<CollectionExpr>.Create();
        a.Unaries = List<UnaryExpr>.Create();
        a.Binaries = List<BinaryExpr>.Create();
        a.Assigns = List<AssignExpr>.Create();
        a.Conds = List<CondExpr>.Create();
        a.Casts = List<CastExpr>.Create();
        a.NewArrays = List<NewArrayExpr>.Create();
        a.NewObjects = List<NewObjectExpr>.Create();
        a.StructInits = List<StructInitExpr>.Create();
        a.Iss = List<IsExpr>.Create();
        a.Trys = List<TryExpr>.Create();
        a.ErrorLits = List<ErrorLitExpr>.Create();
        a.SizeOfs = List<SizeOfExpr>.Create();
        a.Defaults = List<DefaultExpr>.Create();
        a.Uncheckeds = List<UncheckedExpr>.Create();
        a.RefArgs = List<RefArgExpr>.Create();
        a.Starts = List<StartExpr>.Create();
        a.Lambdas = List<LambdaExpr>.Create();
        a.Blocks = List<BlockStmt>.Create();
        a.VarDecls = List<VarDeclStmt>.Create();
        a.ExprStmts = List<ExprStmt>.Create();
        a.Ifs = List<IfStmt>.Create();
        a.Whiles = List<WhileStmt>.Create();
        a.DoWhiles = List<DoWhileStmt>.Create();
        a.Fors = List<ForStmt>.Create();
        a.Foreachs = List<ForeachStmt>.Create();
        a.Switches = List<SwitchStmt>.Create();
        a.Returns = List<ReturnStmt>.Create();
        a.UsingBlocks = List<UsingBlockStmt>.Create();
        return a;
    }

    // ---- types ----

    TypeRef AddType(TypeRefNode node)
    {
        Types.Add(node);
        return TypeRef { Id = Types.Count() };
    }

    TypeRefNode GetType(TypeRef t)
    {
        return Types.Get(t.Id - 1);
    }

    // The type as text: a.b.C<x, y>*[]
    string TypeToString(TypeRef t)
    {
        var node = GetType(t);
        switch (node.Kind)
        {
        case TypeRefKind.Pointer:
            return TypeToString(node.Elem) + "*";
        case TypeRefKind.Array:
            return TypeToString(node.Elem) + "[]";
        default:
            var sb = StringBuilder.Create();
            for (var i = 0; i < node.Path.Length; i += 1)
            {
                if (i > 0)
                    sb.Append('.');
                sb.Append(node.Path[i]);
            }
            if (node.Args.Length > 0)
            {
                sb.Append('<');
                for (var i = 0; i < node.Args.Length; i += 1)
                {
                    if (i > 0)
                        sb.Append(", ");
                    sb.Append(TypeToString(node.Args[i]));
                }
                sb.Append('>');
            }
            return sb.ToString();
        }
    }

    // ---- expressions ----

    Expr NoExpr()
    {
        return Expr { };
    }

    Expr AddIntLit(SourceLoc loc, IntLitExpr n)
    {
        IntLits.Add(n);
        return Expr { Kind = ExprKind.IntLit, Index = IntLits.Count() - 1, Loc = loc };
    }

    Expr AddFloatLit(SourceLoc loc, FloatLitExpr n)
    {
        FloatLits.Add(n);
        return Expr { Kind = ExprKind.FloatLit, Index = FloatLits.Count() - 1, Loc = loc };
    }

    Expr AddCharLit(SourceLoc loc, CharLitExpr n)
    {
        CharLits.Add(n);
        return Expr { Kind = ExprKind.CharLit, Index = CharLits.Count() - 1, Loc = loc };
    }

    Expr AddStringLit(SourceLoc loc, StringLitExpr n)
    {
        StringLits.Add(n);
        return Expr { Kind = ExprKind.StringLit, Index = StringLits.Count() - 1, Loc = loc };
    }

    Expr AddBoolLit(SourceLoc loc, BoolLitExpr n)
    {
        BoolLits.Add(n);
        return Expr { Kind = ExprKind.BoolLit, Index = BoolLits.Count() - 1, Loc = loc };
    }

    Expr AddNullLit(SourceLoc loc)
    {
        return Expr { Kind = ExprKind.NullLit, Index = 0, Loc = loc };
    }

    Expr AddThis(SourceLoc loc)
    {
        return Expr { Kind = ExprKind.This, Index = 0, Loc = loc };
    }

    Expr AddName(SourceLoc loc, NameExpr n)
    {
        Names.Add(n);
        return Expr { Kind = ExprKind.Name, Index = Names.Count() - 1, Loc = loc };
    }

    Expr AddMember(SourceLoc loc, MemberExpr n)
    {
        Members.Add(n);
        return Expr { Kind = ExprKind.Member, Index = Members.Count() - 1, Loc = loc };
    }

    Expr AddCall(SourceLoc loc, CallExpr n)
    {
        Calls.Add(n);
        return Expr { Kind = ExprKind.Call, Index = Calls.Count() - 1, Loc = loc };
    }

    Expr AddCollection(SourceLoc loc, CollectionExpr n)
    {
        Collections.Add(n);
        return Expr { Kind = ExprKind.Collection, Index = Collections.Count() - 1, Loc = loc };
    }

    Expr AddSlice(SourceLoc loc, SliceExpr n)
    {
        Slices.Add(n);
        return Expr { Kind = ExprKind.Slice, Index = Slices.Count() - 1, Loc = loc };
    }

    Expr AddIndex(SourceLoc loc, IndexExpr n)
    {
        Indexes.Add(n);
        return Expr { Kind = ExprKind.Index, Index = Indexes.Count() - 1, Loc = loc };
    }

    Expr AddUnary(SourceLoc loc, UnaryExpr n)
    {
        Unaries.Add(n);
        return Expr { Kind = ExprKind.Unary, Index = Unaries.Count() - 1, Loc = loc };
    }

    Expr AddBinary(SourceLoc loc, BinaryExpr n)
    {
        Binaries.Add(n);
        return Expr { Kind = ExprKind.Binary, Index = Binaries.Count() - 1, Loc = loc };
    }

    Expr AddAssign(SourceLoc loc, AssignExpr n)
    {
        Assigns.Add(n);
        return Expr { Kind = ExprKind.Assign, Index = Assigns.Count() - 1, Loc = loc };
    }

    Expr AddCond(SourceLoc loc, CondExpr n)
    {
        Conds.Add(n);
        return Expr { Kind = ExprKind.Conditional, Index = Conds.Count() - 1, Loc = loc };
    }

    Expr AddCast(SourceLoc loc, CastExpr n)
    {
        Casts.Add(n);
        return Expr { Kind = ExprKind.Cast, Index = Casts.Count() - 1, Loc = loc };
    }

    Expr AddNewArray(SourceLoc loc, NewArrayExpr n)
    {
        NewArrays.Add(n);
        return Expr { Kind = ExprKind.NewArray, Index = NewArrays.Count() - 1, Loc = loc };
    }

    Expr AddNewObject(SourceLoc loc, NewObjectExpr n)
    {
        NewObjects.Add(n);
        return Expr { Kind = ExprKind.NewObject, Index = NewObjects.Count() - 1, Loc = loc };
    }

    Expr AddStructInit(SourceLoc loc, StructInitExpr n)
    {
        StructInits.Add(n);
        return Expr { Kind = ExprKind.StructInit, Index = StructInits.Count() - 1, Loc = loc };
    }

    Expr AddIs(SourceLoc loc, IsExpr n)
    {
        Iss.Add(n);
        return Expr { Kind = ExprKind.Is, Index = Iss.Count() - 1, Loc = loc };
    }

    Expr AddTry(SourceLoc loc, TryExpr n)
    {
        Trys.Add(n);
        return Expr { Kind = ExprKind.Try, Index = Trys.Count() - 1, Loc = loc };
    }

    Expr AddErrorLit(SourceLoc loc, ErrorLitExpr n)
    {
        ErrorLits.Add(n);
        return Expr { Kind = ExprKind.ErrorLit, Index = ErrorLits.Count() - 1, Loc = loc };
    }

    Expr AddSizeOf(SourceLoc loc, SizeOfExpr n)
    {
        SizeOfs.Add(n);
        return Expr { Kind = ExprKind.SizeOf, Index = SizeOfs.Count() - 1, Loc = loc };
    }

    Expr AddDefault(SourceLoc loc, DefaultExpr n)
    {
        Defaults.Add(n);
        return Expr { Kind = ExprKind.Default, Index = Defaults.Count() - 1, Loc = loc };
    }

    Expr AddUnchecked(SourceLoc loc, UncheckedExpr n)
    {
        Uncheckeds.Add(n);
        return Expr { Kind = ExprKind.Unchecked, Index = Uncheckeds.Count() - 1, Loc = loc };
    }

    Expr AddRefArg(SourceLoc loc, RefArgExpr n)
    {
        RefArgs.Add(n);
        return Expr { Kind = ExprKind.RefArg, Index = RefArgs.Count() - 1, Loc = loc };
    }

    Expr AddLambda(SourceLoc loc, LambdaExpr n)
    {
        Lambdas.Add(n);
        return Expr { Kind = ExprKind.Lambda, Index = Lambdas.Count() - 1, Loc = loc };
    }

    Expr AddStart(SourceLoc loc, StartExpr n)
    {
        Starts.Add(n);
        return Expr { Kind = ExprKind.Start, Index = Starts.Count() - 1, Loc = loc };
    }

    IntLitExpr GetIntLit(Expr e) { return IntLits.Get(e.Index); }
    FloatLitExpr GetFloatLit(Expr e) { return FloatLits.Get(e.Index); }
    CharLitExpr GetCharLit(Expr e) { return CharLits.Get(e.Index); }
    StringLitExpr GetStringLit(Expr e) { return StringLits.Get(e.Index); }
    BoolLitExpr GetBoolLit(Expr e) { return BoolLits.Get(e.Index); }
    NameExpr GetName(Expr e) { return Names.Get(e.Index); }
    MemberExpr GetMember(Expr e) { return Members.Get(e.Index); }
    CallExpr GetCall(Expr e) { return Calls.Get(e.Index); }
    IndexExpr GetIndex(Expr e) { return Indexes.Get(e.Index); }
    SliceExpr GetSlice(Expr e) { return Slices.Get(e.Index); }
    CollectionExpr GetCollection(Expr e) { return Collections.Get(e.Index); }
    UnaryExpr GetUnary(Expr e) { return Unaries.Get(e.Index); }
    BinaryExpr GetBinary(Expr e) { return Binaries.Get(e.Index); }
    AssignExpr GetAssign(Expr e) { return Assigns.Get(e.Index); }
    CondExpr GetCond(Expr e) { return Conds.Get(e.Index); }
    CastExpr GetCast(Expr e) { return Casts.Get(e.Index); }
    NewArrayExpr GetNewArray(Expr e) { return NewArrays.Get(e.Index); }
    NewObjectExpr GetNewObject(Expr e) { return NewObjects.Get(e.Index); }
    StructInitExpr GetStructInit(Expr e) { return StructInits.Get(e.Index); }
    IsExpr GetIs(Expr e) { return Iss.Get(e.Index); }
    TryExpr GetTry(Expr e) { return Trys.Get(e.Index); }
    ErrorLitExpr GetErrorLit(Expr e) { return ErrorLits.Get(e.Index); }
    SizeOfExpr GetSizeOf(Expr e) { return SizeOfs.Get(e.Index); }
    DefaultExpr GetDefault(Expr e) { return Defaults.Get(e.Index); }
    UncheckedExpr GetUnchecked(Expr e) { return Uncheckeds.Get(e.Index); }
    RefArgExpr GetRefArg(Expr e) { return RefArgs.Get(e.Index); }
    StartExpr GetStart(Expr e) { return Starts.Get(e.Index); }
    LambdaExpr GetLambda(Expr e) { return Lambdas.Get(e.Index); }

    // ---- statements ----

    Stmt AddBlock(SourceLoc loc, BlockStmt n)
    {
        Blocks.Add(n);
        return Stmt { Kind = StmtKind.Block, Index = Blocks.Count() - 1, Loc = loc };
    }

    Stmt AddVarDecl(SourceLoc loc, VarDeclStmt n)
    {
        VarDecls.Add(n);
        return Stmt { Kind = StmtKind.VarDecl, Index = VarDecls.Count() - 1, Loc = loc };
    }

    Stmt AddExprStmt(SourceLoc loc, ExprStmt n)
    {
        ExprStmts.Add(n);
        return Stmt { Kind = StmtKind.Expr, Index = ExprStmts.Count() - 1, Loc = loc };
    }

    Stmt AddIf(SourceLoc loc, IfStmt n)
    {
        Ifs.Add(n);
        return Stmt { Kind = StmtKind.If, Index = Ifs.Count() - 1, Loc = loc };
    }

    Stmt AddWhile(SourceLoc loc, WhileStmt n)
    {
        Whiles.Add(n);
        return Stmt { Kind = StmtKind.While, Index = Whiles.Count() - 1, Loc = loc };
    }

    Stmt AddDoWhile(SourceLoc loc, DoWhileStmt n)
    {
        DoWhiles.Add(n);
        return Stmt { Kind = StmtKind.DoWhile, Index = DoWhiles.Count() - 1, Loc = loc };
    }

    Stmt AddFor(SourceLoc loc, ForStmt n)
    {
        Fors.Add(n);
        return Stmt { Kind = StmtKind.For, Index = Fors.Count() - 1, Loc = loc };
    }

    Stmt AddForeach(SourceLoc loc, ForeachStmt n)
    {
        Foreachs.Add(n);
        return Stmt { Kind = StmtKind.Foreach, Index = Foreachs.Count() - 1, Loc = loc };
    }

    Stmt AddSwitch(SourceLoc loc, SwitchStmt n)
    {
        Switches.Add(n);
        return Stmt { Kind = StmtKind.Switch, Index = Switches.Count() - 1, Loc = loc };
    }

    Stmt AddReturn(SourceLoc loc, ReturnStmt n)
    {
        Returns.Add(n);
        return Stmt { Kind = StmtKind.Return, Index = Returns.Count() - 1, Loc = loc };
    }

    Stmt AddUsingBlock(SourceLoc loc, UsingBlockStmt n)
    {
        UsingBlocks.Add(n);
        return Stmt { Kind = StmtKind.UsingBlock, Index = UsingBlocks.Count() - 1, Loc = loc };
    }

    Stmt AddBreak(SourceLoc loc)
    {
        return Stmt { Kind = StmtKind.Break, Index = 0, Loc = loc };
    }

    Stmt AddContinue(SourceLoc loc)
    {
        return Stmt { Kind = StmtKind.Continue, Index = 0, Loc = loc };
    }

    Stmt AddEmpty(SourceLoc loc)
    {
        return Stmt { Kind = StmtKind.Empty, Index = 0, Loc = loc };
    }

    BlockStmt GetBlock(Stmt s) { return Blocks.Get(s.Index); }
    VarDeclStmt GetVarDecl(Stmt s) { return VarDecls.Get(s.Index); }
    ExprStmt GetExprStmt(Stmt s) { return ExprStmts.Get(s.Index); }
    IfStmt GetIf(Stmt s) { return Ifs.Get(s.Index); }
    WhileStmt GetWhile(Stmt s) { return Whiles.Get(s.Index); }
    DoWhileStmt GetDoWhile(Stmt s) { return DoWhiles.Get(s.Index); }
    ForStmt GetFor(Stmt s) { return Fors.Get(s.Index); }
    ForeachStmt GetForeach(Stmt s) { return Foreachs.Get(s.Index); }
    SwitchStmt GetSwitch(Stmt s) { return Switches.Get(s.Index); }
    ReturnStmt GetReturn(Stmt s) { return Returns.Get(s.Index); }
    UsingBlockStmt GetUsingBlock(Stmt s) { return UsingBlocks.Get(s.Index); }
}
