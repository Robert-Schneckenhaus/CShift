#include "CodeGen.h"

#include <llvm/IR/Constants.h>
#include <llvm/IR/Intrinsics.h>

// ---------------------------------------------------------------------------
// Values, ownership and temporaries
// ---------------------------------------------------------------------------
//
// ARC rules used throughout the code generator:
//  * A variable, field or array slot of an ARC type owns one reference.
//  * An rvalue is either "owned" (it carries a +1 that must be consumed or released)
//    or borrowed (e.g. loaded from a slot).
//  * consume() turns any value into a +1 value (retaining borrowed ones); it is used
//    when a value is stored, returned or embedded into an aggregate.
//  * holdTemp() schedules the release of an owned temporary at the end of the
//    current full expression / statement.
//  * Function arguments are passed borrowed; the callee retains parameters it keeps.

llvm::AllocaInst* CodeGen::entryAlloca(llvm::Type* t, const std::string& name)
{
    llvm::BasicBlock& entry = fs->fn->getEntryBlock();
    llvm::IRBuilder<> b(&entry, entry.begin());
    return b.CreateAlloca(t, nullptr, name);
}

llvm::Value* CodeGen::zeroValue(Type* t)
{
    return llvm::Constant::getNullValue(llvmTypeOf(t));
}

llvm::Value* CodeGen::materialize(Type* t, llvm::Value* value)
{
    llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(t), "tmp");
    builder.CreateStore(value, slot);
    return slot;
}

Value CodeGen::boolValue(llvm::Value* v)
{
    return Value::rvalue(types.boolTy, v);
}

Value CodeGen::constInt(Type* t, int64_t value)
{
    return Value::rvalue(t, llvm::ConstantInt::get(llvmTypeOf(t), (uint64_t)value, t->isSigned));
}

Value CodeGen::toRValue(const Value& v)
{
    if (!v.isLValue)
        return v;
    Value r = Value::rvalue(v.type, builder.CreateLoad(llvmTypeOf(v.type), v.v));
    return r;
}

llvm::Value* CodeGen::consume(const Value& v)
{
    Value r = toRValue(v);
    if (!r.owned && needsArc(r.type))
        emitRetainValue(r.type, r.v);
    return r.v;
}

void CodeGen::holdTemp(const Value& v)
{
    if (v.owned && !v.isLValue && needsArc(v.type))
        fs->temps.push_back({v.type, v.v});
}

void CodeGen::flushTemps(size_t mark, bool pop)
{
    if (blockOpen())
    {
        for (size_t i = fs->temps.size(); i > mark; i -= 1)
            emitReleaseValue(fs->temps[i - 1].type, fs->temps[i - 1].value);
    }
    if (pop)
        fs->temps.resize(mark);
}

void CodeGen::storeSlot(Type* t, llvm::Value* addr, llvm::Value* newOwned, bool releaseOld)
{
    if (releaseOld && needsArc(t))
    {
        llvm::Value* old = builder.CreateLoad(llvmTypeOf(t), addr);
        builder.CreateStore(newOwned, addr);
        emitReleaseValue(t, old);
    }
    else
    {
        builder.CreateStore(newOwned, addr);
    }
}

llvm::Value* CodeGen::makeSome(Type* resultType, llvm::Value* payloadOwned)
{
    llvm::Value* agg = llvm::Constant::getNullValue(llvmTypeOf(resultType));
    agg = builder.CreateInsertValue(agg, builder.getTrue(), {0});
    if (!payloadOwned) // Error<void>
        return agg;
    return builder.CreateInsertValue(agg, payloadOwned, {1});
}

llvm::Value* CodeGen::makeNone(Type* optionalType)
{
    return llvm::Constant::getNullValue(llvmTypeOf(optionalType));
}

llvm::Value* CodeGen::makeErr(Type* errorType, llvm::Value* msgOwned, llvm::Value* code)
{
    llvm::Value* agg = llvm::Constant::getNullValue(llvmTypeOf(errorType));
    agg = builder.CreateInsertValue(agg, msgOwned, {2});
    return builder.CreateInsertValue(agg, code, {3});
}

void CodeGen::requireUnsafe(SourceLoc loc, const char* what)
{
    if (fs->unsafeDepth == 0)
        err(loc, std::string(what) + " is only allowed in an 'unsafe' context");
}

Type* CodeGen::declTypeOf(const TypeRef& ref)
{
    return resolveValueType(ref, fs->func->file, &fs->func->env);
}

// ---------------------------------------------------------------------------
// Conversions
// ---------------------------------------------------------------------------

static bool literalFits(const Value& v, Type* to)
{
    if (v.litIsFloat)
        return false;
    if (to->isChar())
        return v.litInt >= 0 && v.litInt <= 255;
    if (!to->isInt())
        return false;
    if (to->bits >= 64)
        return to->isSigned || v.litInt >= 0;
    if (to->isSigned)
        return v.litInt >= -(int64_t(1) << (to->bits - 1)) && v.litInt < (int64_t(1) << (to->bits - 1));
    return v.litInt >= 0 && v.litInt < (int64_t(1) << to->bits);
}

llvm::Value* CodeGen::numericConvert(llvm::Value* v, Type* from, Type* to)
{
    auto isIntLike = [](Type* t) { return t->isInt() || t->isChar() || t->isEnum(); };
    auto signedOf = [](Type* t) { return (t->isInt() || t->isEnum()) && t->isSigned; };
    llvm::Type* dst = llvmTypeOf(to);

    if (isIntLike(from) && isIntLike(to))
    {
        if (from->bits == to->bits)
            return v;
        if (from->bits > to->bits)
            return builder.CreateTrunc(v, dst);
        return signedOf(from) ? builder.CreateSExt(v, dst) : builder.CreateZExt(v, dst);
    }
    if (isIntLike(from) && to->isFloat())
        return signedOf(from) ? builder.CreateSIToFP(v, dst) : builder.CreateUIToFP(v, dst);
    if (from->isFloat() && isIntLike(to))
    {
        auto id = signedOf(to) ? llvm::Intrinsic::fptosi_sat : llvm::Intrinsic::fptoui_sat;
        return builder.CreateIntrinsic(id, {dst, llvmTypeOf(from)}, {v});
    }
    if (from->isFloat() && to->isFloat())
    {
        if (from->bits == to->bits)
            return v;
        return from->bits > to->bits ? builder.CreateFPTrunc(v, dst) : builder.CreateFPExt(v, dst);
    }
    err(SourceLoc{}, "internal error: invalid numeric conversion");
}

// Central implementation of implicit conversions. With emit == false only the cost is computed
// (-1 = not convertible), which is used for overload resolution.
static int implicitIntCost(Type* from, Type* to)
{
    if (!(from->isIntegral() && to->isIntegral()))
        return -1;
    if (from->isChar() != to->isChar() && from->bits == 8 && to->bits == 8)
    {
        // char <-> uint8
        Type* other = from->isChar() ? to : from;
        return other->isInt() && !other->isSigned ? 1 : -1;
    }
    bool fromSigned = from->isInt() && from->isSigned;
    bool toSigned = to->isInt() && to->isSigned;
    // Pointer-sized integers (like C#): int32 and smaller convert to nint/nuint, nint/nuint convert to the 64-bit types.
    if (to->isNativeInt && !from->isNativeInt && from->bits <= 32)
        return (toSigned ? (fromSigned || from->bits < 32) : (!fromSigned)) ? 2 : -1;
    if (from->isNativeInt && !to->isNativeInt && to->bits >= 64 && fromSigned == toSigned)
        return 2;
    if (to->bits > from->bits && (!fromSigned || toSigned))
        return 2 + (to->bits - from->bits) / 16;
    return -1;
}

int CodeGen::conversionCost(const Value& v, Type* to)
{
    Type* from = v.type;
    if (from == to)
        return 0;

    if (v.hasLit)
    {
        if (!v.litIsFloat && literalFits(v, to))
            return 1;
        // Integer literals prefer double (exact), float literals prefer float.
        if (to->isFloat())
            return (v.litIsFloat || to->bits == 64) ? 1 : 2;
    }
    if (from->kind == TypeKind::Null)
        return (to->isPointer() || to->isString() || to->isArray() || to->isOptional() || to->isFunction()) ? 1 : -1;
    if (from->kind == TypeKind::MethodGroup)
        return to->isFunction() && resolveGroup(v, to, nullptr) ? 1 : -1;
    if (from->kind == TypeKind::ErrorLit)
        return to->isError() ? 1 : -1;

    int c = implicitIntCost(from, to);
    if (c >= 0)
        return c;
    if (from->isIntegral() && to->isFloat())
        return to->bits == 64 ? 6 : 7; // worse than any integer widening; double is preferred (exact for int32)
    if (from->isFloat() && to->isFloat() && from->bits < to->bits)
        return 2;
    if (from->isPointer() && to->isPointer() && to->elem->isVoid())
        return 2;
    if (from->isStruct() && to->isStruct() && structIsAncestor(to, from))
        return 2;
    if (to->isResultLike() && !from->isResultLike())
    {
        int inner = conversionCost(v, to->elem);
        if (inner >= 0)
            return inner + 3;
    }
    return -1;
}

Value CodeGen::adaptLiteral(const Value& v, Type* to)
{
    if (!v.hasLit)
        return v;
    if (!v.litIsFloat && literalFits(v, to))
        return constInt(to, v.litInt);
    if (to->isFloat())
        return Value::rvalue(to, llvm::ConstantFP::get(llvmTypeOf(to), v.litIsFloat ? v.litFloat : (double)v.litInt));
    return v;
}

Value CodeGen::convertValue(const Value& v, Type* to, SourceLoc loc)
{
    Type* from = v.type;
    if (from == to)
        return toRValue(v);

    if (from->kind == TypeKind::MethodGroup)
    {
        std::string why;
        FuncInfo* fi = to->isFunction() ? resolveGroup(v, to, &why) : nullptr;
        if (!fi)
            err(loc, to->isFunction() ? "cannot convert function '" + v.groupName + "' to '" + to->name + "': " + why
                                      : "'" + v.groupName + "' is a function; call it with '()' or assign it to an Action/Func");
        useFunction(*fi);
        return Value::rvalue(to, fi->fn);
    }

    auto fail = [&]() -> Value {
        std::string hint;
        if (from->isNumeric() && to->isNumeric())
            hint = " (an explicit cast is required)";
        err(loc, "cannot implicitly convert '" + from->name + "' to '" + to->name + "'" + hint);
    };

    if (conversionCost(v, to) < 0)
        return fail();

    if (v.hasLit)
    {
        Value a = adaptLiteral(v, to);
        if (a.type == to)
            return a;
    }

    if (from->kind == TypeKind::Null)
    {
        if (to->isOptional())
            return Value::rvalue(to, makeNone(to));
        return Value::rvalue(to, llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx)));
    }
    if (from->kind == TypeKind::ErrorLit)
    {
        Value r = toRValue(v);
        llvm::Value* msg = builder.CreateExtractValue(r.v, {0});
        llvm::Value* code = builder.CreateExtractValue(r.v, {1});
        return Value::rvalue(to, makeErr(to, msg, code), true);
    }
    if (from->isNumeric() && to->isNumeric())
    {
        Value r = toRValue(v);
        return Value::rvalue(to, numericConvert(r.v, from, to));
    }
    if (from->isPointer() && to->isPointer())
        return Value::rvalue(to, toRValue(v).v);
    if (from->isStruct() && to->isStruct())
    {
        std::vector<unsigned> path;
        structIsAncestor(to, from, &path);
        Value r = toRValue(v);
        holdTemp(r);
        return Value::rvalue(to, builder.CreateExtractValue(r.v, path));
    }
    if (to->isResultLike())
    {
        Value inner = convertValue(v, to->elem, loc);
        llvm::Value* payload = consume(inner);
        llvm::Value* wrapped = makeSome(to, payload);
        return Value::rvalue(to, wrapped, needsArc(to));
    }
    return fail();
}

// ---------------------------------------------------------------------------
// Literals, names, members
// ---------------------------------------------------------------------------

Value CodeGen::emitLiteral(Expr* e)
{
    switch (e->kind)
    {
    case ExprKind::IntLit:
    {
        auto* l = static_cast<IntLitExpr*>(e);
        if (l->isUnsigned || l->isLong)
        {
            Type* t;
            if (l->isUnsigned && l->isLong)
                t = types.u64;
            else if (l->isUnsigned)
                t = l->value <= UINT32_MAX ? types.u32 : types.u64;
            else
                t = l->value <= (uint64_t)INT64_MAX ? types.i64 : types.u64;
            return constInt(t, (int64_t)l->value);
        }
        Value v;
        if (l->value <= (uint64_t)INT32_MAX)
            v = constInt(types.i32, (int64_t)l->value);
        else if (l->value <= (uint64_t)INT64_MAX)
            v = constInt(types.i64, (int64_t)l->value);
        else
            return constInt(types.u64, (int64_t)l->value);
        v.hasLit = true;
        v.litInt = (int64_t)l->value;
        return v;
    }
    case ExprKind::FloatLit:
    {
        auto* l = static_cast<FloatLitExpr*>(e);
        Type* t = l->isFloat32 ? types.f32 : types.f64;
        Value v = Value::rvalue(t, llvm::ConstantFP::get(llvmTypeOf(t), l->value));
        if (!l->isFloat32)
        {
            v.hasLit = true;
            v.litIsFloat = true;
            v.litFloat = l->value;
        }
        return v;
    }
    case ExprKind::CharLit:
        return Value::rvalue(types.charTy, llvm::ConstantInt::get(llvmTypeOf(types.charTy), static_cast<CharLitExpr*>(e)->value));
    case ExprKind::StringLit:
        return Value::rvalue(types.stringTy, stringLiteral(static_cast<StringLitExpr*>(e)->value));
    case ExprKind::BoolLit:
        return boolValue(builder.getInt1(static_cast<BoolLitExpr*>(e)->value));
    case ExprKind::NullLit:
        return Value::rvalue(types.nullTy, llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx)));
    default:
        err(e->loc, "internal error: not a literal");
    }
}

ConstDecl* CodeGen::lookupConst(FileContext* f, const std::string& name) const
{
    for (const auto& c : candidateNames(f, name))
    {
        auto it = constDecls.find(c);
        if (it != constDecls.end())
            return it->second;
    }
    return nullptr;
}

// Constant expressions: literals, operators and other constants.
bool CodeGen::isConstExpr(Expr* e, FileContext* file) const
{
    switch (e->kind)
    {
    case ExprKind::IntLit:
    case ExprKind::FloatLit:
    case ExprKind::CharLit:
    case ExprKind::StringLit:
    case ExprKind::BoolLit:
        return true;
    case ExprKind::Name:
        return lookupConst(file, static_cast<NameExpr*>(e)->name) != nullptr;
    case ExprKind::Member:
    {
        auto* m = static_cast<MemberExpr*>(e);
        return m->object->kind == ExprKind::Name &&
               lookupConst(file, static_cast<NameExpr*>(m->object.get())->name + "." + m->name) != nullptr;
    }
    case ExprKind::Unary:
    {
        auto* u = static_cast<UnaryExpr*>(e);
        return u->op != UnOp::Deref && u->op != UnOp::AddrOf && isConstExpr(u->operand.get(), file);
    }
    case ExprKind::Binary:
    {
        auto* b = static_cast<BinaryExpr*>(e);
        return isConstExpr(b->lhs.get(), file) && isConstExpr(b->rhs.get(), file);
    }
    default:
        return false;
    }
}

// A constant is inlined at every use. Its initializer only consists of literals and other constants, so
// evaluating it has no side effects. It is evaluated in the file context of the declaration.
Value CodeGen::emitConst(ConstDecl* c, SourceLoc loc)
{
    (void)loc;
    if (!isConstExpr(c->init.get(), c->file))
        err(c->loc, "the initializer of constant '" + c->name + "' must be a constant expression (literals, operators, other constants)");
    if (constDepth > 32)
        err(c->loc, "constant '" + c->name + "' depends on itself");
    Type* t = resolveValueType(*c->type, c->file, nullptr);
    if (!(t->isNumeric() || t->isBool() || t->isString() || t->isEnum()))
        err(c->loc, "constants can only be numbers, bool, char, string or enum values");

    FileContext* savedFile = fs->func->file;
    fs->func->file = c->file;
    constDepth += 1;
    try
    {
        Value v;
        if (t->isEnum())
            v = constInt(t, constEvalInt(c->init.get(), nullptr, c->loc)); // enumerators of imported C enums
        else
            v = convertValue(emitExpr(c->init.get()), t, c->init->loc);
        constDepth -= 1;
        fs->func->file = savedFile;
        return v;
    }
    catch (...)
    {
        constDepth -= 1;
        fs->func->file = savedFile;
        throw;
    }
}

Value CodeGen::lookupVariable(const std::string& name)
{
    for (size_t s = fs->scopes.size(); s > 0; s -= 1)
    {
        auto& vars = fs->scopes[s - 1].vars;
        for (size_t i = vars.size(); i > 0; i -= 1)
        {
            ScopeVar& v = vars[i - 1];
            if (v.name != name)
                continue;
            if (v.isRef)
                return Value::lvalue(v.type, builder.CreateLoad(llvm::PointerType::getUnqual(ctx), v.slot), v.isConst);
            return Value::lvalue(v.type, v.slot, v.isConst);
        }
    }
    return Value{};
}

bool CodeGen::isLocalName(const std::string& name)
{
    for (const auto& scope : fs->scopes)
        for (const auto& v : scope.vars)
            if (v.name == name)
                return true;
    FieldPath p;
    return fs->func->owner && findField(fs->func->owner, name, p);
}

Value CodeGen::thisValue(SourceLoc loc)
{
    if (!fs->thisSlot)
        err(loc, "'this' is not available in a static context");
    return Value::lvalue(fs->func->owner, builder.CreateLoad(llvm::PointerType::getUnqual(ctx), fs->thisSlot));
}

Value CodeGen::emitName(NameExpr* e)
{
    Value v = lookupVariable(e->name);
    if (v.type)
        return v;

    if (fs->func->owner)
    {
        FieldPath p;
        if (findField(fs->func->owner, e->name, p))
            return fieldAccess(thisValue(e->loc), e->name, e->loc);
    }

    if (ConstDecl* c = lookupConst(fs->func->file, e->name))
        return emitConst(c, e->loc);

    StaticTarget st = resolveStaticTarget(e);
    if (st.kind == StaticTarget::TypeName || st.kind == StaticTarget::Builtin)
        err(e->loc, "'" + e->name + "' is a type, not a value");
    // A function name is a value that converts to a matching Action/Func type.
    std::vector<Candidate> cands;
    if (fs->func->owner)
        cands = methodCandidates(fs->func->owner, e->name);
    if (cands.empty())
        for (FuncDecl* d : lookupFunctions(fs->func->file, e->name))
            cands.push_back(Candidate{d, nullptr, nullptr, d->file});
    if (!cands.empty())
        return groupValue(cands, resolveTypeArgs(e->typeArgs), e->name);
    err(e->loc, "undefined name '" + e->name + "'");
}

Value CodeGen::fieldAccess(Value obj, const std::string& name, SourceLoc loc)
{
    FieldPath p;
    if (!findField(obj.type, name, p))
        err(loc, "struct '" + obj.type->name + "' has no field '" + name + "'");
    if (p.isPrivate && fs->func->owner != p.owner)
        err(loc, "field '" + name + "' is private to '" + p.owner->name + "'");

    if (obj.isLValue)
    {
        std::vector<llvm::Value*> idx{builder.getInt32(0)};
        for (unsigned i : p.indices)
            idx.push_back(builder.getInt32(i));
        llvm::Value* addr = builder.CreateInBoundsGEP(llvmTypeOf(obj.type), obj.v, idx);
        return Value::lvalue(p.type, addr, obj.isConst);
    }
    holdTemp(obj);
    return Value::rvalue(p.type, builder.CreateExtractValue(obj.v, p.indices));
}

StaticTarget CodeGen::resolveStaticTarget(Expr* e)
{
    // Flatten a.b.c into a dotted name; the root must not be a variable or field.
    std::vector<std::string> parts;
    const std::vector<TypeRefPtr>* lastArgs = nullptr;
    Expr* cur = e;
    bool outermost = true;
    while (true)
    {
        if (cur->kind == ExprKind::Name)
        {
            auto* n = static_cast<NameExpr*>(cur);
            parts.push_back(n->name);
            if (outermost)
                lastArgs = &n->typeArgs;
            break;
        }
        if (cur->kind == ExprKind::Member)
        {
            auto* m = static_cast<MemberExpr*>(cur);
            if (m->viaArrow)
                return StaticTarget{};
            parts.push_back(m->name);
            if (outermost)
                lastArgs = &m->typeArgs;
            outermost = false;
            cur = m->object.get();
            continue;
        }
        return StaticTarget{};
    }
    std::string root = parts.back();
    if (isLocalName(root))
        return StaticTarget{};

    std::string dotted;
    for (size_t i = parts.size(); i > 0; i -= 1)
        dotted += (dotted.empty() ? "" : ".") + parts[i - 1];

    FileContext* file = fs->func->file;
    StaticTarget st;
    st.name = dotted;
    if (const TypeDeclEntry* entry = lookupTypeDecl(file, dotted))
    {
        st.kind = StaticTarget::TypeName;
        std::vector<Type*> args = lastArgs ? resolveTypeArgs(*lastArgs) : std::vector<Type*>{};
        switch (entry->kind)
        {
        case TypeDeclEntry::Struct: st.type = getStructType(entry->structDecl, args, e->loc); break;
        case TypeDeclEntry::Interface: st.type = getInterfaceType(entry->interfaceDecl, args, e->loc); break;
        case TypeDeclEntry::Enum: st.type = getEnumType(entry->enumDecl); break;
        }
        return st;
    }
    if (parts.size() == 1)
    {
        if (Type* p = primitiveType(dotted))
        {
            st.kind = StaticTarget::TypeName;
            st.type = p;
            return st;
        }
        if (dotted == "Console" || dotted == "Memory" || dotted == "Environment" || dotted == "Array")
        {
            st.kind = StaticTarget::Builtin;
            return st;
        }
    }
    if (isNamespace(file, dotted))
    {
        st.kind = StaticTarget::Namespace;
        return st;
    }
    return StaticTarget{};
}

Value CodeGen::derefPointer(const Value& p, SourceLoc loc)
{
    requireUnsafe(loc, "pointer dereference");
    Value pv = toRValue(p);
    if (!pv.type->isPointer())
        err(loc, "cannot dereference a value of type '" + pv.type->name + "'");
    if (pv.type->elem->isVoid())
        err(loc, "cannot dereference 'void*'");
    return Value::lvalue(pv.type->elem, pv.v);
}

Value CodeGen::emitMember(MemberExpr* e)
{
    StaticTarget st = resolveStaticTarget(e->object.get());
    if (st.kind == StaticTarget::TypeName)
    {
        Type* t = st.type;
        if (t->isEnum())
        {
            for (const auto& m : t->en->members)
                if (m.first == e->name)
                    return constInt(t, m.second);
            err(e->loc, "enum '" + t->name + "' has no member '" + e->name + "'");
        }
        bool found = false;
        Value v = emitBuiltinStaticMember(t, e->name, e->loc, found);
        if (found)
            return v;
        if (t->isStruct())
        {
            std::vector<Candidate> cands = methodCandidates(t, e->name);
            if (!cands.empty())
                return groupValue(cands, resolveTypeArgs(e->typeArgs), t->name + "." + e->name);
            err(e->loc, "struct '" + t->name + "' has no static member '" + e->name + "'");
        }
        err(e->loc, "type '" + t->name + "' has no member '" + e->name + "'");
    }
    if (st.kind == StaticTarget::Namespace)
    {
        if (ConstDecl* c = lookupConst(fs->func->file, st.name + "." + e->name))
            return emitConst(c, e->loc);
        std::vector<Candidate> cands;
        for (FuncDecl* d : lookupFunctions(fs->func->file, st.name + "." + e->name))
            cands.push_back(Candidate{d, nullptr, nullptr, d->file});
        if (!cands.empty())
            return groupValue(cands, resolveTypeArgs(e->typeArgs), st.name + "." + e->name);
    }
    if (st.kind == StaticTarget::Namespace || st.kind == StaticTarget::Builtin)
        err(e->loc, "'" + st.name + "' has no value member '" + e->name + "'");

    Value obj = emitExpr(e->object.get());
    if (e->viaArrow)
        obj = derefPointer(obj, e->loc);
    else if (obj.type->isPointer())
        err(e->loc, "use '->' to access members through a pointer");

    Type* t = obj.type;
    switch (t->kind)
    {
    case TypeKind::Struct: return fieldAccess(obj, e->name, e->loc);
    case TypeKind::String:
    case TypeKind::Array:
        if (e->name == "Length")
        {
            Value o = toRValue(obj);
            holdTemp(o);
            return Value::rvalue(types.i32, builder.CreateTrunc(arrayLength(o.v), builder.getInt32Ty()));
        }
        break;
    case TypeKind::Error:
    case TypeKind::Optional:
        if (t->isError() && (e->name == "Message" || e->name == "Code"))
        {
            Value o = toRValue(obj);
            holdTemp(o);
            if (e->name == "Message")
                return Value::rvalue(types.stringTy, builder.CreateExtractValue(o.v, {2}));
            return Value::rvalue(types.i32, builder.CreateExtractValue(o.v, {3}));
        }
        break;
    default: break;
    }
    err(e->loc, "type '" + t->name + "' has no member '" + e->name + "'");
}

Value CodeGen::emitIndex(IndexExpr* e)
{
    Value obj = emitExpr(e->object.get());
    Value idx = emitRValue(e->index.get());
    if (!idx.type->isIntegral())
        err(e->index->loc, "an index must be an integer, not '" + idx.type->name + "'");
    llvm::Value* i64v = numericConvert(idx.v, idx.type, idx.type->isSigned ? types.i64 : types.u64);

    Type* t = obj.type;
    if (t->isArray() || t->isString())
    {
        Value arr = toRValue(obj);
        holdTemp(arr);
        llvm::Value* len = arrayLength(arr.v);
        emitPanicIf(builder.CreateICmpUGE(i64v, len), t->isArray() ? "array index out of range" : "string index out of range");
        llvm::Value* base = dataPtr(arr.v);
        if (t->isString())
            return Value::rvalue(types.charTy, builder.CreateLoad(builder.getInt8Ty(), builder.CreateGEP(builder.getInt8Ty(), base, {i64v})));
        return Value::lvalue(t->elem, builder.CreateGEP(llvmTypeOf(t->elem), base, {i64v}));
    }
    if (t->isPointer())
    {
        requireUnsafe(e->loc, "pointer indexing");
        if (t->elem->isVoid())
            err(e->loc, "cannot index 'void*'");
        Value p = toRValue(obj);
        return Value::lvalue(t->elem, builder.CreateGEP(llvmTypeOf(t->elem), p.v, {i64v}));
    }
    err(e->loc, "cannot index a value of type '" + t->name + "'");
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

Type* CodeGen::promoteTypes(Type* a, Type* b, SourceLoc loc)
{
    if (a->isFloat() || b->isFloat())
    {
        if ((a->isFloat() && a->bits == 64) || (b->isFloat() && b->bits == 64))
            return types.f64;
        return types.f32;
    }

    // nint/nuint promote like the fixed-size integer of the same width; the result stays native when the other
    // operand is native as well or smaller than a pointer.
    if (a->isNativeInt || b->isNativeInt)
    {
        auto plain = [&](Type* t) { return t->isNativeInt ? types.intType(t->bits, t->isSigned) : t; };
        Type* r = promoteTypes(plain(a), plain(b), loc);
        Type* native = a->isNativeInt ? a : b;
        Type* other = native == a ? b : a;
        if (r == plain(native) && (other->isNativeInt || other->isChar() || other->bits < native->bits))
            return native;
        return r;
    }
    auto norm = [&](Type* t) {
        if (t->isChar() || t->bits < 32)
            return types.i32;
        return t;
    };
    Type* x = norm(a);
    Type* y = norm(b);
    if (x == y)
        return x;
    if (x == types.u64 || y == types.u64)
    {
        Type* other = x == types.u64 ? y : x;
        if (other->isSigned)
            err(loc, "operator cannot mix 'uint64' and signed types, use an explicit cast");
        return types.u64;
    }
    if (x == types.i64 || y == types.i64)
        return types.i64;
    return types.i64; // int32 mixed with uint32
}

llvm::Value* CodeGen::emitIntOp(BinOp op, llvm::Value* l, llvm::Value* r, Type* t)
{
    bool isSigned = t->isSigned;
    llvm::Type* ty = l->getType();
    unsigned bits = ty->getIntegerBitWidth();

    switch (op)
    {
    case BinOp::Add:
    case BinOp::Sub:
    case BinOp::Mul:
    {
        if (!fs->checked)
        {
            if (op == BinOp::Add)
                return builder.CreateAdd(l, r);
            if (op == BinOp::Sub)
                return builder.CreateSub(l, r);
            return builder.CreateMul(l, r);
        }
        llvm::Intrinsic::ID id;
        if (op == BinOp::Add)
            id = isSigned ? llvm::Intrinsic::sadd_with_overflow : llvm::Intrinsic::uadd_with_overflow;
        else if (op == BinOp::Sub)
            id = isSigned ? llvm::Intrinsic::ssub_with_overflow : llvm::Intrinsic::usub_with_overflow;
        else
            id = isSigned ? llvm::Intrinsic::smul_with_overflow : llvm::Intrinsic::umul_with_overflow;
        llvm::Value* res = builder.CreateBinaryIntrinsic(id, l, r);
        llvm::Value* value = builder.CreateExtractValue(res, {0});
        llvm::Value* overflow = builder.CreateExtractValue(res, {1});
        emitPanicIf(overflow, "integer overflow");
        return value;
    }
    case BinOp::Div:
    case BinOp::Rem:
    {
        emitPanicIf(builder.CreateICmpEQ(r, llvm::ConstantInt::get(ty, 0)), "division by zero");
        if (isSigned)
        {
            llvm::Value* isMin = builder.CreateICmpEQ(l, llvm::ConstantInt::get(ty, llvm::APInt::getSignedMinValue(bits)));
            llvm::Value* isMinusOne = builder.CreateICmpEQ(r, llvm::ConstantInt::getSigned(ty, -1));
            emitPanicIf(builder.CreateAnd(isMin, isMinusOne), "integer overflow");
            return op == BinOp::Div ? builder.CreateSDiv(l, r) : builder.CreateSRem(l, r);
        }
        return op == BinOp::Div ? builder.CreateUDiv(l, r) : builder.CreateURem(l, r);
    }
    case BinOp::BitAnd: return builder.CreateAnd(l, r);
    case BinOp::BitOr: return builder.CreateOr(l, r);
    case BinOp::BitXor: return builder.CreateXor(l, r);
    case BinOp::Shl:
    case BinOp::Shr:
    {
        llvm::Value* count = builder.CreateAnd(r, llvm::ConstantInt::get(ty, bits - 1));
        if (op == BinOp::Shl)
            return builder.CreateShl(l, count);
        return isSigned ? builder.CreateAShr(l, count) : builder.CreateLShr(l, count);
    }
    default: break;
    }
    err(SourceLoc{}, "internal error: invalid integer operation");
}

Value CodeGen::emitArithmetic(BinOp op, Value l, Value r, SourceLoc loc)
{
    l = l.isLValue ? toRValue(l) : l;
    r = r.isLValue ? toRValue(r) : r;

    // String concatenation (the other operand may be any primitive).
    if (op == BinOp::Add && (l.type->isString() || r.type->isString()))
    {
        auto asString = [&](Value& v) {
            if (v.type->isString() || v.type->kind == TypeKind::Null)
            {
                if (v.type->kind == TypeKind::Null)
                    return Value::rvalue(types.stringTy, llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(ctx)));
                return v;
            }
            return Value::rvalue(types.stringTy, emitToString(v, loc), true);
        };
        Value a = asString(l);
        Value b = asString(r);
        holdTemp(a);
        holdTemp(b);
        llvm::Value* res = builder.CreateCall(concatFn(), {a.v, b.v});
        return Value::rvalue(types.stringTy, res, true);
    }

    // Pointer arithmetic.
    if (l.type->isPointer() || r.type->isPointer())
    {
        requireUnsafe(loc, "pointer arithmetic");
        if (l.type->isPointer() && r.type->isPointer() && op == BinOp::Sub && l.type == r.type && !l.type->elem->isVoid())
        {
            llvm::Value* diff = builder.CreatePtrDiff(llvmTypeOf(l.type->elem), l.v, r.v);
            return Value::rvalue(types.i64, diff);
        }
        Value ptr = l.type->isPointer() ? l : r;
        Value off = l.type->isPointer() ? r : l;
        if ((op == BinOp::Add || (op == BinOp::Sub && l.type->isPointer())) && off.type->isIntegral() &&
            !ptr.type->elem->isVoid())
        {
            llvm::Value* n = numericConvert(off.v, off.type, off.type->isSigned ? types.i64 : types.u64);
            if (op == BinOp::Sub)
                n = builder.CreateNeg(n);
            return Value::rvalue(ptr.type, builder.CreateGEP(llvmTypeOf(ptr.type->elem), ptr.v, {n}));
        }
        err(loc, "invalid pointer arithmetic");
    }

    // Bit operations on enums and bools.
    if (l.type == r.type && (op == BinOp::BitAnd || op == BinOp::BitOr || op == BinOp::BitXor))
    {
        if (l.type->isEnum() || l.type->isBool())
        {
            llvm::Value* res = op == BinOp::BitAnd ? builder.CreateAnd(l.v, r.v)
                               : op == BinOp::BitOr ? builder.CreateOr(l.v, r.v)
                                                    : builder.CreateXor(l.v, r.v);
            return Value::rvalue(l.type, res);
        }
    }

    if (!l.type->isNumeric() || !r.type->isNumeric())
    {
        static const char* names[] = {"+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>"};
        err(loc, std::string("operator '") + names[(int)op] + "' cannot be applied to '" + l.type->name + "' and '" +
                     r.type->name + "'");
    }

    // Shifts: the result has the (promoted) type of the left operand.
    if (op == BinOp::Shl || op == BinOp::Shr)
    {
        if (!l.type->isIntegral() || !r.type->isIntegral())
            err(loc, "shift operators require integer operands");
        Type* t = promoteTypes(l.type, l.type, loc);
        Value lv = convertValue(l.hasLit ? adaptLiteral(l, t) : l, t, loc);
        llvm::Value* count = numericConvert(r.v, r.type, t);
        return Value::rvalue(t, emitIntOp(op, lv.v, count, t));
    }

    // Adapt literals to the other operand's type.
    if (l.hasLit && !r.hasLit)
        l = adaptLiteral(l, r.type);
    else if (r.hasLit && !l.hasLit)
        r = adaptLiteral(r, l.type);

    Type* t = promoteTypes(l.type, r.type, loc);
    Value lv = convertValue(l, t, loc);
    Value rv = convertValue(r, t, loc);

    if (t->isFloat())
    {
        llvm::Value* res;
        switch (op)
        {
        case BinOp::Add: res = builder.CreateFAdd(lv.v, rv.v); break;
        case BinOp::Sub: res = builder.CreateFSub(lv.v, rv.v); break;
        case BinOp::Mul: res = builder.CreateFMul(lv.v, rv.v); break;
        case BinOp::Div: res = builder.CreateFDiv(lv.v, rv.v); break;
        case BinOp::Rem: res = builder.CreateFRem(lv.v, rv.v); break;
        default: err(loc, "bit operations are not defined for floating point values");
        }
        return Value::rvalue(t, res);
    }
    return Value::rvalue(t, emitIntOp(op, lv.v, rv.v, t));
}

Value CodeGen::emitCompare(BinOp op, Value l, Value r, SourceLoc loc)
{
    l = l.isLValue ? toRValue(l) : l;
    r = r.isLValue ? toRValue(r) : r;
    bool isEq = op == BinOp::Eq || op == BinOp::Ne;

    // A function name compared with a function value takes the function's type.
    if (l.type->kind == TypeKind::MethodGroup && r.type->isFunction())
        l = convertValue(l, r.type, loc);
    else if (r.type->kind == TypeKind::MethodGroup && l.type->isFunction())
        r = convertValue(r, l.type, loc);

    // Comparisons with null.
    if (l.type->kind == TypeKind::Null || r.type->kind == TypeKind::Null)
    {
        if (!isEq)
            err(loc, "null can only be compared with '==' and '!='");
        Value other = l.type->kind == TypeKind::Null ? r : l;
        llvm::Value* isNull;
        if (other.type->isPointer() || other.type->isString() || other.type->isArray() || other.type->isFunction())
            isNull = builder.CreateIsNull(other.v);
        else if (other.type->isOptional())
        {
            holdTemp(other);
            isNull = builder.CreateNot(builder.CreateExtractValue(other.v, {0}));
        }
        else if (other.type->kind == TypeKind::Null)
            isNull = builder.getTrue();
        else
            err(loc, "type '" + other.type->name + "' cannot be compared with null");
        return boolValue(op == BinOp::Eq ? isNull : builder.CreateNot(isNull));
    }

    // String equality.
    if (l.type->isString() && r.type->isString())
    {
        if (!isEq)
            err(loc, "strings can only be compared with '==' and '!='");
        holdTemp(l);
        holdTemp(r);
        llvm::Value* eq = builder.CreateCall(streqFn(), {l.v, r.v});
        return boolValue(op == BinOp::Eq ? eq : builder.CreateNot(eq));
    }

    if (l.hasLit && !r.hasLit)
        l = adaptLiteral(l, r.type);
    else if (r.hasLit && !l.hasLit)
        r = adaptLiteral(r, l.type);

    // Bool, enum, pointer.
    if (l.type == r.type && (l.type->isBool() || l.type->isEnum() || l.type->isPointer() || l.type->isFunction()))
    {
        if ((l.type->isBool() || l.type->isFunction()) && !isEq)
            err(loc, l.type->isBool() ? "bool values can only be compared with '==' and '!='"
                                      : "function values can only be compared with '==' and '!='");
        if (l.type->isPointer() && l.type->elem != r.type->elem)
            err(loc, "pointer types differ");
        bool isSigned = l.type->isEnum() && l.type->isSigned;
        llvm::CmpInst::Predicate pred;
        switch (op)
        {
        case BinOp::Eq: pred = llvm::CmpInst::ICMP_EQ; break;
        case BinOp::Ne: pred = llvm::CmpInst::ICMP_NE; break;
        case BinOp::Lt: pred = isSigned ? llvm::CmpInst::ICMP_SLT : llvm::CmpInst::ICMP_ULT; break;
        case BinOp::Gt: pred = isSigned ? llvm::CmpInst::ICMP_SGT : llvm::CmpInst::ICMP_UGT; break;
        case BinOp::Le: pred = isSigned ? llvm::CmpInst::ICMP_SLE : llvm::CmpInst::ICMP_ULE; break;
        default: pred = isSigned ? llvm::CmpInst::ICMP_SGE : llvm::CmpInst::ICMP_UGE; break;
        }
        return boolValue(builder.CreateICmp(pred, l.v, r.v));
    }

    if (!l.type->isNumeric() || !r.type->isNumeric())
        err(loc, "cannot compare '" + l.type->name + "' with '" + r.type->name + "'");

    Type* t = promoteTypes(l.type, r.type, loc);
    Value lv = convertValue(l, t, loc);
    Value rv = convertValue(r, t, loc);
    llvm::Value* res;
    if (t->isFloat())
    {
        switch (op)
        {
        case BinOp::Eq: res = builder.CreateFCmpOEQ(lv.v, rv.v); break;
        case BinOp::Ne: res = builder.CreateFCmpUNE(lv.v, rv.v); break;
        case BinOp::Lt: res = builder.CreateFCmpOLT(lv.v, rv.v); break;
        case BinOp::Gt: res = builder.CreateFCmpOGT(lv.v, rv.v); break;
        case BinOp::Le: res = builder.CreateFCmpOLE(lv.v, rv.v); break;
        default: res = builder.CreateFCmpOGE(lv.v, rv.v); break;
        }
    }
    else
    {
        bool s = t->isSigned;
        switch (op)
        {
        case BinOp::Eq: res = builder.CreateICmpEQ(lv.v, rv.v); break;
        case BinOp::Ne: res = builder.CreateICmpNE(lv.v, rv.v); break;
        case BinOp::Lt: res = s ? builder.CreateICmpSLT(lv.v, rv.v) : builder.CreateICmpULT(lv.v, rv.v); break;
        case BinOp::Gt: res = s ? builder.CreateICmpSGT(lv.v, rv.v) : builder.CreateICmpUGT(lv.v, rv.v); break;
        case BinOp::Le: res = s ? builder.CreateICmpSLE(lv.v, rv.v) : builder.CreateICmpULE(lv.v, rv.v); break;
        default: res = s ? builder.CreateICmpSGE(lv.v, rv.v) : builder.CreateICmpUGE(lv.v, rv.v); break;
        }
    }
    return boolValue(res);
}

Value CodeGen::emitCondition(Expr* e)
{
    Value v = emitRValue(e);
    if (v.type->isBool())
        return v;
    if (v.type->isResultLike())
    {
        holdTemp(v);
        return boolValue(builder.CreateExtractValue(v.v, {0}));
    }
    err(e->loc, "a condition must be of type 'bool', not '" + v.type->name + "' (there is no implicit conversion to bool)");
}

Value CodeGen::emitLogical(BinaryExpr* e)
{
    bool isAnd = e->op == BinOp::LogAnd;
    Value l = emitCondition(e->lhs.get());
    llvm::BasicBlock* lhsEnd = builder.GetInsertBlock();
    llvm::BasicBlock* rhsBB = newBlock(isAnd ? "and.rhs" : "or.rhs");
    llvm::BasicBlock* endBB = newBlock(isAnd ? "and.end" : "or.end");
    if (isAnd)
        builder.CreateCondBr(l.v, rhsBB, endBB);
    else
        builder.CreateCondBr(l.v, endBB, rhsBB);

    setBlock(rhsBB);
    size_t mark = fs->temps.size();
    Value r = emitCondition(e->rhs.get());
    flushTemps(mark);
    llvm::BasicBlock* rhsEnd = builder.GetInsertBlock();
    builder.CreateBr(endBB);

    setBlock(endBB);
    llvm::PHINode* phi = builder.CreatePHI(builder.getInt1Ty(), 2);
    phi->addIncoming(builder.getInt1(!isAnd), lhsEnd);
    phi->addIncoming(r.v, rhsEnd);
    return boolValue(phi);
}

Value CodeGen::emitBinary(BinaryExpr* e)
{
    if (e->op == BinOp::LogAnd || e->op == BinOp::LogOr)
        return emitLogical(e);

    Value l = emitRValue(e->lhs.get());
    Value r = emitRValue(e->rhs.get());
    switch (e->op)
    {
    case BinOp::Eq: case BinOp::Ne: case BinOp::Lt: case BinOp::Gt: case BinOp::Le: case BinOp::Ge:
        return emitCompare(e->op, l, r, e->loc);
    default:
        return emitArithmetic(e->op, l, r, e->loc);
    }
}

Value CodeGen::emitUnary(UnaryExpr* e)
{
    switch (e->op)
    {
    case UnOp::Deref:
        return derefPointer(emitExpr(e->operand.get()), e->loc);
    case UnOp::AddrOf:
    {
        requireUnsafe(e->loc, "taking an address");
        Value o = emitExpr(e->operand.get());
        if (!o.isLValue)
            err(e->loc, "cannot take the address of a temporary value");
        return Value::rvalue(types.pointerTo(o.type), o.v);
    }
    case UnOp::Neg:
    case UnOp::Plus:
    {
        Value v = emitRValue(e->operand.get());
        if (v.hasLit && e->op == UnOp::Neg)
        {
            Value r;
            if (v.litIsFloat)
            {
                r = Value::rvalue(v.type, llvm::ConstantFP::get(llvmTypeOf(v.type), -v.litFloat));
                r.hasLit = true;
                r.litIsFloat = true;
                r.litFloat = -v.litFloat;
                return r;
            }
            int64_t n = -v.litInt;
            Type* t = (n >= INT32_MIN && n <= INT32_MAX) ? types.i32 : types.i64;
            r = constInt(t, n);
            r.hasLit = true;
            r.litInt = n;
            return r;
        }
        if (!v.type->isNumeric())
            err(e->loc, "unary '-' cannot be applied to '" + v.type->name + "'");
        Type* t = v.type->isFloat() ? v.type : promoteTypes(v.type, v.type, e->loc);
        Value c = convertValue(v, t, e->loc);
        if (e->op == UnOp::Plus)
            return c;
        if (t->isFloat())
            return Value::rvalue(t, builder.CreateFNeg(c.v));
        if (!t->isSigned)
            err(e->loc, "unary '-' cannot be applied to unsigned type '" + t->name + "'");
        return Value::rvalue(t, emitIntOp(BinOp::Sub, llvm::ConstantInt::get(c.v->getType(), 0), c.v, t));
    }
    case UnOp::Not:
    {
        Value v = emitRValue(e->operand.get());
        if (v.type->isBool())
            return boolValue(builder.CreateNot(v.v));
        if (v.type->isResultLike())
        {
            holdTemp(v);
            return boolValue(builder.CreateNot(builder.CreateExtractValue(v.v, {0})));
        }
        err(e->loc, "operator '!' cannot be applied to '" + v.type->name + "'");
    }
    case UnOp::BitNot:
    {
        Value v = emitRValue(e->operand.get());
        if (v.type->isEnum())
            return Value::rvalue(v.type, builder.CreateNot(v.v));
        if (!v.type->isIntegral())
            err(e->loc, "operator '~' cannot be applied to '" + v.type->name + "'");
        Type* t = promoteTypes(v.type, v.type, e->loc);
        Value c = convertValue(v, t, e->loc);
        return Value::rvalue(t, builder.CreateNot(c.v));
    }
    }
    err(e->loc, "internal error: unknown unary operator");
}

// ---------------------------------------------------------------------------
// Assignment, conditional, casts
// ---------------------------------------------------------------------------

Value CodeGen::emitAssign(AssignExpr* e)
{
    Value target = emitExpr(e->target.get());
    if (!target.isLValue)
        err(e->loc, "the left side of an assignment must be a variable, field or element");
    if (target.isConst)
        err(e->loc, "cannot assign to a read-only value ('const ref' parameter)");

    Value val;
    if (e->op)
    {
        Value cur = toRValue(target);
        Value rhs = emitRValue(e->value.get());
        Value res = emitArithmetic(*e->op, cur, rhs, e->loc);
        if (res.type == target.type)
            val = res;
        else if (res.type->isNumeric() && target.type->isNumeric())
            val = Value::rvalue(target.type, numericConvert(res.v, res.type, target.type));
        else
            val = convertValue(res, target.type, e->loc);
    }
    else
    {
        Value rhs = emitRValue(e->value.get());
        val = convertValue(rhs, target.type, e->value->loc);
    }

    llvm::Value* nv = consume(val);
    storeSlot(target.type, target.v, nv, true);
    return Value::lvalue(target.type, target.v);
}

Value CodeGen::emitConditional(CondExpr* e)
{
    Value c = emitCondition(e->cond.get());
    llvm::BasicBlock* thenBB = newBlock("cond.then");
    llvm::BasicBlock* elseBB = newBlock("cond.else");
    llvm::BasicBlock* endBB = newBlock("cond.end");
    builder.CreateCondBr(c.v, thenBB, elseBB);

    size_t base = fs->temps.size();

    setBlock(thenBB);
    Value a = emitRValue(e->thenExpr.get());
    llvm::BasicBlock* thenEnd = builder.GetInsertBlock();
    std::vector<TempRelease> thenTemps(fs->temps.begin() + base, fs->temps.end());
    fs->temps.resize(base);

    setBlock(elseBB);
    Value b = emitRValue(e->elseExpr.get());
    llvm::BasicBlock* elseEnd = builder.GetInsertBlock();
    std::vector<TempRelease> elseTemps(fs->temps.begin() + base, fs->temps.end());
    fs->temps.resize(base);

    // Determine the common type.
    Type* t;
    if (a.type == b.type)
        t = a.type;
    else if (conversionCost(a, b.type) >= 0 && (conversionCost(b, a.type) < 0 || a.hasLit))
        t = b.type;
    else if (conversionCost(b, a.type) >= 0)
        t = a.type;
    else
        err(e->loc, "the branches of '?:' have incompatible types '" + a.type->name + "' and '" + b.type->name + "'");
    if (t->kind == TypeKind::Null)
        err(e->loc, "cannot infer the type of a conditional expression with only null");
    if (t->isVoid())
        err(e->loc, "conditional branches cannot be void");

    auto releaseAll = [&](const std::vector<TempRelease>& list) {
        for (size_t i = list.size(); i > 0; i -= 1)
            emitReleaseValue(list[i - 1].type, list[i - 1].value);
    };

    // Finish the else branch (currently positioned at its end).
    builder.SetInsertPoint(elseEnd);
    llvm::Value* bv = consume(convertValue(b, t, e->elseExpr->loc));
    releaseAll(elseTemps);
    llvm::BasicBlock* elseFinal = builder.GetInsertBlock();
    builder.CreateBr(endBB);

    builder.SetInsertPoint(thenEnd);
    llvm::Value* av = consume(convertValue(a, t, e->thenExpr->loc));
    releaseAll(thenTemps);
    llvm::BasicBlock* thenFinal = builder.GetInsertBlock();
    builder.CreateBr(endBB);

    setBlock(endBB);
    llvm::PHINode* phi = builder.CreatePHI(llvmTypeOf(t), 2);
    phi->addIncoming(av, thenFinal);
    phi->addIncoming(bv, elseFinal);
    return Value::rvalue(t, phi, needsArc(t));
}

Value CodeGen::emitCast(CastExpr* e)
{
    Type* to = declTypeOf(*e->type);
    Value v = emitRValue(e->operand.get());
    Type* from = v.type;
    if (from == to)
        return v;
    if (conversionCost(v, to) >= 0)
        return convertValue(v, to, e->loc);

    auto numeric = [](Type* t) { return t->isInt() || t->isChar() || t->isEnum() || t->isFloat(); };
    if (numeric(from) && numeric(to))
    {
        if (from->isEnum() && to->isFloat())
            err(e->loc, "cannot cast an enum to a floating point type");
        return Value::rvalue(to, numericConvert(v.v, from, to));
    }
    if (from->isPointer() && to->isPointer())
    {
        requireUnsafe(e->loc, "pointer cast");
        return Value::rvalue(to, v.v);
    }
    // Function pointers and data pointers convert into each other (for C callbacks that are passed as void*).
    if ((from->isFunction() && to->isPointer()) || (from->isPointer() && to->isFunction()))
    {
        requireUnsafe(e->loc, "pointer cast");
        return Value::rvalue(to, v.v);
    }
    if (from->isPointer() && to->isInt())
    {
        requireUnsafe(e->loc, "pointer cast");
        return Value::rvalue(to, builder.CreateZExtOrTrunc(builder.CreatePtrToInt(v.v, sizeTy()), llvmTypeOf(to)));
    }
    if (from->isInt() && to->isPointer())
    {
        requireUnsafe(e->loc, "pointer cast");
        return Value::rvalue(to, builder.CreateIntToPtr(builder.CreateSExtOrTrunc(v.v, sizeTy()), llvmTypeOf(to)));
    }
    err(e->loc, "cannot cast '" + from->name + "' to '" + to->name + "'");
}

// ---------------------------------------------------------------------------
// Object creation
// ---------------------------------------------------------------------------

Value CodeGen::emitNewArray(NewArrayExpr* e)
{
    Type* elem = declTypeOf(*e->elemType);
    if (elem->isVoid())
        err(e->loc, "cannot create an array of 'void'");
    Type* arrT = types.arrayOf(elem);
    llvm::Type* elemTy = llvmTypeOf(elem);
    unsigned esize = sizeOf(elem);

    if (e->hasInit)
    {
        if (e->size)
        {
            if (e->size->kind != ExprKind::IntLit || static_cast<IntLitExpr*>(e->size.get())->value != e->init.size())
                err(e->loc, "the array size must match the number of initializers");
        }
        uint64_t n = e->init.size();
        llvm::Value* arr = builder.CreateCall(allocFn(), {builder.getInt64(n * esize), builder.getInt64(n)});
        for (uint64_t i = 0; i < n; i += 1)
        {
            Value v = convertValue(emitRValue(e->init[i].get()), elem, e->init[i]->loc);
            llvm::Value* nv = consume(v);
            llvm::Value* slot = builder.CreateGEP(elemTy, dataPtr(arr), {builder.getInt64(i)});
            builder.CreateStore(nv, slot);
        }
        return Value::rvalue(arrT, arr, true);
    }

    Value sz = emitRValue(e->size.get());
    if (!sz.type->isIntegral())
        err(e->size->loc, "the array size must be an integer");
    llvm::Value* n = numericConvert(sz.v, sz.type, sz.type->isSigned ? types.i64 : types.u64);
    if (sz.type->isSigned)
        emitPanicIf(builder.CreateICmpSLT(n, builder.getInt64(0)), "negative array length");
    llvm::Value* bytes = builder.CreateMul(n, builder.getInt64(esize));
    return Value::rvalue(arrT, builder.CreateCall(allocFn(), {bytes, n}), true);
}

Value CodeGen::emitStructInit(StructInitExpr* e)
{
    Type* t = declTypeOf(*e->type);
    if (!t->isStruct())
        err(e->loc, "'" + t->name + "' is not a struct, initializers are only available for structs");

    llvm::Value* agg = zeroValue(t);
    std::set<std::string> seen;
    for (auto& f : e->fields)
    {
        FieldPath p;
        if (!findField(t, f.name, p))
            err(f.loc, "struct '" + t->name + "' has no field '" + f.name + "'");
        if (p.isPrivate && fs->func->owner != p.owner)
            err(f.loc, "field '" + f.name + "' is private to '" + p.owner->name + "'");
        if (!seen.insert(f.name).second)
            err(f.loc, "field '" + f.name + "' is initialized twice");
        Value v = convertValue(emitRValue(f.value.get()), p.type, f.value->loc);
        agg = builder.CreateInsertValue(agg, consume(v), p.indices);
    }
    return Value::rvalue(t, agg, needsArc(t));
}

Value CodeGen::emitErrorLit(ErrorLitExpr* e)
{
    Value m = emitRValue(e->message.get());
    Value msg = convertValue(m, types.stringTy, e->message->loc);
    llvm::Value* codeV = builder.getInt32(0);
    if (e->code)
    {
        Value c = convertValue(emitRValue(e->code.get()), types.i32, e->code->loc);
        codeV = c.v;
    }
    llvm::Value* msgOwned = consume(msg);
    llvm::Value* agg = llvm::Constant::getNullValue(llvmTypeOf(types.errorLitTy));
    agg = builder.CreateInsertValue(agg, msgOwned, {0});
    agg = builder.CreateInsertValue(agg, codeV, {1});
    return Value::rvalue(types.errorLitTy, agg, true);
}

// ---------------------------------------------------------------------------
// Error<T> / Optional<T>: 'is' and 'try'
// ---------------------------------------------------------------------------

Value CodeGen::emitIs(IsExpr* e)
{
    Value subj = emitRValue(e->operand.get());
    if (!subj.type->isResultLike())
        err(e->loc, "'is' can only be used with Error<T> and Optional<T> values, not '" + subj.type->name + "'");
    Type* pattern = declTypeOf(*e->type);
    // "x is T v" tests for a value of the payload type, "x is Error<T> r" always matches and binds the whole result.
    bool whole = pattern == subj.type;
    if (!whole && pattern != subj.type->elem)
        err(e->type->loc, "pattern type '" + pattern->name + "' does not match the payload type '" +
                              subj.type->elem->name + "' of '" + subj.type->name + "'");

    llvm::Value* flag = whole ? (llvm::Value*)builder.getTrue() : builder.CreateExtractValue(subj.v, {0});
    if (!e->bindName.empty())
    {
        // Payload is zero when there is no value, so the binding is unconditionally assigned.
        llvm::Value* payload = whole ? subj.v : builder.CreateExtractValue(subj.v, {1});
        llvm::AllocaInst* slot = entryAlloca(llvmTypeOf(pattern), e->bindName);
        {
            llvm::IRBuilder<> b(slot->getNextNode());
            b.CreateStore(llvm::Constant::getNullValue(llvmTypeOf(pattern)), slot);
        }
        ScopeVar& var = declareVar(e->bindName, pattern, slot);
        var.resetOnCleanup = true;
        if (needsArc(pattern) && !subj.owned)
            emitRetainValue(pattern, payload);
        // If the subject was an owned temporary, its payload reference moves into the binding.
        storeSlot(pattern, slot, payload, true);
        if (subj.owned && needsArc(subj.type) && !whole)
        {
            // Release what remains of the subject (the error message); the payload moved out.
            if (subj.type->isError())
                emitReleaseValue(types.stringTy, builder.CreateExtractValue(subj.v, {2}));
        }
    }
    else
    {
        holdTemp(subj);
    }
    return boolValue(flag);
}

Value CodeGen::emitTry(TryExpr* e)
{
    Value subj = emitRValue(e->operand.get());
    if (!subj.type->isError())
        err(e->loc, "'try' can only be used with Error<T> values, not '" + subj.type->name + "'");

    bool intMain = fs->isIntMain;
    if (!fs->retType->isError() && !intMain)
        err(e->loc, "'try' can only be used in a function that returns Error<T>");

    llvm::Value* flag = builder.CreateExtractValue(subj.v, {0});
    llvm::BasicBlock* okBB = newBlock("try.ok");
    llvm::BasicBlock* failBB = newBlock("try.fail");
    builder.CreateCondBr(flag, okBB, failBB);

    setBlock(failBB);
    llvm::Value* msg = builder.CreateExtractValue(subj.v, {2});
    llvm::Value* code = builder.CreateExtractValue(subj.v, {3});
    if (!subj.owned)
        emitRetainValue(types.stringTy, msg); // the returned error owns its message
    // Release temporaries of the current statement and all live locals, then return.
    flushTemps(0, false);
    emitCleanupsDownTo(0);
    if (intMain)
    {
        llvm::FunctionCallee fprintfFn = cFunction("fprintf", builder.getInt32Ty(),
                                                   {llvm::PointerType::getUnqual(ctx), llvm::PointerType::getUnqual(ctx)}, true);
        builder.CreateCall(fprintfFn, {stderrHandle(builder), cString("error: %s\n"), builder.CreateCall(dataFn(), {msg})});
        builder.CreateRet(builder.getInt32(1));
    }
    else
    {
        builder.CreateRet(makeErr(fs->retType, msg, code));
    }

    setBlock(okBB);
    if (subj.type->elem->isVoid())
        return Value::rvalue(types.voidTy, nullptr);
    llvm::Value* payload = builder.CreateExtractValue(subj.v, {1});
    return Value::rvalue(subj.type->elem, payload, subj.owned && needsArc(subj.type->elem));
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

Value CodeGen::emitExpr(Expr* e)
{
    switch (e->kind)
    {
    case ExprKind::IntLit:
    case ExprKind::FloatLit:
    case ExprKind::CharLit:
    case ExprKind::StringLit:
    case ExprKind::BoolLit:
    case ExprKind::NullLit: return emitLiteral(e);
    case ExprKind::Name: return emitName(static_cast<NameExpr*>(e));
    case ExprKind::Member: return emitMember(static_cast<MemberExpr*>(e));
    case ExprKind::Call: return emitCall(static_cast<CallExpr*>(e));
    case ExprKind::Index: return emitIndex(static_cast<IndexExpr*>(e));
    case ExprKind::Unary: return emitUnary(static_cast<UnaryExpr*>(e));
    case ExprKind::Binary: return emitBinary(static_cast<BinaryExpr*>(e));
    case ExprKind::Assign: return emitAssign(static_cast<AssignExpr*>(e));
    case ExprKind::Conditional: return emitConditional(static_cast<CondExpr*>(e));
    case ExprKind::Cast: return emitCast(static_cast<CastExpr*>(e));
    case ExprKind::NewArray: return emitNewArray(static_cast<NewArrayExpr*>(e));
    case ExprKind::NewObject:
    {
        Type* t = declTypeOf(*static_cast<NewObjectExpr*>(e)->type);
        if (!t->isStruct())
            err(e->loc, "'new " + t->name + "()' is only valid for structs");
        if (t->st->opaque)
            err(e->loc, "'" + t->name + "' is an incomplete C type and can only be used through a pointer");
        return Value::rvalue(t, zeroValue(t), needsArc(t));
    }
    case ExprKind::StructInit: return emitStructInit(static_cast<StructInitExpr*>(e));
    case ExprKind::Is: return emitIs(static_cast<IsExpr*>(e));
    case ExprKind::Try: return emitTry(static_cast<TryExpr*>(e));
    case ExprKind::ErrorLit: return emitErrorLit(static_cast<ErrorLitExpr*>(e));
    case ExprKind::Default:
    {
        Type* t = declTypeOf(*static_cast<DefaultExpr*>(e)->type);
        if (t->isVoid())
            err(e->loc, "default(void) is not defined");
        return Value::rvalue(t, zeroValue(t));
    }
    case ExprKind::SizeOf:
    {
        Type* t = declTypeOf(*static_cast<SizeOfExpr*>(e)->type);
        if (t->isVoid())
            err(e->loc, "sizeof(void) is not defined");
        return constInt(types.i32, sizeOf(t));
    }
    case ExprKind::This: return thisValue(e->loc);
    case ExprKind::Unchecked:
    {
        bool old = fs->checked;
        fs->checked = false;
        Value v = emitExpr(static_cast<UncheckedExpr*>(e)->operand.get());
        fs->checked = old;
        return v;
    }
    case ExprKind::RefArg:
    {
        Value v = emitExpr(static_cast<RefArgExpr*>(e)->operand.get());
        if (!v.isLValue)
            err(e->loc, "'ref' requires a variable, field or element");
        v.isRefArg = true;
        return v;
    }
    }
    err(e->loc, "internal error: unknown expression");
}
