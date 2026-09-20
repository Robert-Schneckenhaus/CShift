#include "Types.h"

Type* TypeContext::create(TypeKind kind, const std::string& name)
{
    all.push_back(std::make_unique<Type>());
    Type* t = all.back().get();
    t->kind = kind;
    t->name = name;
    return t;
}

TypeContext::TypeContext()
{
    voidTy = create(TypeKind::Void, "void");
    boolTy = create(TypeKind::Bool, "bool");
    boolTy->bits = 1;
    charTy = create(TypeKind::Char, "char");
    charTy->bits = 8;
    stringTy = create(TypeKind::String, "string");
    nullTy = create(TypeKind::Null, "null");
    errorLitTy = create(TypeKind::ErrorLit, "error");

    auto makeInt = [&](const char* name, int bits, bool isSigned) {
        Type* t = create(TypeKind::Int, name);
        t->bits = bits;
        t->isSigned = isSigned;
        return t;
    };
    i8 = makeInt("int8", 8, true);
    i16 = makeInt("int16", 16, true);
    i32 = makeInt("int32", 32, true);
    i64 = makeInt("int64", 64, true);
    u8 = makeInt("uint8", 8, false);
    u16 = makeInt("uint16", 16, false);
    u32 = makeInt("uint32", 32, false);
    u64 = makeInt("uint64", 64, false);

    f32 = create(TypeKind::Float, "float32");
    f32->bits = 32;
    f64 = create(TypeKind::Float, "float64");
    f64->bits = 64;
}

Type* TypeContext::intType(int bits, bool isSigned)
{
    switch (bits)
    {
    case 8: return isSigned ? i8 : u8;
    case 16: return isSigned ? i16 : u16;
    case 32: return isSigned ? i32 : u32;
    default: return isSigned ? i64 : u64;
    }
}

Type* TypeContext::pointerTo(Type* elem)
{
    auto it = pointers.find(elem);
    if (it != pointers.end())
        return it->second;
    Type* t = create(TypeKind::Pointer, elem->name + "*");
    t->elem = elem;
    pointers[elem] = t;
    return t;
}

Type* TypeContext::arrayOf(Type* elem)
{
    auto it = arrays.find(elem);
    if (it != arrays.end())
        return it->second;
    Type* t = create(TypeKind::Array, elem->name + "[]");
    t->elem = elem;
    arrays[elem] = t;
    return t;
}

Type* TypeContext::errorOf(Type* elem)
{
    auto it = errors.find(elem);
    if (it != errors.end())
        return it->second;
    Type* t = create(TypeKind::Error, "Error<" + elem->name + ">");
    t->elem = elem;
    errors[elem] = t;
    return t;
}

Type* TypeContext::optionalOf(Type* elem)
{
    auto it = optionals.find(elem);
    if (it != optionals.end())
        return it->second;
    Type* t = create(TypeKind::Optional, "Optional<" + elem->name + ">");
    t->elem = elem;
    optionals[elem] = t;
    return t;
}
