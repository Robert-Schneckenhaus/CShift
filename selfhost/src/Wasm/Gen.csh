// The WebAssembly code generator: translates the IR module (M68k/IrReader.csh, the same reader as the 68000 backend)
// into a WebAssembly module (Encoder.csh) that runs on WASI, with the C library of stdlib/wasm (written in CShift).
//
// Simple and correct first:
//
//   * Values: a scalar value of the IR is a local of the function (i1, i8, i16, i32 and pointers in an i32, kept
//     zero-extended: the bits above the type's width are always zero; i64, float and double in i64, f32, f64). A struct
//     or array value is the address of its bytes (an i32): a slot in the function's frame, or a part of another value;
//     the bytes of a value never change while it can be used.
//   * Memory: the shadow stack (allocas, the slots of struct values) is at the bottom of the memory, [0, StackSize),
//     and grows down from its top (the global $sp); then the globals (those that start as zeros, then the others,
//     written by the data segment), then the heap (malloc in stdlib/wasm, which grows the memory).
//   * Control flow: the blocks of a function are nested wasm blocks, so a jump forward is a 'br' to the end of a wasm
//     block; a function with jumps back puts them in a loop with a 'br_table' on the block number ($pc).
//   * Calls: wasm calls. A struct argument is passed as its address; a struct result is written to the memory whose
//     address the caller passes as a hidden first argument. A call of a C function with variable arguments (printf,
//     snprintf) calls __cs_va_<name> with the fixed arguments and the address of the others, packed like on the stack
//     of the 68000 (4 bytes for integers and pointers, 8 for int64 and double, unaligned).
//   * A function without a body is imported: __wasi_X is X of wasi_snapshot_preview1, the others come from the
//     module "env" (functions of the host, in JavaScript).
//   * Function addresses are slots of the function table (0 is null).

namespace CShift.Wasm;

using System;
using CShift.M68k;

const int StackSize = 8388608; // 8 MB, like the stack of the clang build (Driver/Build.csh)

struct SlotInit
{
    int Local;
    int Offset;
}

struct WasmGen
{
    IrModule M;
    IrTypes T;
    WasmLayouts L;
    List<string> Errors;
    List<string> Warnings;

    // the module
    List<Bytes> Types;                    // the function types (encoded)
    Dictionary<string, int> TypeIndex;    // a type's encoding as text -> its index
    List<string> Imports;                 // the imported functions (IR names), function indexes 0..
    List<string> Defined;                 // the functions with a body, after the imports
    Dictionary<string, int> FuncIndex;    // IR name -> function index
    List<int> Table;                      // the function indexes in the table (slot = position + 1)
    Dictionary<string, int> TableSlot;    // IR name -> slot
    Dictionary<string, int> GlobalAddr;   // IR global -> its address
    HashSet<string> Reached;              // the functions and globals the program uses
    List<string> Work;
    Bytes Data;                           // the memory from DataStart on (the data segment)
    int DataStart;
    int ZeroBlock;                        // zeros for struct constants that are all zeros (zeroinitializer, undef)
    int ZeroSize;
    int HeapBase;

    // the function being written
    string FnName;
    Bytes Code;
    List<int> LocalTypes;                 // the value types of the locals, the parameters first
    List<SlotInit> SlotInits;             // locals that hold the address of a frame slot (set by the prologue)
    Dictionary<string, int> Local;        // value -> its local
    Dictionary<string, int> PhiTmp;       // phi -> the local of its staging copy (struct phis: of the staging slot)
    Dictionary<string, int> SplitFlag;    // { iN, i1 } results of the overflow intrinsics: the local of the flag
    Dictionary<string, int> Uses;         // value -> number of uses
    Dictionary<string, IrInst> Def;       // value -> the instruction that computes it
    Dictionary<string, int> BlockIndex;
    Dictionary<string, int> PosSlot;      // "block:instruction" -> the local of a slot for a call (the packed variable
                                          // arguments, or the struct result nobody uses)
    List<IrBlock> Blocks;
    int FramePointer;                     // the local with the frame's address
    int Pc;                               // the local with the number of the next block (functions with a loop)
    int FrameSize;
    int Current;                          // the block being written
    int Position;                         // the instruction being written (its index in the block)
    int Depth;                            // wasm blocks opened inside its code (if/else)
    int Sret;                             // the local of the hidden result pointer (-1: none)
    bool HasLoop;

    static WasmGen Create(IrModule m)
    {
        return WasmGen { M = m, T = m.Types, L = WasmLayouts.Create(m.Types), Errors = List<string>.Create(),
                         Warnings = List<string>.Create(), Types = List<Bytes>.Create(), TypeIndex = Dictionary<string, int>.Create(), Imports = List<string>.Create(),
                         Defined = List<string>.Create(), FuncIndex = Dictionary<string, int>.Create(), Table = List<int>.Create(),
                         TableSlot = Dictionary<string, int>.Create(), GlobalAddr = Dictionary<string, int>.Create(),
                         Reached = HashSet<string>.Create(), Work = List<string>.Create(), Data = Bytes.Create(), FnName = "",
                         Code = Bytes.Create(), LocalTypes = List<int>.Create(), SlotInits = List<SlotInit>.Create(),
                         Local = Dictionary<string, int>.Create(), PhiTmp = Dictionary<string, int>.Create(),
                         SplitFlag = Dictionary<string, int>.Create(), Uses = Dictionary<string, int>.Create(),
                         Def = Dictionary<string, IrInst>.Create(), BlockIndex = Dictionary<string, int>.Create(),
                         PosSlot = Dictionary<string, int>.Create(),
                         Blocks = List<IrBlock>.Create(), Sret = -1 };
    }

    void Fail(string message)
    {
        string text = FnName.Length > 0 ? FnName + ": " + message : message;
        if (!Errors.Contains(text))
            Errors.Add(text);
    }

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------

    // The wasm value type of an IR type (0 for void); structs and arrays are addresses.
    int ValType(int t)
    {
        var info = T.Info(t);
        switch (info.Kind)
        {
        case IrKind.Int:
            if (info.Bits <= 32)
                return I32;
            if (info.Bits == 64)
                return I64;
            Fail("integers of " + info.Bits.ToString() + " bits are not supported");
            return I64;
        case IrKind.Ptr:
        case IrKind.Struct:
        case IrKind.Array:
            return I32;
        case IrKind.Float:
            return F32;
        case IrKind.Double:
            return F64;
        default:
            return 0;
        }
    }

    // The width of an integer type that lives in an i32 (pointers: 32).
    int Width(int t)
    {
        return T.IsInt(t) ? T.Bits(t) : 32;
    }

    int FuncType(List<int> ps, List<int> results)
    {
        var sb = StringBuilder.Create();
        foreach (var p in ps.ToArray())
            sb.Append(p.ToString() + ",");
        sb.Append(":");
        foreach (var r in results.ToArray())
            sb.Append(r.ToString() + ",");
        string key = sb.ToString();
        var found = TypeIndex.TryGet(key);
        if (found is int index)
            return index;
        var b = Bytes.Create();
        b.Byte(96); // 0x60 func
        b.U32(ps.Count());
        foreach (var p in ps.ToArray())
            b.Byte(p);
        b.U32(results.Count());
        foreach (var r in results.ToArray())
            b.Byte(r);
        Types.Add(b);
        TypeIndex.Set(key, Types.Count() - 1);
        return Types.Count() - 1;
    }

    // The type of an IR function: a struct result becomes a hidden first parameter.
    int SignatureOf(IrFunc f)
    {
        var ps = List<int>.Create();
        var results = List<int>.Create();
        if (T.IsAggregate(f.Ret))
            ps.Add(I32);
        else if (T.Kind(f.Ret) != IrKind.Void)
            results.Add(ValType(f.Ret));
        foreach (var p in f.Params)
            ps.Add(ValType(p.Type));
        return FuncType(ps, results);
    }

    // -----------------------------------------------------------------------
    // What the program uses
    // -----------------------------------------------------------------------

    void Reach(string name)
    {
        if (Reached.Contains(name))
            return;
        Reached.Add(name);
        Work.Add(name);
    }

    // The global that an external global of the IR means: the C library defines stdout as a global of stdlib/wasm.
    string GlobalName(string name)
    {
        var found = M.GlobalIndex.TryGet(name);
        if (found is int index && M.Globals.Get(index).Init >= 0)
            return name;
        string runtime = "global.System.Wasm." + name;
        if (M.GlobalIndex.ContainsKey(runtime))
            return runtime;
        return name;
    }

    void ReachValue(int vi)
    {
        var v = M.Vals.Get(vi);
        if (v.Kind == ValKind.Global)
        {
            if (M.FuncIndex.ContainsKey(v.Name))
                Reach(v.Name);
            else
                Reach(GlobalName(v.Name));
        }
        foreach (var item in v.Items)
            ReachValue(item);
    }

    // The C functions whose calls are instructions (and builtins of the backend).
    bool IsInlineCall(string name)
    {
        return name == "sqrt" || name == "sqrtf" || name == "fabs" || name == "fabsf" || name == "floor" || name == "floorf" ||
               name == "ceil" || name == "ceilf" || name == "trunc" || name == "truncf" || name == "nearbyint" ||
               name == "nearbyintf" || name == "rint" || name == "rintf" || name == "memcpy" || name == "memmove" || name == "memset" ||
               name == "__cs_wasm_memory_size" || name == "__cs_wasm_memory_grow" || name == "__cs_wasm_heap_base";
    }

    // The function a call of 'name' calls ("" for an instruction).
    string CallTarget(string name)
    {
        if (name.StartsWith("llvm.") || IsInlineCall(name))
            return "";
        var found = M.FuncIndex.TryGet(name);
        if (found is int index && M.Funcs.Get(index).Varargs)
            return "__cs_va_" + name;
        return name;
    }

    // From _start on: every function and global that is used, and the size of the block of zeros.
    void FindReached()
    {
        Reach("__cs_wasm_start");
        int next = 0;
        while (next < Work.Count())
        {
            string name = Work.Get(next);
            next += 1;
            var fi = M.FuncIndex.TryGet(name);
            if (fi is int funcIndex)
            {
                var f = M.Funcs.Get(funcIndex);
                if (!f.Defined)
                    continue;
                foreach (var block in f.Blocks.ToArray())
                {
                    foreach (var inst in block.Insts.ToArray())
                    {
                        if (inst.Callee >= 0)
                        {
                            var callee = M.Vals.Get(inst.Callee);
                            if (callee.Kind == ValKind.Global)
                            {
                                string target = CallTarget(callee.Name);
                                if (target.Length > 0)
                                    Reach(target);
                            }
                        }
                        if (inst.Op == "frem")
                            Reach(T.Kind(inst.Type) == IrKind.Float ? "fmodf" : "fmod");
                        foreach (var a in inst.Args)
                        {
                            ReachValue(a);
                            var av = M.Vals.Get(a);
                            if (av.Kind == ValKind.Zero && T.IsAggregate(av.Type) && L.Size(av.Type) > ZeroSize)
                                ZeroSize = L.Size(av.Type);
                        }
                    }
                }
                continue;
            }
            var gi = M.GlobalIndex.TryGet(name);
            if (gi is int globalIndex)
            {
                var g = M.Globals.Get(globalIndex);
                if (g.Init >= 0)
                    ReachValue(g.Init);
                else
                    Fail("the global '" + name + "' is not defined");
                continue;
            }
            Fail("'" + name + "' is not defined");
        }
    }

    // -----------------------------------------------------------------------
    // Memory: globals and constants
    // -----------------------------------------------------------------------

    bool IsZero(int vi)
    {
        var v = M.Vals.Get(vi);
        switch (v.Kind)
        {
        case ValKind.Null:
        case ValKind.Zero:
            return true;
        case ValKind.Int:
        case ValKind.FloatBits:
            return v.Int == 0;
        case ValKind.Bytes:
            foreach (var c in v.Text)
            {
                if (c != (char)0)
                    return false;
            }
            return true;
        case ValKind.Aggregate:
            foreach (var item in v.Items)
            {
                if (!IsZero(item))
                    return false;
            }
            return true;
        default:
            return false;
        }
    }

    // The addresses of the globals: [StackSize, ...) the globals that start as zeros and the block of zeros, then the
    // data segment with the others.
    void LayoutGlobals()
    {
        int pos = StackSize;
        var withData = List<int>.Create();
        for (var i = 0; i < M.Globals.Count(); i += 1)
        {
            var g = M.Globals.Get(i);
            if (g.Init < 0 || !Reached.Contains(g.Name))
                continue;
            if (!IsZero(g.Init))
            {
                withData.Add(i);
                continue;
            }
            pos = WasmAlignTo(pos, L.Align(g.Type));
            GlobalAddr.Set(g.Name, pos);
            pos += L.Size(g.Type) > 0 ? L.Size(g.Type) : 1;
        }
        pos = WasmAlignTo(pos, 16);
        ZeroBlock = pos;
        pos += ZeroSize;
        DataStart = WasmAlignTo(pos, 16);
        // the addresses first (the values may refer to each other), then the bytes
        int at = DataStart;
        foreach (var i in withData.ToArray())
        {
            var g = M.Globals.Get(i);
            at = WasmAlignTo(at, L.Align(g.Type));
            GlobalAddr.Set(g.Name, at);
            at += L.Size(g.Type);
        }
        foreach (var i in withData.ToArray())
        {
            var g = M.Globals.Get(i);
            Data.PadTo(GlobalAddr.Get(g.Name) - DataStart);
            WriteConst(g.Init, g.Type);
        }
    }

    // The bytes of a constant at the end of Data (Size(t) bytes).
    void WriteConst(int vi, int t)
    {
        var v = M.Vals.Get(vi);
        int start = Data.Count();
        int size = L.Size(t);
        switch (v.Kind)
        {
        case ValKind.Int:
            Data.Fixed(v.Int, size);
            break;
        case ValKind.FloatBits:
            if (T.Kind(t) == IrKind.Float)
                Data.Fixed(FloatBitsOfDouble(v.Int), 4);
            else
                Data.Fixed(v.Int, 8);
            break;
        case ValKind.Global:
        case ValKind.Expr:
            Data.Fixed(ConstValue(vi), size);
            break;
        case ValKind.Bytes:
            foreach (var c in v.Text)
                Data.Byte((int)c);
            break;
        case ValKind.Aggregate:
        {
            var info = T.Info(t);
            for (var i = 0; i < v.Items.Length; i += 1)
            {
                Data.PadTo(start + L.FieldOffset(t, i));
                WriteConst(v.Items[i], info.Kind == IrKind.Array ? info.Elem : info.Fields[i]);
            }
            break;
        }
        default:
            break; // null, zeroinitializer
        }
        Data.PadTo(start + size);
    }

    // The address of a constant (struct, array, string) in the data segment.
    int ConstAddress(int vi, int t)
    {
        if (IsZero(vi) && L.Size(t) <= ZeroSize)
            return ZeroBlock;
        Data.PadTo(WasmAlignTo(Data.Count(), L.Align(t) > 4 ? L.Align(t) : 4));
        int address = DataStart + Data.Count();
        WriteConst(vi, t);
        return address;
    }

    // The table slot of a function (its address).
    int SlotOf(string name)
    {
        var found = TableSlot.TryGet(name);
        if (found is int slot)
            return slot;
        var index = FuncIndex.TryGet(name);
        if (index is int fi)
        {
            Table.Add(fi);
            TableSlot.Set(name, Table.Count());
            return Table.Count();
        }
        Fail("the address of '" + name + "' is taken, but it is not a function of the program");
        return 0;
    }

    // The address of a global or function.
    int64 AddressOf(string name)
    {
        if (M.FuncIndex.ContainsKey(name))
            return SlotOf(name);
        var found = GlobalAddr.TryGet(GlobalName(name));
        if (found is int address)
            return address;
        Fail("unknown global '" + name + "'");
        return 0;
    }

    // The value of an integer or address constant (also constant expressions).
    int64 ConstValue(int vi)
    {
        var v = M.Vals.Get(vi);
        switch (v.Kind)
        {
        case ValKind.Int:
            return v.Int;
        case ValKind.Null:
        case ValKind.Zero:
            return 0;
        case ValKind.Global:
            return AddressOf(v.Name);
        case ValKind.Expr:
        {
            if (v.Text == "getelementptr")
            {
                int64 address = ConstValue(v.Items[0]);
                int cur = v.ExprType;
                for (var i = 1; i < v.Items.Length; i += 1)
                {
                    int64 index = ConstValue(v.Items[i]);
                    if (i == 1)
                        address += index * L.Stride(cur);
                    else
                    {
                        var info = T.Info(cur);
                        if (info.Kind == IrKind.Struct)
                        {
                            address += L.FieldOffset(cur, (int)index);
                            cur = info.Fields[(int)index];
                        }
                        else
                        {
                            address += index * L.Stride(info.Elem);
                            cur = info.Elem;
                        }
                    }
                }
                return address;
            }
            int64 inner = ConstValue(v.Items[0]);
            if (v.Text == "trunc")
                return WasmTruncate(inner, T.Bits(v.ExprType), false);
            if (v.Text == "sext")
                return WasmTruncate(inner, Width(M.Vals.Get(v.Items[0]).Type), true);
            return inner;
        }
        default:
            Fail("a constant that is not a number");
            return 0;
        }
    }

    // -----------------------------------------------------------------------
    // Writing instructions
    // -----------------------------------------------------------------------

    void Op(int code) { Code.Byte(code); }

    void I32Const(int64 value)
    {
        Code.Byte(65); // 0x41
        Code.S64(WasmTruncate(value, 32, true));
    }

    void I64Const(int64 value)
    {
        Code.Byte(66); // 0x42
        Code.S64(value);
    }

    void LocalGet(int local)
    {
        Code.Byte(32);
        Code.U32(local);
    }

    void LocalSet(int local)
    {
        Code.Byte(33);
        Code.U32(local);
    }

    void LocalTee(int local)
    {
        Code.Byte(34);
        Code.U32(local);
    }

    // memory access: the opcode, then align (log2) and offset
    void MemOp(int code, int alignLog, int64 offset)
    {
        Code.Byte(code);
        Code.U32(alignLog);
        Code.U32(offset);
    }

    void MemoryCopy()
    {
        Code.Byte(252); // 0xFC 10 0 0
        Code.U32(10);
        Code.Byte(0);
        Code.Byte(0);
    }

    void MemoryFill()
    {
        Code.Byte(252); // 0xFC 11 0
        Code.U32(11);
        Code.Byte(0);
    }

    // Loads a value of type t from the address on the stack (+ offset).
    void Load(int t, int64 offset)
    {
        var info = T.Info(t);
        switch (info.Kind)
        {
        case IrKind.Int:
            if (info.Bits <= 8)
                MemOp(45, 0, offset);       // i32.load8_u
            else if (info.Bits == 16)
                MemOp(47, 1, offset);       // i32.load16_u
            else if (info.Bits == 32)
                MemOp(40, 2, offset);       // i32.load
            else if (info.Bits == 64)
                MemOp(41, 3, offset);       // i64.load
            else
                Fail("cannot load an i" + info.Bits.ToString());
            break;
        case IrKind.Ptr:
            MemOp(40, 2, offset);
            break;
        case IrKind.Float:
            MemOp(42, 2, offset);
            break;
        case IrKind.Double:
            MemOp(43, 3, offset);
            break;
        default:
            Fail("cannot load a value of type " + T.Text(t));
            break;
        }
    }

    // Stores the value on the stack (of type t) at the address below it (+ offset).
    void Store(int t, int64 offset)
    {
        var info = T.Info(t);
        switch (info.Kind)
        {
        case IrKind.Int:
            if (info.Bits <= 8)
                MemOp(58, 0, offset);       // i32.store8
            else if (info.Bits == 16)
                MemOp(59, 1, offset);       // i32.store16
            else if (info.Bits == 32)
                MemOp(54, 2, offset);       // i32.store
            else if (info.Bits == 64)
                MemOp(55, 3, offset);       // i64.store
            else
                Fail("cannot store an i" + info.Bits.ToString());
            break;
        case IrKind.Ptr:
            MemOp(54, 2, offset);
            break;
        case IrKind.Float:
            MemOp(56, 2, offset);
            break;
        case IrKind.Double:
            MemOp(57, 3, offset);
            break;
        default:
            Fail("cannot store a value of type " + T.Text(t));
            break;
        }
    }

    // Keeps the low 'bits' bits of the i32 on the stack.
    void Mask(int bits)
    {
        if (bits >= 32)
            return;
        I32Const(((int64)1 << bits) - 1);
        Op(113); // i32.and
    }

    // Sign-extends the low 'bits' bits of the i32 on the stack to 32 bits.
    void SignExtend(int bits)
    {
        if (bits == 8)
            Op(192);      // i32.extend8_s
        else if (bits == 16)
            Op(193);      // i32.extend16_s
        else if (bits < 32)
        {
            I32Const(32 - bits);
            Op(116);      // shl
            I32Const(32 - bits);
            Op(117);      // shr_s
        }
    }

    // Pushes a value of the IR.
    void Push(int vi)
    {
        var v = M.Vals.Get(vi);
        switch (v.Kind)
        {
        case ValKind.Local:
        {
            var found = Local.TryGet(v.Name);
            if (found is int local)
                LocalGet(local);
            else
            {
                Fail("unknown value %" + v.Name);
                I32Const(0);
            }
            break;
        }
        case ValKind.Int:
            PushInt(v.Int, v.Type);
            break;
        case ValKind.FloatBits:
            if (T.Kind(v.Type) == IrKind.Float)
            {
                Op(67); // f32.const
                Code.Fixed(FloatBitsOfDouble(v.Int), 4);
            }
            else
            {
                Op(68); // f64.const
                Code.Fixed(v.Int, 8);
            }
            break;
        case ValKind.Null:
            I32Const(0);
            break;
        case ValKind.Zero:
            if (T.IsAggregate(v.Type))
                I32Const(ConstAddress(vi, v.Type));
            else
                PushZero(v.Type);
            break;
        case ValKind.Global:
            I32Const(AddressOf(v.Name));
            break;
        case ValKind.Expr:
            PushInt(ConstValue(vi), v.Type);
            break;
        default:
            I32Const(ConstAddress(vi, v.Type)); // structs, arrays, strings
            break;
        }
    }

    void PushInt(int64 value, int t)
    {
        if (ValType(t) == I64)
            I64Const(value);
        else
            I32Const(WasmTruncate(value, Width(t), false));
    }

    void PushZero(int t)
    {
        int vt = ValType(t);
        if (vt == I64)
            I64Const(0);
        else if (vt == F32)
        {
            Op(67);
            Code.Fixed(0, 4);
        }
        else if (vt == F64)
        {
            Op(68);
            Code.Fixed(0, 8);
        }
        else
            I32Const(0);
    }

    // Pushes an integer sign-extended to its wasm type.
    void PushSigned(int vi, int t)
    {
        Push(vi);
        if (ValType(t) == I32)
            SignExtend(Width(t));
    }

    // Pushes an integer as an i64, extended with its sign or with zeros.
    void PushI64(int vi, bool signed)
    {
        int t = M.Vals.Get(vi).Type;
        if (ValType(t) == I64)
        {
            Push(vi);
            return;
        }
        if (signed)
        {
            PushSigned(vi, t);
            Op(172); // i64.extend_i32_s
        }
        else
        {
            Push(vi);
            Op(173); // i64.extend_i32_u
        }
    }

    // Pushes an index (i32 or i64) as an i32, with its sign.
    void PushIndex(int vi)
    {
        int t = M.Vals.Get(vi).Type;
        if (ValType(t) == I64)
        {
            Push(vi);
            Op(167); // i32.wrap_i64
        }
        else
            PushSigned(vi, t);
    }

    bool IsConstInt(int vi)
    {
        var v = M.Vals.Get(vi);
        return v.Kind == ValKind.Int || v.Kind == ValKind.Null || (v.Kind == ValKind.Zero && !T.IsAggregate(v.Type));
    }

    bool IsZeroConst(int vi)
    {
        var v = M.Vals.Get(vi);
        return v.Kind == ValKind.Zero || v.Kind == ValKind.Null;
    }

    // Copies a struct value (its address is the value) to the address 'dst' pushes.
    void CopyValue(int dstLocal, int64 dstOffset, int vi, int t)
    {
        int size = L.Size(t);
        if (size == 0)
            return;
        LocalGet(dstLocal);
        if (dstOffset != 0)
        {
            I32Const(dstOffset);
            Op(106); // i32.add
        }
        if (IsZeroConst(vi))
        {
            I32Const(0);
            I32Const(size);
            MemoryFill();
            return;
        }
        Push(vi);
        I32Const(size);
        MemoryCopy();
    }

    void SetResult(IrInst inst)
    {
        if (inst.Res.Length == 0)
        {
            Op(26); // drop
            return;
        }
        LocalSet(Local.Get(inst.Res));
    }

    int NewLocal(int vt)
    {
        LocalTypes.Add(vt);
        return LocalTypes.Count() - 1;
    }

    int AllocSlot(int size, int align)
    {
        FrameSize = WasmAlignTo(FrameSize, align > 4 ? align : 4);
        int offset = FrameSize;
        FrameSize += size > 0 ? size : 1;
        return offset;
    }

    // A local that holds the address of a new slot of the frame.
    int SlotLocal(int t)
    {
        int local = NewLocal(I32);
        SlotInits.Add(SlotInit { Local = local, Offset = AllocSlot(L.Size(t), L.Align(t)) });
        return local;
    }

    // -----------------------------------------------------------------------
    // Functions
    // -----------------------------------------------------------------------

    void CountUse(int vi)
    {
        var v = M.Vals.Get(vi);
        if (v.Kind == ValKind.Local)
            Uses.Set(v.Name, Uses.GetOrDefault(v.Name, 0) + 1);
    }

    bool IsOverflowCall(IrInst inst)
    {
        if (inst.Op != "call" || inst.Callee < 0)
            return false;
        var callee = M.Vals.Get(inst.Callee);
        return callee.Kind == ValKind.Global && callee.Name.StartsWith("llvm.") && callee.Name.Contains(".with.overflow.");
    }

    // Can the struct value 'base' be changed in place by the insertvalue that uses it? Only when that is its only use
    // and its bytes are its own (a slot of the frame, not a parameter, a part of another value or a constant).
    bool OwnsSlot(int vi)
    {
        var v = M.Vals.Get(vi);
        if (v.Kind != ValKind.Local || Uses.GetOrDefault(v.Name, 0) != 1)
            return false;
        var def = Def.TryGet(v.Name);
        if (def is IrInst d)
            return (d.Op == "load" || d.Op == "insertvalue" || (d.Op == "call" && !IsOverflowCall(d))) && !SplitFlag.ContainsKey(v.Name);
        return false;
    }

    // The body of a function: locals, then the code.
    Bytes GenFunction(IrFunc f)
    {
        FnName = f.Name;
        Code = Bytes.Create();
        LocalTypes.Clear();
        SlotInits.Clear();
        Local.Clear();
        PhiTmp.Clear();
        SplitFlag.Clear();
        Uses.Clear();
        Def.Clear();
        BlockIndex.Clear();
        PosSlot.Clear();
        Blocks = f.Blocks;
        FrameSize = 0;
        Depth = 0;
        Sret = -1;

        // the parameters
        if (T.IsAggregate(f.Ret))
            Sret = NewLocal(I32);
        foreach (var p in f.Params)
        {
            int local = NewLocal(ValType(p.Type));
            if (p.Name.Length > 0)
                Local.Set(p.Name, local);
        }
        int paramCount = LocalTypes.Count();
        FramePointer = NewLocal(I32);
        Pc = NewLocal(I32);

        // the blocks, the uses of the values, the jumps back
        for (var b = 0; b < Blocks.Count(); b += 1)
            BlockIndex.Set(Blocks.Get(b).Label, b);
        HasLoop = false;
        for (var b = 0; b < Blocks.Count(); b += 1)
        {
            foreach (var inst in Blocks.Get(b).Insts.ToArray())
            {
                if (inst.Res.Length > 0)
                    Def.Set(inst.Res, inst);
                foreach (var a in inst.Args)
                    CountUse(a);
                if (inst.Callee >= 0)
                    CountUse(inst.Callee);
                if (inst.Op == "br" || inst.Op == "switch")
                {
                    foreach (var label in inst.Labels)
                    {
                        if (BlockIndex.GetOrDefault(label, 0) <= b)
                            HasLoop = true;
                    }
                }
            }
        }

        // { iN, i1 } results that are only taken apart live in two locals
        foreach (var block in Blocks.ToArray())
        {
            foreach (var inst in block.Insts.ToArray())
            {
                if (IsOverflowCall(inst) && inst.Res.Length > 0)
                    SplitFlag.Set(inst.Res, -1);
            }
        }
        foreach (var block in Blocks.ToArray())
        {
            foreach (var inst in block.Insts.ToArray())
            {
                for (var i = 0; i < inst.Args.Length; i += 1)
                {
                    var v = M.Vals.Get(inst.Args[i]);
                    if (v.Kind == ValKind.Local && SplitFlag.ContainsKey(v.Name) && !(inst.Op == "extractvalue" && i == 0 && inst.Cases.Length == 1))
                        SplitFlag.Remove(v.Name);
                }
            }
        }

        // the locals of the values
        var shared = List<IrInst>.Create();
        foreach (var block in Blocks.ToArray())
        {
            foreach (var inst in block.Insts.ToArray())
            {
                if (inst.Res.Length == 0)
                    continue;
                if (inst.Op == "alloca")
                {
                    Local.Set(inst.Res, SlotLocal(inst.OpType));
                    continue;
                }
                if (SplitFlag.ContainsKey(inst.Res))
                {
                    Local.Set(inst.Res, NewLocal(ValType(T.Info(inst.Type).Fields[0])));
                    SplitFlag.Set(inst.Res, NewLocal(I32));
                    continue;
                }
                bool aggregate = T.IsAggregate(inst.Type);
                if (inst.Op == "phi")
                {
                    if (aggregate)
                    {
                        Local.Set(inst.Res, SlotLocal(inst.Type));
                        PhiTmp.Set(inst.Res, SlotLocal(inst.Type));
                    }
                    else
                    {
                        Local.Set(inst.Res, NewLocal(ValType(inst.Type)));
                        PhiTmp.Set(inst.Res, NewLocal(ValType(inst.Type)));
                    }
                    continue;
                }
                if (aggregate && inst.Op == "insertvalue" && OwnsSlot(inst.Args[0]))
                {
                    shared.Add(inst);
                    continue;
                }
                if (aggregate && (inst.Op == "load" || inst.Op == "insertvalue" || inst.Op == "call"))
                    Local.Set(inst.Res, SlotLocal(inst.Type));
                else
                    Local.Set(inst.Res, NewLocal(ValType(inst.Type)));
            }
        }
        // the slots of calls: packed variable arguments, struct results that are not used
        for (var b = 0; b < Blocks.Count(); b += 1)
        {
            var insts = Blocks.Get(b).Insts;
            for (var i = 0; i < insts.Count(); i += 1)
            {
                var inst = insts.Get(i);
                if (inst.Op != "call")
                    continue;
                string key = b.ToString() + ":" + i.ToString();
                if (T.IsAggregate(inst.Type) && inst.Res.Length == 0)
                    PosSlot.Set(key, SlotLocal(inst.Type));
                int packed = VarargsSize(inst);
                if (packed > 0)
                {
                    int local = NewLocal(I32);
                    SlotInits.Add(SlotInit { Local = local, Offset = AllocSlot(packed, 8) });
                    PosSlot.Set(key, local);
                }
            }
        }

        // an insertvalue that changes its base in place has the base's slot (bases first: they may be shared too)
        int pending = shared.Count();
        while (pending > 0)
        {
            int before = pending;
            foreach (var inst in shared.ToArray())
            {
                if (Local.ContainsKey(inst.Res))
                    continue;
                string baseName = M.Vals.Get(inst.Args[0]).Name;
                var found = Local.TryGet(baseName);
                if (found is int local)
                {
                    Local.Set(inst.Res, local);
                    pending -= 1;
                }
            }
            if (pending == before)
            {
                Fail("cannot place the struct values");
                break;
            }
        }

        FrameSize = WasmAlignTo(FrameSize, 16);

        // the code
        if (HasLoop)
        {
            Op(3);  // loop
            Op(64);
        }
        int opened = HasLoop ? Blocks.Count() : Blocks.Count() - 1;
        for (var i = 0; i < opened; i += 1)
        {
            Op(2);  // block
            Op(64);
        }
        if (HasLoop)
        {
            LocalGet(Pc);
            Op(14); // br_table 0 1 ... n-1, default 0
            Code.U32(Blocks.Count());
            for (var i = 0; i < Blocks.Count(); i += 1)
                Code.U32(i);
            Code.U32(0);
            Op(11); // the end of block 0
        }
        for (var b = 0; b < Blocks.Count(); b += 1)
        {
            if (b > 0)
                Op(11); // the end of block b: its code follows
            Current = b;
            Depth = 0;
            var insts = Blocks.Get(b).Insts;
            for (var i = 0; i < insts.Count(); i += 1)
            {
                Position = i;
                GenInst(insts.Get(i));
            }
        }
        if (HasLoop)
            Op(11);  // the end of the loop
        Op(0);       // unreachable
        Op(11);      // the end of the function

        // the frame: the prologue allocates it on the shadow stack and sets the locals of the slots
        var body = Bytes.Create();
        var groups = List<int>.Create(); // count, type, count, type ...
        for (var i = paramCount; i < LocalTypes.Count(); i += 1)
        {
            int vt = LocalTypes.Get(i);
            if (groups.Count() > 0 && groups.Get(groups.Count() - 1) == vt)
                groups.Set(groups.Count() - 2, groups.Get(groups.Count() - 2) + 1);
            else
            {
                groups.Add(1);
                groups.Add(vt);
            }
        }
        body.U32(groups.Count() / 2);
        for (var i = 0; i < groups.Count(); i += 2)
        {
            body.U32(groups.Get(i));
            body.Byte(groups.Get(i + 1));
        }
        var main = Code;
        Code = body;
        if (FrameSize > 0)
        {
            Op(35);      // global.get $sp
            Code.U32(0);
            I32Const(FrameSize);
            Op(107);     // i32.sub
            LocalTee(FramePointer);
            Op(36);      // global.set $sp
            Code.U32(0);
            foreach (var init in SlotInits.ToArray())
            {
                LocalGet(FramePointer);
                if (init.Offset != 0)
                {
                    I32Const(init.Offset);
                    Op(106);
                }
                LocalSet(init.Local);
            }
        }
        body.Append(main);
        Code = main;
        return body;
    }

    // -----------------------------------------------------------------------
    // Instructions
    // -----------------------------------------------------------------------

    void GenInst(IrInst inst)
    {
        string op = inst.Op;
        if (op == "add" || op == "sub" || op == "mul" || op == "sdiv" || op == "udiv" || op == "srem" || op == "urem" || op == "and" ||
            op == "or" || op == "xor" || op == "shl" || op == "lshr" || op == "ashr")
            GenIntBinary(inst);
        else if (op == "fadd" || op == "fsub" || op == "fmul" || op == "fdiv" || op == "frem")
            GenFloatBinary(inst);
        else if (op == "icmp")
            GenIcmp(inst);
        else if (op == "fcmp")
            GenFcmp(inst);
        else if (op == "sext" || op == "zext" || op == "trunc" || op == "bitcast" || op == "ptrtoint" || op == "inttoptr" ||
                 op == "fptrunc" || op == "fpext" || op == "sitofp" || op == "uitofp" || op == "fptosi" || op == "fptoui")
            GenCast(inst);
        else if (op == "load")
        {
            if (T.IsAggregate(inst.Type))
                CopyValue(Local.Get(inst.Res), 0, inst.Args[0], inst.Type);
            else
            {
                Push(inst.Args[0]);
                Load(inst.Type, 0);
                SetResult(inst);
            }
        }
        else if (op == "store")
        {
            if (T.IsAggregate(inst.OpType))
            {
                int dst = NewLocal(I32);
                Push(inst.Args[1]);
                LocalSet(dst);
                CopyValue(dst, 0, inst.Args[0], inst.OpType);
            }
            else
            {
                Push(inst.Args[1]);
                Push(inst.Args[0]);
                Store(inst.OpType, 0);
            }
        }
        else if (op == "alloca" || op == "phi")
        {
            // the prologue sets the address; phis are set by the jumps
        }
        else if (op == "getelementptr")
            GenGep(inst);
        else if (op == "extractvalue")
            GenExtract(inst);
        else if (op == "insertvalue")
            GenInsert(inst);
        else if (op == "select")
        {
            Push(inst.Args[1]);
            Push(inst.Args[2]);
            Push(inst.Args[0]);
            Op(27); // select
            SetResult(inst);
        }
        else if (op == "br")
            GenBr(inst);
        else if (op == "switch")
            GenSwitch(inst);
        else if (op == "ret")
        {
            if (inst.Args.Length > 0 && Sret >= 0)
            {
                CopyValue(Sret, 0, inst.Args[0], inst.OpType);
                Epilogue();
            }
            else
            {
                Epilogue();
                if (inst.Args.Length > 0)
                    Push(inst.Args[0]);
            }
            Op(15); // return
        }
        else if (op == "unreachable")
            Op(0);
        else if (op == "call")
            GenCall(inst);
        else if (op == "atomicrmw")
            GenAtomic(inst);
        else
            Fail("the wasm backend does not know the instruction '" + op + "'");
    }

    void GenIntBinary(IrInst inst)
    {
        string op = inst.Op;
        int t = inst.Type;
        bool wide = ValType(t) == I64;
        int bits = Width(t);
        // i32 opcodes; the i64 ones are 18 higher (add 0x6A -> 0x7C)
        int code = 0;
        bool signed = false;
        bool mask = false;
        if (op == "add") { code = 106; mask = true; }
        else if (op == "sub") { code = 107; mask = true; }
        else if (op == "mul") { code = 108; mask = true; }
        else if (op == "sdiv") { code = 109; signed = true; mask = true; }
        else if (op == "udiv") code = 110;
        else if (op == "srem") { code = 111; signed = true; mask = true; }
        else if (op == "urem") code = 112;
        else if (op == "and") code = 113;
        else if (op == "or") code = 114;
        else if (op == "xor") code = 115;
        else if (op == "shl") { code = 116; mask = true; }
        else if (op == "ashr") { code = 117; mask = true; }
        else if (op == "lshr") code = 118;
        if (signed || op == "ashr")
            PushSigned(inst.Args[0], t);
        else
            Push(inst.Args[0]);
        if (signed)
            PushSigned(inst.Args[1], t);
        else
            Push(inst.Args[1]);
        Op(wide ? code + 18 : code);
        if (!wide && mask)
            Mask(bits);
        SetResult(inst);
    }

    void GenFloatBinary(IrInst inst)
    {
        bool single = T.Kind(inst.Type) == IrKind.Float;
        if (inst.Op == "frem")
        {
            Push(inst.Args[0]);
            Push(inst.Args[1]);
            CallFunction(single ? "fmodf" : "fmod");
            SetResult(inst);
            return;
        }
        int code = inst.Op == "fadd" ? 160 : inst.Op == "fsub" ? 161 : inst.Op == "fmul" ? 162 : 163; // f64.add/sub/mul/div
        Push(inst.Args[0]);
        Push(inst.Args[1]);
        Op(single ? code - 14 : code);
        SetResult(inst);
    }

    void GenIcmp(IrInst inst)
    {
        int t = inst.OpType;
        bool wide = ValType(t) == I64;
        string p = inst.Pred;
        bool signed = p == "slt" || p == "sle" || p == "sgt" || p == "sge";
        int code = p == "eq" ? 70 : p == "ne" ? 71 : p == "slt" ? 72 : p == "ult" ? 73 : p == "sgt" ? 74 : p == "ugt" ? 75 :
                   p == "sle" ? 76 : p == "ule" ? 77 : p == "sge" ? 78 : 79;
        if (signed)
        {
            PushSigned(inst.Args[0], t);
            PushSigned(inst.Args[1], t);
        }
        else
        {
            Push(inst.Args[0]);
            Push(inst.Args[1]);
        }
        Op(wide ? code + 11 : code);
        SetResult(inst);
    }

    // one comparison of floats: eq ne lt gt le ge
    void FloatCompare(IrInst inst, int which)
    {
        bool single = T.Kind(inst.OpType) == IrKind.Float;
        Push(inst.Args[0]);
        Push(inst.Args[1]);
        Op((single ? 91 : 97) + which);
    }

    void IsNaN(IrInst inst, int arg)
    {
        bool single = T.Kind(inst.OpType) == IrKind.Float;
        Push(inst.Args[arg]);
        Push(inst.Args[arg]);
        Op(single ? 92 : 98); // ne
    }

    void GenFcmp(IrInst inst)
    {
        string p = inst.Pred;
        if (p == "oeq") FloatCompare(inst, 0);
        else if (p == "une") FloatCompare(inst, 1);
        else if (p == "olt") FloatCompare(inst, 2);
        else if (p == "ogt") FloatCompare(inst, 3);
        else if (p == "ole") FloatCompare(inst, 4);
        else if (p == "oge") FloatCompare(inst, 5);
        else if (p == "ult" || p == "ugt" || p == "ule" || p == "uge")
        {
            // unordered or ...: not the ordered opposite
            FloatCompare(inst, p == "ult" ? 5 : p == "ugt" ? 4 : p == "ule" ? 3 : 2);
            Op(69); // i32.eqz
        }
        else if (p == "one" || p == "ueq")
        {
            FloatCompare(inst, 2);
            FloatCompare(inst, 3);
            Op(114); // or
            if (p == "ueq")
                Op(69);
        }
        else if (p == "uno" || p == "ord")
        {
            IsNaN(inst, 0);
            IsNaN(inst, 1);
            Op(114);
            if (p == "ord")
                Op(69);
        }
        else if (p == "true")
            I32Const(1);
        else if (p == "false")
            I32Const(0);
        else
            Fail("unknown fcmp predicate '" + p + "'");
        SetResult(inst);
    }

    void GenCast(IrInst inst)
    {
        string op = inst.Op;
        int from = inst.OpType;
        int to = inst.Type;
        int a = inst.Args[0];
        int fv = ValType(from);
        int tv = ValType(to);
        if (op == "zext" || op == "ptrtoint" || op == "inttoptr" || op == "trunc")
        {
            Push(a);
            if (fv == I32 && tv == I64)
                Op(173); // i64.extend_i32_u
            else if (fv == I64 && tv == I32)
                Op(167); // i32.wrap_i64
            if (tv == I32)
                Mask(Width(to));
        }
        else if (op == "sext")
        {
            PushSigned(a, from);
            if (tv == I64 && fv == I32)
                Op(172); // i64.extend_i32_s
            if (tv == I32)
                Mask(Width(to));
        }
        else if (op == "bitcast")
        {
            Push(a);
            if (fv == F32 && tv == I32) Op(188);
            else if (fv == F64 && tv == I64) Op(189);
            else if (fv == I32 && tv == F32) Op(190);
            else if (fv == I64 && tv == F64) Op(191);
        }
        else if (op == "fptrunc")
        {
            Push(a);
            Op(182); // f32.demote_f64
        }
        else if (op == "fpext")
        {
            Push(a);
            Op(187); // f64.promote_f32
        }
        else if (op == "sitofp" || op == "uitofp")
        {
            bool signed = op == "sitofp";
            if (signed)
                PushSigned(a, from);
            else
                Push(a);
            // f32.convert_i32_s 0xB2 .. f64.convert_i64_u 0xBA
            int code = tv == F32 ? 178 : 183;
            if (fv == I64)
                code += 2;
            if (!signed)
                code += 1;
            Op(code);
        }
        else
        {
            // fptosi/fptoui: saturating (out of range is poison in the IR; wasm's trapping conversion would trap)
            Push(a);
            TruncSat(fv, to, op == "fptosi");
        }
        SetResult(inst);
    }

    // The float on the stack converted to the integer type 'to' (saturating).
    void TruncSat(int fromVt, int to, bool signed)
    {
        bool wide = ValType(to) == I64;
        int sub = (wide ? 4 : 0) + (fromVt == F64 ? 2 : 0) + (signed ? 0 : 1);
        Op(252);
        Code.U32(sub);
        int bits = Width(to);
        if (wide || bits >= 32)
            return;
        // narrower: clamp the i32 to the range of the type
        int t = NewLocal(I32);
        LocalSet(t);
        int64 lo = signed ? -((int64)1 << (bits - 1)) : 0;
        int64 hi = signed ? ((int64)1 << (bits - 1)) - 1 : ((int64)1 << bits) - 1;
        I32Const(lo);
        LocalGet(t);
        LocalGet(t);
        I32Const(lo);
        Op(signed ? 72 : 73); // t < lo
        Op(27);
        LocalSet(t);
        I32Const(hi);
        LocalGet(t);
        LocalGet(t);
        I32Const(hi);
        Op(signed ? 74 : 75); // t > hi
        Op(27);
        Mask(bits);
    }

    void GenGep(IrInst inst)
    {
        Push(inst.Args[0]);
        int64 offset = 0;
        int cur = inst.OpType;
        for (var i = 1; i < inst.Args.Length; i += 1)
        {
            int idx = inst.Args[i];
            int stride;
            if (i == 1)
                stride = L.Stride(cur);
            else
            {
                var info = T.Info(cur);
                if (info.Kind == IrKind.Struct)
                {
                    int field = (int)ConstValue(idx);
                    offset += L.FieldOffset(cur, field);
                    cur = info.Fields[field];
                    continue;
                }
                stride = L.Stride(info.Elem);
                cur = info.Elem;
            }
            if (IsConstInt(idx))
            {
                var iv = M.Vals.Get(idx);
                offset += WasmTruncate(ConstValue(idx), Width(iv.Type) > 32 ? 64 : Width(iv.Type), true) * stride;
                continue;
            }
            PushIndex(idx);
            if (stride != 1)
            {
                I32Const(stride);
                Op(108); // i32.mul
            }
            Op(106);
        }
        if (WasmTruncate(offset, 32, true) != 0)
        {
            I32Const(offset);
            Op(106);
        }
        SetResult(inst);
    }

    // The offset of a path of extractvalue/insertvalue indexes.
    int PathOffset(int t, int64[] path)
    {
        int offset = 0;
        int cur = t;
        foreach (var i in path)
        {
            offset += L.FieldOffset(cur, (int)i);
            var info = T.Info(cur);
            cur = info.Kind == IrKind.Array ? info.Elem : info.Fields[(int)i];
        }
        return offset;
    }

    void GenExtract(IrInst inst)
    {
        var agg = M.Vals.Get(inst.Args[0]);
        if (agg.Kind == ValKind.Local && SplitFlag.ContainsKey(agg.Name))
        {
            LocalGet(inst.Cases[0] == 0 ? Local.Get(agg.Name) : SplitFlag.Get(agg.Name));
            SetResult(inst);
            return;
        }
        int offset = PathOffset(inst.OpType, inst.Cases);
        Push(inst.Args[0]);
        if (T.IsAggregate(inst.Type))
        {
            if (offset != 0)
            {
                I32Const(offset);
                Op(106);
            }
        }
        else
            Load(inst.Type, offset);
        SetResult(inst);
    }

    void GenInsert(IrInst inst)
    {
        int dst = Local.Get(inst.Res);
        var baseVal = M.Vals.Get(inst.Args[0]);
        bool inPlace = baseVal.Kind == ValKind.Local && Local.ContainsKey(baseVal.Name) && Local.Get(baseVal.Name) == dst;
        if (!inPlace)
            CopyValue(dst, 0, inst.Args[0], inst.Type);
        int offset = PathOffset(inst.Type, inst.Cases);
        int elem = FieldTypeAt(T, inst.Type, inst.Cases);
        if (T.IsAggregate(elem))
            CopyValue(dst, offset, inst.Args[1], elem);
        else
        {
            LocalGet(dst);
            Push(inst.Args[1]);
            Store(elem, offset);
        }
    }

    void GenAtomic(IrInst inst)
    {
        int t = inst.Type;
        int old = Local.Get(inst.Res);
        Push(inst.Args[0]);
        Load(t, 0);
        LocalSet(old);
        Push(inst.Args[0]);
        string p = inst.Pred;
        if (p == "xchg")
            Push(inst.Args[1]);
        else
        {
            LocalGet(old);
            Push(inst.Args[1]);
            int code = p == "add" ? 106 : p == "sub" ? 107 : p == "and" ? 113 : p == "or" ? 114 : p == "xor" ? 115 : 0;
            if (code == 0)
                Fail("atomicrmw " + p + " is not supported");
            Op(ValType(t) == I64 ? code + 18 : code);
            if (ValType(t) == I32)
                Mask(Width(t));
        }
        Store(t, 0);
    }

    // -----------------------------------------------------------------------
    // Jumps
    // -----------------------------------------------------------------------

    // The phis of block 'to' get their values for the jump from the current block.
    bool HasCopies(int to)
    {
        foreach (var inst in Blocks.Get(to).Insts.ToArray())
        {
            if (inst.Op == "phi")
                return true;
        }
        return false;
    }

    int Incoming(IrInst phi)
    {
        string from = Blocks.Get(Current).Label;
        for (var i = 0; i < phi.Labels.Length; i += 1)
        {
            if (phi.Labels[i] == from)
                return phi.Args[i];
        }
        Fail("phi %" + phi.Res + " has no value for the block " + from);
        return phi.Args[0];
    }

    void EdgeCopies(int to)
    {
        var phis = List<IrInst>.Create();
        foreach (var inst in Blocks.Get(to).Insts.ToArray())
        {
            if (inst.Op == "phi")
                phis.Add(inst);
        }
        if (phis.Count() == 0)
            return;
        // without staging when no value is a phi of the block (no phi is read after it got its new value)
        bool direct = true;
        if (phis.Count() > 1)
        {
            foreach (var phi in phis.ToArray())
            {
                var v = M.Vals.Get(Incoming(phi));
                if (T.IsAggregate(phi.Type) || (v.Kind == ValKind.Local && PhiOf(to, v.Name)))
                    direct = false;
            }
        }
        foreach (var phi in phis.ToArray())
        {
            int value = Incoming(phi);
            int target = direct ? Local.Get(phi.Res) : PhiTmp.Get(phi.Res);
            if (T.IsAggregate(phi.Type))
                CopyValue(target, 0, value, phi.Type);
            else
            {
                Push(value);
                LocalSet(target);
            }
        }
        if (direct)
            return;
        foreach (var phi in phis.ToArray())
        {
            if (T.IsAggregate(phi.Type))
            {
                LocalGet(Local.Get(phi.Res));
                LocalGet(PhiTmp.Get(phi.Res));
                I32Const(L.Size(phi.Type));
                MemoryCopy();
            }
            else
            {
                LocalGet(PhiTmp.Get(phi.Res));
                LocalSet(Local.Get(phi.Res));
            }
        }
    }

    bool PhiOf(int block, string name)
    {
        foreach (var inst in Blocks.Get(block).Insts.ToArray())
        {
            if (inst.Op == "phi" && inst.Res == name)
                return true;
        }
        return false;
    }

    // Jumps to a block (after the copies of its phis).
    void Goto(int to)
    {
        int k = Current;
        if (to > k)
        {
            if (Depth == 0 && to == k + 1)
                return; // the next block follows
            Op(12); // br
            Code.U32(Depth + to - k - 1);
            return;
        }
        I32Const(to);
        LocalSet(Pc);
        Op(12);
        Code.U32(Depth + Blocks.Count() - 1 - k);
    }

    // A jump if the i32 on the stack is not zero; false if it needs code (the caller writes an if).
    bool BranchIf(int to)
    {
        if (to <= Current || HasCopies(to))
            return false;
        Op(13); // br_if
        Code.U32(Depth + to - Current - 1);
        return true;
    }

    void Target(string label, ref int index)
    {
        var found = BlockIndex.TryGet(label);
        if (found is int b)
            index = b;
        else
            Fail("unknown block " + label);
    }

    void GenBr(IrInst inst)
    {
        if (inst.Labels.Length == 1)
        {
            int to = 0;
            Target(inst.Labels[0], ref to);
            EdgeCopies(to);
            Goto(to);
            return;
        }
        int yes = 0;
        int no = 0;
        Target(inst.Labels[0], ref yes);
        Target(inst.Labels[1], ref no);
        Push(inst.Args[0]);
        if (CanBranchIf(yes))
        {
            BranchIf(yes);
            EdgeCopies(no);
            Goto(no);
            return;
        }
        if (CanBranchIf(no))
        {
            Op(69); // i32.eqz
            BranchIf(no);
            EdgeCopies(yes);
            Goto(yes);
            return;
        }
        Op(4);  // if
        Op(64);
        Depth += 1;
        EdgeCopies(yes);
        Goto(yes);
        Op(5);  // else
        EdgeCopies(no);
        Goto(no);
        Op(11);
        Depth -= 1;
    }

    // Can a conditional jump to the block be a br_if?
    bool CanBranchIf(int to)
    {
        return to > Current && !HasCopies(to);
    }

    void GenSwitch(IrInst inst)
    {
        int t = inst.OpType;
        bool wide = ValType(t) == I64;
        for (var i = 0; i < inst.Cases.Length; i += 1)
        {
            int to = 0;
            Target(inst.Labels[i + 1], ref to);
            Push(inst.Args[0]);
            if (wide)
            {
                I64Const(inst.Cases[i]);
                Op(81); // i64.eq
            }
            else
            {
                I32Const(WasmTruncate(inst.Cases[i], Width(t), false));
                Op(70); // i32.eq
            }
            if (CanBranchIf(to))
            {
                BranchIf(to);
                continue;
            }
            Op(4);
            Op(64);
            Depth += 1;
            EdgeCopies(to);
            Goto(to);
            Op(11);
            Depth -= 1;
        }
        int fallback = 0;
        Target(inst.Labels[0], ref fallback);
        EdgeCopies(fallback);
        Goto(fallback);
    }

    // -----------------------------------------------------------------------
    // Calls
    // -----------------------------------------------------------------------

    // The bytes the variable arguments of a call take when they are packed (0: not a call with variable arguments).
    int VarargsSize(IrInst inst)
    {
        var callee = M.Vals.Get(inst.Callee);
        if (callee.Kind != ValKind.Global || CallTarget(callee.Name) != "__cs_va_" + callee.Name)
            return 0;
        var f = M.Funcs.Get(M.FuncIndex.Get(callee.Name));
        int size = 0;
        for (var i = f.Params.Length; i < inst.Args.Length; i += 1)
        {
            int vt = ValType(M.Vals.Get(inst.Args[i]).Type);
            size += vt == I64 || vt == F64 || vt == F32 ? 8 : 4;
        }
        return size;
    }

    // Calls a function of the module by its IR name (the arguments are on the stack).
    void CallFunction(string name)
    {
        var found = FuncIndex.TryGet(name);
        if (found is int index)
        {
            Op(16); // call
            Code.U32(index);
        }
        else
            Fail("'" + name + "' is not defined");
    }

    // Pushes an argument converted to the wasm type of the parameter (C functions may be declared with other integer
    // widths than they are defined with).
    void PushArg(int vi, int want)
    {
        Push(vi);
        int have = ValType(M.Vals.Get(vi).Type);
        if (have == want || want == 0)
            return;
        if (have == I32 && want == I64)
            Op(173);
        else if (have == I64 && want == I32)
            Op(167);
        else
            Fail("an argument of the wrong type");
    }

    void GenCall(IrInst inst)
    {
        var callee = M.Vals.Get(inst.Callee);
        if (callee.Kind != ValKind.Global)
        {
            GenIndirectCall(inst);
            return;
        }
        string name = callee.Name;
        if (name.StartsWith("llvm."))
        {
            GenIntrinsic(inst, name);
            return;
        }
        if (IsInlineCall(name))
        {
            GenInlineCall(inst, name);
            return;
        }
        string target = CallTarget(name);
        if (!M.FuncIndex.ContainsKey(target))
        {
            Fail("'" + target + "' is not defined");
            return;
        }
        var f = M.Funcs.Get(M.FuncIndex.Get(target));
        string key = Current.ToString() + ":" + Position.ToString();
        bool sret = T.IsAggregate(inst.Type);
        if (sret)
            LocalGet(inst.Res.Length > 0 ? Local.Get(inst.Res) : PosSlot.Get(key));
        if (target != name)
        {
            // variable arguments: the fixed ones, then the address of the others (packed)
            var declared = M.Funcs.Get(M.FuncIndex.Get(name));
            int fixedCount = declared.Params.Length;
            int buffer = PosSlot.GetOrDefault(key, -1);
            int offset = 0;
            for (var i = fixedCount; i < inst.Args.Length; i += 1)
            {
                int a = inst.Args[i];
                int at = M.Vals.Get(a).Type;
                int vt = ValType(at);
                LocalGet(buffer);
                Push(a);
                if (vt == F32)
                    Op(187); // promoted to double
                if (vt == I32 && T.IsInt(at) && (Width(at) == 8 || Width(at) == 16))
                    SignExtend(Width(at)); // like C's promotion of char and short
                if (vt == I64 || vt == F64 || vt == F32)
                {
                    MemOp(vt == I64 ? 55 : 57, 0, offset);
                    offset += 8;
                }
                else
                {
                    MemOp(54, 0, offset);
                    offset += 4;
                }
            }
            for (var i = 0; i < fixedCount && i < f.Params.Length; i += 1)
                PushArg(inst.Args[i], ValType(f.Params[i].Type));
            if (buffer >= 0)
                LocalGet(buffer);
            else
                I32Const(0);
        }
        else
        {
            if (inst.Args.Length != f.Params.Length)
                Fail("the call of '" + name + "' has " + inst.Args.Length.ToString() + " arguments, the function " + f.Params.Length.ToString());
            for (var i = 0; i < inst.Args.Length && i < f.Params.Length; i += 1)
                PushArg(inst.Args[i], ValType(f.Params[i].Type));
        }
        CallFunction(target);
        CallResult(inst, sret ? 0 : ValType(f.Ret));
    }

    // After a call: the result (converted from the function's type) to the instruction's local, or dropped.
    void CallResult(IrInst inst, int have)
    {
        if (have == 0)
            return;
        int want = ValType(inst.Type);
        if (T.Kind(inst.Type) == IrKind.Void || inst.Res.Length == 0)
        {
            Op(26); // drop
            return;
        }
        if (have == I64 && want == I32)
            Op(167);
        else if (have == I32 && want == I64)
            Op(173);
        if (want == I32 && T.IsInt(inst.Type))
            Mask(Width(inst.Type));
        LocalSet(Local.Get(inst.Res));
    }

    void GenIndirectCall(IrInst inst)
    {
        var ps = List<int>.Create();
        var results = List<int>.Create();
        bool sret = T.IsAggregate(inst.Type);
        if (sret)
        {
            ps.Add(I32);
            LocalGet(inst.Res.Length > 0 ? Local.Get(inst.Res) : PosSlot.Get(Current.ToString() + ":" + Position.ToString()));
        }
        else if (T.Kind(inst.Type) != IrKind.Void)
            results.Add(ValType(inst.Type));
        foreach (var a in inst.Args)
        {
            ps.Add(ValType(M.Vals.Get(a).Type));
            Push(a);
        }
        Push(inst.Callee);
        Op(17); // call_indirect
        Code.U32(FuncType(ps, results));
        Code.Byte(0);
        CallResult(inst, sret || T.Kind(inst.Type) == IrKind.Void ? 0 : ValType(inst.Type));
    }

    // C functions that are instructions, and the builtins of the backend.
    void GenInlineCall(IrInst inst, string name)
    {
        if (name == "memcpy" || name == "memmove" || name == "memset")
        {
            Push(inst.Args[0]);
            Push(inst.Args[1]);
            PushArg(inst.Args[2], I32);
            if (name == "memset")
                MemoryFill();
            else
                MemoryCopy();
            if (inst.Res.Length > 0)
            {
                Push(inst.Args[0]);
                SetResult(inst);
            }
            return;
        }
        if (name == "__cs_wasm_memory_size")
        {
            Op(63);
            Code.Byte(0);
        }
        else if (name == "__cs_wasm_memory_grow")
        {
            Push(inst.Args[0]);
            Op(64);
            Code.Byte(0);
        }
        else if (name == "__cs_wasm_heap_base")
        {
            Op(35); // global.get $heap_base (known when everything is written)
            Code.U32(1);
        }
        else
        {
            bool single = name.EndsWith("f");
            string root = single ? name.Substring(0, name.Length - 1).ToString() : name;
            Push(inst.Args[0]);
            int code = root == "fabs" ? 153 : root == "ceil" ? 155 : root == "floor" ? 156 : root == "trunc" ? 157 : root == "sqrt" ? 159 : 158;
            Op(single ? code - 14 : code);
        }
        if (inst.Res.Length > 0)
            SetResult(inst);
        else
            Op(26);
    }

    void GenIntrinsic(IrInst inst, string name)
    {
        if (name.StartsWith("llvm.memcpy") || name.StartsWith("llvm.memmove") || name.StartsWith("llvm.memset"))
        {
            Push(inst.Args[0]);
            Push(inst.Args[1]);
            PushArg(inst.Args[2], I32);
            if (name.StartsWith("llvm.memset"))
                MemoryFill();
            else
                MemoryCopy();
            return;
        }
        if (name.StartsWith("llvm.lifetime") || name.StartsWith("llvm.dbg") || name.StartsWith("llvm.assume") || name.StartsWith("llvm.donothing"))
            return;
        if (name == "llvm.trap")
        {
            Op(0);
            return;
        }
        if (name.Contains(".with.overflow."))
        {
            GenOverflow(inst, name);
            return;
        }
        if (name.StartsWith("llvm.fptosi.sat") || name.StartsWith("llvm.fptoui.sat"))
        {
            Push(inst.Args[0]);
            TruncSat(ValType(M.Vals.Get(inst.Args[0]).Type), inst.Type, name.StartsWith("llvm.fptosi"));
            SetResult(inst);
            return;
        }
        bool single = name.EndsWith(".f32");
        if (name.EndsWith(".f32") || name.EndsWith(".f64"))
        {
            string root = name.Substring(5, name.Length - 9).ToString();
            int code = root == "fabs" ? 153 : root == "ceil" ? 155 : root == "floor" ? 156 : root == "trunc" ? 157 :
                       root == "nearbyint" || root == "rint" || root == "roundeven" ? 158 : root == "sqrt" ? 159 :
                       root == "minnum" || root == "minimum" ? 164 : root == "maxnum" || root == "maximum" ? 165 : root == "copysign" ? 166 : 0;
            if (code == 0)
            {
                Fail("the wasm backend does not know '" + name + "'");
                return;
            }
            foreach (var a in inst.Args)
                Push(a);
            Op(single ? code - 14 : code);
            SetResult(inst);
            return;
        }
        bool wide = ValType(inst.Type) == I64;
        if (name.StartsWith("llvm.ctpop") || name.StartsWith("llvm.ctlz") || name.StartsWith("llvm.cttz"))
        {
            Push(inst.Args[0]);
            int code = name.StartsWith("llvm.ctpop") ? 105 : name.StartsWith("llvm.ctlz") ? 103 : 104;
            Op(wide ? code + 18 : code);
            int bits = Width(inst.Type);
            if (!wide && bits < 32 && name.StartsWith("llvm.ctlz"))
            {
                I32Const(32 - bits);
                Op(107);
            }
            else if (!wide && bits < 32 && name.StartsWith("llvm.cttz"))
            {
                // a zero has 'bits' trailing zeros, not 32
                int t = NewLocal(I32);
                LocalSet(t);
                LocalGet(t);
                I32Const(bits);
                LocalGet(t);
                I32Const(bits);
                Op(73); // t < bits
                Op(27);
            }
            SetResult(inst);
            return;
        }
        if (name.StartsWith("llvm.smin") || name.StartsWith("llvm.smax") || name.StartsWith("llvm.umin") || name.StartsWith("llvm.umax"))
        {
            bool signed = name.StartsWith("llvm.s");
            bool min = name.Contains("min.");
            int t = inst.Type;
            Push(inst.Args[0]);
            Push(inst.Args[1]);
            if (signed)
            {
                PushSigned(inst.Args[0], t);
                PushSigned(inst.Args[1], t);
            }
            else
            {
                Push(inst.Args[0]);
                Push(inst.Args[1]);
            }
            int code = min ? (signed ? 72 : 73) : (signed ? 74 : 75); // a < b / a > b
            Op(wide ? code + 11 : code);
            Op(27);
            SetResult(inst);
            return;
        }
        if (name.StartsWith("llvm.abs"))
        {
            int t = inst.Type;
            // x < 0 ? 0 - x : x
            if (wide)
                I64Const(0);
            else
                I32Const(0);
            PushSigned(inst.Args[0], t);
            Op(wide ? 125 : 107);
            PushSigned(inst.Args[0], t);
            PushSigned(inst.Args[0], t);
            if (wide)
            {
                I64Const(0);
                Op(83); // i64.lt_s
            }
            else
            {
                I32Const(0);
                Op(72);
            }
            Op(27);
            if (!wide)
                Mask(Width(t));
            SetResult(inst);
            return;
        }
        Fail("the wasm backend does not know '" + name + "'");
    }

    // llvm.{s,u}{add,sub,mul}.with.overflow.iN: { result, overflow } (in two locals, or in the result's slot)
    void GenOverflow(IrInst inst, string name)
    {
        bool signed = name.StartsWith("llvm.s");
        string what = name.Contains("add") ? "add" : name.Contains("sub") ? "sub" : "mul";
        int t = T.Info(inst.Type).Fields[0];
        int bits = Width(t);
        bool wide = ValType(t) == I64;
        int a = inst.Args[0];
        int b = inst.Args[1];
        int value;
        int flag;
        bool split = inst.Res.Length > 0 && SplitFlag.ContainsKey(inst.Res);
        if (split)
        {
            value = Local.Get(inst.Res);
            flag = SplitFlag.Get(inst.Res);
        }
        else
        {
            value = NewLocal(wide ? I64 : I32);
            flag = NewLocal(I32);
        }
        int code = what == "add" ? 124 : what == "sub" ? 125 : 126; // i64.add/sub/mul
        if (!wide)
        {
            // in 64 bits, where nothing overflows: too big if the result does not fit
            int r = NewLocal(I64);
            PushI64(a, signed);
            PushI64(b, signed);
            Op(code);
            LocalTee(r);
            Op(167);
            Mask(bits);
            LocalTee(value);
            if (signed)
            {
                SignExtend(bits);
                Op(172);
            }
            else
                Op(173);
            LocalGet(r);
            Op(82); // i64.ne
            LocalSet(flag);
        }
        else
        {
            Push(a);
            Push(b);
            Op(code);
            LocalSet(value);
            if (what == "add" && signed)
            {
                // ((a ^ r) & (b ^ r)) < 0
                Push(a);
                LocalGet(value);
                Op(133);
                Push(b);
                LocalGet(value);
                Op(133);
                Op(131);
                I64Const(0);
                Op(83);
            }
            else if (what == "sub" && signed)
            {
                // ((a ^ b) & (a ^ r)) < 0
                Push(a);
                Push(b);
                Op(133);
                Push(a);
                LocalGet(value);
                Op(133);
                Op(131);
                I64Const(0);
                Op(83);
            }
            else if (what == "add")
            {
                LocalGet(value);
                Push(a);
                Op(84); // r <u a
            }
            else if (what == "sub")
            {
                Push(a);
                Push(b);
                Op(84); // a <u b
            }
            else
            {
                // a not 0 (or -1): r / a != b; a == -1: b == MIN
                int d = NewLocal(I64);
                int special = NewLocal(I32);
                Push(a);
                Op(80); // i64.eqz
                if (signed)
                {
                    Push(a);
                    I64Const(-1);
                    Op(81);
                    Op(114);
                }
                LocalSet(special);
                I64Const(1);
                Push(a);
                LocalGet(special);
                Op(27);
                LocalSet(d);
                LocalGet(value);
                LocalGet(d);
                Op(signed ? 127 : 128); // div_s / div_u
                Push(b);
                Op(82); // ne
                LocalGet(special);
                Op(69);
                Op(113);
                if (signed)
                {
                    Push(a);
                    I64Const(-1);
                    Op(81);
                    Push(b);
                    I64Const(-9223372036854775807 - 1);
                    Op(81);
                    Op(113);
                    Op(114);
                }
            }
            LocalSet(flag);
        }
        if (split || inst.Res.Length == 0)
            return;
        int dst = Local.Get(inst.Res);
        LocalGet(dst);
        LocalGet(value);
        Store(t, 0);
        LocalGet(dst);
        LocalGet(flag);
        Store(T.I1, L.FieldOffset(inst.Type, 1));
    }

    // -----------------------------------------------------------------------
    // The module
    // -----------------------------------------------------------------------

    // The function indexes: the imports of WASI first, then the functions with a body.
    void AssignFunctions()
    {
        foreach (var f in M.Funcs.ToArray())
        {
            if (!Reached.Contains(f.Name))
                continue;
            if (f.Defined)
                Defined.Add(f.Name);
            else
            {
                // __wasi_X: X of WASI; anything else: a function of the host (JavaScript), from the module "env"
                Imports.Add(f.Name);
                if (!f.Name.StartsWith("__wasi_"))
                    Warnings.Add("'" + f.Name + "' is not defined: it is imported from the module \"env\"");
            }
        }
        int index = 0;
        foreach (var name in Imports.ToArray())
        {
            FuncIndex.Set(name, index);
            index += 1;
        }
        foreach (var name in Defined.ToArray())
        {
            FuncIndex.Set(name, index);
            index += 1;
        }
    }

    uint8[] Assemble(List<Bytes> bodies)
    {
        HeapBase = WasmAlignTo(DataStart + Data.Count(), 16);
        var importTypes = List<int>.Create();
        foreach (var name in Imports.ToArray())
            importTypes.Add(SignatureOf(M.Funcs.Get(M.FuncIndex.Get(name))));
        var definedTypes = List<int>.Create();
        foreach (var name in Defined.ToArray())
            definedTypes.Add(SignatureOf(M.Funcs.Get(M.FuncIndex.Get(name))));

        var out = Bytes.Create();
        out.Byte(0);
        out.Byte(97);  // a
        out.Byte(115); // s
        out.Byte(109); // m
        out.Fixed(1, 4);

        var types = Bytes.Create();
        types.U32(Types.Count());
        foreach (var t in Types.ToArray())
            types.Append(t);
        out.Section(SecType, types);

        var imports = Bytes.Create();
        imports.U32(Imports.Count());
        for (var i = 0; i < Imports.Count(); i += 1)
        {
            string name = Imports.Get(i);
            bool wasi = name.StartsWith("__wasi_");
            imports.Name(wasi ? "wasi_snapshot_preview1" : "env");
            imports.Name(wasi ? name.Substring(7).ToString() : name);
            imports.Byte(0);
            imports.U32(importTypes.Get(i));
        }
        if (Imports.Count() > 0)
            out.Section(SecImport, imports);

        var functions = Bytes.Create();
        functions.U32(Defined.Count());
        foreach (var t in definedTypes.ToArray())
            functions.U32(t);
        out.Section(SecFunction, functions);

        var table = Bytes.Create();
        table.U32(1);
        table.Byte(112); // funcref
        table.Byte(0);
        table.U32(Table.Count() + 1);
        out.Section(SecTable, table);

        var memory = Bytes.Create();
        memory.U32(1);
        memory.Byte(0);
        memory.U32(HeapBase / 65536 + 2);
        out.Section(SecMemory, memory);

        var globals = Bytes.Create();
        globals.U32(2);
        globals.Byte(I32);
        globals.Byte(1);   // $sp: mutable
        globals.Byte(65);
        globals.S64(StackSize);
        globals.Byte(11);
        globals.Byte(I32);
        globals.Byte(0);   // $heap_base
        globals.Byte(65);
        globals.S64(HeapBase);
        globals.Byte(11);
        out.Section(SecGlobal, globals);

        var exports = Bytes.Create();
        exports.U32(2);
        exports.Name("memory");
        exports.Byte(2);
        exports.U32(0);
        exports.Name("_start");
        exports.Byte(0);
        exports.U32(FuncIndex.GetOrDefault("__cs_wasm_start", 0));
        out.Section(SecExport, exports);

        if (Table.Count() > 0)
        {
            var elements = Bytes.Create();
            elements.U32(1);
            elements.U32(0);   // active, table 0, functions
            elements.Byte(65);
            elements.S64(1);
            elements.Byte(11);
            elements.U32(Table.Count());
            foreach (var fi in Table.ToArray())
                elements.U32(fi);
            out.Section(SecElement, elements);
        }

        var code = Bytes.Create();
        code.U32(bodies.Count());
        foreach (var body in bodies.ToArray())
        {
            code.U32(body.Count());
            code.Append(body);
        }
        out.Section(SecCode, code);

        if (Data.Count() > 0)
        {
            var data = Bytes.Create();
            data.U32(1);
            data.U32(0);   // active, memory 0
            data.Byte(65);
            data.S64(DataStart);
            data.Byte(11);
            data.U32(Data.Count());
            data.Append(Data);
            out.Section(SecData, data);
        }
        return out.ToArray();
    }

    // Restores the shadow stack before a return.
    void Epilogue()
    {
        if (FrameSize == 0)
            return;
        LocalGet(FramePointer);
        I32Const(FrameSize);
        Op(106);  // i32.add
        Op(36);   // global.set $sp
        Code.U32(0);
    }
}

// The value truncated to 'bits' bits, extended with its sign or with zeros.
int64 WasmTruncate(int64 value, int bits, bool signed)
{
    if (bits >= 64)
        return value;
    unchecked
    {
        int64 mask = ((int64)1 << bits) - 1;
        int64 v = value & mask;
        if (signed && (v >> (bits - 1)) != 0)
            v = v - ((int64)1 << bits);
        return v;
    }
}

// The bits of a float that is a double's value rounded (float constants are written as doubles in the IR).
int64 FloatBitsOfDouble(int64 bits)
{
    unsafe
    {
        int64 copy = bits;
        double d = *(double*)&copy;
        float f = (float)d;
        uint32 fb = *(uint32*)&f;
        return (int64)fb;
    }
}

// The WebAssembly module of an IR module, or the errors; the warnings go to 'warnings'.
Error<uint8[]> GenerateWasm(IrModule m, List<string> warnings)
{
    var g = WasmGen.Create(m);
    g.Warnings = warnings;
    g.FindReached();
    g.AssignFunctions();
    if (g.Errors.Count() > 0)
        return error(string.Join("\n", g.Errors.ToArray()));
    g.LayoutGlobals();
    var bodies = List<Bytes>.Create();
    foreach (var name in g.Defined.ToArray())
        bodies.Add(g.GenFunction(m.Funcs.Get(m.FuncIndex.Get(name))));
    if (g.Errors.Count() > 0)
        return error(string.Join("\n", g.Errors.ToArray()));
    return g.Assemble(bodies);
}
