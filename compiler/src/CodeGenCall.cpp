#include "CodeGen.h"

#include <cfloat>
#include <llvm/ADT/APFloat.h>
#include <llvm/ADT/APInt.h>
#include <llvm/IR/Constants.h>

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

int CodeGen::argCost(const Arg& arg, Type* paramType, RefKind rk)
{
    const Value& v = arg.v;
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
                if (actual->kind == TypeKind::Null || actual->kind == TypeKind::ErrorLit)
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
        if (!unify(*d->params[i].type, args[i].v.type, d->typeParams, c.file, c.ownerEnv, bound))
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
            int cost = argCost(args[i], fi->paramTypes[i], fi->paramRefs[i]);
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
            Value cv = convertValue(a.v, pt, aloc);
            holdTemp(cv);
            callArgs.push_back(cv.v);
            break;
        }
        case RefKind::Ref:
            callArgs.push_back(a.v.v);
            break;
        case RefKind::ConstRef:
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

    llvm::CallInst* call = builder.CreateCall(fi.fn, callArgs);
    if (fi.ret->isVoid())
        return Value::rvalue(types.voidTy, nullptr);
    return Value::rvalue(fi.ret, call, needsArc(fi.ret));
}

void CodeGen::callDispose(const ScopeVar& var)
{
    for (const Candidate& c : methodCandidates(var.type, "Dispose"))
    {
        if (!c.decl->params.empty() || !c.decl->typeParams.empty() || c.decl->isStatic)
            continue;
        FuncInfo* fi = getFuncInstance(c.decl, c.owner, c.ownerEnv, c.file, {}, c.decl->loc);
        useFunction(*fi);
        builder.CreateCall(fi->fn, {var.slot});
        return;
    }
    err(SourceLoc{}, "internal error: missing Dispose method on '" + var.type->name + "'");
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

Value CodeGen::emitCall(CallExpr* e)
{
    Expr* callee = e->callee.get();

    if (callee->kind == ExprKind::Name)
    {
        auto* n = static_cast<NameExpr*>(callee);
        if (lookupVariable(n->name).type)
            err(e->loc, "'" + n->name + "' is a variable, not a function");

        std::vector<Type*> targs = resolveTypeArgs(n->typeArgs);
        std::vector<Candidate> cands;
        if (fs->func->owner)
            cands = methodCandidates(fs->func->owner, n->name);
        if (cands.empty())
        {
            for (FuncDecl* d : lookupFunctions(fs->func->file, n->name))
                cands.push_back(Candidate{d, nullptr, nullptr, d->file});
        }
        if (cands.empty())
            err(e->loc, "undefined function '" + n->name + "'");

        std::vector<Arg> args = emitArgs(e->args);
        FuncInfo* fi = resolveOverload(cands, args, targs, e->loc, n->name);
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
            return emitDirectCall(*fi, nullptr, args, e->loc);
        }

        if (st.kind == StaticTarget::TypeName)
        {
            Type* t = st.type;
            if (t->isString())
            {
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
            return emitDirectCall(*fi, nullptr, args, e->loc);
        }

        // Instance call.
        Value obj = emitExpr(m->object.get());
        if (m->viaArrow)
            obj = derefPointer(obj, e->loc);
        else if (obj.type->isPointer())
            err(e->loc, "use '->' to call methods through a pointer");
        std::vector<Arg> args = emitArgs(e->args);

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

    err(e->loc, "this expression cannot be called");
}

// ---------------------------------------------------------------------------
// Built-in static functions (Console, Memory) and methods on built-in types
// ---------------------------------------------------------------------------

Value CodeGen::emitBuiltinStatic(const std::string& type, const std::string& method, std::vector<Arg>& args, SourceLoc loc)
{
    Value voidValue = Value::rvalue(types.voidTy, nullptr);

    if (type == "Console")
    {
        if (method != "Write" && method != "WriteLine")
            err(loc, "Console has no function '" + method + "'");
        bool newline = method == "WriteLine";
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
        builder.CreateCall(printFn(), {s, builder.getInt1(newline)});
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
