#include "CodeGen.h"

#include <cfloat>
#include <llvm/ADT/APFloat.h>
#include <llvm/ADT/APInt.h>
#include <llvm/IR/Constants.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/Path.h>
#include <algorithm>

// ---------------------------------------------------------------------------
// Argument handling
// ---------------------------------------------------------------------------

std::vector<Type*> CodeGen::resolveTypeArgs(const std::vector<TypeRefPtr>& refs)
{
    std::vector<Type*> out;
    for (const auto& r : refs)
        out.push_back(resolveValueType(*r, fs->func->file, &fs->func->env));
    return out;
}

std::vector<Arg> CodeGen::emitArgs(std::vector<ExprPtr>& args)
{
    std::vector<Arg> out;
    for (auto& a : args)
    {
        Arg x;
        x.expr = a.get();
        x.v = emitExpr(a.get());
        out.push_back(std::move(x));
    }
    return out;
}

int CodeGen::argCost(const Arg& arg, Type* paramType, RefKind rk, bool nullable, bool cstring)
{
    const Value& v = arg.v;
    // Parameters that come from C pointers accept null (NULL) and a raw pointer to the same type.
    if (nullable && rk != RefKind::None && !v.isRefArg)
    {
        if (v.type->kind == TypeKind::Null)
            return 1;
        if (v.type->isPointer() && v.type->elem == paramType)
            return 2;
    }
    // A parameter that C declares as const char* also takes a raw char* (e.g. a string that came from C).
    if (cstring && rk == RefKind::None && !v.isRefArg && v.type->isPointer() &&
        (v.type->elem->isChar() || v.type->elem == types.i8 || v.type->elem == types.u8 || v.type->elem->isVoid()))
        return 2;
    switch (rk)
    {
    case RefKind::None:
        if (v.isRefArg)
            return -1;
        return conversionCost(v, paramType);
    case RefKind::Ref:
        if (!v.isRefArg || !v.isLValue || v.isConst)
            return -1;
        if (v.type == paramType)
            return 0;
        if (v.type->isStruct() && paramType->isStruct() && structIsAncestor(paramType, v.type))
            return 1;
        return -1;
    case RefKind::ConstRef:
        if (v.isLValue)
        {
            if (v.type == paramType)
                return 0;
            if (v.type->isStruct() && paramType->isStruct() && structIsAncestor(paramType, v.type))
                return 1;
        }
        {
            int c = conversionCost(v, paramType);
            return c < 0 ? -1 : c + 1;
        }
    }
    return -1;
}

bool CodeGen::unify(const TypeRef& pattern, Type* actual, const std::vector<std::string>& params, FileContext* file,
                    const TypeEnv* env, std::vector<Type*>& bound)
{
    (void)env;
    switch (pattern.kind)
    {
    case TypeRef::Pointer:
        return actual->isPointer() && unify(*pattern.elem, actual->elem, params, file, env, bound);
    case TypeRef::Array:
        return actual->isArray() && unify(*pattern.elem, actual->elem, params, file, env, bound);
    case TypeRef::Named:
        break;
    }

    if (pattern.path.size() == 1 && pattern.args.empty())
    {
        for (size_t i = 0; i < params.size(); i += 1)
        {
            if (params[i] == pattern.path[0])
            {
                if (actual->kind == TypeKind::Null || actual->kind == TypeKind::ErrorLit || actual->kind == TypeKind::MethodGroup)
                    return true; // cannot infer from these; another argument may bind it
                if (!bound[i])
                    bound[i] = actual;
                return true;
            }
        }
        return true;
    }

    if (pattern.path.size() == 1 && pattern.args.size() == 1 && (pattern.path[0] == "Error" || pattern.path[0] == "Optional") &&
        !lookupTypeDecl(file, pattern.path[0]))
    {
        if ((pattern.path[0] == "Error" && actual->isError()) || (pattern.path[0] == "Optional" && actual->isOptional()))
            return unify(*pattern.args[0], actual->elem, params, file, env, bound);
        return actual->kind == TypeKind::Null || actual->kind == TypeKind::ErrorLit;
    }

    if (pattern.path.size() == 1 && (pattern.path[0] == "Action" || pattern.path[0] == "Func") && !lookupTypeDecl(file, pattern.path[0]))
    {
        if (!actual->isFunction())
            return actual->kind == TypeKind::Null || actual->kind == TypeKind::MethodGroup;
        bool isFunc = pattern.path[0] == "Func";
        size_t n = pattern.args.size();
        if (isFunc && n == 0)
            return false;
        size_t paramCount = isFunc ? n - 1 : n;
        if (paramCount != actual->params.size() || isFunc == actual->elem->isVoid())
            return false;
        for (size_t i = 0; i < paramCount; i += 1)
            if (!unify(*pattern.args[i], actual->params[i], params, file, env, bound))
                return false;
        return !isFunc || unify(*pattern.args[n - 1], actual->elem, params, file, env, bound);
    }

    if (!pattern.args.empty() && actual->isStruct())
    {
        std::string dotted;
        for (size_t i = 0; i < pattern.path.size(); i += 1)
            dotted += (i ? "." : "") + pattern.path[i];
        const TypeDeclEntry* entry = lookupTypeDecl(file, dotted);
        if (entry && entry->kind == TypeDeclEntry::Struct && entry->structDecl == actual->st->decl &&
            pattern.args.size() == entry->structDecl->typeParams.size())
        {
            for (size_t k = 0; k < pattern.args.size(); k += 1)
            {
                Type* argT = actual->st->env[entry->structDecl->typeParams[k]];
                if (!unify(*pattern.args[k], argT, params, file, env, bound))
                    return false;
            }
        }
    }
    return true;
}

bool CodeGen::inferTypeArgs(const Candidate& c, std::vector<Arg>& args, std::vector<Type*>& out)
{
    FuncDecl* d = c.decl;
    std::vector<Type*> bound(d->typeParams.size(), nullptr);
    for (size_t i = 0; i < d->params.size() && i < args.size(); i += 1)
    {
        Type* actual = args[i].v.type;
        if (actual->kind == TypeKind::MethodGroup)
            if (Type* ft = groupFunctionType(args[i].v))
                actual = ft; // the natural type of a function name with a single meaning
        if (!unify(*d->params[i].type, actual, d->typeParams, c.file, c.ownerEnv, bound))
            return false;
    }
    for (Type* t : bound)
        if (!t)
            return false;
    out = bound;
    return true;
}

FuncInfo* CodeGen::resolveOverload(const std::vector<Candidate>& candidates, std::vector<Arg>& args,
                                   const std::vector<Type*>& explicitTypeArgs, SourceLoc loc, const std::string& name)
{
    struct Match
    {
        FuncInfo* fi;
        int cost;
    };
    std::vector<Match> matches;
    std::string reason;

    for (const Candidate& c : candidates)
    {
        FuncDecl* d = c.decl;
        if (args.size() < d->params.size() || (!d->isVariadic && args.size() != d->params.size()))
        {
            reason = "expected " + std::to_string(d->params.size()) + " argument(s), got " + std::to_string(args.size());
            continue;
        }

        std::vector<Type*> targs;
        if (!d->typeParams.empty())
        {
            if (!explicitTypeArgs.empty())
            {
                if (explicitTypeArgs.size() != d->typeParams.size())
                {
                    reason = "wrong number of type arguments";
                    continue;
                }
                targs = explicitTypeArgs;
            }
            else if (!inferTypeArgs(c, args, targs))
            {
                reason = "cannot infer the type arguments, specify them explicitly (e.g. " + name + "<int>(...))";
                continue;
            }
        }
        else if (!explicitTypeArgs.empty())
        {
            reason = "'" + name + "' is not generic";
            continue;
        }

        FuncInfo* fi;
        try
        {
            fi = getFuncInstance(d, c.owner, c.ownerEnv, c.file, targs, loc);
        }
        catch (const CompileError& e)
        {
            reason = e.message;
            continue;
        }

        int total = 0;
        bool ok = true;
        for (size_t i = 0; i < fi->paramTypes.size(); i += 1)
        {
            int cost = argCost(args[i], fi->paramTypes[i], fi->paramRefs[i], fi->paramNullable[i], fi->paramCString[i]);
            if (cost < 0)
            {
                reason = "argument " + std::to_string(i + 1) + ": cannot convert '" + args[i].v.type->name + "' to '" +
                         (fi->paramRefs[i] == RefKind::Ref ? "ref " : fi->paramRefs[i] == RefKind::ConstRef ? "const ref " : "") +
                         fi->paramTypes[i]->name + "'";
                if (fi->paramRefs[i] == RefKind::Ref && !args[i].v.isRefArg)
                    reason += " (pass it with 'ref')";
                ok = false;
                break;
            }
            total += cost;
        }
        for (size_t i = fi->paramTypes.size(); ok && i < args.size(); i += 1)
            if (args[i].v.isRefArg)
                ok = false;
        if (!ok)
            continue;
        matches.push_back({fi, total * 2 + (d->typeParams.empty() ? 0 : 1)});
    }

    if (matches.empty())
    {
        std::string sig = name + "(";
        for (size_t i = 0; i < args.size(); i += 1)
            sig += (i ? ", " : "") + (args[i].v.isRefArg ? std::string("ref ") : std::string()) + args[i].v.type->name;
        sig += ")";
        std::string msg = "no matching function for call '" + sig + "'";
        if (!reason.empty())
            msg += ": " + reason;
        err(loc, msg);
    }

    size_t best = 0;
    for (size_t i = 1; i < matches.size(); i += 1)
        if (matches[i].cost < matches[best].cost)
            best = i;
    for (size_t i = 0; i < matches.size(); i += 1)
        if (i != best && matches[i].cost == matches[best].cost && matches[i].fi != matches[best].fi)
            err(loc, "the call to '" + name + "' is ambiguous");
    return matches[best].fi;
}

Value CodeGen::emitDirectCall(FuncInfo& fi, llvm::Value* thisPtr, std::vector<Arg>& args, SourceLoc loc)
{
    useFunction(fi);
    noteCall(fi);
    std::vector<llvm::Value*> callArgs;
    if (fi.hasThis)
        callArgs.push_back(thisPtr);

    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
    {
        Arg& a = args[i];
        Type* pt = fi.paramTypes[i];
        SourceLoc aloc = a.expr ? a.expr->loc : loc;
        switch (fi.paramRefs[i])
        {
        case RefKind::None:
        {
            if (fi.paramCString[i] && a.v.type->isPointer())
            {
                callArgs.push_back(toRValue(a.v).v); // a raw char* is passed as it is
                break;
            }
            Value cv = convertValue(a.v, pt, aloc);
            holdTemp(cv);
            llvm::Value* passed = cv.v;
            if (fi.paramCString[i])
            {
                // const char*: pass the character data of the string (null stays NULL). Strings are NUL-terminated.
                passed = builder.CreateSelect(builder.CreateIsNull(cv.v), llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx)),
                                              dataPtr(cv.v));
            }
            callArgs.push_back(passed);
            break;
        }
        case RefKind::Ref:
        case RefKind::ConstRef:
            if (fi.paramNullable[i] && !a.v.isRefArg && a.v.type->kind == TypeKind::Null)
            {
                callArgs.push_back(llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx)));
                break;
            }
            if (fi.paramNullable[i] && !a.v.isRefArg && a.v.type->isPointer() && a.v.type->elem == pt)
            {
                callArgs.push_back(toRValue(a.v).v);
                break;
            }
            if (fi.paramRefs[i] == RefKind::Ref)
            {
                callArgs.push_back(a.v.v);
                break;
            }
            if (a.v.isLValue && (a.v.type == pt || (a.v.type->isStruct() && pt->isStruct() && structIsAncestor(pt, a.v.type))))
            {
                callArgs.push_back(a.v.v);
            }
            else
            {
                Value cv = convertValue(a.v, pt, aloc);
                holdTemp(cv);
                callArgs.push_back(materialize(pt, cv.v));
            }
            break;
        }
    }

    // Extra arguments of variadic C functions get the default argument promotions.
    for (size_t i = fi.paramTypes.size(); i < args.size(); i += 1)
    {
        Value r = toRValue(args[i].v);
        SourceLoc aloc = args[i].expr ? args[i].expr->loc : loc;
        llvm::Value* v = r.v;
        Type* t = r.type;
        if (t->isFloat())
        {
            if (t->bits == 32)
                v = builder.CreateFPExt(v, builder.getDoubleTy());
        }
        else if (t->isBool())
            v = builder.CreateZExt(v, builder.getInt32Ty());
        else if (t->isIntegral() || t->isEnum())
        {
            if (t->bits < 32)
                v = (t->isInt() && t->isSigned) ? builder.CreateSExt(v, builder.getInt32Ty()) : builder.CreateZExt(v, builder.getInt32Ty());
        }
        else if (t->isPointer() || t->kind == TypeKind::Null)
        {
        }
        else
            err(aloc, "cannot pass a value of type '" + t->name + "' to a variadic C function (use '.CStr()' for strings)");
        holdTemp(r);
        callArgs.push_back(v);
    }

    // Shims return structs through a pointer to a temporary.
    llvm::Value* outSlot = nullptr;
    if (fi.decl->retOut)
    {
        outSlot = entryAlloca(llvmTypeOf(fi.ret), "ret");
        callArgs.push_back(outSlot);
    }

    llvm::CallInst* call = builder.CreateCall(fi.fn, callArgs);
    if (fi.decl->retOut)
        return Value::rvalue(fi.ret, builder.CreateLoad(llvmTypeOf(fi.ret), outSlot), needsArc(fi.ret));
    if (fi.ret->isVoid())
        return Value::rvalue(types.voidTy, nullptr);
    if (fi.decl->retCString)
    {
        // const char* result: copy it into a string that the caller owns.
        return Value::rvalue(types.stringTy, builder.CreateCall(fromCStrFn(), {call}), true);
    }
    return Value::rvalue(fi.ret, call, needsArc(fi.ret));
}

// ---------------------------------------------------------------------------
// Function pointers: Action<...> / Func<..., R>
// ---------------------------------------------------------------------------

// A function name used as a value. It becomes a function pointer when it is converted to an Action/Func type.
Value CodeGen::groupValue(const std::vector<Candidate>& cands, const std::vector<Type*>& typeArgs, const std::string& name)
{
    Value v = Value::rvalue(types.methodGroupTy, nullptr);
    v.group = cands;
    v.groupTypeArgs = typeArgs;
    v.groupName = name;
    return v;
}

static std::string functionSignature(const FuncInfo& fi, TypeContext& types)
{
    std::vector<Type*> params = fi.paramTypes;
    return types.functionOf(params, fi.ret)->name;
}

// Finds the function that a function name refers to when it is converted to the function type 'to'. The signature
// must match exactly.
FuncInfo* CodeGen::resolveGroup(const Value& g, Type* to, std::string* why)
{
    std::string reason = "no function with this name matches";
    for (const Candidate& c : g.group)
    {
        FuncDecl* d = c.decl;
        std::vector<Type*> targs = g.groupTypeArgs;
        if (!d->typeParams.empty())
        {
            if (targs.empty())
            {
                // Infer the type arguments from the target type.
                std::vector<Type*> bound(d->typeParams.size(), nullptr);
                bool ok = d->params.size() == to->params.size();
                for (size_t i = 0; ok && i < d->params.size(); i += 1)
                    ok = unify(*d->params[i].type, to->params[i], d->typeParams, c.file, c.ownerEnv, bound);
                if (ok)
                    ok = unify(*d->ret, to->elem, d->typeParams, c.file, c.ownerEnv, bound);
                for (Type* b : bound)
                    ok = ok && b;
                if (!ok)
                {
                    reason = "cannot infer the type arguments of '" + g.groupName + "', specify them explicitly";
                    continue;
                }
                targs = bound;
            }
            else if (targs.size() != d->typeParams.size())
            {
                reason = "wrong number of type arguments";
                continue;
            }
        }
        else if (!targs.empty())
        {
            reason = "'" + g.groupName + "' is not generic";
            continue;
        }

        FuncInfo* fi;
        try
        {
            fi = getFuncInstance(d, c.owner, c.ownerEnv, c.file, targs, d->loc);
        }
        catch (const CompileError& e)
        {
            reason = e.message;
            continue;
        }
        if (fi->hasThis)
        {
            reason = "'" + g.groupName + "' is an instance method; only static methods and free functions can be function values";
            continue;
        }
        if (d->isThread)
        {
            reason = "'" + g.groupName + "' is a 'thread' function and cannot be used as a function pointer (use 'start " + g.groupName + "(...)' to start it)";
            continue;
        }
        bool plain = !d->isVariadic && !d->retOut && !d->retCString;
        for (size_t i = 0; i < fi->paramTypes.size(); i += 1)
            plain = plain && fi->paramRefs[i] == RefKind::None && !fi->paramCString[i];
        if (!plain)
        {
            reason = "'" + g.groupName + "' has ref parameters or C conversions (string/struct marshalling) and cannot be used as a function pointer";
            continue;
        }
        if (fi->paramTypes != to->params || fi->ret != to->elem)
        {
            reason = "'" + g.groupName + "' has the signature " + functionSignature(*fi, types);
            continue;
        }
        return fi;
    }
    if (why)
        *why = reason;
    return nullptr;
}

// The function type of a function name that has exactly one meaning (for 'var' and type inference).
Type* CodeGen::groupFunctionType(const Value& g)
{
    if (g.group.size() != 1)
        return nullptr;
    const Candidate& c = g.group[0];
    if (c.decl->typeParams.size() != g.groupTypeArgs.size())
        return nullptr;
    FuncInfo* fi;
    try
    {
        fi = getFuncInstance(c.decl, c.owner, c.ownerEnv, c.file, g.groupTypeArgs, c.decl->loc);
    }
    catch (const CompileError&)
    {
        return nullptr;
    }
    if (fi->hasThis || c.decl->isVariadic || c.decl->retOut || c.decl->retCString || c.decl->isThread)
        return nullptr;
    for (size_t i = 0; i < fi->paramTypes.size(); i += 1)
        if (fi->paramRefs[i] != RefKind::None || fi->paramCString[i])
            return nullptr;
    if (fi->paramTypes.size() > 8)
        return nullptr;
    return types.functionOf(fi->paramTypes, fi->ret);
}

Value CodeGen::emitIndirectCall(Value callee, std::vector<Arg>& args, SourceLoc loc)
{
    Value f = toRValue(callee);
    Type* ft = f.type;
    if (args.size() != ft->params.size())
        err(loc, "a call of '" + ft->name + "' needs " + std::to_string(ft->params.size()) + " argument(s), got " +
                     std::to_string(args.size()));

    std::vector<llvm::Value*> callArgs;
    std::vector<llvm::Type*> paramTypes;
    for (size_t i = 0; i < args.size(); i += 1)
    {
        SourceLoc aloc = args[i].expr ? args[i].expr->loc : loc;
        if (args[i].v.isRefArg)
            err(aloc, "function values (Action/Func) have no 'ref' parameters");
        Value cv = convertValue(args[i].v, ft->params[i], aloc);
        holdTemp(cv);
        callArgs.push_back(cv.v);
        paramTypes.push_back(llvmTypeOf(ft->params[i]));
    }

    emitPanicIf(builder.CreateIsNull(f.v), "call of a null function");
    auto* fty = llvm::FunctionType::get(llvmTypeOf(ft->elem), paramTypes, false);
    llvm::CallInst* call = builder.CreateCall(fty, f.v, callArgs);
    addAbiAttributes(nullptr, call, ft->params, std::vector<bool>(ft->params.size(), false), ft->elem);
    if (ft->elem->isVoid())
        return Value::rvalue(types.voidTy, nullptr);
    return Value::rvalue(ft->elem, call, needsArc(ft->elem));
}

void CodeGen::callDispose(const ScopeVar& var)
{
    for (const Candidate& c : methodCandidates(var.type, "Dispose"))
    {
        if (!c.decl->params.empty() || !c.decl->typeParams.empty() || c.decl->isStatic)
            continue;
        FuncInfo* fi = getFuncInstance(c.decl, c.owner, c.ownerEnv, c.file, {}, c.decl->loc);
        useFunction(*fi);
        noteCall(*fi);
        builder.CreateCall(fi->fn, {var.slot});
        return;
    }
    err(SourceLoc{}, "internal error: missing Dispose method on '" + var.type->name + "'");
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

// Files that are embedded into the program at compile time (paths are relative to the source file with the call):
//   EmbedText("file")            the text of a file (string)
//   EmbedNames("dir", ".ext")    the names of the files of a directory with this extension, sorted (string[])
//   EmbedTexts("dir", ".ext")    their texts in the same order (string[])
// Line ends are normalized to '\n' and a byte order mark is removed.
Value CodeGen::emitEmbed(CallExpr* e, const std::string& name)
{
    size_t wanted = name == "EmbedText" ? 1 : 2;
    if (e->args.size() != wanted)
        err(e->loc, name + " takes " + std::to_string(wanted) + " string literal argument(s)");
    std::vector<std::string> literals;
    for (auto& a : e->args)
    {
        if (a->kind != ExprKind::StringLit)
            err(a->loc, name + " needs string literals (the files are read when the program is compiled)");
        literals.push_back(static_cast<StringLitExpr*>(a.get())->value);
    }
    std::string source = e->loc.file < (int)diag.files.size() ? diag.files[e->loc.file] : "";
    llvm::SmallString<256> base(llvm::sys::path::parent_path(source));
    auto resolve = [&](const std::string& relative) {
        llvm::SmallString<256> p(base);
        llvm::sys::path::append(p, relative);
        return std::string(p.str());
    };
    auto readText = [&](const std::string& path) {
        auto buffer = llvm::MemoryBuffer::getFile(path);
        if (!buffer)
            err(e->loc, name + ": cannot read '" + path + "'");
        std::string text = (*buffer)->getBuffer().str();
        if (text.size() >= 3 && (unsigned char)text[0] == 0xEF && (unsigned char)text[1] == 0xBB && (unsigned char)text[2] == 0xBF)
            text.erase(0, 3);
        std::string normalized;
        for (char c : text)
            if (c != '\r')
                normalized += c;
        return normalized;
    };

    if (name == "EmbedText")
    {
        Value v = Value::rvalue(types.stringTy, stringLiteral(readText(resolve(literals[0])))); // literals are never freed
        return v;
    }

    std::string dir = resolve(literals[0]);
    if (!llvm::sys::fs::is_directory(dir))
        err(e->loc, name + ": '" + dir + "' is not a directory");
    std::vector<std::string> names;
    std::error_code ec;
    for (llvm::sys::fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec))
    {
        std::string file = llvm::sys::path::filename(it->path()).str();
        bool matches = literals[1].empty() ||
                       (file.size() >= literals[1].size() && file.compare(file.size() - literals[1].size(), literals[1].size(), literals[1]) == 0);
        if (matches && llvm::sys::fs::is_regular_file(it->path()))
            names.push_back(file);
    }
    std::sort(names.begin(), names.end());

    Type* arrT = types.arrayOf(types.stringTy);
    uint64_t n = names.size();
    llvm::Value* arr = builder.CreateCall(allocFn(), {builder.getInt64(n * sizeOf(types.stringTy)), builder.getInt64(n)});
    for (uint64_t i = 0; i < n; i += 1)
    {
        std::string text = name == "EmbedNames" ? names[i] : readText(resolve(literals[0] + "/" + names[i]));
        llvm::Value* slot = builder.CreateGEP(llvmTypeOf(types.stringTy), dataPtr(arr), {builder.getInt64(i)});
        builder.CreateStore(stringLiteral(text), slot);
    }
    return Value::rvalue(arrT, arr, true);
}

// 'start f(...)': the only way to call a 'thread' function (see emitCall's viaStart handling - a plain call to
// one is a compile-time error, and 'start' on anything else is too).
Value CodeGen::emitStart(StartExpr* e)
{
    if (e->operand->kind != ExprKind::Call)
        err(e->loc, "'start' must be followed directly by a call, e.g. 'start Foo(...)'");
    return emitCall(static_cast<CallExpr*>(e->operand.get()), true);
}

// A call is normally 'e', but 'start f(...)' (emitStart) re-enters this with viaStart=true and 'e' being the
// call inside 'start'. A 'thread' function can only be called via 'start'; conversely 'start' only ever makes
// sense directly in front of a call to one (never an indirect call through a function pointer/value - a
// 'thread' function can never become one, see resolveGroup/groupFunctionType).
Value CodeGen::emitCall(CallExpr* e, bool viaStart)
{
    Expr* callee = e->callee.get();
    auto rejectIndirectStart = [&] {
        if (viaStart)
            err(e->loc, "'start' can only be used with a direct call to a 'thread' function");
    };

    if (callee->kind == ExprKind::Name)
    {
        auto* n = static_cast<NameExpr*>(callee);
        Value var = lookupVariable(n->name);
        if (var.type)
        {
            if (!var.type->isFunction())
                err(e->loc, "'" + n->name + "' is a variable, not a function");
            rejectIndirectStart();
            std::vector<Arg> args = emitArgs(e->args);
            return emitIndirectCall(var, args, e->loc);
        }
        if (fs->func->owner)
        {
            // A field with a function type is called like a function.
            FieldPath p;
            if (findField(fs->func->owner, n->name, p) && p.type->isFunction())
            {
                rejectIndirectStart();
                Value field = emitName(n);
                std::vector<Arg> args = emitArgs(e->args);
                return emitIndirectCall(field, args, e->loc);
            }
        }

        if (GlobalInfo* g = lookupGlobal(fs->func->file, n->name))
        {
            Value global = globalValue(*g);
            if (global.type->isFunction() && !(fs->func->owner && methodCandidates(fs->func->owner, n->name).size()))
            {
                rejectIndirectStart();
                std::vector<Arg> args = emitArgs(e->args);
                return emitIndirectCall(global, args, e->loc);
            }
        }

        std::vector<Type*> targs = resolveTypeArgs(n->typeArgs);
        std::vector<Candidate> cands;
        if (fs->func->owner)
            cands = methodCandidates(fs->func->owner, n->name);
        if (cands.empty())
        {
            for (FuncDecl* d : lookupFunctions(fs->func->file, n->name))
                cands.push_back(Candidate{d, nullptr, nullptr, d->file});
        }
        if (cands.empty() && (n->name == "EmbedText" || n->name == "EmbedTexts" || n->name == "EmbedNames"))
        {
            rejectIndirectStart();
            return emitEmbed(e, n->name);
        }
        if (cands.empty())
            err(e->loc, "undefined function '" + n->name + "'");

        std::vector<Arg> args = emitArgs(e->args);
        FuncInfo* fi = resolveOverload(cands, args, targs, e->loc, n->name);
        if (fi->decl->isThread)
        {
            if (!viaStart)
                err(e->loc, "call to the 'thread' function '" + n->name + "' must be prefixed with 'start': 'start " +
                                n->name + "(...)'");
            return emitThreadSpawn(*fi, args, e->loc);
        }
        if (viaStart)
            err(e->loc, "'start' can only be used with a 'thread' function, not '" + n->name + "'");
        llvm::Value* thisPtr = nullptr;
        if (fi->hasThis)
        {
            if (!fs->thisSlot)
                err(e->loc, "cannot call the instance method '" + n->name + "' from a static context");
            thisPtr = builder.CreateLoad(llvm::PointerType::getUnqual(ctx), fs->thisSlot);
        }
        return emitDirectCall(*fi, thisPtr, args, e->loc);
    }

    if (callee->kind == ExprKind::Member)
    {
        auto* m = static_cast<MemberExpr*>(callee);
        std::vector<Type*> targs = resolveTypeArgs(m->typeArgs);
        StaticTarget st = resolveStaticTarget(m->object.get());

        if (st.kind == StaticTarget::Builtin)
        {
            rejectIndirectStart();
            std::vector<Arg> args = emitArgs(e->args);
            return emitBuiltinStatic(st.name, m->name, args, e->loc);
        }

        if (st.kind == StaticTarget::Namespace)
        {
            std::vector<Candidate> cands;
            for (FuncDecl* d : lookupFunctions(fs->func->file, st.name + "." + m->name))
                cands.push_back(Candidate{d, nullptr, nullptr, d->file});
            if (cands.empty())
                err(e->loc, "namespace '" + st.name + "' has no function '" + m->name + "'");
            std::vector<Arg> args = emitArgs(e->args);
            FuncInfo* fi = resolveOverload(cands, args, targs, e->loc, m->name);
            if (fi->decl->isThread)
            {
                if (!viaStart)
                    err(e->loc, "call to the 'thread' function '" + m->name + "' must be prefixed with 'start'");
                return emitThreadSpawn(*fi, args, e->loc);
            }
            if (viaStart)
                err(e->loc, "'start' can only be used with a 'thread' function, not '" + m->name + "'");
            return emitDirectCall(*fi, nullptr, args, e->loc);
        }

        if (st.kind == StaticTarget::TypeName)
        {
            Type* t = st.type;
            if (t->kind == TypeKind::SharedPtr)
            {
                rejectIndirectStart();
                if (m->name != "Create")
                    err(e->loc, "type '" + t->name + "' has no static method '" + m->name + "'");
                std::vector<Arg> args = emitArgs(e->args);
                if (args.size() != 1)
                    err(e->loc, "SharedPtr<T>.Create takes one argument (the value)");
                Value v = convertValue(args[0].v, t->elem, e->loc);
                llvm::Value* owned = consume(v);
                llvm::Value* block = builder.CreateCall(allocFn(), {builder.getInt64(sizeOf(t->elem)), builder.getInt64(0)});
                llvm::Value* slot = builder.CreateConstGEP1_64(builder.getInt8Ty(), block, 16);
                builder.CreateStore(owned, slot);
                return Value::rvalue(t, block, true);
            }
            if (t->isString())
            {
                rejectIndirectStart();
                // string.FromBytes(uint8[] bytes [, start, count]) builds a string from raw (UTF-8) bytes.
                std::vector<Arg> args = emitArgs(e->args);
                if (m->name == "FromBytes")
                {
                    if (args.empty() || args.size() == 2 || args.size() > 3)
                        err(e->loc, "string.FromBytes takes (bytes) or (bytes, start, count)");
                    Value bytes = toRValue(args[0].v);
                    Type* byteArray = types.arrayOf(types.u8);
                    if (bytes.type != byteArray && bytes.type->kind != TypeKind::Null)
                        err(e->loc, "string.FromBytes needs a 'uint8[]', not '" + bytes.type->name + "'");
                    holdTemp(bytes);
                    llvm::Value* start = builder.getInt32(0);
                    llvm::Value* count = builder.CreateTrunc(arrayLength(bytes.v), builder.getInt32Ty());
                    if (args.size() == 3)
                    {
                        start = convertValue(args[1].v, types.i32, e->loc).v;
                        count = convertValue(args[2].v, types.i32, e->loc).v;
                    }
                    // Arrays and strings share the block layout, so the substring helper copies the bytes.
                    return Value::rvalue(types.stringTy, builder.CreateCall(substringFn(), {bytes.v, start, count}), true);
                }
                if (m->name == "FromCStr")
                {
                    // string.FromCStr(char* p): copies a NUL-terminated C string into a string (null -> null).
                    if (args.size() != 1)
                        err(e->loc, "string.FromCStr takes one argument (char*)");
                    requireUnsafe(e->loc, "string.FromCStr");
                    Value p = toRValue(args[0].v);
                    if (!(p.type->isPointer() && (p.type->elem->isChar() || p.type->elem->isVoid() || p.type->elem == types.u8 ||
                                                  p.type->elem == types.i8)) &&
                        p.type->kind != TypeKind::Null)
                        err(e->loc, "string.FromCStr needs a 'char*', not '" + p.type->name + "'");
                    return Value::rvalue(types.stringTy, builder.CreateCall(fromCStrFn(), {p.v}), true);
                }
                bool found = false;
                Value r = emitExtensionCall("String", nullptr, m->name, args, e->loc, found);
                if (found)
                    return r;
                err(e->loc, "type 'string' has no static method '" + m->name + "'");
            }
            if (!t->isStruct())
                err(e->loc, "type '" + t->name + "' has no static method '" + m->name + "'");
            std::vector<Candidate> cands = methodCandidates(t, m->name);
            if (cands.empty())
                err(e->loc, "struct '" + t->name + "' has no method '" + m->name + "'");
            std::vector<Arg> args = emitArgs(e->args);
            FuncInfo* fi = resolveOverload(cands, args, targs, e->loc, m->name);
            if (fi->hasThis)
                err(e->loc, "'" + t->name + "." + m->name + "' is an instance method and needs an object");
            if (!m->name.empty() && m->name[0] == '_' && fs->func->owner != fi->owner)
                err(e->loc, "method '" + m->name + "' is private to '" + fi->owner->name + "'");
            if (fi->decl->isThread)
            {
                if (!viaStart)
                    err(e->loc, "call to the 'thread' method '" + t->name + "." + m->name + "' must be prefixed with 'start'");
                return emitThreadSpawn(*fi, args, e->loc);
            }
            if (viaStart)
                err(e->loc, "'start' can only be used with a 'thread' function, not '" + t->name + "." + m->name + "'");
            return emitDirectCall(*fi, nullptr, args, e->loc);
        }

        // Instance call: never a 'thread' function (thread functions can't be instance methods).
        rejectIndirectStart();
        Value obj = emitExpr(m->object.get());
        if (m->viaArrow)
            obj = derefPointer(obj, e->loc);
        else if (obj.type->isPointer())
            err(e->loc, "use '->' to call methods through a pointer");
        if (obj.type->isStruct() && methodCandidates(obj.type, m->name).empty())
        {
            // A field with a function type is called like a method: obj.Callback(x)
            FieldPath p;
            if (findField(obj.type, m->name, p) && p.type->isFunction())
            {
                Value field = fieldAccess(obj, m->name, e->loc);
                std::vector<Arg> args = emitArgs(e->args);
                return emitIndirectCall(field, args, e->loc);
            }
        }
        std::vector<Arg> args = emitArgs(e->args);
        if (obj.type->isFunction() && m->name == "Invoke")
            return emitIndirectCall(obj, args, e->loc);

        if (obj.type->isStruct())
        {
            std::vector<Candidate> cands = methodCandidates(obj.type, m->name);
            if (cands.empty())
                err(e->loc, "struct '" + obj.type->name + "' has no method '" + m->name + "'");
            FuncInfo* fi = resolveOverload(cands, args, targs, e->loc, m->name);
            if (!fi->hasThis)
                err(e->loc, "'" + m->name + "' is a static method, call it as '" + fi->owner->name + "." + m->name + "(...)'");
            if (!m->name.empty() && m->name[0] == '_' && fs->func->owner != fi->owner)
                err(e->loc, "method '" + m->name + "' is private to '" + fi->owner->name + "'");
            llvm::Value* thisPtr;
            if (obj.isLValue && !obj.isConst)
            {
                thisPtr = obj.v;
            }
            else if (obj.isLValue)
            {
                // A read-only alias ('const ref'): the method could modify the object, so it works on a copy.
                Value copy = Value::rvalue(obj.type, consume(obj), true);
                holdTemp(copy);
                thisPtr = materialize(obj.type, copy.v);
            }
            else
            {
                holdTemp(obj);
                thisPtr = materialize(obj.type, obj.v);
            }
            return emitDirectCall(*fi, thisPtr, args, e->loc);
        }
        return emitBuiltinMethod(obj, m->name, args, e->loc);
    }

    // Any other expression that yields a function: handlers[i](x), MakeCallback()(x)
    rejectIndirectStart();
    Value fv = emitExpr(callee);
    if (!fv.type->isFunction())
        err(e->loc, "this expression cannot be called (type '" + fv.type->name + "')");
    std::vector<Arg> args = emitArgs(e->args);
    return emitIndirectCall(fv, args, e->loc);
}

// ---------------------------------------------------------------------------
// Built-in static functions (Console, Memory) and methods on built-in types
// ---------------------------------------------------------------------------

Value CodeGen::emitBuiltinStatic(const std::string& type, const std::string& method, std::vector<Arg>& args, SourceLoc loc)
{
    Value voidValue = Value::rvalue(types.voidTy, nullptr);

    if (type == "Console")
    {
        bool toStderr = method == "WriteError" || method == "WriteErrorLine";
        if (method != "Write" && method != "WriteLine" && !toStderr)
            err(loc, "Console has no function '" + method + "'");
        bool newline = method == "WriteLine" || method == "WriteErrorLine";
        if (args.size() > 1)
            err(loc, "Console." + method + " takes at most one argument");
        llvm::Value* s;
        if (args.empty())
        {
            if (!newline)
                err(loc, "Console.Write needs an argument");
            s = llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx));
        }
        else
        {
            Value v = toRValue(args[0].v);
            if (v.type->kind == TypeKind::Null)
            {
                s = v.v;
            }
            else if (v.type->isString())
            {
                holdTemp(v);
                s = v.v;
            }
            else
            {
                s = emitToString(v, args[0].expr ? args[0].expr->loc : loc);
                holdTemp(Value::rvalue(types.stringTy, s, true)); // emitToString returns a +1 reference
            }
        }
        builder.CreateCall(printFn(toStderr), {s, builder.getInt1(newline)});
        return voidValue;
    }

    if (type == "Memory")
    {
        requireUnsafe(loc, ("Memory." + method).c_str());
        auto* voidPtr = types.pointerTo(types.voidTy);
        if (method == "Allocate")
        {
            if (args.size() != 1)
                err(loc, "Memory.Allocate takes one argument (size in bytes)");
            Value n = toRValue(args[0].v);
            if (!n.type->isIntegral())
                err(loc, "Memory.Allocate needs an integer size");
            llvm::Value* size = numericConvert(n.v, n.type, n.type->isSigned ? types.i64 : types.u64);
            llvm::FunctionCallee mallocFn = cFunction("malloc", llvm::PointerType::getUnqual(ctx), {sizeTy()});
            return Value::rvalue(voidPtr, builder.CreateCall(mallocFn, {builder.CreateZExtOrTrunc(size, sizeTy())}));
        }
        if (method == "Free")
        {
            if (args.size() != 1)
                err(loc, "Memory.Free takes one argument");
            Value p = toRValue(args[0].v);
            if (!p.type->isPointer() && p.type->kind != TypeKind::Null)
                err(loc, "Memory.Free needs a pointer");
            llvm::FunctionCallee freeFn = cFunction("free", builder.getVoidTy(), {llvm::PointerType::getUnqual(ctx)});
            builder.CreateCall(freeFn, {p.v});
            return voidValue;
        }
        err(loc, "Memory has no function '" + method + "'");
    }
    if (type == "Environment")
    {
        if (method == "Panic")
        {
            // Terminates the program like a failed runtime check (exit code 101).
            if (args.size() != 1)
                err(loc, "Environment.Panic takes one argument (message)");
            Value msg = convertValue(args[0].v, types.stringTy, loc);
            holdTemp(msg);
            builder.CreateCall(panicFn(), {builder.CreateCall(dataFn(), {msg.v})});
            builder.CreateUnreachable();
            return voidValue;
        }
        if (method == "Exit")
        {
            if (args.size() != 1)
                err(loc, "Environment.Exit takes one argument (exit code)");
            Value code = convertValue(args[0].v, types.i32, loc);
            llvm::FunctionCallee exitFn = cFunction("exit", builder.getVoidTy(), {builder.getInt32Ty()});
            builder.CreateCall(exitFn, {code.v});
            builder.CreateUnreachable();
            return voidValue;
        }
        err(loc, "Environment has no function '" + method + "'");
    }

    if (type == "Array")
    {
        // Array.Copy(source, sourceIndex, destination, destinationIndex, count) or Array.Copy(source, destination, count).
        // Overlapping ranges of the same array are handled; ARC elements are retained/released correctly.
        if (method != "Copy" || (args.size() != 5 && args.size() != 3))
            err(loc, "Array.Copy takes (source, sourceIndex, destination, destinationIndex, count) or (source, destination, count)");
        bool shortForm = args.size() == 3;
        Value src = toRValue(args[0].v);
        Value dst = toRValue(args[shortForm ? 1 : 2].v);
        if (!src.type->isArray() || src.type != dst.type)
            err(loc, "Array.Copy needs two arrays of the same type, got '" + src.type->name + "' and '" + dst.type->name + "'");
        holdTemp(src);
        holdTemp(dst);
        auto index = [&](size_t i) {
            Value v = convertValue(args[i].v, types.i32, loc);
            return builder.CreateSExt(v.v, builder.getInt64Ty());
        };
        llvm::Value* si = shortForm ? builder.getInt64(0) : index(1);
        llvm::Value* di = shortForm ? builder.getInt64(0) : index(3);
        llvm::Value* count = index(shortForm ? 2 : 4);
        builder.CreateCall(copyFn(src.type), {src.v, si, dst.v, di, count});
        return voidValue;
    }
    err(loc, "unknown built-in '" + type + "'");
}

// Calls a function of the standard library that extends a built-in type: "String.Method(self, args...)".
Value CodeGen::emitExtensionCall(const std::string& ns, const Value* self, const std::string& method,
                                 std::vector<Arg>& args, SourceLoc loc, bool& found)
{
    std::vector<Candidate> cands;
    for (FuncDecl* d : lookupFunctions(fs->func->file, ns + "." + method))
        cands.push_back(Candidate{d, nullptr, nullptr, d->file});
    found = !cands.empty();
    if (!found)
        return Value{};

    std::vector<Arg> all;
    if (self)
    {
        Arg a;
        a.v = *self;
        all.push_back(a);
    }
    for (auto& a : args)
        all.push_back(a);
    FuncInfo* fi = resolveOverload(cands, all, {}, loc, ns + "." + method);
    return emitDirectCall(*fi, nullptr, all, loc);
}

Value CodeGen::emitBuiltinMethod(Value obj, const std::string& method, std::vector<Arg>& args, SourceLoc loc)
{
    Type* t = obj.type;
    auto expectArgs = [&](size_t n) {
        if (args.size() != n)
            err(loc, "'" + t->name + "." + method + "' takes " + std::to_string(n) + " argument(s)");
    };

    if (t->isString())
    {
        Value s = toRValue(obj);
        if (method == "ToString")
        {
            expectArgs(0);
            return s;
        }
        if (method == "Clone")
        {
            // Strings are immutable, but an explicit independent copy is possible.
            expectArgs(0);
            holdTemp(s);
            llvm::Value* len = builder.CreateTrunc(arrayLength(s.v), builder.getInt32Ty());
            return Value::rvalue(types.stringTy, builder.CreateCall(substringFn(), {s.v, builder.getInt32(0), len}), true);
        }
        if (method == "CStr")
        {
            expectArgs(0);
            requireUnsafe(loc, "string.CStr()");
            holdTemp(s);
            return Value::rvalue(types.pointerTo(types.charTy), builder.CreateCall(dataFn(), {s.v}));
        }
        if (method == "Substring")
        {
            if (args.empty() || args.size() > 2)
                err(loc, "string.Substring takes (start) or (start, length)");
            holdTemp(s);
            llvm::Value* start = convertValue(args[0].v, types.i32, loc).v;
            llvm::Value* count;
            if (args.size() == 2)
                count = convertValue(args[1].v, types.i32, loc).v;
            else
                count = builder.CreateSub(builder.CreateTrunc(arrayLength(s.v), builder.getInt32Ty()), start);
            return Value::rvalue(types.stringTy, builder.CreateCall(substringFn(), {s.v, start, count}), true);
        }
        // Everything else (Contains, Trim, Split, ...) is written in CShift: namespace String of the standard library.
        bool found = false;
        Value r = emitExtensionCall("String", &s, method, args, loc, found);
        if (found)
            return r;
    }
    else if (t->isArray())
    {
        if (method == "Clone")
        {
            expectArgs(0);
            Value a = toRValue(obj);
            holdTemp(a);
            return Value::rvalue(t, builder.CreateCall(cloneFn(t), {a.v}), true);
        }
    }
    else if (t->isSharedPtr())
    {
        if (method == "IsNull")
        {
            expectArgs(0);
            Value p = toRValue(obj);
            holdTemp(p);
            return boolValue(builder.CreateIsNull(p.v));
        }
        if (method == "Get")
        {
            // A copy of the shared value (retained if it needs ARC itself).
            expectArgs(0);
            Value p = toRValue(obj);
            holdTemp(p);
            emitPanicIf(builder.CreateIsNull(p.v), "SharedPtr.Get(): the pointer is null");
            llvm::Value* slot = builder.CreateConstGEP1_64(builder.getInt8Ty(), p.v, 16);
            llvm::Value* payload = builder.CreateLoad(llvmTypeOf(t->elem), slot);
            emitRetainValue(t->elem, payload);
            return Value::rvalue(t->elem, payload, true);
        }
        if (method == "Ptr")
        {
            // A raw pointer to the shared value, for in-place (mutable) access. Concurrent access through it is
            // not synchronized by SharedPtr itself, the same as std::shared_ptr in C++: only the reference count
            // is thread-safe, the pointee is not.
            expectArgs(0);
            requireUnsafe(loc, "SharedPtr.Ptr()");
            Value p = toRValue(obj);
            holdTemp(p);
            emitPanicIf(builder.CreateIsNull(p.v), "SharedPtr.Ptr(): the pointer is null");
            return Value::rvalue(types.pointerTo(t->elem), builder.CreateConstGEP1_64(builder.getInt8Ty(), p.v, 16));
        }
    }
    else if (t->isNumeric() || t->isBool() || t->isEnum())
    {
        if (method == "ToString")
        {
            expectArgs(0);
            llvm::Value* s = emitToString(obj, loc);
            return Value::rvalue(types.stringTy, s, true);
        }
        if (method == "Equals")
        {
            expectArgs(1);
            Value a = toRValue(obj);
            Value b = convertValue(args[0].v, t, loc);
            return emitCompare(BinOp::Eq, a, b, loc);
        }
        if (method == "GetHashCode")
        {
            expectArgs(0);
            Value a = toRValue(obj);
            llvm::Value* v = a.v;
            if (t->isFloat())
                v = builder.CreateBitCast(v, builder.getIntNTy(t->bits));
            unsigned bits = v->getType()->getIntegerBitWidth();
            bool isSigned = (t->isInt() || t->isEnum()) && t->isSigned;
            if (bits < 32)
                v = isSigned ? builder.CreateSExt(v, builder.getInt32Ty()) : builder.CreateZExt(v, builder.getInt32Ty());
            else if (bits == 64)
                v = builder.CreateXor(builder.CreateTrunc(v, builder.getInt32Ty()),
                                      builder.CreateTrunc(builder.CreateLShr(v, 32), builder.getInt32Ty()));
            return Value::rvalue(types.i32, v);
        }
        if (method == "CompareTo" && t->isNumeric())
        {
            expectArgs(1);
            Value a = toRValue(obj);
            Value b = convertValue(args[0].v, t, loc);
            llvm::Value *gt, *lt;
            if (t->isFloat())
            {
                gt = builder.CreateFCmpOGT(a.v, b.v);
                lt = builder.CreateFCmpOLT(a.v, b.v);
            }
            else if (t->isInt() && t->isSigned)
            {
                gt = builder.CreateICmpSGT(a.v, b.v);
                lt = builder.CreateICmpSLT(a.v, b.v);
            }
            else
            {
                gt = builder.CreateICmpUGT(a.v, b.v);
                lt = builder.CreateICmpULT(a.v, b.v);
            }
            llvm::Value* r = builder.CreateSub(builder.CreateZExt(gt, builder.getInt32Ty()),
                                               builder.CreateZExt(lt, builder.getInt32Ty()));
            return Value::rvalue(types.i32, r);
        }
    }
    err(loc, "type '" + t->name + "' has no method '" + method + "'");
}

Value CodeGen::emitBuiltinStaticMember(Type* type, const std::string& member, SourceLoc loc, bool& found)
{
    (void)loc;
    found = true;
    if (type->isInt() || type->isChar())
    {
        unsigned bits = type->bits;
        bool isSigned = type->isInt() && type->isSigned;
        if (member == "MaxValue")
            return Value::rvalue(type, llvm::ConstantInt::get(ctx, isSigned ? llvm::APInt::getSignedMaxValue(bits) : llvm::APInt::getMaxValue(bits)));
        if (member == "MinValue")
            return Value::rvalue(type, llvm::ConstantInt::get(ctx, isSigned ? llvm::APInt::getSignedMinValue(bits) : llvm::APInt::getMinValue(bits)));
    }
    else if (type->isFloat())
    {
        bool is32 = type->bits == 32;
        auto make = [&](double d32, double d64) {
            return Value::rvalue(type, llvm::ConstantFP::get(llvmTypeOf(type), is32 ? d32 : d64));
        };
        if (member == "MaxValue")
            return make(FLT_MAX, DBL_MAX);
        if (member == "MinValue")
            return make(-FLT_MAX, -DBL_MAX);
        if (member == "Epsilon")
            return make(FLT_EPSILON, DBL_EPSILON);
        if (member == "NaN")
            return Value::rvalue(type, llvm::ConstantFP::getNaN(llvmTypeOf(type)));
        if (member == "PositiveInfinity")
            return Value::rvalue(type, llvm::ConstantFP::getInfinity(llvmTypeOf(type), false));
        if (member == "NegativeInfinity")
            return Value::rvalue(type, llvm::ConstantFP::getInfinity(llvmTypeOf(type), true));
    }
    found = false;
    return Value{};
}
