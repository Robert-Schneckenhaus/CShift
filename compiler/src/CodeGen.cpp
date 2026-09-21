#include "CodeGen.h"

#include <algorithm>

#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/TargetParser/Triple.h>

CodeGen::CodeGen(Diagnostics& diag, const std::string& moduleName)
    : diag(diag), mod(new llvm::Module(moduleName, ctx)), builder(ctx)
{
    namespaces.insert("System");
}

void CodeGen::setDataLayout(const llvm::DataLayout& dl)
{
    mod->setDataLayout(dl);
    // nint/nuint have the size of a pointer on the target.
    types.nint->bits = types.nuint->bits = (int)dl.getPointerSizeInBits();
}

void CodeGen::setTargetTriple(const std::string& triple)
{
    mod->setTargetTriple(llvm::Triple(triple));
}

// ---------------------------------------------------------------------------
// Symbol registration and lookup
// ---------------------------------------------------------------------------

void CodeGen::addUnit(std::unique_ptr<CompilationUnit> unit)
{
    CompilationUnit& u = *unit;
    units.push_back(std::move(unit));
    registerUnit(u);
}

std::string CodeGen::qualified(FileContext* f, const std::string& name) const
{
    return f->ns.empty() ? name : f->ns + "." + name;
}

void CodeGen::registerUnit(CompilationUnit& u)
{
    if (!u.file.ns.empty())
    {
        std::string prefix;
        size_t start = 0;
        while (start <= u.file.ns.size())
        {
            size_t dot = u.file.ns.find('.', start);
            std::string part = u.file.ns.substr(start, dot == std::string::npos ? std::string::npos : dot - start);
            prefix += (prefix.empty() ? "" : ".") + part;
            namespaces.insert(prefix);
            if (dot == std::string::npos)
                break;
            start = dot + 1;
        }
    }

    auto addType = [&](const std::string& name, SourceLoc loc, const TypeDeclEntry& entry) {
        std::string q = qualified(&u.file, name);
        if (typeDecls.count(q))
        {
            diag.error(loc, "type '" + q + "' is already defined");
            return;
        }
        typeDecls[q] = entry;
    };

    for (auto& s : u.structs)
    {
        TypeDeclEntry e;
        e.kind = TypeDeclEntry::Struct;
        e.structDecl = s.get();
        addType(s->name, s->loc, e);
    }
    for (auto& i : u.interfaces)
    {
        TypeDeclEntry e;
        e.kind = TypeDeclEntry::Interface;
        e.interfaceDecl = i.get();
        addType(i->name, i->loc, e);
    }
    for (auto& en : u.enums)
    {
        TypeDeclEntry e;
        e.kind = TypeDeclEntry::Enum;
        e.enumDecl = en.get();
        addType(en->name, en->loc, e);
    }
    for (auto& f : u.funcs)
        funcDecls[qualified(&u.file, f->name)].push_back(f.get());
    for (auto& c : u.consts)
    {
        std::string q = qualified(&u.file, c->name);
        if (constDecls.count(q))
            diag.error(c->loc, "constant '" + q + "' is already defined");
        else
            constDecls[q] = c.get();
    }

    for (auto& l : u.links)
        links.push_back(l);
}

std::vector<std::string> CodeGen::candidateNames(FileContext* f, const std::string& name) const
{
    std::vector<std::string> out;
    std::string ns = f->ns;
    while (!ns.empty())
    {
        out.push_back(ns + "." + name);
        size_t dot = ns.rfind('.');
        ns = dot == std::string::npos ? "" : ns.substr(0, dot);
    }
    // Like C#: the file's own namespaces and the global namespace win over 'using' directives.
    out.push_back(name);
    for (const auto& u : f->usings)
        out.push_back(u + "." + name);
    return out;
}

const TypeDeclEntry* CodeGen::lookupTypeDecl(FileContext* f, const std::string& name) const
{
    for (const auto& c : candidateNames(f, name))
    {
        auto it = typeDecls.find(c);
        if (it != typeDecls.end())
            return &it->second;
    }
    return nullptr;
}

std::vector<FuncDecl*> CodeGen::lookupFunctions(FileContext* f, const std::string& name) const
{
    std::vector<FuncDecl*> out;
    std::unordered_set<FuncDecl*> seen;
    for (const auto& c : candidateNames(f, name))
    {
        auto it = funcDecls.find(c);
        if (it == funcDecls.end())
            continue;
        for (FuncDecl* d : it->second)
            if (seen.insert(d).second)
                out.push_back(d);
    }
    return out;
}

bool CodeGen::isNamespace(FileContext* f, const std::string& name) const
{
    for (const auto& c : candidateNames(f, name))
        if (namespaces.count(c))
            return true;
    return false;
}

Type* CodeGen::primitiveType(const std::string& name)
{
    static const std::unordered_map<std::string, int> ids = {
        {"int", 0},    {"int32", 0},  {"uint", 1},   {"uint32", 1}, {"float", 2},  {"float32", 2},
        {"double", 3}, {"float64", 3}, {"int8", 4},  {"int16", 5},  {"int64", 6},  {"uint8", 7},
        {"uint16", 8}, {"uint64", 9}, {"bool", 10},  {"char", 11},  {"string", 12}, {"void", 13},
        {"nint", 14},  {"nuint", 15}};
    auto it = ids.find(name);
    if (it == ids.end())
        return nullptr;
    TypeContext& t = types;
    switch (it->second)
    {
    case 0: return t.i32;
    case 1: return t.u32;
    case 2: return t.f32;
    case 3: return t.f64;
    case 4: return t.i8;
    case 5: return t.i16;
    case 6: return t.i64;
    case 7: return t.u8;
    case 8: return t.u16;
    case 9: return t.u64;
    case 10: return t.boolTy;
    case 11: return t.charTy;
    case 12: return t.stringTy;
    case 14: return t.nint;
    case 15: return t.nuint;
    default: return t.voidTy;
    }
}

// ---------------------------------------------------------------------------
// Type resolution
// ---------------------------------------------------------------------------

Type* CodeGen::resolveType(const TypeRef& ref, FileContext* file, const TypeEnv* env)
{
    switch (ref.kind)
    {
    case TypeRef::Pointer:
        return types.pointerTo(resolveType(*ref.elem, file, env));
    case TypeRef::Array:
    {
        Type* elem = resolveValueType(*ref.elem, file, env);
        if (elem->isVoid())
            err(ref.loc, "arrays of 'void' are not allowed");
        return types.arrayOf(elem);
    }
    case TypeRef::Named:
        break;
    }

    std::string dotted;
    for (size_t i = 0; i < ref.path.size(); i += 1)
        dotted += (i ? "." : "") + ref.path[i];

    if (ref.path.size() == 1)
    {
        if (env)
        {
            auto it = env->find(dotted);
            if (it != env->end())
                return it->second;
        }
        if (Type* p = primitiveType(dotted))
        {
            if (!ref.args.empty())
                err(ref.loc, "type '" + dotted + "' is not generic");
            return p;
        }
    }

    const TypeDeclEntry* entry = lookupTypeDecl(file, dotted);
    if (!entry && ref.path.size() == 1 && (dotted == "Error" || dotted == "Optional"))
    {
        if (ref.args.size() != 1)
            err(ref.loc, "'" + dotted + "' expects exactly one type argument");
        Type* inner = resolveValueType(*ref.args[0], file, env);
        if (inner->isResultLike())
            err(ref.loc, "Error<T> and Optional<T> cannot be nested (" + dotted + "<" + inner->name + ">)");
        // Error<void> is a result without a payload (success or error); Optional<void> makes no sense.
        if (inner->isVoid() && dotted != "Error")
            err(ref.loc, dotted + "<void> is not supported");
        return dotted == "Error" ? types.errorOf(inner) : types.optionalOf(inner);
    }
    if (!entry && ref.path.size() == 1 && (dotted == "Action" || dotted == "Func"))
        return resolveFunctionType(ref, dotted, file, env);
    if (!entry)
        err(ref.loc, "unknown type '" + ref.toString() + "'");

    std::vector<Type*> args;
    for (const auto& a : ref.args)
        args.push_back(resolveValueType(*a, file, env));

    switch (entry->kind)
    {
    case TypeDeclEntry::Struct: return getStructType(entry->structDecl, args, ref.loc);
    case TypeDeclEntry::Interface: return getInterfaceType(entry->interfaceDecl, args, ref.loc);
    case TypeDeclEntry::Enum:
        if (!args.empty())
            err(ref.loc, "enum '" + dotted + "' is not generic");
        return getEnumType(entry->enumDecl);
    }
    return nullptr;
}

// Action, Action<T1, ...> (no result) and Func<R>, Func<T1, ..., R> (last argument is the result) are pointers to
// functions, like delegates in C# but without closures: only named functions can be assigned to them.
static constexpr size_t kMaxFunctionParams = 8;

Type* CodeGen::resolveFunctionType(const TypeRef& ref, const std::string& dotted, FileContext* file, const TypeEnv* env)
{
    bool isAction = dotted == "Action";
    if (!isAction && ref.args.empty())
        err(ref.loc, "'Func' needs at least the result type: Func<TResult>, Func<TArg, TResult>, ...");
    std::vector<Type*> params;
    Type* ret = types.voidTy;
    for (size_t i = 0; i < ref.args.size(); i += 1)
    {
        Type* t = resolveValueType(*ref.args[i], file, env);
        if (!isAction && i + 1 == ref.args.size())
        {
            if (t->isVoid())
                err(ref.args[i]->loc, "use 'Action' for functions without a result, not Func<..., void>");
            ret = t;
            break;
        }
        if (t->isVoid())
            err(ref.args[i]->loc, "a function parameter cannot have type 'void'");
        params.push_back(t);
    }
    if (params.size() > kMaxFunctionParams)
        err(ref.loc, "'" + dotted + "' supports at most " + std::to_string(kMaxFunctionParams) + " parameters");
    return types.functionOf(params, ret);
}

Type* CodeGen::resolveValueType(const TypeRef& ref, FileContext* file, const TypeEnv* env)
{
    Type* t = resolveType(ref, file, env);
    if (t->kind == TypeKind::Interface)
        err(ref.loc, "interface '" + t->name + "' can only be used as a generic constraint or in a base list");
    return t;
}

Type* CodeGen::getStructType(StructDecl* decl, const std::vector<Type*>& args, SourceLoc loc)
{
    if (args.size() != decl->typeParams.size())
        err(loc, "struct '" + decl->name + "' expects " + std::to_string(decl->typeParams.size()) +
                     " type argument(s), got " + std::to_string(args.size()));

    std::string key = qualified(decl->file, decl->name);
    if (!args.empty())
    {
        key += "<";
        for (size_t i = 0; i < args.size(); i += 1)
            key += (i ? "," : "") + args[i]->name;
        key += ">";
    }
    auto it = structTypes.find(key);
    if (it != structTypes.end())
        return it->second;

    auto info = std::make_unique<StructInfo>();
    info->decl = decl;
    info->name = key;
    Type* t = types.create(TypeKind::Struct, key);
    t->st = info.get();
    info->type = t;
    for (size_t i = 0; i < args.size(); i += 1)
        info->env[decl->typeParams[i]] = args[i];
    info->llvmType = llvm::StructType::create(ctx, key);
    StructInfo& si = *info;
    structInfos.push_back(std::move(info));
    structTypes[key] = t;

    layoutStruct(si);
    checkConstraints(decl->constraints, si.env, decl->file, decl->loc);
    pendingVerify.push_back(&si);

    if (!decl->file->isPrelude)
    {
        for (auto& m : decl->methods)
        {
            if (!m->typeParams.empty())
                continue;
            try
            {
                useFunction(*getFuncInstance(m.get(), t, &si.env, decl->file, {}, m->loc));
            }
            catch (const CompileError& e)
            {
                diag.error(e);
            }
        }
    }
    return t;
}

void CodeGen::layoutStruct(StructInfo& si)
{
    StructDecl* decl = si.decl;
    si.layoutInProgress = true;
    try
    {
        std::vector<llvm::Type*> elems;

        if (decl->explicitLayout)
        {
            // A struct imported from a C header: the layout is exactly the one the C compiler chose. Fields are
            // placed at their offsets, everything else (arrays, bit fields, union members, padding) is filler.
            const llvm::DataLayout& dl = mod->getDataLayout();
            auto* i8 = llvm::Type::getInt8Ty(ctx);
            si.opaque = decl->opaque;

            std::vector<size_t> order(decl->fields.size());
            for (size_t i = 0; i < order.size(); i += 1)
                order[i] = i;
            std::sort(order.begin(), order.end(),
                      [&](size_t a, size_t b) { return decl->fields[a].offset < decl->fields[b].offset; });

            struct Placed
            {
                size_t field;
                Type* type;
                uint64_t size;
            };
            std::vector<Placed> placed;
            uint64_t maxAlign = 1;
            for (size_t idx : order)
            {
                auto& f = decl->fields[idx];
                Type* ft = resolveValueType(*f.type, decl->file, &si.env);
                if (ft->isVoid())
                    err(f.loc, "field '" + f.name + "' cannot have type 'void'");
                llvm::Type* lt = llvmTypeOf(ft);
                uint64_t align = dl.getABITypeAlign(lt).value();
                if ((uint64_t)f.offset % align != 0)
                    err(decl->loc, "struct '" + decl->name + "': field '" + f.name + "' is not naturally aligned (packed structs are not supported)");
                maxAlign = std::max(maxAlign, align);
                placed.push_back({idx, ft, dl.getTypeAllocSize(lt).getFixedValue()});
            }

            // An alignment that the fields do not imply (alignas, unions) comes from a zero-sized array in front.
            if (decl->layoutAlign > maxAlign)
                elems.push_back(llvm::ArrayType::get(llvm::Type::getIntNTy(ctx, (unsigned)(decl->layoutAlign * 8)), 0));

            uint64_t pos = 0;
            for (const Placed& p : placed)
            {
                auto& f = decl->fields[p.field];
                uint64_t offset = (uint64_t)f.offset;
                if (offset < pos)
                    err(decl->loc, "struct '" + decl->name + "': field '" + f.name + "' overlaps the previous field");
                if (offset > pos)
                    elems.push_back(llvm::ArrayType::get(i8, offset - pos));

                FieldInfo fi;
                fi.name = f.name;
                fi.type = p.type;
                fi.index = (unsigned)elems.size();
                elems.push_back(llvmTypeOf(p.type));
                si.fields.push_back(fi);
                pos = offset + p.size;
            }
            if (pos > decl->layoutSize)
                err(decl->loc, "struct '" + decl->name + "': the fields are larger than the struct");
            if (pos < decl->layoutSize)
                elems.push_back(llvm::ArrayType::get(i8, decl->layoutSize - pos));

            si.llvmType->setBody(elems);
            if (!decl->opaque && dl.getTypeAllocSize(si.llvmType).getFixedValue() != decl->layoutSize)
                err(decl->loc, "struct '" + decl->name + "': the layout does not match the C layout (size " +
                                   std::to_string(dl.getTypeAllocSize(si.llvmType).getFixedValue()) + " instead of " +
                                   std::to_string(decl->layoutSize) + ")");
            si.layoutInProgress = false;
            return;
        }

        for (size_t i = 0; i < decl->bases.size(); i += 1)
        {
            Type* b = resolveType(*decl->bases[i], decl->file, &si.env);
            if (b->isStruct())
            {
                if (i != 0)
                    err(decl->bases[i]->loc, "the base struct must be listed first");
                if (b->st->layoutInProgress)
                    err(decl->bases[i]->loc, "cyclic struct inheritance");
                si.base = b;
            }
            else if (b->kind == TypeKind::Interface)
            {
                si.interfaces.push_back(b);
            }
            else
            {
                err(decl->bases[i]->loc, "'" + b->name + "' is neither a struct nor an interface");
            }
        }
        if (si.base)
            elems.push_back(llvmTypeOf(si.base));

        for (auto& f : decl->fields)
        {
            Type* ft = resolveValueType(*f.type, decl->file, &si.env);
            if (ft->isVoid())
                err(f.loc, "field '" + f.name + "' cannot have type 'void'");
            for (const auto& other : si.fields)
                if (other.name == f.name)
                    err(f.loc, "field '" + f.name + "' is declared twice");
            FieldPath existing;
            if (si.base && findField(si.base, f.name, existing))
                err(f.loc, "field '" + f.name + "' hides an inherited field");

            FieldInfo fi;
            fi.name = f.name;
            fi.type = ft;
            fi.index = (unsigned)elems.size();
            fi.isPrivate = !f.name.empty() && f.name[0] == '_';
            elems.push_back(llvmTypeOf(ft));
            si.fields.push_back(fi);
        }
        si.llvmType->setBody(elems);
    }
    catch (CompileError& e)
    {
        si.layoutInProgress = false;
        if (e.loc.line == 0)
            e.loc = decl->loc;
        throw;
    }
    si.layoutInProgress = false;
}

Type* CodeGen::getInterfaceType(InterfaceDecl* decl, const std::vector<Type*>& args, SourceLoc loc)
{
    if (args.size() != decl->typeParams.size())
        err(loc, "interface '" + decl->name + "' expects " + std::to_string(decl->typeParams.size()) +
                     " type argument(s), got " + std::to_string(args.size()));
    std::string key = qualified(decl->file, decl->name);
    if (!args.empty())
    {
        key += "<";
        for (size_t i = 0; i < args.size(); i += 1)
            key += (i ? "," : "") + args[i]->name;
        key += ">";
    }
    auto it = interfaceTypes.find(key);
    if (it != interfaceTypes.end())
        return it->second;

    auto info = std::make_unique<InterfaceInfo>();
    info->decl = decl;
    info->name = key;
    Type* t = types.create(TypeKind::Interface, key);
    t->iface = info.get();
    info->type = t;
    for (size_t i = 0; i < args.size(); i += 1)
        info->env[decl->typeParams[i]] = args[i];
    interfaceInfos.push_back(std::move(info));
    interfaceTypes[key] = t;
    return t;
}

int64_t CodeGen::constEvalInt(Expr* e, EnumInfo* current, SourceLoc loc)
{
    switch (e->kind)
    {
    case ExprKind::IntLit: return (int64_t) static_cast<IntLitExpr*>(e)->value;
    case ExprKind::CharLit: return static_cast<CharLitExpr*>(e)->value;
    case ExprKind::Unary:
    {
        auto* u = static_cast<UnaryExpr*>(e);
        int64_t v = constEvalInt(u->operand.get(), current, loc);
        switch (u->op)
        {
        case UnOp::Neg: return -v;
        case UnOp::Plus: return v;
        case UnOp::BitNot: return ~v;
        default: break;
        }
        break;
    }
    case ExprKind::Binary:
    {
        auto* b = static_cast<BinaryExpr*>(e);
        int64_t l = constEvalInt(b->lhs.get(), current, loc);
        int64_t r = constEvalInt(b->rhs.get(), current, loc);
        switch (b->op)
        {
        case BinOp::Add: return l + r;
        case BinOp::Sub: return l - r;
        case BinOp::Mul: return l * r;
        case BinOp::Div:
            if (r == 0)
                err(e->loc, "division by zero in constant expression");
            return l / r;
        case BinOp::Rem:
            if (r == 0)
                err(e->loc, "division by zero in constant expression");
            return l % r;
        case BinOp::BitAnd: return l & r;
        case BinOp::BitOr: return l | r;
        case BinOp::BitXor: return l ^ r;
        case BinOp::Shl: return l << r;
        case BinOp::Shr: return l >> r;
        default: break;
        }
        break;
    }
    case ExprKind::Name:
    {
        auto* n = static_cast<NameExpr*>(e);
        if (current)
            for (const auto& m : current->members)
                if (m.first == n->name)
                    return m.second;
        break;
    }
    default: break;
    }
    err(e->loc.line ? e->loc : loc, "expected a constant integer expression");
}

static bool fitsInt(int64_t v, Type* t)
{
    if (t->bits >= 64)
        return t->isSigned || v >= 0;
    if (t->isSigned)
        return v >= -(int64_t(1) << (t->bits - 1)) && v < (int64_t(1) << (t->bits - 1));
    return v >= 0 && v < (int64_t(1) << t->bits);
}

Type* CodeGen::getEnumType(EnumDecl* decl)
{
    std::string key = qualified(decl->file, decl->name);
    auto it = enumTypes.find(key);
    if (it != enumTypes.end())
        return it->second;

    Type* base = resolveType(*decl->base, decl->file, nullptr);
    if (!base->isInt())
        err(decl->base->loc, "enum base type must be an integer type");

    auto info = std::make_unique<EnumInfo>();
    info->decl = decl;
    info->name = key;
    info->base = base;
    Type* t = types.create(TypeKind::Enum, key);
    t->bits = base->bits;
    t->isSigned = base->isSigned;
    t->elem = base;
    t->en = info.get();
    info->type = t;
    EnumInfo& ei = *info;
    enumInfos.push_back(std::move(info));
    enumTypes[key] = t;

    int64_t next = 0;
    for (auto& m : decl->members)
    {
        int64_t v = m.value ? constEvalInt(m.value.get(), &ei, m.loc) : next;
        if (!fitsInt(v, base))
            err(m.loc, "enum value " + std::to_string(v) + " does not fit into " + base->name);
        for (const auto& other : ei.members)
            if (other.first == m.name)
                err(m.loc, "enum member '" + m.name + "' is declared twice");
        ei.members.push_back({m.name, v});
        next = v + 1;
    }
    return t;
}

// ---------------------------------------------------------------------------
// Constraints and interfaces
// ---------------------------------------------------------------------------

bool CodeGen::structImplements(Type* structType, Type* iface)
{
    for (Type* t = structType; t; t = t->st->base)
        for (Type* i : t->st->interfaces)
            if (i == iface)
                return true;
    return false;
}

bool CodeGen::satisfiesInterface(Type* t, Type* iface)
{
    InterfaceInfo* ii = iface->iface;
    // Built-in types implement the standard interfaces of the prelude. Their methods are provided by the
    // compiler (numbers, bool, char, enums) or by the String namespace of the standard library (strings).
    if (ii->decl->file->isPrelude)
    {
        const std::string& name = ii->decl->name;
        auto it = ii->env.find("T");
        bool selfArg = it != ii->env.end() && it->second == t;
        bool primitive = t->isNumeric() || t->isBool() || t->isString() || t->isEnum();
        if (name == "IComparable" && (t->isNumeric() || t->isString()))
            return selfArg;
        if (name == "IEquatable" && primitive)
            return selfArg;
        if (name == "IHashable" && primitive)
            return true;
    }
    if (t->isStruct())
        return structImplements(t, iface);
    return false;
}

void CodeGen::checkConstraints(const std::vector<Constraint>& constraints, const TypeEnv& env, FileContext* file,
                               SourceLoc loc)
{
    for (const auto& c : constraints)
    {
        auto it = env.find(c.param);
        if (it == env.end())
            err(loc, "constraint refers to unknown type parameter '" + c.param + "'");
        for (const auto& b : c.bounds)
        {
            Type* bound = resolveType(*b, file, &env);
            if (bound->kind != TypeKind::Interface)
                err(b->loc, "a constraint must be an interface, but '" + bound->name + "' is not");
            if (!satisfiesInterface(it->second, bound))
                err(loc, "type '" + it->second->name + "' does not satisfy the constraint '" + c.param + " : " +
                             bound->name + "'");
        }
    }
}

void CodeGen::verifyStruct(StructInfo& si)
{
    for (Type* iface : si.interfaces)
    {
        InterfaceInfo* ii = iface->iface;
        for (auto& m : ii->decl->methods)
        {
            // Resolve the interface method signature with the interface's own type arguments.
            std::vector<Type*> params;
            std::vector<RefKind> refs;
            for (auto& p : m->params)
            {
                params.push_back(resolveValueType(*p.type, ii->decl->file, &ii->env));
                refs.push_back(p.refKind);
            }
            Type* ret = resolveValueType(*m->ret, ii->decl->file, &ii->env);

            bool found = false;
            for (const Candidate& c : methodCandidates(si.type, m->name))
            {
                if (!c.decl->typeParams.empty() || c.decl->isStatic)
                    continue;
                FuncInfo* fi = getFuncInstance(c.decl, c.owner, c.ownerEnv, c.file, {}, c.decl->loc);
                if (fi->paramTypes == params && fi->paramRefs == refs && fi->ret == ret)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
            {
                std::string sig = ret->name + " " + m->name + "(";
                for (size_t i = 0; i < params.size(); i += 1)
                    sig += (i ? ", " : "") + params[i]->name;
                sig += ")";
                err(si.decl->loc, "struct '" + si.name + "' does not implement '" + iface->name + "." + sig + "'");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// LLVM type mapping
// ---------------------------------------------------------------------------

llvm::Type* CodeGen::llvmTypeOf(Type* t)
{
    if (t->llvmType)
        return t->llvmType;

    llvm::Type* r = nullptr;
    switch (t->kind)
    {
    case TypeKind::Void: r = llvm::Type::getVoidTy(ctx); break;
    case TypeKind::Bool: r = llvm::Type::getInt1Ty(ctx); break;
    case TypeKind::Int:
    case TypeKind::Char: r = llvm::Type::getIntNTy(ctx, t->bits); break;
    case TypeKind::Float: r = t->bits == 32 ? llvm::Type::getFloatTy(ctx) : llvm::Type::getDoubleTy(ctx); break;
    case TypeKind::String:
    case TypeKind::Pointer:
    case TypeKind::Array:
    case TypeKind::Function:
    case TypeKind::MethodGroup:
    case TypeKind::Null: r = llvm::PointerType::getUnqual(ctx); break;
    case TypeKind::Enum: r = llvm::Type::getIntNTy(ctx, t->bits); break;
    case TypeKind::Struct:
        if (t->st->layoutInProgress)
            err(t->st->decl->loc, "struct '" + t->name + "' contains itself by value");
        r = t->st->llvmType;
        break;
    case TypeKind::Error:
        // Error<void> keeps the same layout with an empty payload so that member indices stay the same.
        r = llvm::StructType::get(ctx, {llvm::Type::getInt1Ty(ctx),
                                        t->elem->isVoid() ? (llvm::Type*)llvm::StructType::get(ctx, {}) : llvmTypeOf(t->elem),
                                        llvm::PointerType::getUnqual(ctx), llvm::Type::getInt32Ty(ctx)});
        break;
    case TypeKind::Optional: r = llvm::StructType::get(ctx, {llvm::Type::getInt1Ty(ctx), llvmTypeOf(t->elem)}); break;
    case TypeKind::ErrorLit: r = llvm::StructType::get(ctx, {llvm::PointerType::getUnqual(ctx), llvm::Type::getInt32Ty(ctx)}); break;
    case TypeKind::Interface: r = llvm::StructType::get(ctx, {}); break;
    }
    t->llvmType = r;
    return r;
}

bool CodeGen::needsArc(Type* t)
{
    if (t->arc >= 0)
        return t->arc != 0;
    bool r = false;
    switch (t->kind)
    {
    case TypeKind::String:
    case TypeKind::Array:
    case TypeKind::Error:
    case TypeKind::ErrorLit: r = true; break;
    case TypeKind::Optional: r = needsArc(t->elem); break;
    case TypeKind::Struct:
        if (t->st->layoutInProgress)
            return false;
        if (t->st->base && needsArc(t->st->base))
            r = true;
        for (const auto& f : t->st->fields)
            if (needsArc(f.type))
                r = true;
        break;
    default: break;
    }
    t->arc = r ? 1 : 0;
    return r;
}

unsigned CodeGen::sizeOf(Type* t)
{
    return (unsigned)mod->getDataLayout().getTypeAllocSize(llvmTypeOf(t));
}

bool CodeGen::structIsAncestor(Type* base, Type* derived, std::vector<unsigned>* path)
{
    std::vector<unsigned> p;
    for (Type* t = derived; t && t->isStruct(); t = t->st->base)
    {
        if (t == base)
        {
            if (path)
                *path = p;
            return true;
        }
        p.push_back(0);
    }
    return false;
}

bool CodeGen::findField(Type* structType, const std::string& name, FieldPath& out)
{
    StructInfo& si = *structType->st;
    for (const auto& f : si.fields)
    {
        if (f.name == name)
        {
            out.indices = {f.index};
            out.type = f.type;
            out.isPrivate = f.isPrivate;
            out.owner = structType;
            return true;
        }
    }
    if (si.base)
    {
        FieldPath inner;
        if (findField(si.base, name, inner))
        {
            out.indices = {0};
            out.indices.insert(out.indices.end(), inner.indices.begin(), inner.indices.end());
            out.type = inner.type;
            out.isPrivate = inner.isPrivate;
            out.owner = inner.owner;
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Function instances (monomorphization)
// ---------------------------------------------------------------------------

std::vector<Candidate> CodeGen::methodCandidates(Type* structType, const std::string& name)
{
    for (Type* t = structType; t && t->isStruct(); t = t->st->base)
    {
        std::vector<Candidate> out;
        for (auto& m : t->st->decl->methods)
        {
            if (m->name == name)
            {
                Candidate c;
                c.decl = m.get();
                c.owner = t;
                c.ownerEnv = &t->st->env;
                c.file = t->st->decl->file;
                out.push_back(c);
            }
        }
        if (!out.empty())
            return out;
    }
    return {};
}

FuncInfo* CodeGen::getFuncInstance(FuncDecl* decl, Type* owner, const TypeEnv* ownerEnv, FileContext* file,
                                   const std::vector<Type*>& typeArgs, SourceLoc loc)
{
    if (typeArgs.size() != decl->typeParams.size())
        err(loc, "function '" + decl->name + "' expects " + std::to_string(decl->typeParams.size()) +
                     " type argument(s), got " + std::to_string(typeArgs.size()));

    std::string key = std::to_string((uintptr_t)decl) + "|" + (owner ? owner->name : "");
    for (Type* a : typeArgs)
        key += "|" + a->name;
    auto it = funcInstances.find(key);
    if (it != funcInstances.end())
        return it->second.get();

    auto fi = std::make_unique<FuncInfo>();
    fi->decl = decl;
    fi->file = file;
    fi->owner = owner;
    if (ownerEnv)
        fi->env = *ownerEnv;
    for (size_t i = 0; i < typeArgs.size(); i += 1)
        fi->env[decl->typeParams[i]] = typeArgs[i];
    fi->name = owner ? owner->name + "." + decl->name : qualified(file, decl->name);
    if (!typeArgs.empty())
    {
        fi->name += "<";
        for (size_t i = 0; i < typeArgs.size(); i += 1)
            fi->name += (i ? "," : "") + typeArgs[i]->name;
        fi->name += ">";
    }
    fi->hasThis = owner && !decl->isStatic;
    FuncInfo* p = fi.get();
    funcInstances[key] = std::move(fi);

    try
    {
        checkConstraints(decl->constraints, p->env, file, loc);
        ensureSignature(*p);
    }
    catch (...)
    {
        funcInstances.erase(key);
        throw;
    }
    return p;
}

void CodeGen::ensureSignature(FuncInfo& fi)
{
    if (fi.signatureResolved)
        return;
    FuncDecl* d = fi.decl;
    for (auto& p : d->params)
    {
        Type* t = resolveValueType(*p.type, fi.file, &fi.env);
        if (t->isVoid())
            err(p.loc, "parameter '" + p.name + "' cannot have type 'void'");
        if (p.refKind != RefKind::None && t->isVoid())
            err(p.loc, "invalid 'ref' parameter");
        fi.paramTypes.push_back(t);
        fi.paramRefs.push_back(p.refKind);
        fi.paramNullable.push_back(p.nullable);
        fi.paramCString.push_back(p.cstring);
        if (p.cstring && !t->isString())
            err(p.loc, "internal error: a C string parameter must be a string");
    }
    fi.ret = resolveValueType(*d->ret, fi.file, &fi.env);
    fi.signatureResolved = true;
}

llvm::Function* CodeGen::declareFunction(FuncInfo& fi)
{
    if (fi.fn)
        return fi.fn;
    ensureSignature(fi);
    FuncDecl* d = fi.decl;

    std::vector<llvm::Type*> params;
    if (fi.hasThis)
        params.push_back(llvm::PointerType::getUnqual(ctx));
    for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
        params.push_back(fi.paramRefs[i] != RefKind::None ? (llvm::Type*)llvm::PointerType::getUnqual(ctx)
                                                          : llvmTypeOf(fi.paramTypes[i]));
    // A shim returns a struct through an extra trailing pointer parameter and itself returns void.
    if (d->retOut)
        params.push_back(llvm::PointerType::getUnqual(ctx));
    auto* fty = llvm::FunctionType::get(d->retOut ? llvm::Type::getVoidTy(ctx) : llvmTypeOf(fi.ret), params, d->isVariadic);

    std::string name;
    if (d->isExtern)
    {
        name = d->symbol.empty() ? d->name : d->symbol;
    }
    else
    {
        name = fi.name + "(";
        for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
            name += (i ? "," : "") + std::string(fi.paramRefs[i] == RefKind::Ref ? "ref " : fi.paramRefs[i] == RefKind::ConstRef ? "const ref " : "") +
                    fi.paramTypes[i]->name;
        name += ")";
    }

    if (d->isExtern)
    {
        // Aggregates are not passed according to the C ABI yet, so only scalars and pointers are allowed.
        for (size_t i = 0; i < fi.paramTypes.size(); i += 1)
        {
            Type* t = fi.paramTypes[i];
            if (fi.paramRefs[i] == RefKind::None && (t->isStruct() || t->isResultLike()))
                err(d->loc, "extern function '" + d->name + "': passing '" + t->name +
                                "' by value to C is not supported, pass a pointer instead");
        }
        if (!d->retOut && (fi.ret->isStruct() || fi.ret->isResultLike()))
            err(d->loc, "extern function '" + d->name + "': returning '" + fi.ret->name +
                            "' by value from C is not supported, use a pointer instead");
        if (llvm::Function* existing = mod->getFunction(name))
        {
            if (existing->getFunctionType() != fty)
                err(d->loc, "extern function '" + name + "' is declared with conflicting signatures");
            fi.fn = existing;
            return fi.fn;
        }
    }
    else if (mod->getFunction(name))
    {
        err(d->loc, "function '" + name + "' is already defined");
    }

    fi.fn = llvm::Function::Create(fty, d->isExtern ? llvm::GlobalValue::ExternalLinkage : llvm::GlobalValue::InternalLinkage,
                                   name, mod.get());
    // Small integers and bool are passed extended (C ABI). This matters for functions that C calls (callbacks) and
    // for C functions that CShift calls.
    if (!d->retOut && !fi.hasThis)
    {
        std::vector<bool> isRef;
        for (RefKind r : fi.paramRefs)
            isRef.push_back(r != RefKind::None);
        addAbiAttributes(fi.fn, nullptr, fi.paramTypes, isRef, fi.ret);
    }
    return fi.fn;
}

// Attributes that tell LLVM how small integer parameters/results are extended. Either 'fn' (a declaration or
// definition) or 'call' (an indirect call) is given. Parameter i is LLVM parameter i, so this is only used for
// functions without 'this' and without a trailing result pointer.
void CodeGen::addAbiAttributes(llvm::Function* fn, llvm::CallInst* call, const std::vector<Type*>& params,
                               const std::vector<bool>& isRef, Type* ret)
{
    auto extension = [&](Type* t) -> llvm::Attribute::AttrKind {
        if (t->isBool())
            return llvm::Attribute::ZExt;
        if ((t->isIntegral() || t->isEnum()) && t->bits < 32)
            return (t->isSigned && !t->isChar()) ? llvm::Attribute::SExt : llvm::Attribute::ZExt;
        return llvm::Attribute::None;
    };
    for (size_t i = 0; i < params.size(); i += 1)
    {
        if (isRef[i])
            continue;
        llvm::Attribute::AttrKind k = extension(params[i]);
        if (k == llvm::Attribute::None)
            continue;
        if (fn)
            fn->addParamAttr((unsigned)i, k);
        else
            call->addParamAttr((unsigned)i, k);
    }
    llvm::Attribute::AttrKind k = extension(ret);
    if (k != llvm::Attribute::None)
    {
        if (fn)
            fn->addRetAttr(k);
        else
            call->addRetAttr(k);
    }
}

void CodeGen::useFunction(FuncInfo& fi)
{
    declareFunction(fi);
    if (fi.decl->body)
    {
        if (!fi.queued)
        {
            fi.queued = true;
            workQueue.push_back(&fi);
        }
    }
    else if (!fi.decl->isExtern)
    {
        err(fi.decl->loc, "function '" + fi.name + "' has no body");
    }
}

// ---------------------------------------------------------------------------
// Whole-program compilation
// ---------------------------------------------------------------------------

bool CodeGen::compile()
{
    // 1. Check 'using' directives.
    for (auto& u : units)
    {
        for (const auto& name : u->file.usings)
        {
            if (!namespaces.count(name))
                diag.error(SourceLoc{u->file.fileId, 1, 1}, "unknown namespace '" + name + "' in using directive");
        }
    }

    // 2. Eagerly analyze everything that is not generic (and not part of the prelude).
    for (auto& u : units)
    {
        if (u->file.isPrelude)
            continue;
        for (auto& s : u->structs)
        {
            if (!s->typeParams.empty())
                continue;
            try
            {
                getStructType(s.get(), {}, s->loc);
            }
            catch (const CompileError& e)
            {
                diag.error(e);
            }
        }
        for (auto& en : u->enums)
        {
            try
            {
                getEnumType(en.get());
            }
            catch (const CompileError& ex)
            {
                diag.error(ex);
            }
        }
        for (auto& f : u->funcs)
        {
            if (!f->typeParams.empty() || f->isExtern)
                continue;
            try
            {
                FuncInfo* fi = getFuncInstance(f.get(), nullptr, nullptr, &u->file, {}, f->loc);
                useFunction(*fi);
                bool takesArgs = fi->paramTypes.size() == 1 && fi->paramTypes[0] == types.arrayOf(types.stringTy) &&
                                 fi->paramRefs[0] == RefKind::None;
                if (f->name == "Main" && (f->params.empty() || takesArgs))
                {
                    if (mainFunc)
                        diag.error(f->loc, "more than one 'Main' function");
                    else
                        mainFunc = fi;
                }
            }
            catch (const CompileError& e)
            {
                diag.error(e);
            }
        }
    }

    // 'Main(string[] args)' gets its argument array from a helper written in CShift (stdlib/args.csh).
    if (mainFunc && !mainFunc->paramTypes.empty())
    {
        try
        {
            std::vector<FuncDecl*> helper = lookupFunctions(mainFunc->file, "System.Native.MakeArgs");
            if (helper.empty())
                err(mainFunc->decl->loc, "internal error: System.Native.MakeArgs is missing from the standard library");
            mainArgsHelper = getFuncInstance(helper[0], nullptr, nullptr, helper[0]->file, {}, helper[0]->loc);
            useFunction(*mainArgsHelper);
        }
        catch (const CompileError& e)
        {
            diag.error(e);
        }
    }

    // 3. Generate function bodies. Generic instantiations add new work while this runs.
    while (!workQueue.empty() || !pendingVerify.empty())
    {
        while (!pendingVerify.empty())
        {
            StructInfo* si = pendingVerify.back();
            pendingVerify.pop_back();
            try
            {
                verifyStruct(*si);
            }
            catch (const CompileError& e)
            {
                diag.error(e);
            }
        }
        if (!workQueue.empty())
        {
            FuncInfo* fi = workQueue.front();
            workQueue.pop_front();
            emitFunctionBody(*fi);
        }
    }

    if (diag.hasErrors())
        return false;

    try
    {
        emitEntryPoint();
    }
    catch (const CompileError& e)
    {
        diag.error(e);
        return false;
    }

    std::string verifyErrors;
    llvm::raw_string_ostream os(verifyErrors);
    if (llvm::verifyModule(*mod, &os))
    {
        os.flush();
        diag.error(SourceLoc{}, "internal compiler error: invalid LLVM module\n" + verifyErrors);
        return false;
    }
    return !diag.hasErrors();
}

void CodeGen::emitEntryPoint()
{
    if (!mainFunc)
        err(SourceLoc{}, "no entry point: define a function 'int Main()'");

    FuncInfo& m = *mainFunc;
    Type* rt = m.ret;
    bool okRet = rt->isVoid() || rt->isInt() || (rt->isError() && rt->elem->isInt());
    if (!okRet)
        err(m.decl->loc, "'Main' must return void, int or Error<int>");

    auto* i32 = llvm::Type::getInt32Ty(ctx);
    auto* mainTy = llvm::FunctionType::get(i32, {i32, llvm::PointerType::getUnqual(ctx)}, false);
    auto* cmain = llvm::Function::Create(mainTy, llvm::GlobalValue::ExternalLinkage, "main", mod.get());
    llvm::IRBuilder<> b(llvm::BasicBlock::Create(ctx, "entry", cmain));
    auto* ptrArg = llvm::PointerType::getUnqual(ctx);

    // Returns from main; with --arc-stats the heap block balance is printed first.
    auto finish = [&](llvm::Value* code) {
        if (arcStats)
        {
            llvm::Value* allocs = b.CreateLoad(b.getInt64Ty(), arcCounter("__cs_allocs"));
            llvm::Value* frees = b.CreateLoad(b.getInt64Ty(), arcCounter("__cs_frees"));
            llvm::FunctionCallee f = cFunction("fprintf", b.getInt32Ty(), {ptrArg, ptrArg}, true);
            b.CreateCall(f, {stderrHandle(b), cString("[arc] allocs=%lld frees=%lld live=%lld\n"), allocs, frees,
                             b.CreateSub(allocs, frees)});
        }
        b.CreateRet(code);
    };

    llvm::Value* result;
    if (mainArgsHelper)
    {
        llvm::Value* args = b.CreateCall(mainArgsHelper->fn, {cmain->getArg(0), cmain->getArg(1)});
        result = b.CreateCall(m.fn, {args});
        builder.SetInsertPoint(b.GetInsertBlock());
        emitReleaseValue(m.paramTypes[0], args); // Main only borrows its parameter
    }
    else
    {
        result = b.CreateCall(m.fn, {});
    }
    if (rt->isVoid())
    {
        finish(b.getInt32(0));
    }
    else if (rt->isInt())
    {
        finish(b.CreateIntCast(result, i32, rt->isSigned));
    }
    else
    {
        llvm::Value* ok = b.CreateExtractValue(result, 0);
        auto* okBB = llvm::BasicBlock::Create(ctx, "ok", cmain);
        auto* failBB = llvm::BasicBlock::Create(ctx, "fail", cmain);
        b.CreateCondBr(ok, okBB, failBB);
        b.SetInsertPoint(okBB);
        finish(b.CreateIntCast(b.CreateExtractValue(result, 1), i32, rt->elem->isSigned));
        b.SetInsertPoint(failBB);
        llvm::Value* msg = b.CreateExtractValue(result, 2);
        llvm::Value* stderrH = stderrHandle(b);
        auto fmt = b.CreateGlobalString("error: %s\n");
        llvm::FunctionCallee fprintfFn = cFunction("fprintf", i32, {llvm::PointerType::getUnqual(ctx), llvm::PointerType::getUnqual(ctx)}, true);
        b.CreateCall(fprintfFn, {stderrH, fmt, b.CreateCall(dataFn(), {msg})});
        finish(b.getInt32(1));
    }
}
