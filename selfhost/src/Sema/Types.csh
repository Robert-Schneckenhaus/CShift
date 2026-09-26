// Types of the language, as seen by the code generator.
//
// A type is a plain integer (an id into TypeContext) so that types can be compared with '==': like in the C++
// compiler every type is interned, equal types have the same id. Id 0 means "no type".

namespace CShift.Sema;

using System;

enum TypeKind : int32
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
    Error,       // Error<T>
    Optional,    // Optional<T>
    Null,        // type of the 'null' literal
    ErrorLit,    // type of error("...") before it is converted to Error<T>
    Function,    // Action<...> / Func<..., R>
    MethodGroup, // a function name used as a value
    SharedPtr,   // SharedPtr<T>: an atomically reference-counted box, safe to share between threads
    CFunction,   // a function pointer field of a C struct (a plain pointer; Elem is its Action/Func type)
    Lambda,      // a lambda before it is converted to an Action/Func type
    Union        // union U { A, B }: one of the member types with a tag (Decl: index in Compiler.UnionInfos)
}

struct TypeInfo
{
    TypeKind Kind;
    string Name;
    int Bits;          // Int, Char, Float, Enum
    bool IsSigned;     // Int, Enum
    bool IsNative;     // nint / nuint
    int Elem;          // Pointer, Array, Error, Optional, Enum (base type), Function (result), SharedPtr
    int[] Params;      // Function: parameter types
    int Decl;          // Struct / Enum / Interface: index of its info in the compiler
    int Code;          // Error: the error enum of Error<T, E> (0: plain int codes); ErrorLit: see ErrorLitOf
    int Arc;           // cache for NeedsArc: -1 unknown, 0 no, 1 yes
}

struct TypeContext
{
    List<TypeInfo> Infos;
    Dictionary<string, int> Interned;

    // The primitive types
    int Void;
    int Bool;
    int Char;
    int String;
    int Null;
    int ErrorLit;
    int MethodGroup;
    int Lambda;
    int I8;
    int I16;
    int I32;
    int I64;
    int U8;
    int U16;
    int U32;
    int U64;
    int F32;
    int F64;
    int Nint;   // pointer-sized signed integer
    int Nuint;  // pointer-sized unsigned integer

    static TypeContext Create()
    {
        var tc = TypeContext { };
        tc.Infos = List<TypeInfo>.Create();
        tc.Interned = Dictionary<string, int>.Create();
        tc.Void = tc.Add(TypeKind.Void, "void", 0, false);
        tc.Bool = tc.Add(TypeKind.Bool, "bool", 1, false);
        tc.Char = tc.Add(TypeKind.Char, "char", 8, false);
        tc.String = tc.Add(TypeKind.String, "string", 0, false);
        tc.Null = tc.Add(TypeKind.Null, "null", 0, false);
        tc.ErrorLit = tc.Add(TypeKind.ErrorLit, "error", 0, false);
        tc.MethodGroup = tc.Add(TypeKind.MethodGroup, "function", 0, false);
        tc.I8 = tc.Add(TypeKind.Int, "int8", 8, true);
        tc.I16 = tc.Add(TypeKind.Int, "int16", 16, true);
        tc.I32 = tc.Add(TypeKind.Int, "int32", 32, true);
        tc.I64 = tc.Add(TypeKind.Int, "int64", 64, true);
        tc.U8 = tc.Add(TypeKind.Int, "uint8", 8, false);
        tc.U16 = tc.Add(TypeKind.Int, "uint16", 16, false);
        tc.U32 = tc.Add(TypeKind.Int, "uint32", 32, false);
        tc.U64 = tc.Add(TypeKind.Int, "uint64", 64, false);
        tc.F32 = tc.Add(TypeKind.Float, "float32", 32, false);
        tc.F64 = tc.Add(TypeKind.Float, "float64", 64, false);
        // 64 bits: only 64-bit targets are supported so far
        tc.Nint = tc.Add(TypeKind.Int, "nint", 64, true);
        tc.SetNative(tc.Nint);
        tc.Nuint = tc.Add(TypeKind.Int, "nuint", 64, false);
        tc.SetNative(tc.Nuint);
        tc.Lambda = tc.Add(TypeKind.Lambda, "lambda", 0, false);
        return tc;
    }

    // Creates a new type. The caller interns it by name where that matters.
    int Add(TypeKind kind, string name, int bits, bool isSigned)
    {
        Infos.Add(TypeInfo { Kind = kind, Name = name, Bits = bits, IsSigned = isSigned, Params = new int[0], Arc = -1 });
        return Infos.Count();
    }

    void SetNative(int t)
    {
        var info = Infos.Get(t - 1);
        info.IsNative = true;
        Infos.Set(t - 1, info);
    }

    TypeInfo Info(int t)
    {
        return Infos.Get(t - 1);
    }

    void SetInfo(int t, TypeInfo info)
    {
        Infos.Set(t - 1, info);
    }

    TypeKind Kind(int t) { return Infos.Get(t - 1).Kind; }
    string Name(int t) { return Infos.Get(t - 1).Name; }
    int Bits(int t) { return Infos.Get(t - 1).Bits; }
    bool IsSigned(int t) { return Infos.Get(t - 1).IsSigned; }
    bool IsNative(int t) { return Infos.Get(t - 1).IsNative; }
    int Elem(int t) { return Infos.Get(t - 1).Elem; }
    int Decl(int t) { return Infos.Get(t - 1).Decl; }
    int[] Params(int t) { return Infos.Get(t - 1).Params; }
    int Code(int t) { return Infos.Get(t - 1).Code; }

    bool IsVoid(int t) { return Kind(t) == TypeKind.Void; }
    bool IsBool(int t) { return Kind(t) == TypeKind.Bool; }
    bool IsInt(int t) { return Kind(t) == TypeKind.Int; }
    bool IsChar(int t) { return Kind(t) == TypeKind.Char; }
    bool IsIntegral(int t) { var k = Kind(t); return k == TypeKind.Int || k == TypeKind.Char; }
    bool IsFloat(int t) { return Kind(t) == TypeKind.Float; }
    bool IsNumeric(int t) { return IsIntegral(t) || IsFloat(t); }
    bool IsString(int t) { return Kind(t) == TypeKind.String; }
    bool IsPointer(int t) { return Kind(t) == TypeKind.Pointer; }
    bool IsArray(int t) { return Kind(t) == TypeKind.Array; }
    bool IsStruct(int t) { return Kind(t) == TypeKind.Struct; }
    bool IsEnum(int t) { return Kind(t) == TypeKind.Enum; }
    bool IsError(int t) { return Kind(t) == TypeKind.Error; }
    bool IsOptional(int t) { return Kind(t) == TypeKind.Optional; }
    bool IsResultLike(int t) { var k = Kind(t); return k == TypeKind.Error || k == TypeKind.Optional; }
    bool IsFunction(int t) { return Kind(t) == TypeKind.Function; }
    bool IsSharedPtr(int t) { return Kind(t) == TypeKind.SharedPtr; }
    bool IsCFunction(int t) { return Kind(t) == TypeKind.CFunction; }
    bool IsRefLike(int t) { var k = Kind(t); return k == TypeKind.String || k == TypeKind.Array; }

    // The integer type with the given width.
    int IntType(int bits, bool isSigned)
    {
        switch (bits)
        {
        case 8: return isSigned ? I8 : U8;
        case 16: return isSigned ? I16 : U16;
        case 32: return isSigned ? I32 : U32;
        default: return isSigned ? I64 : U64;
        }
    }

    int Derived(TypeKind kind, string name, int elem)
    {
        var found = Interned.TryGet(name);
        if (found is int existing)
            return existing;
        int t = Add(kind, name, 0, false);
        var info = Infos.Get(t - 1);
        info.Elem = elem;
        Infos.Set(t - 1, info);
        Interned.Set(name, t);
        return t;
    }

    int PointerTo(int elem) { return Derived(TypeKind.Pointer, Name(elem) + "*", elem); }
    int ArrayOf(int elem) { return Derived(TypeKind.Array, Name(elem) + "[]", elem); }
    int ErrorOf(int elem) { return Derived(TypeKind.Error, "Error<" + Name(elem) + ">", elem); }
    // Error<T, E>: a result whose error code is a value of the error enum E (same layout as Error<T>)
    int ErrorOf(int elem, int code)
    {
        if (code == 0)
            return ErrorOf(elem);
        string name = "Error<" + Name(elem) + ", " + Name(code) + ">";
        var found = Interned.TryGet(name);
        if (found is int existing)
            return existing;
        int t = Derived(TypeKind.Error, name, elem);
        var info = Infos.Get(t - 1);
        info.Code = code;
        Infos.Set(t - 1, info);
        return t;
    }

    // The type of an error literal: 'code' is 0 for error("text"), -1 for error("text", int), else the error enum of
    // error(E.X) / error("text", E.X).
    int ErrorLitOf(int code)
    {
        if (code == 0)
            return ErrorLit;
        string name = code < 0 ? "error(int)" : "error(" + Name(code) + ")";
        var found = Interned.TryGet(name);
        if (found is int existing)
            return existing;
        int t = Add(TypeKind.ErrorLit, name, 0, false);
        var info = Infos.Get(t - 1);
        info.Code = code;
        Infos.Set(t - 1, info);
        Interned.Set(name, t);
        return t;
    }

    int OptionalOf(int elem) { return Derived(TypeKind.Optional, "Optional<" + Name(elem) + ">", elem); }
    int SharedPtrOf(int elem) { return Derived(TypeKind.SharedPtr, "SharedPtr<" + Name(elem) + ">", elem); }
    int CFunctionOf(int function) { return Derived(TypeKind.CFunction, Name(function) + " (C function pointer)", function); }

    // Action<params> for a void result, Func<params, ret> otherwise.
    int FunctionOf(int[] parameters, int ret)
    {
        string name = IsVoid(ret) ? "Action" : "Func";
        if (parameters.Length > 0 || !IsVoid(ret))
        {
            var sb = StringBuilder.Create();
            sb.Append(name);
            sb.Append('<');
            for (var i = 0; i < parameters.Length; i += 1)
            {
                if (i > 0)
                    sb.Append(", ");
                sb.Append(Name(parameters[i]));
            }
            if (!IsVoid(ret))
            {
                if (parameters.Length > 0)
                    sb.Append(", ");
                sb.Append(Name(ret));
            }
            sb.Append('>');
            name = sb.ToString();
        }
        var found = Interned.TryGet(name);
        if (found is int existing)
            return existing;
        int t = Add(TypeKind.Function, name, 0, false);
        var info = Infos.Get(t - 1);
        info.Elem = ret;
        info.Params = parameters;
        Infos.Set(t - 1, info);
        Interned.Set(name, t);
        return t;
    }
}
