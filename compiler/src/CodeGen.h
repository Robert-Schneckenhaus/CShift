#pragma once

#include <deque>
#include <map>
#include <set>
#include <unordered_map>
#include <unordered_set>

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>

#include "AST.h"
#include "Types.h"

using TypeEnv = std::unordered_map<std::string, Type*>;

struct FuncInfo;

struct FieldInfo
{
    std::string name;
    Type* type = nullptr;
    unsigned index = 0; // index in the LLVM struct
    bool isPrivate = false;
};

struct StructInfo
{
    StructDecl* decl = nullptr;
    std::string name; // display name including type arguments
    Type* type = nullptr;
    TypeEnv env;
    Type* base = nullptr;
    std::vector<Type*> interfaces;
    std::vector<FieldInfo> fields; // own fields only
    llvm::StructType* llvmType = nullptr;
    bool layoutInProgress = false;
    bool opaque = false; // incomplete C type (only usable through pointers)
};

struct InterfaceInfo
{
    InterfaceDecl* decl = nullptr;
    std::string name;
    Type* type = nullptr;
    TypeEnv env;
};

struct EnumInfo
{
    EnumDecl* decl = nullptr;
    std::string name;
    Type* type = nullptr;
    Type* base = nullptr;
    std::vector<std::pair<std::string, int64_t>> members;
};

struct FuncInfo
{
    FuncDecl* decl = nullptr;
    FileContext* file = nullptr;
    Type* owner = nullptr; // struct type for methods
    TypeEnv env;           // type parameters (of the owner and of the function)
    std::string name;      // display name
    std::vector<Type*> paramTypes;
    std::vector<RefKind> paramRefs;
    std::vector<bool> paramNullable; // FFI: ref/string parameter that accepts null
    std::vector<bool> paramCString;  // FFI: string passed as const char*
    Type* ret = nullptr;
    bool signatureResolved = false;
    bool hasThis = false;
    llvm::Function* fn = nullptr;
    bool queued = false;
};

// A global variable of the program; its type and LLVM variable are created when it is first needed.
struct GlobalInfo
{
    GlobalDecl* decl = nullptr;
    std::string name; // qualified
    int order = 0;    // position in the order of the declarations (the order of the initializers)
    Type* type = nullptr;
    llvm::GlobalVariable* var = nullptr;
};

struct TypeDeclEntry
{
    enum Kind { Struct, Interface, Enum } kind = Struct;
    StructDecl* structDecl = nullptr;
    InterfaceDecl* interfaceDecl = nullptr;
    EnumDecl* enumDecl = nullptr;
};

struct Candidate
{
    FuncDecl* decl = nullptr;
    Type* owner = nullptr;
    const TypeEnv* ownerEnv = nullptr;
    FileContext* file = nullptr;
};

// Result of evaluating an expression. May be an lvalue (v is an address) or an rvalue.
struct Value
{
    Type* type = nullptr;
    llvm::Value* v = nullptr;
    bool isLValue = false;
    bool isConst = false;  // lvalue that must not be written
    bool owned = false;    // an rvalue that holds a +1 reference count (ARC types only)
    bool isRefArg = false; // was written as 'ref x'
    bool hasLit = false;   // adaptable numeric literal
    bool litIsFloat = false;
    int64_t litInt = 0;
    double litFloat = 0;
    // A function name used as a value (type methodGroupTy): the candidates it may refer to.
    std::vector<Candidate> group;
    std::vector<Type*> groupTypeArgs;
    std::string groupName;

    static Value rvalue(Type* t, llvm::Value* v, bool owned = false)
    {
        Value r;
        r.type = t;
        r.v = v;
        r.owned = owned;
        return r;
    }
    static Value lvalue(Type* t, llvm::Value* addr, bool isConst = false)
    {
        Value r;
        r.type = t;
        r.v = addr;
        r.isLValue = true;
        r.isConst = isConst;
        return r;
    }
};

struct Arg
{
    Value v;
    Expr* expr = nullptr;
};

struct StaticTarget
{
    enum Kind { None, TypeName, Namespace, Builtin } kind = None;
    Type* type = nullptr;
    std::string name;
};

// The value of a constant expression, computed at compile time (ConstEval.cpp).
struct ConstVal
{
    enum Kind { Int, Float, Bool, String } kind = Int;
    Type* type = nullptr;
    bool neg = false;      // Int (also char and enum): sign and magnitude
    uint64_t mag = 0;
    double f = 0;          // Float (a float32 holds a value that is exactly representable as float)
    bool b = false;        // Bool
    std::string s;         // String
    bool hasLit = false;   // an unsuffixed literal: adapts to the type of the value it is combined with
};

// What a constant expression may refer to.
struct ConstScope
{
    FileContext* file = nullptr;        // names are looked up from this file
    bool locals = false;                // the local constants of the function that is being written are visible
    EnumInfo* enumInfo = nullptr;       // the enum whose members are being declared (earlier members are visible)
    std::string what;                   // for error messages: "constant 'X'" or "enum member 'X'"
    SourceLoc declLoc;
    const TypeEnv* env = nullptr;       // type parameters (for casts and sizeof in generic functions)
};

struct ScopeVar
{
    std::string name;
    Type* type = nullptr;
    llvm::Value* slot = nullptr;
    bool isRef = false;     // slot holds a pointer to the real storage (ref parameters)
    bool isConst = false;
    bool ownsArc = false;   // release on scope exit
    bool disposable = false; // call Dispose() on scope exit
    bool resetOnCleanup = false; // zero the slot after releasing (pattern variables)
    bool isConstant = false;    // a local constant: no variable, its value is constValue
    ConstVal constValue;
};

struct Scope
{
    std::vector<ScopeVar> vars;
};

struct LoopCtx
{
    llvm::BasicBlock* breakBB = nullptr;
    llvm::BasicBlock* continueBB = nullptr; // null for switch
    size_t scopeDepth = 0;
};

struct TempRelease
{
    Type* type = nullptr;
    llvm::Value* value = nullptr;
};

struct FnState
{
    FuncInfo* func = nullptr;
    llvm::Function* fn = nullptr;
    Type* retType = nullptr;
    std::vector<Scope> scopes;
    std::vector<LoopCtx> loops;
    std::vector<TempRelease> temps;
    int unsafeDepth = 0;
    bool checked = true;
    llvm::Value* thisSlot = nullptr;
    Type* thisType = nullptr;
    std::set<llvm::BasicBlock*> deadBlocks;
    bool isIntMain = false;
};

// The stdlib types involved in spawning one 'thread' function (CodeGenThread.cpp).
struct ThreadTypes
{
    Type* coreType = nullptr;    // System._ThreadCore
    Type* payloadType = nullptr; // what is stored at offset 16 of the control block: _ThreadCore (void) or
                                  // _ThreadControl<T> (T result), whose first field is a _ThreadCore
    Type* handleType = nullptr;  // System._ThreadVoid ('Thread' in source) or System.Thread<T>
    bool hasResult = false;
};

class CodeGen
{
public:
    CodeGen(Diagnostics& diag, const std::string& moduleName);

    llvm::Module& module() { return *mod; }
    llvm::LLVMContext& context() { return ctx; }
    void setDataLayout(const llvm::DataLayout& dl);
    void setTargetTriple(const std::string& triple);
    void setArcStats(bool enabled) { arcStats = enabled; }

    void addUnit(std::unique_ptr<CompilationUnit> unit);
    // Analyzes and generates code for everything. Returns false if errors occurred.
    bool compile();

    const std::vector<std::string>& linkLibraries() const { return links; }

private:
    // ---- Declarations and symbols (CodeGen.cpp) ----
    void registerUnit(CompilationUnit& unit);
    std::string qualified(FileContext* f, const std::string& name) const;
    std::vector<std::string> candidateNames(FileContext* f, const std::string& name) const;
    const TypeDeclEntry* lookupTypeDecl(FileContext* f, const std::string& name) const;
    std::vector<FuncDecl*> lookupFunctions(FileContext* f, const std::string& name) const;
    bool isNamespace(FileContext* f, const std::string& name) const;
    Type* primitiveType(const std::string& name);
    Type* resolveFunctionType(const TypeRef& ref, const std::string& dotted, FileContext* file, const TypeEnv* env);

    Type* resolveType(const TypeRef& ref, FileContext* file, const TypeEnv* env);
    Type* resolveValueType(const TypeRef& ref, FileContext* file, const TypeEnv* env);
    Type* getStructType(StructDecl* decl, const std::vector<Type*>& args, SourceLoc loc);
    Type* getInterfaceType(InterfaceDecl* decl, const std::vector<Type*>& args, SourceLoc loc);
    Type* getEnumType(EnumDecl* decl);
    void layoutStruct(StructInfo& info);
    void instantiateStructMethods();
    void verifyStruct(StructInfo& info);
    void checkConstraints(const std::vector<Constraint>& constraints, const TypeEnv& env, FileContext* file,
                          SourceLoc loc);
    bool satisfiesInterface(Type* t, Type* iface);
    bool structImplements(Type* structType, Type* iface);
    // The compile-time evaluator (ConstEval.cpp)
    ConstVal constEval(Expr* e, const ConstScope& sc);
    ConstVal constEvalDecl(ConstDecl* c);
    int64_t constEvalEnumMember(Expr* init, EnumInfo& ei, FileContext* file, const std::string& memberName, SourceLoc loc);
    ConstVal constConvert(const ConstVal& v, Type* to, SourceLoc loc, bool allowEnumInt = false);
    ConstVal constNumericConvert(const ConstVal& v, Type* to);
    ConstVal constAdaptLiteral(const ConstVal& v, Type* to);
    ConstVal constIntOp(BinOp op, const ConstVal& l, const ConstVal& r, Type* t, SourceLoc loc);
    ConstVal constArith(BinOp op, ConstVal l, ConstVal r, SourceLoc loc);
    ConstVal constCompare(BinOp op, ConstVal l, ConstVal r, SourceLoc loc);
    std::string constToText(const ConstVal& v);
    Value constToValue(const ConstVal& v);

    llvm::Type* llvmTypeOf(Type* t);
    bool needsArc(Type* t);
    unsigned sizeOf(Type* t);
    bool structIsAncestor(Type* base, Type* derived, std::vector<unsigned>* path = nullptr);

    struct FieldPath
    {
        std::vector<unsigned> indices;
        Type* type = nullptr;
        bool isPrivate = false;
        Type* owner = nullptr;
    };
    bool findField(Type* structType, const std::string& name, FieldPath& out);

    FuncInfo* getFuncInstance(FuncDecl* decl, Type* owner, const TypeEnv* ownerEnv, FileContext* file,
                              const std::vector<Type*>& typeArgs, SourceLoc loc);
    void ensureSignature(FuncInfo& fi);
    llvm::Function* declareFunction(FuncInfo& fi);
    // Function pointers (Action/Func): a function name as a value, and indirect calls.
    Value groupValue(const std::vector<Candidate>& cands, const std::vector<Type*>& typeArgs, const std::string& name);
    FuncInfo* resolveGroup(const Value& group, Type* to, std::string* why);
    Type* groupFunctionType(const Value& group);
    Value emitIndirectCall(Value callee, std::vector<Arg>& args, SourceLoc loc);
    void addAbiAttributes(llvm::Function* fn, llvm::CallInst* call, const std::vector<Type*>& params, const std::vector<bool>& isRef, Type* ret);
    void useFunction(FuncInfo& fi);
    std::vector<Candidate> methodCandidates(Type* structType, const std::string& name);
    void emitEntryPoint();

    [[noreturn]] void err(SourceLoc loc, const std::string& message) const { fail(loc, message); }

    // ---- Runtime helpers (CodeGenRuntime.cpp) ----
    llvm::FunctionCallee cFunction(const char* name, llvm::Type* ret, std::vector<llvm::Type*> params,
                                   bool variadic = false);
    llvm::IntegerType* sizeTy();
    llvm::GlobalVariable* arcCounter(const char* name);
    void bumpCounter(llvm::IRBuilder<>& b, const char* name);
    llvm::Constant* cString(const std::string& s); // NUL-terminated C string constant
    llvm::Value* stderrHandle(llvm::IRBuilder<>& b);
    llvm::Function* panicFn();
    void emitPanic(const std::string& message);
    void emitPanicIf(llvm::Value* cond, const std::string& message);
    llvm::Function* allocFn();
    llvm::Function* retainFn();
    llvm::Function* releaseFlatFn();
    llvm::Function* retainSharedFn(); // SharedPtr<T>: atomic increment (shared by every instantiation)
    llvm::Function* lenFn();
    llvm::Function* dataFn();
    llvm::Function* concatFn();
    llvm::Function* streqFn();
    llvm::Function* substringFn();
    llvm::Function* printFn(bool toStderr = false);
    llvm::Function* fmtFn(const std::string& key, const char* format, llvm::Type* argType);
    llvm::Function* retainFor(Type* t);
    llvm::Function* releaseFor(Type* t);
    llvm::Function* fromCStrFn();
    llvm::Function* cloneFn(Type* arrayType);
    llvm::Function* copyFn(Type* arrayType);
    llvm::Constant* stringLiteral(const std::string& value);
    llvm::Value* newString(llvm::Value* len);
    llvm::Value* emitToString(const Value& v, SourceLoc loc);
    llvm::Value* dataPtr(llvm::Value* arrayOrString);
    llvm::Value* arrayLength(llvm::Value* arrayOrString);
    void emitRetainValue(Type* t, llvm::Value* v);
    void emitReleaseValue(Type* t, llvm::Value* v);
    llvm::Function* makeHelper(const std::string& name, llvm::Type* ret, std::vector<llvm::Type*> params);

    // ---- Values and ownership (CodeGenExpr.cpp) ----
    Value toRValue(const Value& v);
    llvm::Value* consume(const Value& v);
    void holdTemp(const Value& v);
    void flushTemps(size_t mark, bool pop = true);
    void storeSlot(Type* t, llvm::Value* addr, llvm::Value* newOwned, bool releaseOld);
    llvm::Value* zeroValue(Type* t);
    llvm::AllocaInst* entryAlloca(llvm::Type* t, const std::string& name);
    llvm::Value* materialize(Type* t, llvm::Value* value);
    Value boolValue(llvm::Value* v);
    Value constInt(Type* t, int64_t value);
    llvm::Value* makeSome(Type* resultType, llvm::Value* payloadOwned);
    llvm::Value* makeNone(Type* optionalType);
    llvm::Value* makeErr(Type* errorType, llvm::Value* msgOwned, llvm::Value* code);

    Value emitExpr(Expr* e);
    Value emitRValue(Expr* e) { return toRValue(emitExpr(e)); }
    Value emitCondition(Expr* e);
    Value emitName(NameExpr* e);
    Value emitMember(MemberExpr* e);
    Value emitIndex(IndexExpr* e);
    Value emitUnary(UnaryExpr* e);
    Value emitBinary(BinaryExpr* e);
    Value emitLogical(BinaryExpr* e);
    Value emitAssign(AssignExpr* e);
    Value emitConditional(CondExpr* e);
    Value emitCast(CastExpr* e);
    Value emitNewArray(NewArrayExpr* e);
    Value emitStructInit(StructInitExpr* e);
    Value emitIs(IsExpr* e);
    Value emitTry(TryExpr* e);
    Value emitErrorLit(ErrorLitExpr* e);
    Value emitLiteral(Expr* e);
    ConstDecl* lookupConst(FileContext* f, const std::string& name) const;
    GlobalInfo* lookupGlobal(FileContext* f, const std::string& name) const;
    Value globalValue(GlobalInfo& g, bool note = true);
    void noteGlobalUse(GlobalInfo& g);
    void noteCall(FuncInfo& fi);
    void checkGlobalInitOrder();
    void checkConstants();

    // ---- 'thread' functions and Thread / Thread<T> / SharedPtr<T> (CodeGenThread.cpp) ----
    bool isThreadSafeType(Type* t);
    void checkThreadSignature(FuncInfo& fi);
    void checkThreadPurity();
    FuncInfo* threadMethod(Type* owner, const std::string& name, SourceLoc loc);
    ThreadTypes resolveThreadTypes(FileContext* file, Type* resultType, SourceLoc loc);
    Value emitThreadSpawn(FuncInfo& fi, std::vector<Arg>& args, SourceLoc loc);
    llvm::Function* threadTrampolineFor(FuncInfo& fi, llvm::StructType* argsStructTy, const ThreadTypes& tt);
    llvm::GlobalVariable* currentThreadCoreGlobal();
    Value emitThreadCancelled(SourceLoc loc);
    llvm::Function* beginSyntheticFunction(const std::string& name);
    void endSyntheticFunction(llvm::Function* f, bool keep);
    bool isConstantType(Type* t) const;
    ScopeVar* findLocal(const std::string& name);
    void emitGlobalsInit();
    llvm::Function* emitGlobalsRelease();
    Value emitConst(ConstDecl* c, SourceLoc loc);

    Value convertValue(const Value& v, Type* to, SourceLoc loc);
    int conversionCost(const Value& v, Type* to);
    llvm::Value* numericConvert(llvm::Value* v, Type* from, Type* to);
    Value emitArithmetic(BinOp op, Value l, Value r, SourceLoc loc);
    Value emitCompare(BinOp op, Value l, Value r, SourceLoc loc);
    llvm::Value* emitIntOp(BinOp op, llvm::Value* l, llvm::Value* r, Type* t);
    Type* promoteTypes(Type* a, Type* b, SourceLoc loc);
    Value adaptLiteral(const Value& v, Type* to);
    Value derefPointer(const Value& p, SourceLoc loc);
    void requireUnsafe(SourceLoc loc, const char* what);
    StaticTarget resolveStaticTarget(Expr* e);
    bool isLocalName(const std::string& name);
    Value lookupVariable(const std::string& name);
    Value thisValue(SourceLoc loc);
    Value fieldAccess(Value obj, const std::string& name, SourceLoc loc);

    // ---- Calls (CodeGenCall.cpp) ----
    Value emitCall(CallExpr* e, bool viaStart = false);
    Value emitStart(StartExpr* e);
    Value emitEmbed(CallExpr* e, const std::string& name);
    Value emitBuiltinStatic(const std::string& type, const std::string& method, std::vector<Arg>& args, SourceLoc loc);
    Value emitBuiltinMethod(Value obj, const std::string& method, std::vector<Arg>& args, SourceLoc loc);
    Value emitExtensionCall(const std::string& ns, const Value* self, const std::string& method,
                            std::vector<Arg>& args, SourceLoc loc, bool& found);
    Value emitBuiltinStaticMember(Type* type, const std::string& member, SourceLoc loc, bool& found);
    FuncInfo* resolveOverload(const std::vector<Candidate>& candidates, std::vector<Arg>& args,
                              const std::vector<Type*>& explicitTypeArgs, SourceLoc loc, const std::string& name);
    bool inferTypeArgs(const Candidate& c, std::vector<Arg>& args, std::vector<Type*>& out);
    bool unify(const TypeRef& pattern, Type* actual, const std::vector<std::string>& params, FileContext* file,
               const TypeEnv* env, std::vector<Type*>& bound);
    int argCost(const Arg& arg, Type* paramType, RefKind rk, bool nullable, bool cstring = false);
    Value emitDirectCall(FuncInfo& fi, llvm::Value* thisPtr, std::vector<Arg>& args, SourceLoc loc);
    std::vector<Arg> emitArgs(std::vector<ExprPtr>& args);
    std::vector<Type*> resolveTypeArgs(const std::vector<TypeRefPtr>& refs);
    void callDispose(const ScopeVar& var);

    // ---- Statements and functions (CodeGenStmt.cpp) ----
    void emitFunctionBody(FuncInfo& fi);
    void emitStmt(Stmt* s);
    void emitBlock(BlockStmt* b, bool newScope = true);
    void emitVarDecl(VarDeclStmt* s);
    void emitIf(IfStmt* s);
    void emitWhile(WhileStmt* s);
    void emitDoWhile(DoWhileStmt* s);
    void emitFor(ForStmt* s);
    void emitForeach(ForeachStmt* s);
    void emitForeachStruct(ForeachStmt* s, const Value& it);
    void emitSwitch(SwitchStmt* s);
    void emitReturn(ReturnStmt* s);
    void emitUsingBlock(UsingBlockStmt* s);
    void emitBreakContinue(bool isBreak, SourceLoc loc);
    void emitExprStmt(ExprStmt* s);

    void pushScope();
    void popScope(bool emitCleanup);
    void emitScopeCleanup(const Scope& scope);
    void emitCleanupsDownTo(size_t depth);
    ScopeVar& declareVar(const std::string& name, Type* type, llvm::Value* slot);
    bool isVoidResult(Type* t) const;
    bool blockOpen() const;
    bool reachable() const;
    void ensureInsertPoint();
    void branchTo(llvm::BasicBlock* bb);
    llvm::BasicBlock* newBlock(const char* name);
    void setBlock(llvm::BasicBlock* bb);
    Type* declTypeOf(const TypeRef& ref);

    // ---- State ----
    Diagnostics& diag;
    llvm::LLVMContext ctx;
    std::unique_ptr<llvm::Module> mod;
    llvm::IRBuilder<> builder;
    TypeContext types;

    std::vector<std::unique_ptr<CompilationUnit>> units;
    std::vector<std::string> links;
    FileContext preludeContext;

    std::unordered_map<std::string, TypeDeclEntry> typeDecls;
    std::unordered_map<std::string, std::vector<FuncDecl*>> funcDecls;
    std::unordered_map<std::string, ConstDecl*> constDecls;
    std::unordered_map<std::string, std::unique_ptr<GlobalInfo>> globalDecls;
    // Which globals and functions the code of every function (and every global initializer) uses; checked after all bodies
    // are written to see whether an initializer needs a global that is initialized later.
    struct CodeUses
    {
        std::set<GlobalInfo*> globals;
        std::set<FuncInfo*> calls;
    };
    std::unordered_map<const void*, CodeUses> codeUses; // key: FuncInfo* or the GlobalInfo* whose initializer it is
    GlobalInfo* currentInit = nullptr;
    int globalCounter = 0;
    std::vector<GlobalInfo*> createdGlobals; // in the order in which the LLVM variables were created
    llvm::Function* globalsInitFn = nullptr;
    std::unique_ptr<FuncDecl> initDecl; // the function that initializes the globals looks like a function to the code generator
    std::unique_ptr<FuncInfo> initInfo;
    std::unordered_set<std::string> namespaces;

    std::unordered_map<std::string, Type*> structTypes;
    std::unordered_map<std::string, Type*> interfaceTypes;
    std::unordered_map<std::string, Type*> enumTypes;
    std::vector<std::unique_ptr<StructInfo>> structInfos;
    std::vector<std::unique_ptr<InterfaceInfo>> interfaceInfos;
    std::vector<std::unique_ptr<EnumInfo>> enumInfos;
    std::vector<StructInfo*> pendingVerify;
    // Structs whose methods are instantiated once no struct layout is running (see getStructType).
    std::vector<StructInfo*> pendingMethods;
    int layoutDepth = 0;
    bool instantiatingMethods = false;

    std::unordered_map<std::string, std::unique_ptr<FuncInfo>> funcInstances;
    std::deque<FuncInfo*> workQueue;

    std::unordered_map<std::string, llvm::Function*> helpers;
    std::unordered_map<std::string, llvm::Constant*> stringLiterals;
    std::unordered_map<std::string, llvm::Constant*> cStrings;
    std::unordered_map<FuncInfo*, llvm::Function*> threadTrampolines; // one per 'thread' function instance
    FuncInfo* mainFunc = nullptr;
    FuncInfo* mainArgsHelper = nullptr; // System.Native.MakeArgs, when Main takes string[] args
    bool arcStats = false;
    struct ConstState
    {
        int state = 0; // 0 = not evaluated, 1 = being evaluated, 2 = done
        ConstVal value;
    };
    std::unordered_map<ConstDecl*, ConstState> constCache;

    std::unique_ptr<FnState> fs;
};
