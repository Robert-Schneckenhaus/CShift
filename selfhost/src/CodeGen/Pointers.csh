// Raw pointers (unsafe code): dereference, address-of, arithmetic and casts (the pointer parts of CodeGenExpr.cpp).
// A pointer is an LLVM 'ptr'; the type only tells what a load or store through it means.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// *p: the pointed-to memory as an lvalue.
Value DerefPointer(Compiler cg, Value p, SourceLoc loc)
{
    var types = cg.Types;
    RequireUnsafe(cg, loc, "pointer dereference");
    Value pv = ToRValue(cg, p);
    string why = DerefError(cg, pv.Type);
    if (why.Length > 0)
        Fail(cg, loc, why);
    return Lvalue(types.Elem(pv.Type), pv.V, false);
}

// *p: "" if a value of type t can be dereferenced, otherwise the error.
string DerefError(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsUnknown(t))
        return "";
    if (!types.IsPointer(t))
        return "cannot dereference a value of type '" + types.Name(t) + "'";
    if (types.IsVoid(types.Elem(t)))
        return "cannot dereference 'void*'";
    return "";
}

// &x
Value EmitAddressOf(Compiler cg, Expr e, Expr operand)
{
    RequireUnsafe(cg, e.Loc, "taking an address");
    Value o = EmitExpr(cg, operand);
    if (!o.IsLValue)
        Fail(cg, e.Loc, "cannot take the address of a temporary value");
    return Rvalue(cg.Types.PointerTo(o.Type), o.V, false);
}

// Memory.VolatileRead/VolatileWrite: a pointer to a number, bool, char, enum or pointer (what one load or store can
// access). "" if the type is fine, otherwise the error.
string VolatileTargetError(Compiler cg, int pointerType, string method)
{
    var types = cg.Types;
    if (types.IsUnknown(pointerType))
        return "";
    if (!types.IsPointer(pointerType))
        return "Memory." + method + " needs a pointer, not '" + types.Name(pointerType) + "'";
    int elem = types.Elem(pointerType);
    if (types.IsUnknown(elem))
        return "";
    if (!(types.IsIntegral(elem) || types.IsFloat(elem) || types.IsBool(elem) || types.IsEnum(elem) || types.IsPointer(elem)))
        return "Memory." + method + " needs a pointer to a number, bool, char, enum or pointer, not '" + types.Name(pointerType) + "'";
    return "";
}

// p + n, n + p, p - n, p - q (in elements)
Value EmitPointerArithmetic(Compiler cg, BinOp op, Value l, Value r, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    RequireUnsafe(cg, loc, "pointer arithmetic");
    if (types.IsPointer(l.Type) && types.IsPointer(r.Type) && op == BinOp.Sub && l.Type == r.Type && !types.IsVoid(types.Elem(l.Type)))
    {
        string size = SizeIr(cg);
        string a = ir.Cast("ptrtoint", "ptr", l.V, size);
        string b = ir.Cast("ptrtoint", "ptr", r.V, size);
        string bytes = ir.Bin("sub", size, a, b);
        return Rvalue(types.I64, SizeToI64(cg, ir.Bin("sdiv", size, bytes, SizeOfType(cg, types.Elem(l.Type))), true), false);
    }
    Value ptr = types.IsPointer(l.Type) ? l : r;
    Value off = types.IsPointer(l.Type) ? r : l;
    if ((op == BinOp.Add || (op == BinOp.Sub && types.IsPointer(l.Type))) && types.IsIntegral(off.Type) &&
        !types.IsVoid(types.Elem(ptr.Type)))
    {
        // like C: the offset is converted to a pointer-sized integer (a 64-bit offset is cut on a 32-bit target)
        bool isSigned = types.IsInt(off.Type) && types.IsSigned(off.Type);
        string n = NumericConvert(cg, off.V, off.Type, isSigned ? types.Nint : types.Nuint);
        if (op == BinOp.Sub)
            n = ir.Bin("sub", SizeIr(cg), "0", n);
        return Rvalue(ptr.Type, ir.Gep(LlvmType(cg, types.Elem(ptr.Type)), ptr.V, SizeIr(cg) + " " + n), false);
    }
    Fail(cg, loc, "invalid pointer arithmetic");
    return l;
}

// (T*)p, (nint)p, (T*)n. Returns false if the cast is not one of these.
bool EmitPointerCast(Compiler cg, Value v, int to, SourceLoc loc, ref Value result)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int from = v.Type;
    if (types.IsPointer(from) && types.IsPointer(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        result = Rvalue(to, v.V, false);
        return true;
    }
    // Function pointers and data pointers convert into each other (for C callbacks that are passed as void*).
    if (types.IsFunction(from) && types.IsPointer(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        Value f = ToRValue(cg, v);
        HoldTemp(cg, f);
        result = Rvalue(to, RawFunctionPointer(cg, f.V), false);
        return true;
    }
    if (types.IsPointer(from) && types.IsFunction(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        result = Rvalue(to, ir.InsertValue("{ ptr, ptr }", "zeroinitializer", "ptr", ToRValue(cg, v).V, "0"), false);
        return true;
    }
    // A C function pointer (the field of a C struct) is a plain pointer: void* <-> C function pointer, e.g. an address
    // from glfwGetProcAddress stored into an OpenGL function table.
    if ((types.IsPointer(from) && types.IsCFunction(to)) || (types.IsCFunction(from) && types.IsPointer(to)))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        result = Rvalue(to, ToRValue(cg, v).V, false);
        return true;
    }
    if (types.IsPointer(from) && types.IsInt(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        // through an integer as wide as a pointer of the target
        int pointerBits = cg.Ir.Target.PtrBytes * 8;
        string pointerInt = "i" + pointerBits.ToString();
        string wide = ir.Cast("ptrtoint", "ptr", v.V, pointerInt);
        int bits = types.Bits(to);
        if (bits < pointerBits)
            wide = ir.Cast("trunc", pointerInt, wide, LlvmType(cg, to));
        else if (bits > pointerBits)
            wide = ir.Cast("zext", pointerInt, wide, LlvmType(cg, to));
        result = Rvalue(to, wide, false);
        return true;
    }
    if (types.IsInt(from) && types.IsPointer(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        int pointerBits = cg.Ir.Target.PtrBytes * 8;
        string pointerInt = "i" + pointerBits.ToString();
        string wide = v.V;
        int bits = types.Bits(from);
        if (bits < pointerBits)
            wide = ir.Cast(types.IsSigned(from) ? "sext" : "zext", LlvmType(cg, from), v.V, pointerInt);
        else if (bits > pointerBits)
            wide = ir.Cast("trunc", LlvmType(cg, from), v.V, pointerInt);
        result = Rvalue(to, ir.Cast("inttoptr", pointerInt, wide, "ptr"), false);
        return true;
    }
    return false;
}

// string.FromCStr(char* p): copies a NUL-terminated C string into a string (null -> null).
Value EmitStringFromCStr(Compiler cg, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    if (args.Length != 1)
        Fail(cg, loc, "string.FromCStr takes one argument (char*)");
    RequireUnsafe(cg, loc, "string.FromCStr");
    Value p = ToRValue(cg, args[0].V);
    bool charLike = false;
    if (types.IsPointer(p.Type))
    {
        int elem = types.Elem(p.Type);
        charLike = types.IsChar(elem) || types.IsVoid(elem) || elem == types.U8 || elem == types.I8;
    }
    if (!charLike && types.Kind(p.Type) != TypeKind.Null)
        Fail(cg, loc, "string.FromCStr needs a 'char*', not '" + types.Name(p.Type) + "'");
    return Rvalue(types.String, cg.Ir.Call("ptr", "@__cs_from_cstr", "ptr " + p.V), true);
}
