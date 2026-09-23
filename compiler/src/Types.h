#pragma once

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace llvm
{
class Type;
}

enum class TypeKind
{
    Void,
    Bool,
    Int,
    Char,
    Float,
    String,
    Pointer,
    Array,
    Struct,
    Enum,
    Interface,
    Error,    // Error<T>
    Optional, // Optional<T>
    Null,     // type of the 'null' literal
    ErrorLit, // type of error("...") before it is converted to Error<T>
    Function, // Action<...> / Func<..., R>: pointer to a function (no closure)
    MethodGroup, // type of a function name used as a value; converts to a matching Function type
    SharedPtr // SharedPtr<T>: an atomically reference-counted box, safe to share between threads
};

struct StructInfo;
struct EnumInfo;
struct InterfaceInfo;

// Types are interned by TypeContext, so pointer equality means type equality.
struct Type
{
    TypeKind kind = TypeKind::Void;
    std::string name;
    int bits = 0;           // Int, Char, Float, Enum (bits of the base type)
    bool isSigned = false;  // Int, Enum
    bool isNativeInt = false; // nint/nuint: integer of pointer size (bits is set from the target's data layout)
    Type* elem = nullptr;   // Pointer, Array, Error, Optional, Enum (base type), Function (return type), SharedPtr
    std::vector<Type*> params; // Function: parameter types
    StructInfo* st = nullptr;
    EnumInfo* en = nullptr;
    InterfaceInfo* iface = nullptr;

    llvm::Type* llvmType = nullptr; // cache
    int arc = -1;                   // cache for needsArc: -1 = unknown

    bool isVoid() const { return kind == TypeKind::Void; }
    bool isBool() const { return kind == TypeKind::Bool; }
    bool isInt() const { return kind == TypeKind::Int; }
    bool isChar() const { return kind == TypeKind::Char; }
    bool isIntegral() const { return kind == TypeKind::Int || kind == TypeKind::Char; }
    bool isFloat() const { return kind == TypeKind::Float; }
    bool isNumeric() const { return isIntegral() || isFloat(); }
    bool isString() const { return kind == TypeKind::String; }
    bool isPointer() const { return kind == TypeKind::Pointer; }
    bool isArray() const { return kind == TypeKind::Array; }
    bool isStruct() const { return kind == TypeKind::Struct; }
    bool isEnum() const { return kind == TypeKind::Enum; }
    bool isError() const { return kind == TypeKind::Error; }
    bool isOptional() const { return kind == TypeKind::Optional; }
    bool isResultLike() const { return isError() || isOptional(); }
    bool isSignedInt() const { return kind == TypeKind::Int && isSigned; }
    bool isFunction() const { return kind == TypeKind::Function; }
    bool isSharedPtr() const { return kind == TypeKind::SharedPtr; }
    bool isRefLike() const { return kind == TypeKind::String || kind == TypeKind::Array; }
};

class TypeContext
{
public:
    TypeContext();

    Type* voidTy;
    Type* boolTy;
    Type* charTy;
    Type* stringTy;
    Type* nullTy;
    Type* errorLitTy;
    Type* methodGroupTy;
    Type* i8;
    Type* i16;
    Type* i32;
    Type* i64;
    Type* u8;
    Type* u16;
    Type* u32;
    Type* u64;
    Type* f32;
    Type* f64;
    Type* nint;  // pointer-sized signed integer (like C# nint, C intptr_t/ptrdiff_t)
    Type* nuint; // pointer-sized unsigned integer (like C# nuint, C size_t/uintptr_t)

    Type* intType(int bits, bool isSigned);
    Type* pointerTo(Type* elem);
    Type* arrayOf(Type* elem);
    Type* errorOf(Type* elem);
    Type* optionalOf(Type* elem);
    Type* sharedPtrOf(Type* elem);
    // Action<params> for a void result, Func<params, ret> otherwise.
    Type* functionOf(const std::vector<Type*>& params, Type* ret);

    // Creates a fresh (non-interned) type object; the caller interns by name.
    Type* create(TypeKind kind, const std::string& name);

private:
    std::vector<std::unique_ptr<Type>> all;
    std::map<Type*, Type*> pointers;
    std::map<Type*, Type*> arrays;
    std::map<Type*, Type*> errors;
    std::map<Type*, Type*> optionals;
    std::map<Type*, Type*> sharedPtrs;
    std::map<std::string, Type*> functions;
};
