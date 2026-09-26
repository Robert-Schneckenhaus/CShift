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
    if (!types.IsPointer(pv.Type))
        Fail(cg, loc, "cannot dereference a value of type '" + types.Name(pv.Type) + "'");
    if (types.IsVoid(types.Elem(pv.Type)))
        Fail(cg, loc, "cannot dereference 'void*'");
    return Lvalue(types.Elem(pv.Type), pv.V, false);
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

// p + n, n + p, p - n, p - q (in elements)
Value EmitPointerArithmetic(Compiler cg, BinOp op, Value l, Value r, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    RequireUnsafe(cg, loc, "pointer arithmetic");
    if (types.IsPointer(l.Type) && types.IsPointer(r.Type) && op == BinOp.Sub && l.Type == r.Type && !types.IsVoid(types.Elem(l.Type)))
    {
        string a = ir.Cast("ptrtoint", "ptr", l.V, "i64");
        string b = ir.Cast("ptrtoint", "ptr", r.V, "i64");
        string bytes = ir.Bin("sub", "i64", a, b);
        return Rvalue(types.I64, ir.Bin("sdiv", "i64", bytes, SizeOfType(cg, types.Elem(l.Type))), false);
    }
    Value ptr = types.IsPointer(l.Type) ? l : r;
    Value off = types.IsPointer(l.Type) ? r : l;
    if ((op == BinOp.Add || (op == BinOp.Sub && types.IsPointer(l.Type))) && types.IsIntegral(off.Type) &&
        !types.IsVoid(types.Elem(ptr.Type)))
    {
        bool isSigned = types.IsInt(off.Type) && types.IsSigned(off.Type);
        string n = NumericConvert(cg, off.V, off.Type, isSigned ? types.I64 : types.U64);
        if (op == BinOp.Sub)
            n = ir.Bin("sub", "i64", "0", n);
        return Rvalue(ptr.Type, ir.Gep(LlvmType(cg, types.Elem(ptr.Type)), ptr.V, "i64 " + n), false);
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
    if (types.IsPointer(from) && types.IsInt(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        string wide = ir.Cast("ptrtoint", "ptr", v.V, "i64");
        int bits = types.Bits(to);
        result = Rvalue(to, bits == 64 ? wide : ir.Cast("trunc", "i64", wide, LlvmType(cg, to)), false);
        return true;
    }
    if (types.IsInt(from) && types.IsPointer(to))
    {
        RequireUnsafe(cg, loc, "pointer cast");
        string wide = v.V;
        int bits = types.Bits(from);
        if (bits < 64)
            wide = ir.Cast("sext", LlvmType(cg, from), v.V, "i64");
        result = Rvalue(to, ir.Cast("inttoptr", "i64", wide, "ptr"), false);
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
