// Runtime support emitted directly into every module as LLVM IR:
// ARC (retain/release), heap block allocation, strings, panics.
//
// Heap block layout for strings and arrays:
//   offset 0:  int64 reference count
//   offset 8:  int64 length (bytes for strings, elements for arrays)
//   offset 16: payload (strings are additionally NUL-terminated)

#include "CodeGen.h"

#include <llvm/Config/llvm-config.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/GlobalVariable.h>

namespace
{
constexpr int64_t kImmortalRefCount = int64_t(1) << 60; // string literals
}

llvm::FunctionCallee CodeGen::cFunction(const char* name, llvm::Type* ret, std::vector<llvm::Type*> params,
                                        bool variadic)
{
    return mod->getOrInsertFunction(name, llvm::FunctionType::get(ret, params, variadic));
}

llvm::IntegerType* CodeGen::sizeTy()
{
    return mod->getDataLayout().getIntPtrType(ctx);
}

llvm::GlobalVariable* CodeGen::arcCounter(const char* name)
{
    if (llvm::GlobalVariable* g = mod->getNamedGlobal(name))
        return g;
    auto* i64 = llvm::Type::getInt64Ty(ctx);
    return new llvm::GlobalVariable(*mod, i64, false, llvm::GlobalValue::InternalLinkage, llvm::ConstantInt::get(i64, 0), name);
}

// Increments a debug counter (only when --arc-stats is enabled).
void CodeGen::bumpCounter(llvm::IRBuilder<>& b, const char* name)
{
    if (!arcStats)
        return;
    llvm::GlobalVariable* g = arcCounter(name);
    llvm::Value* v = b.CreateLoad(b.getInt64Ty(), g);
    b.CreateStore(b.CreateAdd(v, b.getInt64(1)), g);
}

llvm::Function* CodeGen::makeHelper(const std::string& name, llvm::Type* ret, std::vector<llvm::Type*> params)
{
    auto* f = llvm::Function::Create(llvm::FunctionType::get(ret, params, false), llvm::GlobalValue::InternalLinkage,
                                     name, mod.get());
    helpers[name] = f;
    return f;
}

llvm::Constant* CodeGen::cString(const std::string& s)
{
    auto it = cStrings.find(s);
    if (it != cStrings.end())
        return it->second;
    auto* init = llvm::ConstantDataArray::getString(ctx, s, true);
    auto* gv = new llvm::GlobalVariable(*mod, init->getType(), true, llvm::GlobalValue::PrivateLinkage, init, ".cstr");
    cStrings[s] = gv;
    return gv;
}

llvm::Value* CodeGen::stderrHandle(llvm::IRBuilder<>& b)
{
#if LLVM_VERSION_MAJOR >= 21
    const llvm::Triple& triple = mod->getTargetTriple();
#else
    llvm::Triple triple(mod->getTargetTriple());
#endif
    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    if (triple.isOSWindows())
    {
        llvm::FunctionCallee f = cFunction("__acrt_iob_func", ptrTy, {b.getInt32Ty()});
        return b.CreateCall(f, {b.getInt32(2)});
    }
    const char* name = triple.isOSDarwin() ? "__stderrp" : "stderr";
    llvm::Constant* g = mod->getOrInsertGlobal(name, ptrTy);
    return b.CreateLoad(ptrTy, g);
}

// ---------------------------------------------------------------------------
// Panics
// ---------------------------------------------------------------------------

llvm::Function* CodeGen::panicFn()
{
    auto it = helpers.find("__cs_panic");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_panic", llvm::Type::getVoidTy(ctx), {ptrTy});
    f->addFnAttr(llvm::Attribute::NoReturn);
    f->addFnAttr(llvm::Attribute::NoInline);
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    llvm::FunctionCallee fprintfFn = cFunction("fprintf", b.getInt32Ty(), {ptrTy, ptrTy}, true);
    b.CreateCall(fprintfFn, {stderrHandle(b), cString("panic: %s\n"), f->getArg(0)});
    llvm::FunctionCallee exitFn = cFunction("exit", b.getVoidTy(), {b.getInt32Ty()});
    b.CreateCall(exitFn, {b.getInt32(101)});
    b.CreateUnreachable();
    return f;
}

void CodeGen::emitPanic(const std::string& message)
{
    builder.CreateCall(panicFn(), {cString(message)});
    builder.CreateUnreachable();
}

void CodeGen::emitPanicIf(llvm::Value* cond, const std::string& message)
{
    llvm::BasicBlock* failBB = newBlock("panic");
    llvm::BasicBlock* okBB = newBlock("cont");
    builder.CreateCondBr(cond, failBB, okBB);
    setBlock(failBB);
    emitPanic(message);
    setBlock(okBB);
}

// ---------------------------------------------------------------------------
// Heap blocks and reference counting
// ---------------------------------------------------------------------------

llvm::Function* CodeGen::allocFn()
{
    auto it = helpers.find("__cs_alloc");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i64 = llvm::Type::getInt64Ty(ctx);
    llvm::Function* f = makeHelper("__cs_alloc", ptrTy, {i64, i64});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* failBB = llvm::BasicBlock::Create(ctx, "oom", f);
    auto* okBB = llvm::BasicBlock::Create(ctx, "ok", f);

    llvm::Value* total = b.CreateAdd(f->getArg(0), b.getInt64(16));
    llvm::FunctionCallee callocFn = cFunction("calloc", ptrTy, {sizeTy(), sizeTy()});
    llvm::Value* p = b.CreateCall(callocFn, {llvm::ConstantInt::get(sizeTy(), 1), b.CreateZExtOrTrunc(total, sizeTy())});
    b.CreateCondBr(b.CreateIsNull(p), failBB, okBB);

    b.SetInsertPoint(failBB);
    b.CreateCall(panicFn(), {cString("out of memory")});
    b.CreateUnreachable();

    b.SetInsertPoint(okBB);
    bumpCounter(b, "__cs_allocs");
    b.CreateStore(b.getInt64(1), p);
    b.CreateStore(f->getArg(1), b.CreateConstGEP1_64(b.getInt8Ty(), p, 8));
    b.CreateRet(p);
    return f;
}

llvm::Function* CodeGen::retainFn()
{
    auto it = helpers.find("__cs_retain");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_retain", llvm::Type::getVoidTy(ctx), {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* doBB = llvm::BasicBlock::Create(ctx, "inc", f);
    auto* doneBB = llvm::BasicBlock::Create(ctx, "done", f);
    b.CreateCondBr(b.CreateIsNull(f->getArg(0)), doneBB, doBB);
    b.SetInsertPoint(doBB);
    llvm::Value* rc = b.CreateLoad(b.getInt64Ty(), f->getArg(0));
    b.CreateStore(b.CreateAdd(rc, b.getInt64(1)), f->getArg(0));
    b.CreateBr(doneBB);
    b.SetInsertPoint(doneBB);
    b.CreateRetVoid();
    return f;
}

llvm::Function* CodeGen::releaseFlatFn()
{
    auto it = helpers.find("__cs_release_flat");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_release_flat", llvm::Type::getVoidTy(ctx), {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* decBB = llvm::BasicBlock::Create(ctx, "dec", f);
    auto* freeBB = llvm::BasicBlock::Create(ctx, "free", f);
    auto* doneBB = llvm::BasicBlock::Create(ctx, "done", f);
    b.CreateCondBr(b.CreateIsNull(f->getArg(0)), doneBB, decBB);
    b.SetInsertPoint(decBB);
    llvm::Value* rc = b.CreateSub(b.CreateLoad(b.getInt64Ty(), f->getArg(0)), b.getInt64(1));
    b.CreateStore(rc, f->getArg(0));
    b.CreateCondBr(b.CreateICmpEQ(rc, b.getInt64(0)), freeBB, doneBB);
    b.SetInsertPoint(freeBB);
    llvm::FunctionCallee freeFn = cFunction("free", b.getVoidTy(), {ptrTy});
    b.CreateCall(freeFn, {f->getArg(0)});
    bumpCounter(b, "__cs_frees");
    b.CreateBr(doneBB);
    b.SetInsertPoint(doneBB);
    b.CreateRetVoid();
    return f;
}

llvm::Function* CodeGen::lenFn()
{
    auto it = helpers.find("__cs_len");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i64 = llvm::Type::getInt64Ty(ctx);
    llvm::Function* f = makeHelper("__cs_len", i64, {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* loadBB = llvm::BasicBlock::Create(ctx, "load", f);
    auto* nullBB = llvm::BasicBlock::Create(ctx, "null", f);
    b.CreateCondBr(b.CreateIsNull(f->getArg(0)), nullBB, loadBB);
    b.SetInsertPoint(nullBB);
    b.CreateRet(b.getInt64(0));
    b.SetInsertPoint(loadBB);
    b.CreateRet(b.CreateLoad(i64, b.CreateConstGEP1_64(b.getInt8Ty(), f->getArg(0), 8)));
    return f;
}

// Pointer to the character data of a string; a pointer to "" for null strings.
llvm::Function* CodeGen::dataFn()
{
    auto it = helpers.find("__cs_data");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_data", ptrTy, {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    llvm::Value* data = b.CreateConstGEP1_64(b.getInt8Ty(), f->getArg(0), 16);
    b.CreateRet(b.CreateSelect(b.CreateIsNull(f->getArg(0)), cString(""), data));
    return f;
}

llvm::Value* CodeGen::dataPtr(llvm::Value* block)
{
    return builder.CreateConstGEP1_64(builder.getInt8Ty(), block, 16);
}

llvm::Value* CodeGen::arrayLength(llvm::Value* block)
{
    return builder.CreateCall(lenFn(), {block});
}

llvm::Constant* CodeGen::stringLiteral(const std::string& value)
{
    auto it = stringLiterals.find(value);
    if (it != stringLiterals.end())
        return it->second;

    auto* i64 = llvm::Type::getInt64Ty(ctx);
    auto* chars = llvm::ConstantDataArray::getString(ctx, value, true);
    auto* sty = llvm::StructType::get(ctx, {i64, i64, chars->getType()});
    auto* init = llvm::ConstantStruct::get(
        sty, {llvm::ConstantInt::get(i64, kImmortalRefCount), llvm::ConstantInt::get(i64, value.size()), chars});
    auto* gv = new llvm::GlobalVariable(*mod, sty, false, llvm::GlobalValue::PrivateLinkage, init, ".str");
    stringLiterals[value] = gv;
    return gv;
}

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

llvm::Function* CodeGen::concatFn()
{
    auto it = helpers.find("__cs_concat");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_concat", ptrTy, {ptrTy, ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    llvm::Value* a = f->getArg(0);
    llvm::Value* c = f->getArg(1);
    llvm::Value* la = b.CreateCall(lenFn(), {a});
    llvm::Value* lb = b.CreateCall(lenFn(), {c});
    llvm::Value* total = b.CreateAdd(la, lb);
    llvm::Value* r = b.CreateCall(allocFn(), {b.CreateAdd(total, b.getInt64(1)), total});
    llvm::Value* dst = b.CreateConstGEP1_64(b.getInt8Ty(), r, 16);
    b.CreateMemCpy(dst, llvm::MaybeAlign(1), b.CreateCall(dataFn(), {a}), llvm::MaybeAlign(1), la);
    b.CreateMemCpy(b.CreateGEP(b.getInt8Ty(), dst, {la}), llvm::MaybeAlign(1), b.CreateCall(dataFn(), {c}),
                   llvm::MaybeAlign(1), lb);
    b.CreateRet(r);
    return f;
}

llvm::Function* CodeGen::streqFn()
{
    auto it = helpers.find("__cs_streq");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_streq", llvm::Type::getInt1Ty(ctx), {ptrTy, ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* cmpBB = llvm::BasicBlock::Create(ctx, "cmp", f);
    auto* neBB = llvm::BasicBlock::Create(ctx, "ne", f);
    llvm::Value* la = b.CreateCall(lenFn(), {f->getArg(0)});
    llvm::Value* lb = b.CreateCall(lenFn(), {f->getArg(1)});
    b.CreateCondBr(b.CreateICmpEQ(la, lb), cmpBB, neBB);
    b.SetInsertPoint(neBB);
    b.CreateRet(b.getFalse());
    b.SetInsertPoint(cmpBB);
    llvm::FunctionCallee memcmpFn = cFunction("memcmp", b.getInt32Ty(), {ptrTy, ptrTy, sizeTy()});
    llvm::Value* r = b.CreateCall(memcmpFn, {b.CreateCall(dataFn(), {f->getArg(0)}),
                                             b.CreateCall(dataFn(), {f->getArg(1)}), b.CreateZExtOrTrunc(la, sizeTy())});
    b.CreateRet(b.CreateICmpEQ(r, b.getInt32(0)));
    return f;
}

llvm::Function* CodeGen::substringFn()
{
    auto it = helpers.find("__cs_substring");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i32 = llvm::Type::getInt32Ty(ctx);
    llvm::Function* f = makeHelper("__cs_substring", ptrTy, {ptrTy, i32, i32});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* failBB = llvm::BasicBlock::Create(ctx, "range", f);
    auto* okBB = llvm::BasicBlock::Create(ctx, "ok", f);

    llvm::Value* len = b.CreateCall(lenFn(), {f->getArg(0)});
    llvm::Value* start = b.CreateSExt(f->getArg(1), b.getInt64Ty());
    llvm::Value* count = b.CreateSExt(f->getArg(2), b.getInt64Ty());
    llvm::Value* bad = b.CreateOr(b.CreateICmpSLT(start, b.getInt64(0)), b.CreateICmpSLT(count, b.getInt64(0)));
    bad = b.CreateOr(bad, b.CreateICmpSGT(b.CreateAdd(start, count), len));
    b.CreateCondBr(bad, failBB, okBB);

    b.SetInsertPoint(failBB);
    b.CreateCall(panicFn(), {cString("substring out of range")});
    b.CreateUnreachable();

    b.SetInsertPoint(okBB);
    llvm::Value* r = b.CreateCall(allocFn(), {b.CreateAdd(count, b.getInt64(1)), count});
    llvm::Value* src = b.CreateGEP(b.getInt8Ty(), b.CreateCall(dataFn(), {f->getArg(0)}), {start});
    b.CreateMemCpy(b.CreateConstGEP1_64(b.getInt8Ty(), r, 16), llvm::MaybeAlign(1), src, llvm::MaybeAlign(1), count);
    b.CreateRet(r);
    return f;
}

llvm::Function* CodeGen::printFn()
{
    auto it = helpers.find("__cs_print");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_print", llvm::Type::getVoidTy(ctx), {ptrTy, llvm::Type::getInt1Ty(ctx)});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    llvm::Value* len = b.CreateTrunc(b.CreateCall(lenFn(), {f->getArg(0)}), b.getInt32Ty());
    llvm::Value* fmt = b.CreateSelect(f->getArg(1), cString("%.*s\n"), cString("%.*s"));
    llvm::FunctionCallee printfFn = cFunction("printf", b.getInt32Ty(), {ptrTy}, true);
    b.CreateCall(printfFn, {fmt, len, b.CreateCall(dataFn(), {f->getArg(0)})});
    b.CreateRetVoid();
    return f;
}

// Creates a helper "string fmt(argType)" that formats one value with snprintf.
llvm::Function* CodeGen::fmtFn(const std::string& key, const char* format, llvm::Type* argType)
{
    std::string name = "__cs_fmt_" + key;
    auto it = helpers.find(name);
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper(name, ptrTy, {argType});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    llvm::FunctionCallee snprintfFn = cFunction("snprintf", b.getInt32Ty(), {ptrTy, sizeTy(), ptrTy}, true);
    llvm::Value* fmt = cString(format);
    llvm::Value* n = b.CreateCall(snprintfFn, {llvm::ConstantPointerNull::get(ptrTy), llvm::ConstantInt::get(sizeTy(), 0),
                                               fmt, f->getArg(0)});
    llvm::Value* len = b.CreateSExt(n, b.getInt64Ty());
    llvm::Value* r = b.CreateCall(allocFn(), {b.CreateAdd(len, b.getInt64(1)), len});
    b.CreateCall(snprintfFn, {b.CreateConstGEP1_64(b.getInt8Ty(), r, 16),
                              b.CreateZExtOrTrunc(b.CreateAdd(len, b.getInt64(1)), sizeTy()), fmt, f->getArg(0)});
    b.CreateRet(r);
    return f;
}

// Converts a primitive value to a new (owned) string.
llvm::Value* CodeGen::emitToString(const Value& value, SourceLoc loc)
{
    Value v = toRValue(value);
    Type* t = v.type;
    auto* i64 = llvm::Type::getInt64Ty(ctx);

    if (t->isString())
    {
        llvm::Value* s = consume(v);
        return s;
    }
    if (t->isBool())
    {
        llvm::Value* s = builder.CreateSelect(v.v, stringLiteral("true"), stringLiteral("false"));
        builder.CreateCall(retainFn(), {s});
        return s;
    }
    if (t->isChar())
    {
        llvm::Value* r = builder.CreateCall(allocFn(), {builder.getInt64(2), builder.getInt64(1)});
        builder.CreateStore(v.v, dataPtr(r));
        return r;
    }
    if (t->isEnum() || t->isInt())
    {
        bool isSigned = t->isSigned;
        llvm::Value* wide = isSigned ? builder.CreateSExt(v.v, i64) : builder.CreateZExt(v.v, i64);
        return builder.CreateCall(isSigned ? fmtFn("i64", "%lld", i64) : fmtFn("u64", "%llu", i64), {wide});
    }
    if (t->isFloat())
    {
        if (t->bits == 32)
            return builder.CreateCall(fmtFn("f32", "%.7g", builder.getDoubleTy()),
                                      {builder.CreateFPExt(v.v, builder.getDoubleTy())});
        return builder.CreateCall(fmtFn("f64", "%.15g", builder.getDoubleTy()), {v.v});
    }
    err(loc, "cannot convert '" + t->name + "' to a string");
}

llvm::Value* CodeGen::newString(llvm::Value* len)
{
    return builder.CreateCall(allocFn(), {builder.CreateAdd(len, builder.getInt64(1)), len});
}

// ---------------------------------------------------------------------------
// Per-type retain / release
// ---------------------------------------------------------------------------

namespace
{
// Calls fn(extractvalue(agg, index)) for every ARC member of an aggregate type.
struct MemberVisit
{
    unsigned index;
    Type* type;
};
} // namespace

static std::vector<MemberVisit> arcMembers(Type* t)
{
    std::vector<MemberVisit> out;
    switch (t->kind)
    {
    case TypeKind::Struct:
        if (t->st->base)
            out.push_back({0, t->st->base});
        for (const auto& f : t->st->fields)
            out.push_back({f.index, f.type});
        break;
    case TypeKind::Error:
        out.push_back({1, t->elem});
        break;
    case TypeKind::Optional:
        out.push_back({1, t->elem});
        break;
    default: break;
    }
    return out;
}

llvm::Function* CodeGen::retainFor(Type* t)
{
    if (t->isString() || t->isArray())
        return retainFn();

    std::string name = "__retain." + t->name;
    auto it = helpers.find(name);
    if (it != helpers.end())
        return it->second;

    llvm::Function* f = makeHelper(name, llvm::Type::getVoidTy(ctx), {llvmTypeOf(t)});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto visit = [&](unsigned index, Type* mt) {
        if (needsArc(mt))
            b.CreateCall(retainFor(mt), {b.CreateExtractValue(f->getArg(0), index)});
    };
    if (t->kind == TypeKind::ErrorLit)
        visit(0, types.stringTy);
    else
    {
        for (const auto& m : arcMembers(t))
            visit(m.index, m.type);
        if (t->isError())
            visit(2, types.stringTy);
    }
    b.CreateRetVoid();
    return f;
}

llvm::Function* CodeGen::releaseFor(Type* t)
{
    if (t->isString())
        return releaseFlatFn();
    if (t->isArray() && !needsArc(t->elem))
        return releaseFlatFn();

    std::string name = "__release." + t->name;
    auto it = helpers.find(name);
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    if (t->isArray())
    {
        // Array of ARC elements: release every element when the count drops to zero.
        llvm::Function* f = makeHelper(name, llvm::Type::getVoidTy(ctx), {ptrTy});
        llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
        auto* decBB = llvm::BasicBlock::Create(ctx, "dec", f);
        auto* loopBB = llvm::BasicBlock::Create(ctx, "loop", f);
        auto* bodyBB = llvm::BasicBlock::Create(ctx, "body", f);
        auto* freeBB = llvm::BasicBlock::Create(ctx, "free", f);
        auto* doneBB = llvm::BasicBlock::Create(ctx, "done", f);
        llvm::Value* p = f->getArg(0);
        auto* i64 = b.getInt64Ty();
        b.CreateCondBr(b.CreateIsNull(p), doneBB, decBB);

        b.SetInsertPoint(decBB);
        llvm::Value* rc = b.CreateSub(b.CreateLoad(i64, p), b.getInt64(1));
        b.CreateStore(rc, p);
        llvm::Value* len = b.CreateLoad(i64, b.CreateConstGEP1_64(b.getInt8Ty(), p, 8));
        b.CreateCondBr(b.CreateICmpEQ(rc, b.getInt64(0)), loopBB, doneBB);

        b.SetInsertPoint(loopBB);
        llvm::PHINode* i = b.CreatePHI(i64, 2);
        i->addIncoming(b.getInt64(0), decBB);
        b.CreateCondBr(b.CreateICmpULT(i, len), bodyBB, freeBB);

        b.SetInsertPoint(bodyBB);
        llvm::Type* elemTy = llvmTypeOf(t->elem);
        llvm::Value* elemPtr = b.CreateGEP(elemTy, b.CreateConstGEP1_64(b.getInt8Ty(), p, 16), {i});
        b.CreateCall(releaseFor(t->elem), {b.CreateLoad(elemTy, elemPtr)});
        i->addIncoming(b.CreateAdd(i, b.getInt64(1)), bodyBB);
        b.CreateBr(loopBB);

        b.SetInsertPoint(freeBB);
        b.CreateCall(cFunction("free", b.getVoidTy(), {ptrTy}), {p});
        bumpCounter(b, "__cs_frees");
        b.CreateBr(doneBB);
        b.SetInsertPoint(doneBB);
        b.CreateRetVoid();
        return f;
    }

    llvm::Function* f = makeHelper(name, llvm::Type::getVoidTy(ctx), {llvmTypeOf(t)});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto visit = [&](unsigned index, Type* mt) {
        if (needsArc(mt))
            b.CreateCall(releaseFor(mt), {b.CreateExtractValue(f->getArg(0), index)});
    };
    if (t->kind == TypeKind::ErrorLit)
        visit(0, types.stringTy);
    else
    {
        for (const auto& m : arcMembers(t))
            visit(m.index, m.type);
        if (t->isError())
            visit(2, types.stringTy);
    }
    b.CreateRetVoid();
    return f;
}

void CodeGen::emitRetainValue(Type* t, llvm::Value* v)
{
    if (needsArc(t))
        builder.CreateCall(retainFor(t), {v});
}

void CodeGen::emitReleaseValue(Type* t, llvm::Value* v)
{
    if (needsArc(t))
        builder.CreateCall(releaseFor(t), {v});
}

llvm::Function* CodeGen::cloneFn(Type* arrayType)
{
    std::string name = "__clone." + arrayType->name;
    auto it = helpers.find(name);
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    Type* elem = arrayType->elem;
    llvm::Function* f = makeHelper(name, ptrTy, {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* copyBB = llvm::BasicBlock::Create(ctx, "copy", f);
    auto* nullBB = llvm::BasicBlock::Create(ctx, "null", f);
    auto* i64 = b.getInt64Ty();
    llvm::Value* p = f->getArg(0);
    b.CreateCondBr(b.CreateIsNull(p), nullBB, copyBB);
    b.SetInsertPoint(nullBB);
    b.CreateRet(llvm::ConstantPointerNull::get(ptrTy));

    b.SetInsertPoint(copyBB);
    llvm::Value* len = b.CreateLoad(i64, b.CreateConstGEP1_64(b.getInt8Ty(), p, 8));
    llvm::Value* bytes = b.CreateMul(len, b.getInt64(sizeOf(elem)));
    llvm::Value* r = b.CreateCall(allocFn(), {bytes, len});
    llvm::Value* dst = b.CreateConstGEP1_64(b.getInt8Ty(), r, 16);
    b.CreateMemCpy(dst, llvm::MaybeAlign(8), b.CreateConstGEP1_64(b.getInt8Ty(), p, 16), llvm::MaybeAlign(8), bytes);

    if (needsArc(elem))
    {
        auto* loopBB = llvm::BasicBlock::Create(ctx, "loop", f);
        auto* bodyBB = llvm::BasicBlock::Create(ctx, "body", f);
        auto* doneBB = llvm::BasicBlock::Create(ctx, "done", f);
        b.CreateBr(loopBB);
        b.SetInsertPoint(loopBB);
        llvm::PHINode* i = b.CreatePHI(i64, 2);
        i->addIncoming(b.getInt64(0), copyBB);
        b.CreateCondBr(b.CreateICmpULT(i, len), bodyBB, doneBB);
        b.SetInsertPoint(bodyBB);
        llvm::Type* elemTy = llvmTypeOf(elem);
        llvm::Value* elemPtr = b.CreateGEP(elemTy, dst, {i});
        b.CreateCall(retainFor(elem), {b.CreateLoad(elemTy, elemPtr)});
        i->addIncoming(b.CreateAdd(i, b.getInt64(1)), bodyBB);
        b.CreateBr(loopBB);
        b.SetInsertPoint(doneBB);
    }
    b.CreateRet(r);
    return f;
}

// void copy(src, srcIndex, dst, dstIndex, count): bounds-checked copy that also works for overlapping
// ranges of one array. Arrays with ARC elements copy element by element (retain new, release old).
llvm::Function* CodeGen::copyFn(Type* arrayType)
{
    std::string name = "__copy." + arrayType->name;
    auto it = helpers.find(name);
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    auto* i64 = llvm::Type::getInt64Ty(ctx);
    Type* elem = arrayType->elem;
    llvm::Type* elemTy = llvmTypeOf(elem);
    llvm::Function* f = makeHelper(name, llvm::Type::getVoidTy(ctx), {ptrTy, i64, ptrTy, i64, i64});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* failBB = llvm::BasicBlock::Create(ctx, "range", f);
    auto* okBB = llvm::BasicBlock::Create(ctx, "ok", f);
    llvm::Value* src = f->getArg(0);
    llvm::Value* si = f->getArg(1);
    llvm::Value* dst = f->getArg(2);
    llvm::Value* di = f->getArg(3);
    llvm::Value* count = f->getArg(4);

    llvm::Value* srcLen = b.CreateCall(lenFn(), {src});
    llvm::Value* dstLen = b.CreateCall(lenFn(), {dst});
    llvm::Value* bad = b.CreateOr(b.CreateICmpSLT(si, b.getInt64(0)), b.CreateICmpSLT(di, b.getInt64(0)));
    bad = b.CreateOr(bad, b.CreateICmpSLT(count, b.getInt64(0)));
    bad = b.CreateOr(bad, b.CreateICmpSGT(b.CreateAdd(si, count), srcLen));
    bad = b.CreateOr(bad, b.CreateICmpSGT(b.CreateAdd(di, count), dstLen));
    b.CreateCondBr(bad, failBB, okBB);

    b.SetInsertPoint(failBB);
    b.CreateCall(panicFn(), {cString("array copy out of range")});
    b.CreateUnreachable();

    b.SetInsertPoint(okBB);
    llvm::Value* srcBase = b.CreateGEP(elemTy, b.CreateConstGEP1_64(b.getInt8Ty(), src, 16), {si});
    llvm::Value* dstBase = b.CreateGEP(elemTy, b.CreateConstGEP1_64(b.getInt8Ty(), dst, 16), {di});

    if (!needsArc(elem))
    {
        b.CreateMemMove(dstBase, llvm::MaybeAlign(1), srcBase, llvm::MaybeAlign(1),
                        b.CreateMul(count, b.getInt64(sizeOf(elem))));
        b.CreateRetVoid();
        return f;
    }

    auto* fwdHead = llvm::BasicBlock::Create(ctx, "fwd.head", f);
    auto* fwdBody = llvm::BasicBlock::Create(ctx, "fwd.body", f);
    auto* bwdHead = llvm::BasicBlock::Create(ctx, "bwd.head", f);
    auto* bwdBody = llvm::BasicBlock::Create(ctx, "bwd.body", f);
    auto* doneBB = llvm::BasicBlock::Create(ctx, "done", f);
    // Copy backwards when the destination lies behind the source inside the same array.
    llvm::Value* backward = b.CreateAnd(b.CreateICmpEQ(src, dst), b.CreateICmpSGT(di, si));
    b.CreateCondBr(backward, bwdHead, fwdHead);

    auto makeLoop = [&](bool back, llvm::BasicBlock* head, llvm::BasicBlock* body) {
        b.SetInsertPoint(head);
        llvm::PHINode* i = b.CreatePHI(i64, 2);
        i->addIncoming(b.getInt64(0), okBB);
        b.CreateCondBr(b.CreateICmpSLT(i, count), body, doneBB);
        b.SetInsertPoint(body);
        llvm::Value* idx = back ? b.CreateSub(b.CreateSub(count, b.getInt64(1)), i) : (llvm::Value*)i;
        llvm::Value* sp = b.CreateGEP(elemTy, srcBase, {idx});
        llvm::Value* dp = b.CreateGEP(elemTy, dstBase, {idx});
        llvm::Value* v = b.CreateLoad(elemTy, sp);
        b.CreateCall(retainFor(elem), {v});
        llvm::Value* old = b.CreateLoad(elemTy, dp);
        b.CreateStore(v, dp);
        b.CreateCall(releaseFor(elem), {old});
        i->addIncoming(b.CreateAdd(i, b.getInt64(1)), body);
        b.CreateBr(head);
    };
    makeLoop(false, fwdHead, fwdBody);
    makeLoop(true, bwdHead, bwdBody);

    b.SetInsertPoint(doneBB);
    b.CreateRetVoid();
    return f;
}

// string __cs_from_cstr(const char*): copies a NUL-terminated C string into a new string (null stays null).
llvm::Function* CodeGen::fromCStrFn()
{
    auto it = helpers.find("__cs_from_cstr");
    if (it != helpers.end())
        return it->second;

    auto* ptrTy = llvm::PointerType::getUnqual(ctx);
    llvm::Function* f = makeHelper("__cs_from_cstr", ptrTy, {ptrTy});
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", f));
    auto* copyBB = llvm::BasicBlock::Create(ctx, "copy", f);
    auto* nullBB = llvm::BasicBlock::Create(ctx, "null", f);
    b.CreateCondBr(b.CreateIsNull(f->getArg(0)), nullBB, copyBB);
    b.SetInsertPoint(nullBB);
    b.CreateRet(llvm::ConstantPointerNull::get(ptrTy));

    b.SetInsertPoint(copyBB);
    llvm::FunctionCallee strlenFn = cFunction("strlen", sizeTy(), {ptrTy});
    llvm::Value* len = b.CreateZExtOrTrunc(b.CreateCall(strlenFn, {f->getArg(0)}), b.getInt64Ty());
    llvm::Value* r = b.CreateCall(allocFn(), {b.CreateAdd(len, b.getInt64(1)), len});
    b.CreateMemCpy(b.CreateConstGEP1_64(b.getInt8Ty(), r, 16), llvm::MaybeAlign(1), f->getArg(0), llvm::MaybeAlign(1), len);
    b.CreateRet(r);
    return f;
}
