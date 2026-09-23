// The 'thread' keyword: calling a function marked 'thread' does not call it directly, it spawns a new OS thread
// (pthreads, used the same way on every supported platform) and returns immediately with a handle - 'Thread' for
// a 'void' result, 'Thread<T>' otherwise (System, stdlib/thread.csh).
//
// The mutex/condition-variable protocol, Join/Cancel/CancelAndWait, and the 'is' pattern are ordinary CShift code
// in stdlib/thread.csh. This file only does what cannot be written in CShift:
//  - checking that a 'thread' function's signature is safe (isThreadSafeType, checkThreadSignature) and that it
//    never touches global state, even indirectly (checkThreadPurity, reusing the call-graph data
//    checkGlobalInitOrder() already collects);
//  - the call site of a spawn: allocating the control block shared with the worker thread, packing the
//    arguments, and starting the OS thread (emitThreadSpawn);
//  - the small per-function trampoline pthread_create calls (threadTrampolineFor);
//  - 'Thread.Cancelled', which reads a thread-local variable set by the trampoline (emitThreadCancelled).

#include "CodeGen.h"

#include <llvm/IR/Constants.h>

// ---------------------------------------------------------------------------
// Signature checks
// ---------------------------------------------------------------------------

// True for every type a 'thread' function may take as a parameter: plain values (no reference counting at all)
// and SharedPtr<T>, whose reference count is atomic and therefore safe to copy into another thread. Nothing else
// - strings, arrays, the built-in containers, Error<T> (it always carries a string), raw pointers and
// Action/Func - is allowed, because copying them across threads would race on a non-atomic reference count (or,
// for pointers/closures, silently alias data the other thread does not expect).
bool CodeGen::isThreadSafeType(Type* t)
{
    switch (t->kind)
    {
    case TypeKind::Bool:
    case TypeKind::Int:
    case TypeKind::Char:
    case TypeKind::Float:
    case TypeKind::Enum:
    case TypeKind::SharedPtr:
        return true;
    case TypeKind::Optional:
        return isThreadSafeType(t->elem);
    case TypeKind::Struct:
        if (t->st->layoutInProgress)
            return false;
        if (t->st->base && !isThreadSafeType(t->st->base))
            return false;
        for (const auto& f : t->st->fields)
            if (!isThreadSafeType(f.type))
                return false;
        return true;
    default:
        return false;
    }
}

// Called from ensureSignature() once a 'thread' function's parameter/return types are resolved.
void CodeGen::checkThreadSignature(FuncInfo& fi)
{
    FuncDecl* d = fi.decl;
    if (!d->typeParams.empty())
        err(d->loc, "a 'thread' function cannot be generic");
    if (d->isVariadic)
        err(d->loc, "a 'thread' function cannot be variadic");
    if (d->owner && !d->isStatic)
        err(d->loc, "'thread' can only be used on a free function or a static method, not an instance method (it "
                    "cannot see 'this')");
    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
    {
        if (fi.paramRefs[i] != RefKind::None)
            err(d->params[i].loc,
                "a 'thread' function parameter cannot be 'ref' or 'const ref' ('" + d->params[i].name + "')");
        else if (!isThreadSafeType(fi.paramTypes[i]))
            err(d->params[i].loc, "a 'thread' function parameter must be a plain value type or SharedPtr<T>, not '" +
                                       fi.paramTypes[i]->name + "' (parameter '" + d->params[i].name + "')");
    }
}

// A 'thread' function (and everything it calls, directly or not) may never read or write a global variable: it
// may only see its parameters and return a value. This reuses the call-graph data (codeUses) that
// checkGlobalInitOrder() collects while every function body is generated, just starting the search from a
// different place and reporting a different problem.
void CodeGen::checkThreadPurity()
{
    for (auto& kv : funcInstances)
    {
        FuncInfo* fi = kv.second.get();
        if (!fi->decl->isThread)
            continue;

        std::set<GlobalInfo*> reported;
        auto report = [&](GlobalInfo* g, FuncInfo* via) {
            if (!reported.insert(g).second)
                return;
            diag.error(fi->decl->loc, "'thread' function '" + fi->name + "' uses the global variable '" + g->name + "'" +
                                          (via ? " (through '" + via->name + "')" : "") +
                                          "; a thread can only see its parameters and return value");
        };

        std::set<FuncInfo*> seen;
        std::vector<std::pair<FuncInfo*, FuncInfo*>> work;
        auto own = codeUses.find(fi);
        if (own != codeUses.end())
        {
            for (GlobalInfo* g : own->second.globals)
                report(g, nullptr);
            for (FuncInfo* callee : own->second.calls)
                work.push_back({callee, callee});
        }
        while (!work.empty())
        {
            auto [fn, via] = work.back();
            work.pop_back();
            if (!seen.insert(fn).second)
                continue;
            auto uses = codeUses.find(fn);
            if (uses == codeUses.end())
                continue;
            for (GlobalInfo* g : uses->second.globals)
                report(g, via);
            for (FuncInfo* callee : uses->second.calls)
                work.push_back({callee, via});
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// A struct method looked up by name; only 'coreType'/'controlType' (System._ThreadCore / _ThreadControl<T>) are
// ever passed here, both of which are compiled in from stdlib/thread.csh, so an empty result means the stdlib
// that was linked in does not match this compiler.
FuncInfo* CodeGen::threadMethod(Type* owner, const std::string& name, SourceLoc loc)
{
    std::vector<Candidate> cands = methodCandidates(owner, name);
    if (cands.empty())
        err(loc, "internal error: '" + name + "' is missing on '" + owner->name + "' (stdlib/thread.csh not compiled in)");
    return getFuncInstance(cands[0].decl, cands[0].owner, cands[0].ownerEnv, cands[0].file, {}, loc);
}

// The thread-local variable the trampoline sets before calling the thread function's body: a pointer to the
// (_ThreadCore-compatible) control block of the thread that is currently running. Read by 'Thread.Cancelled'.
llvm::GlobalVariable* CodeGen::currentThreadCoreGlobal()
{
    const char* name = "__cs_thread_current_core";
    if (llvm::GlobalVariable* g = mod->getNamedGlobal(name))
        return g;
    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* g = new llvm::GlobalVariable(*mod, ptrTy, false, llvm::GlobalValue::InternalLinkage,
                                       llvm::ConstantPointerNull::get(ptrTy), name);
    g->setThreadLocal(true);
    return g;
}

// Resolves the stdlib types needed to spawn a thread function with the given result type. Uses fully qualified
// names, so it works no matter what the calling file's own 'using' directives are.
ThreadTypes CodeGen::resolveThreadTypes(FileContext* file, Type* resultType, SourceLoc loc)
{
    ThreadTypes tt;
    tt.hasResult = !resultType->isVoid();

    const TypeDeclEntry* coreEntry = lookupTypeDecl(file, "System._ThreadCore");
    if (!coreEntry)
        err(loc, "internal error: 'System._ThreadCore' is missing (stdlib/thread.csh not compiled in)");
    tt.coreType = getStructType(coreEntry->structDecl, {}, loc);

    if (tt.hasResult)
    {
        const TypeDeclEntry* controlEntry = lookupTypeDecl(file, "System._ThreadControl");
        if (!controlEntry)
            err(loc, "internal error: 'System._ThreadControl' is missing (stdlib/thread.csh not compiled in)");
        tt.payloadType = getStructType(controlEntry->structDecl, {resultType}, loc);
        const TypeDeclEntry* threadEntry = lookupTypeDecl(file, "System.Thread");
        if (!threadEntry)
            err(loc, "internal error: 'System.Thread' is missing (stdlib/thread.csh not compiled in)");
        tt.handleType = getStructType(threadEntry->structDecl, {resultType}, loc);
    }
    else
    {
        tt.payloadType = tt.coreType;
        const TypeDeclEntry* voidEntry = lookupTypeDecl(file, "System._ThreadVoid");
        if (!voidEntry)
            err(loc, "internal error: 'System._ThreadVoid' is missing (stdlib/thread.csh not compiled in)");
        tt.handleType = getStructType(voidEntry->structDecl, {}, loc);
    }
    return tt;
}

// ---------------------------------------------------------------------------
// Spawning: the call site of a 'thread' function
// ---------------------------------------------------------------------------

Value CodeGen::emitThreadSpawn(FuncInfo& fi, std::vector<Arg>& args, SourceLoc loc)
{
    useFunction(fi);
    noteCall(fi); // spawning still counts as reaching the function, e.g. for dead-code and call-graph purposes

    FileContext* file = fs->func->file;
    ThreadTypes tt = resolveThreadTypes(file, fi.ret, loc);
    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i8 = builder.getInt8Ty();

    // 1. Allocate and initialize the control block shared with the worker thread: the same layout SharedPtr<T>
    //    uses ({i64 refcount, i64 unused, payload}), so it can be released through the normal SharedPtr<T>
    //    machinery later. Two references are handed out: one to the caller's handle, one to the worker thread
    //    itself (so the block survives even if the caller never looks at the handle again).
    llvm::Value* blockSize = llvm::ConstantInt::get(sizeTy(), 16 + (uint64_t)sizeOf(tt.payloadType));
    llvm::Value* block = builder.CreateCall(cFunction("calloc", ptrTy, {sizeTy(), sizeTy()}),
                                            {llvm::ConstantInt::get(sizeTy(), 1), blockSize});
    emitPanicIf(builder.CreateIsNull(block), "out of memory");
    bumpCounter(builder, "__cs_allocs"); // matches the free that releaseFor(SharedPtr<...>) counts (CodeGenRuntime.cpp)
    builder.CreateStore(builder.getInt64(2), block);
    llvm::Value* payload = builder.CreateConstGEP1_64(i8, block, 16);
    {
        FuncInfo* initFi = threadMethod(tt.coreType, "Init", loc);
        std::vector<Arg> noArgs;
        emitDirectCall(*initFi, payload, noArgs, loc);
    }

    // 2. Pack the (converted) arguments, plus the control block's payload pointer, into a block that the
    //    trampoline reads on the worker thread and then frees. A thread function's parameters are restricted to
    //    types that never need ARC except SharedPtr<T> (checkThreadSignature), whose own reference count is
    //    atomic, so 'consume' (retain if owned) is all the ownership bookkeeping this needs.
    std::vector<llvm::Type*> fieldTypes{ptrTy};
    std::vector<llvm::Value*> fieldValues{payload};
    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
    {
        SourceLoc aloc = args[i].expr ? args[i].expr->loc : loc;
        Value converted = convertValue(args[i].v, fi.paramTypes[i], aloc);
        fieldValues.push_back(consume(converted));
        fieldTypes.push_back(llvmTypeOf(fi.paramTypes[i]));
    }
    auto* argsStructTy = llvm::StructType::get(ctx, fieldTypes);
    llvm::Value* argsBlock = builder.CreateCall(
        cFunction("malloc", ptrTy, {sizeTy()}),
        {llvm::ConstantInt::get(sizeTy(), (uint64_t)mod->getDataLayout().getTypeAllocSize(argsStructTy))});
    emitPanicIf(builder.CreateIsNull(argsBlock), "out of memory");
    for (size_t i = 0; i < fieldValues.size(); i += 1)
    {
        llvm::Value* slot = builder.CreateInBoundsGEP(argsStructTy, argsBlock, {builder.getInt32(0), builder.getInt32((unsigned)i)});
        builder.CreateStore(fieldValues[i], slot);
    }

    // 3. The trampoline pthread_create calls (one per 'thread' function, reused across every call site).
    llvm::Function* trampoline = threadTrampolineFor(fi, argsStructTy, tt);

    // 4. Start the OS thread. It detaches itself immediately: Join()/CancelAndWait() (stdlib/thread.csh)
    //    synchronize through the condition variable in _ThreadCore, never through pthread_join.
    llvm::Value* idSlot = entryAlloca(ptrTy, "thread.id");
    llvm::Value* rc = builder.CreateCall(cFunction("pthread_create", builder.getInt32Ty(), {ptrTy, ptrTy, ptrTy, ptrTy}),
                                         {idSlot, llvm::ConstantPointerNull::get(ptrTy), trampoline, argsBlock});
    emitPanicIf(builder.CreateICmpNE(rc, builder.getInt32(0)), "cannot create a thread");

    // 5. Wrap the block (the caller's half of the two references) into a Thread / Thread<T> handle.
    Type* sharedPtrType = types.sharedPtrOf(tt.payloadType);
    Value coreValue = Value::rvalue(sharedPtrType, block, true);
    std::vector<Candidate> wrapCands = methodCandidates(tt.handleType, "_Wrap");
    if (wrapCands.empty())
        err(loc, "internal error: '_Wrap' is missing on '" + tt.handleType->name + "'");
    FuncInfo* wrapFi = getFuncInstance(wrapCands[0].decl, wrapCands[0].owner, wrapCands[0].ownerEnv, wrapCands[0].file, {}, loc);
    std::vector<Arg> wrapArgs(1);
    wrapArgs[0].v = coreValue;
    return emitDirectCall(*wrapFi, nullptr, wrapArgs, loc);
}

// ---------------------------------------------------------------------------
// The trampoline: what pthread_create actually calls on the worker thread
// ---------------------------------------------------------------------------

llvm::Function* CodeGen::threadTrampolineFor(FuncInfo& fi, llvm::StructType* argsStructTy, const ThreadTypes& tt)
{
    auto it = threadTrampolines.find(&fi);
    if (it != threadTrampolines.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i8 = builder.getInt8Ty();
    llvm::Function* f = llvm::Function::Create(llvm::FunctionType::get(ptrTy, {ptrTy}, false),
                                               llvm::GlobalValue::InternalLinkage, "__cs_thread_start." + fi.name, mod.get());
    threadTrampolines[&fi] = f;

    // Building the trampoline body uses the same emitDirectCall/consume machinery as ordinary code, so it
    // temporarily takes over the shared IR builder and function state - exactly like
    // beginSyntheticFunction/endSyntheticFunction, which this mirrors (but for a function with a real
    // signature and without dropping it when done).
    std::unique_ptr<FnState> saved = std::move(fs);
    llvm::BasicBlock* savedBlock = builder.GetInsertBlock();

    fs = std::make_unique<FnState>();
    fs->func = &fi;
    fs->fn = f;
    fs->retType = types.voidTy; // unused: the trampoline never executes a CShift 'return'
    builder.SetInsertPoint(llvm::BasicBlock::Create(ctx, "entry", f));

    // A detached thread cleans up its own OS resources when it exits; Join()/CancelAndWait() never call
    // pthread_join.
    builder.CreateCall(cFunction("pthread_detach", builder.getInt32Ty(), {ptrTy}),
                       {builder.CreateCall(cFunction("pthread_self", ptrTy, {}), {})});

    llvm::Value* argsBlock = f->getArg(0);
    llvm::Value* payload = builder.CreateLoad(
        ptrTy, builder.CreateInBoundsGEP(argsStructTy, argsBlock, {builder.getInt32(0), builder.getInt32(0)}));
    builder.CreateStore(payload, currentThreadCoreGlobal());

    std::vector<llvm::Value*> callArgs;
    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
    {
        llvm::Value* slot =
            builder.CreateInBoundsGEP(argsStructTy, argsBlock, {builder.getInt32(0), builder.getInt32((unsigned)(i + 1))});
        callArgs.push_back(builder.CreateLoad(llvmTypeOf(fi.paramTypes[i]), slot));
    }
    builder.CreateCall(cFunction("free", builder.getVoidTy(), {ptrTy}), {argsBlock});

    llvm::Value* result = builder.CreateCall(fi.fn, callArgs);

    // The arguments were packed into the args block already retained (emitThreadSpawn's 'consume'), matching how
    // a normal call's caller holds its own temporary copy of an ARC argument. fi.fn's own prologue retains its
    // own copy of any parameter that needs ARC ('the callee owns its copy'), so the trampoline's copy - the one
    // that came from the args block - must be released now, exactly like a normal call releases its temporaries
    // once the call is done.
    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
        if (needsArc(fi.paramTypes[i]))
            emitReleaseValue(fi.paramTypes[i], callArgs[i]);

    if (tt.hasResult)
    {
        // payload._SetResult(result): an ordinary (generic) assignment to a field, so it retains 'result' itself
        // if T needs ARC. The trampoline's own +1 from calling fi.fn is then released.
        FuncInfo* setFi = threadMethod(tt.payloadType, "SetResult", fi.decl->loc);
        std::vector<Arg> a(1);
        a[0].v = Value::rvalue(fi.ret, result, needsArc(fi.ret));
        emitDirectCall(*setFi, payload, a, fi.decl->loc);
        if (needsArc(fi.ret))
            emitReleaseValue(fi.ret, result);
    }

    {
        // _ThreadCore is always field 0, so 'payload' (a _ThreadCore* or a _ThreadControl<T>*) is a valid 'this'
        // for a _ThreadCore method either way.
        FuncInfo* markFi = threadMethod(tt.coreType, "MarkCompleted", fi.decl->loc);
        std::vector<Arg> noArgs;
        emitDirectCall(*markFi, payload, noArgs, fi.decl->loc);
    }

    // Release the worker's own reference to the control block; the spawning side kept the other one.
    llvm::Value* blockPtr = builder.CreateConstGEP1_64(i8, payload, (uint64_t)-16);
    builder.CreateCall(releaseFor(types.sharedPtrOf(tt.payloadType)), {blockPtr});

    builder.CreateRet(llvm::ConstantPointerNull::get(ptrTy));

    fs.reset();
    fs = std::move(saved);
    if (savedBlock)
        builder.SetInsertPoint(savedBlock);

    return f;
}

// ---------------------------------------------------------------------------
// Thread.Cancelled
// ---------------------------------------------------------------------------

// Only usable directly inside a 'thread' function's own body; reads the thread-local control-block pointer the
// trampoline set before calling it.
Value CodeGen::emitThreadCancelled(SourceLoc loc)
{
    if (!fs->func->decl->isThread)
        err(loc, "'Thread.Cancelled' can only be used inside a 'thread' function");
    FileContext* file = fs->func->file;
    llvm::Value* core = builder.CreateLoad(llvm::PointerType::getUnqual(ctx), currentThreadCoreGlobal());
    const TypeDeclEntry* coreEntry = lookupTypeDecl(file, "System._ThreadCore");
    if (!coreEntry)
        err(loc, "internal error: 'System._ThreadCore' is missing (stdlib/thread.csh not compiled in)");
    Type* coreType = getStructType(coreEntry->structDecl, {}, loc);
    FuncInfo* fi = threadMethod(coreType, "IsCancelled", loc);
    std::vector<Arg> noArgs;
    return emitDirectCall(*fi, core, noArgs, loc);
}
