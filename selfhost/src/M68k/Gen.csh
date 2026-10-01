// The 68000 code generator: translates the IR module (IrReader.csh) into assembly for the 68000 (GNU as syntax,
// assembled by M68k/Asm.csh or by GNU as when testing).
//
// Simple and correct first: every value of a function has a slot in its stack frame (addressed through a6, the frame
// pointer); an instruction loads its operands into d0/d1 (d2/d3 for the second operand of 64-bit operations),
// computes and stores the result into its slot.
//
//   * A value of up to 4 bytes (i1, i8, i16, i32, ptr, float) is a long in its slot: only its low bits are meaningful,
//     so operations that look at the high bits (compare, divide, shift right, widen) extend first.
//   * i64 and double: two longs, high first (the memory order of the 68000).
//   * Structs and arrays: their bytes (Layout.csh).
//
// Calls use the C convention of m68k (the one GCC and LLVM use, so C functions can be called): arguments on the
// stack, pushed from the last, each in 4 bytes (8 for i64/double, structs rounded up to 4); integers are returned in
// d0 (i64/double in d0:d1), pointers in a0 (our functions set d0 as well); a struct result is written to the memory
// whose address the caller passes as a hidden first argument. d2-d7/a2-a6 are kept.

namespace CShift.M68k;

using System;

struct Gen
{
    IrModule M;
    IrTypes T;
    Layouts L;
    StringBuilder Out;
    StringBuilder Data;
    Dictionary<string, string> Symbols;
    Dictionary<string, string> Reverse;   // assembly name -> IR name
    List<string> Libraries;               // the AmigaOS libraries that are called (their bases: __cs_lib_<index>)
    int[] Counters;                       // [0] labels, [1] symbols, [2] the optimization level (-O0..-O3)
    List<string> Errors;

    // the function being written
    Dictionary<string, int> Slot;         // value -> frame offset (negative) or parameter offset (positive)
    Dictionary<string, int> ValType;
    Dictionary<string, int> Alloca;       // alloca result -> offset of its memory
    Dictionary<string, int> PhiTmp;       // phi result -> offset of its staging slot
    Dictionary<string, List<IrInst>> Phis; // block -> its phis
    Dictionary<string, string> Home;       // values and allocas that live in a register for the whole function
    List<string> Saved;                   // the registers the function keeps (movem)
    Dictionary<string, AddrFold> Folds;   // pointers whose load/store uses an addressing mode (Prepare.csh)
    HashSet<string> Skip;                 // instructions that are not written (folded)
    Dictionary<string, string> BlockLabel; // IR block -> assembly label
    string[] Fn;                          // [0] the IR name of the function, [1] the current IR block, [2] the epilogue
    int[] Frame;                          // [0] frame size, [1] 1 if the function returns a struct (hidden pointer)

    static Gen Create(IrModule m)
    {
        var g = Gen { M = m, T = m.Types, L = Layouts.Create(m.Types), Out = StringBuilder.Create(), Data = StringBuilder.Create(),
                      Symbols = Dictionary<string, string>.Create(), Reverse = Dictionary<string, string>.Create(), Libraries = List<string>.Create(), Home = Dictionary<string, string>.Create(),
                      Saved = List<string>.Create(), Folds = Dictionary<string, AddrFold>.Create(), Skip = HashSet<string>.Create(),
                      Counters = new int[3], Errors = List<string>.Create() };
        g.Fn = new string[3];
        g.Frame = new int[2];
        return g;
    }

    void Line(string text)
    {
        Out.Append("\t");
        Out.Append(text);
        Out.Append('\n');
    }

    void Label(string name)
    {
        Out.Append(name);
        Out.Append(":\n");
    }

    string NewLabel()
    {
        Counters[0] += 1;
        return ".L" + Counters[0].ToString();
    }

    void Fail(string message)
    {
        Errors.Add(Fn[0] + ": " + message);
    }
}

// ---------------------------------------------------------------------------
// The module
// ---------------------------------------------------------------------------

// The assembly of a whole module, or the errors. Only what is used is written: the functions and globals that main,
// the prelude (the startup code of AmigaOS) and the runtime refer to, and so on.
Error<string> GenerateModule(IrModule m, string prelude, int optimize)
{
    var g = Gen.Create(m);
    g.Counters[2] = optimize;
    var funcText = Dictionary<int, string>.Create();
    var globalText = Dictionary<int, string>.Create();
    var work = List<string>.Create();
    var seen = HashSet<string>.Create();
    string runtime = RuntimeAsm();
    ScanSymbols(prelude, work, seen);
    ScanSymbols(runtime, work, seen);
    AddWork("main", work, seen);
    var output = g.Out;
    for (var next = 0; next < work.Count(); next += 1)
    {
        string name = work.Get(next);
        var irName = g.Reverse.TryGet(name);
        string ir = irName is string known ? known : name;
        var fi = m.FuncIndex.TryGet(ir);
        if (fi is int f && m.Funcs.Get(f).Defined && !funcText.ContainsKey(f))
        {
            g.Out = StringBuilder.Create();
            GenFunction(g, m.Funcs.Get(f));
            string text = g.Out.ToString();
            funcText.Set(f, FinishSaves(Peephole(text)));
            ScanSymbols(text, work, seen);
        }
        var gi = m.GlobalIndex.TryGet(ir);
        if (gi is int x && m.Globals.Get(x).Init >= 0 && !globalText.ContainsKey(x))
        {
            var gl = m.Globals.Get(x);
            g.Out = StringBuilder.Create();
            g.Out.Append("\t.even\n");
            g.Out.Append(Sym(g, gl.Name) + ":\n");
            EmitConst(g, gl.Init, gl.Type);
            string text = g.Out.ToString();
            globalText.Set(x, text);
            ScanSymbols(text, work, seen);
        }
    }
    g.Out = output;
    g.Out.Append(prelude);
    g.Out.Append("\t.text\n");
    for (var i = 0; i < m.Funcs.Count(); i += 1)
    {
        var text = funcText.TryGet(i);
        if (text is string code)
            g.Out.Append(code);
    }
    g.Out.Append(runtime);
    g.Out.Append("\t.data\n");
    for (var i = 0; i < m.Globals.Count(); i += 1)
    {
        var text = globalText.TryGet(i);
        if (text is string data)
            g.Out.Append(data);
    }
    g.Out.Append(LibraryTable(g));
    if (g.Errors.Count() > 0)
        return error(string.Join("\n", g.Errors.ToArray()));
    return g.Out.ToString();
}

// The prologue and the epilogue keep exactly the registers d2-d7/a2-a5 that the code of the function uses.
string FinishSaves(string text)
{
    string[] regs = ["%d2", "%d3", "%d4", "%d5", "%d6", "%d7", "%a2", "%a3", "%a4", "%a5"];
    var used = List<string>.Create();
    foreach (var r in regs)
    {
        if (text.Contains(r))
            used.Add(r);
    }
    if (used.Count() == 0)
        return text.Replace("\tmovem.l\t@SAVE@,-(%sp)\n", "").Replace("\tmovem.l\t(%sp)+,@SAVE@\n", "");
    return text.Replace("@SAVE@", string.Join("/", used.ToArray()));
}

void AddWork(string name, List<string> work, HashSet<string> seen)
{
    if (!seen.Contains(name))
    {
        seen.Add(name);
        work.Add(name);
    }
}

// The symbols the operands of the assembly text refer to (not local labels and registers).
void ScanSymbols(string text, List<string> work, HashSet<string> seen)
{
    int i = 0;
    int n = text.Length;
    while (i < n)
    {
        // an instruction line: a tab, the mnemonic, a tab, the operands
        int lineEnd = text.IndexOf('\n', i);
        if (lineEnd < 0)
            lineEnd = n;
        int tab = text.IndexOf('\t', i);
        if (tab >= 0 && tab < lineEnd)
        {
            int ops = text.IndexOf('\t', tab + 1);
            if (ops >= 0 && ops < lineEnd)
            {
                int k = ops + 1;
                while (k < lineEnd)
                {
                    char c = text[k];
                    bool start = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
                    bool prevOk = k == ops + 1 || !IsSymbolChar(text[k - 1]) && text[k - 1] != '%' && text[k - 1] != '.';
                    if (start && prevOk)
                    {
                        int e = k;
                        while (e < lineEnd && IsSymbolChar(text[e]))
                            e += 1;
                        AddWork(text.Substring(k, e - k).ToString(), work, seen);
                        k = e;
                    }
                    else
                        k += 1;
                }
            }
        }
        i = lineEnd + 1;
    }
}

bool IsSymbolChar(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '$';
}

// The assembly name of a global or function: external C names (and main) stay, everything else gets a short name
// (CShift's names contain '<', '(' and spaces).
string Sym(Gen g, string name)
{
    var found = g.Symbols.TryGet(name);
    if (found is string s)
        return s;
    string result;
    bool external = name == "main";
    var fi = g.M.FuncIndex.TryGet(name);
    if (fi is int f)
        external = external || !g.M.Funcs.Get(f).Internal;
    var gi = g.M.GlobalIndex.TryGet(name);
    if (gi is int gx)
        external = external || g.M.Globals.Get(gx).Init < 0;
    if (external)
        result = name;
    else
    {
        g.Counters[1] += 1;
        result = "_cs" + g.Counters[1].ToString();
    }
    g.Symbols.Set(name, result);
    g.Reverse.Set(result, name);
    return result;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// A constant as a symbol plus offset, or a plain number (Sym == "").
struct ConstValue
{
    string Sym;
    int64 Off;
    bool Ok;
}

ConstValue EvalConst(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    switch (v.Kind)
    {
    case ValKind.Int:
    case ValKind.FloatBits:
        return ConstValue { Sym = "", Off = v.Int, Ok = true };
    case ValKind.Null:
    case ValKind.Zero:
        return ConstValue { Sym = "", Off = 0, Ok = true };
    case ValKind.Global:
        return ConstValue { Sym = Sym(g, v.Name), Off = 0, Ok = true };
    case ValKind.Expr:
    {
        if (v.Text == "getelementptr")
        {
            var baseValue = EvalConst(g, v.Items[0]);
            int t = v.ExprType;
            int64 off = baseValue.Off;
            for (var k = 1; k < v.Items.Length; k += 1)
            {
                var idx = EvalConst(g, v.Items[k]);
                if (k == 1)
                    off += idx.Off * (int64)g.L.Stride(t);
                else if (g.T.Kind(t) == IrKind.Struct)
                {
                    off += (int64)g.L.FieldOffset(t, (int)idx.Off);
                    t = g.T.Info(t).Fields[(int)idx.Off];
                }
                else
                {
                    t = g.T.Info(t).Elem;
                    off += idx.Off * (int64)g.L.Stride(t);
                }
            }
            return ConstValue { Sym = baseValue.Sym, Off = off, Ok = baseValue.Ok };
        }
        var inner = EvalConst(g, v.Items[0]);
        if (v.Text == "trunc" && inner.Sym.Length == 0)
        {
            int bits = g.T.Bits(v.ExprType);
            if (bits < 64)
                inner.Off = unchecked(inner.Off & (((int64)1 << bits) - 1));
        }
        return inner;
    }
    default:
        return ConstValue { Sym = "", Off = 0, Ok = false };
    }
}

string ConstText(ConstValue c)
{
    if (c.Sym.Length == 0)
        return c.Off.ToString();
    if (c.Off == 0)
        return c.Sym;
    return c.Sym + (c.Off > 0 ? "+" : "") + c.Off.ToString();
}

// The IEEE bits of a float from the bits of the double that has the same value (float constants are written as doubles).
int64 FloatBitsOf(int64 d)
{
    int64 sign = (d >> 63) & 1;
    int64 exp = (d >> 52) & 2047;
    int64 mant = d & 4503599627370495; // 2^52 - 1
    if (exp == 0)
        return sign << 31;
    if (exp == 2047)
        return (sign << 31) | ((int64)255 << 23) | (mant >> 29);
    int64 e = exp - 1023 + 127;
    if (e <= 0)
        return sign << 31;
    if (e >= 255)
        return (sign << 31) | ((int64)255 << 23);
    return (sign << 31) | (e << 23) | (mant >> 29);
}

// The data of a constant of type t (a global's initializer).
void EmitConst(Gen g, int vi, int t)
{
    var v = g.M.Vals.Get(vi);
    int size = g.L.Size(t);
    var kind = g.T.Kind(t);
    if (v.Kind == ValKind.Zero || v.Kind == ValKind.Null)
    {
        if (size > 0)
            g.Line(".space\t" + size.ToString());
        return;
    }
    if (v.Kind == ValKind.Bytes)
    {
        var sb = StringBuilder.Create();
        for (var i = 0; i < v.Text.Length; i += 1)
        {
            if (i % 16 == 0)
            {
                if (i > 0)
                    sb.Append("\n");
                sb.Append("\t.byte\t");
            }
            else
                sb.Append(",");
            sb.Append(((int)v.Text[i]).ToString());
        }
        g.Out.Append(sb.ToString() + "\n");
        if (v.Text.Length < size)
            g.Line(".space\t" + (size - v.Text.Length).ToString());
        return;
    }
    if (v.Kind == ValKind.Aggregate)
    {
        var info = g.T.Info(t);
        int pos = 0;
        for (var i = 0; i < v.Items.Length; i += 1)
        {
            int ft = kind == IrKind.Array ? info.Elem : info.Fields[i];
            int at = kind == IrKind.Array ? i * g.L.Stride(ft) : g.L.FieldOffset(t, i);
            if (at > pos)
                g.Line(".space\t" + (at - pos).ToString());
            EmitConst(g, v.Items[i], ft);
            pos = at + g.L.Size(ft);
        }
        if (size > pos)
            g.Line(".space\t" + (size - pos).ToString());
        return;
    }
    var c = EvalConst(g, vi);
    if (!c.Ok)
    {
        g.Fail("cannot write the constant of a global");
        return;
    }
    if (kind == IrKind.Double || (kind == IrKind.Int && size == 8))
    {
        int64 bits = c.Off;
        g.Line(".long\t" + ((bits >> 32) & 4294967295).ToString());
        g.Line(".long\t" + (bits & 4294967295).ToString());
        return;
    }
    if (kind == IrKind.Float)
    {
        g.Line(".long\t" + FloatBitsOf(c.Off).ToString());
        return;
    }
    if (size == 1)
        g.Line(".byte\t" + (c.Off & 255).ToString());
    else if (size == 2)
        g.Line(".short\t" + (c.Off & 65535).ToString());
    else if (c.Sym.Length > 0)
        g.Line(".long\t" + ConstText(c));
    else
        g.Line(".long\t" + (c.Off & 4294967295).ToString());
}

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

// The size of the slot of a value of type t.
int SlotSize(Gen g, int t)
{
    var k = g.T.Kind(t);
    if (k == IrKind.Struct || k == IrKind.Array)
    {
        int s = g.L.Size(t);
        return s < 2 ? 2 : (s + 1) / 2 * 2;
    }
    return g.L.Size(t) > 4 ? 8 : 4;
}

// The bytes a value of type t takes as an argument.
int ArgSize(Gen g, int t)
{
    var k = g.T.Kind(t);
    if (k == IrKind.Struct || k == IrKind.Array)
        return (g.L.Size(t) + 3) / 4 * 4;
    return g.L.Size(t) > 4 ? 8 : 4;
}

bool ReturnsStruct(Gen g, int t)
{
    return g.T.IsAggregate(t);
}

void GenFunction(Gen g, IrFunc f)
{
    g.Slot = Dictionary<string, int>.Create();
    g.ValType = Dictionary<string, int>.Create();
    g.Alloca = Dictionary<string, int>.Create();
    g.PhiTmp = Dictionary<string, int>.Create();
    g.Phis = Dictionary<string, List<IrInst>>.Create();
    g.BlockLabel = Dictionary<string, string>.Create();
    g.Fn[0] = f.Name;
    g.Fn[2] = g.NewLabel();
    g.Frame[1] = ReturnsStruct(g, f.Ret) ? 1 : 0;
    PrepareFunction(g, f);

    // parameters: above the return address and the saved a6
    int pos = 8 + (g.Frame[1] == 1 ? 4 : 0);
    foreach (var p in f.Params)
    {
        int size = ArgSize(g, p.Type);
        int at = pos;
        if (size == 4 && !g.T.IsAggregate(p.Type))
            at = pos; // the long of the slot
        g.Slot.Set(p.Name, at);
        g.ValType.Set(p.Name, p.Type);
        pos += size;
    }

    // slots for every result, memory for every alloca, staging slots for phis
    int frame = 0;
    foreach (var b in f.Blocks.ToArray())
    {
        g.BlockLabel.Set(b.Label, g.NewLabel());
        foreach (var inst in b.Insts.ToArray())
        {
            if (inst.Op == "alloca")
            {
                int size = g.L.Size(inst.OpType);
                frame += size < 2 ? 2 : (size + 1) / 2 * 2;
                if (g.L.Size(inst.OpType) >= 4)
                    frame = (frame + 3) / 4 * 4;
                g.Alloca.Set(inst.Res, -frame);
                g.ValType.Set(inst.Res, g.T.Ptr);
                continue;
            }
            if (inst.Res.Length == 0)
                continue;
            frame += SlotSize(g, inst.Type);
            frame = (frame + 1) / 2 * 2;
            g.Slot.Set(inst.Res, -frame);
            g.ValType.Set(inst.Res, inst.Type);
            if (inst.Op == "phi")
            {
                frame += SlotSize(g, inst.Type);
                g.PhiTmp.Set(inst.Res, -frame);
                var found = g.Phis.TryGet(b.Label);
                if (found is List<IrInst> list)
                    list.Add(inst);
                else
                {
                    var fresh = List<IrInst>.Create();
                    fresh.Add(inst);
                    g.Phis.Set(b.Label, fresh);
                }
            }
        }
    }
    frame = (frame + 3) / 4 * 4;
    if (frame > 32000)
        g.Fail("the stack frame is too large (" + frame.ToString() + " bytes)");
    g.Frame[0] = frame;

    // how often each value is used
    var uses = Dictionary<string, int>.Create();
    foreach (var b in f.Blocks.ToArray())
    {
        foreach (var inst in b.Insts.ToArray())
        {
            foreach (var a in inst.Args)
            {
                var v = g.M.Vals.Get(a);
                if (v.Kind == ValKind.Local)
                    uses.Set(v.Name, uses.GetOrDefault(v.Name, 0) + 1);
            }
        }
    }

    string name = Sym(g, f.Name);
    if (!f.Internal)
        g.Out.Append("\t.globl\t" + name + "\n");
    AllocateRegisters(g, f);
    string savedList = string.Join("/", g.Saved.ToArray());
    g.Label(name);
    g.Line("link.w\t%a6,#-" + frame.ToString());
    g.Line("movem.l\t@SAVE@,-(%sp)"); // the registers the function uses (FinishSaves)
    foreach (var b in f.Blocks.ToArray())
    {
        g.Fn[1] = b.Label;
        g.Label(g.BlockLabel.Get(b.Label));
        // phis: from their staging slots (written by the predecessor before its branch)
        var phis = g.Phis.TryGet(b.Label);
        if (phis is List<IrInst> list)
        {
            foreach (var phi in list)
            {
                if (PhiRegister(g, phi).Length == 0)
                    CopyFrame(g, g.PhiTmp.Get(phi.Res), g.Slot.Get(phi.Res), SlotSize(g, phi.Type));
            }
        }
        var insts = b.Insts.ToArray();
        for (var k = 0; k < insts.Length; k += 1)
        {
            var inst = insts[k];
            if (inst.Op == "phi" || inst.Op == "alloca" || (inst.Res.Length > 0 && g.Skip.Contains(inst.Res)))
                continue;
            // a comparison that only decides the branch after it: compare and branch, no flag in between
            if (inst.Op == "icmp" && k + 1 < insts.Length && insts[k + 1].Op == "br" && insts[k + 1].Labels.Length == 2 &&
                IsLocal(g, insts[k + 1].Args[0]) && g.M.Vals.Get(insts[k + 1].Args[0]).Name == inst.Res && uses.GetOrDefault(inst.Res, 0) == 1 &&
                g.T.Bits(inst.OpType) != 64)
            {
                GenCompareBranch(g, f, inst, insts[k + 1]);
                k += 1;
                continue;
            }
            // an add/sub with an overflow check: add, branch on the flag (checked arithmetic)
            if (k + 3 < insts.Length && IsFusableOverflow(g, insts, k, uses))
            {
                GenOverflowBranch(g, insts, k);
                k += 3;
                continue;
            }
            GenInst(g, f, inst);
        }
    }
    g.Label(g.Fn[2]);
    g.Line("movem.l\t(%sp)+,@SAVE@");
    g.Line("unlk\t%a6");
    g.Line("rts");
}

// ---------------------------------------------------------------------------
// Registers: the values used most (weighted by loop nesting) live in d4-d7/a2-a5 for the whole function
// ---------------------------------------------------------------------------

// Where a result is kept: its register or its slot.
string SlotOperand(Gen g, string name)
{
    var home = g.Home.TryGet(name);
    if (home is string reg)
        return reg;
    return Frame(g.Slot.Get(name));
}

// The register of a variable (an alloca: load and store use the register instead of memory), "" if it has none.
string HomeOf(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind != ValKind.Local || !g.Alloca.ContainsKey(v.Name))
        return "";
    var home = g.Home.TryGet(v.Name);
    if (home is string reg)
        return reg;
    return "";
}

// The data register a result lives in, "" if it has none (or lives in an address register).
string ResultRegister(Gen g, string name)
{
    var home = g.Home.TryGet(name);
    if (home is string reg && reg.StartsWith("%d"))
        return reg;
    return "";
}

// A value as the source operand of an instruction of 'bits' bits: its register, an immediate or (32 bits) its slot;
// "" if it has to be loaded into a register first.
string SourceOperand(Gen g, int vi, int bits)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local)
    {
        if (g.Alloca.ContainsKey(v.Name))
            return "";
        var home = g.Home.TryGet(v.Name);
        if (home is string reg)
            return bits < 32 && !reg.StartsWith("%d") ? "" : reg;
        var t = g.ValType.TryGet(v.Name);
        if (bits == 32 && t is int vt && g.L.Size(vt) == 4 && !g.T.IsAggregate(vt))
            return Frame(g.Slot.Get(v.Name));
        return "";
    }
    if (v.Kind == ValKind.Int || v.Kind == ValKind.Null || v.Kind == ValKind.Zero)
    {
        int64 n = v.Kind == ValKind.Int ? v.Int : 0;
        return "#" + (n & 4294967295).ToString();
    }
    return "";
}

// One arm of a select into the result.
void SelectArm(Gen g, IrInst inst, int arm, int off)
{
    if (g.T.IsAggregate(inst.Type))
    {
        CopyToSlot(g, inst.Args[arm], inst.Type, off);
        return;
    }
    if (g.L.Size(inst.Type) == 8)
        Load64(g, inst.Args[arm], "%d0", "%d1");
    else
        Load32(g, inst.Args[arm], "%d0");
    StoreResult(g, inst);
}

bool IsScalar4(Gen g, int t)
{
    var k = g.T.Kind(t);
    return (k == IrKind.Int || k == IrKind.Ptr || k == IrKind.Float) && g.L.Size(t) <= 4;
}

// ---------------------------------------------------------------------------
// Operands
// ---------------------------------------------------------------------------

string Frame(int off)
{
    return "(" + off.ToString() + ",%a6)";
}

bool IsLocal(Gen g, int vi)
{
    return g.M.Vals.Get(vi).Kind == ValKind.Local;
}

// The frame offset of a local value's slot.
int SlotOf(Gen g, int vi)
{
    string name = g.M.Vals.Get(vi).Name;
    var found = g.Slot.TryGet(name);
    if (found is int off)
        return off;
    g.Fail("unknown value %" + name);
    return 0;
}

bool IsAllocaVal(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    return v.Kind == ValKind.Local && g.Alloca.ContainsKey(v.Name);
}

// A value of up to 32 bits into a data register (for i64: the low half).
void Load32(Gen g, int vi, string reg)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local)
    {
        var a = g.Alloca.TryGet(v.Name);
        if (a is int aoff)
        {
            g.Line("lea\t" + Frame(aoff) + ",%a0");
            g.Line("move.l\t%a0," + reg);
            return;
        }
        var home = g.Home.TryGet(v.Name);
        if (home is string homeReg)
        {
            if (homeReg != reg)
                g.Line("move.l\t" + homeReg + "," + reg);
            return;
        }
        int off = SlotOf(g, vi);
        int t = g.ValType.Get(v.Name);
        if (g.L.Size(t) == 8)
            off += 4;
        g.Line("move.l\t" + Frame(off) + "," + reg);
        return;
    }
    var c = EvalConst(g, vi);
    if (v.Kind == ValKind.FloatBits && g.T.Kind(v.Type) == IrKind.Float)
        c.Off = FloatBitsOf(c.Off);
    if (!c.Ok)
    {
        g.Fail("cannot use this constant as a scalar");
        return;
    }
    if (c.Sym.Length == 0)
    {
        int64 n = c.Off & 4294967295;
        if (n >= 4294967168)
            n = n - 4294967296;
        if (n >= -128 && n <= 127 && reg.StartsWith("%d"))
            g.Line("moveq\t#" + n.ToString() + "," + reg);
        else
            g.Line("move.l\t#" + n.ToString() + "," + reg);
    }
    else
        g.Line("move.l\t#" + ConstText(c) + "," + reg);
}

// A 64-bit value into two data registers (high, low).
void Load64(Gen g, int vi, string hi, string lo)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local)
    {
        int off = SlotOf(g, vi);
        g.Line("move.l\t" + Frame(off) + "," + hi);
        g.Line("move.l\t" + Frame(off + 4) + "," + lo);
        return;
    }
    var c = EvalConst(g, vi);
    g.Line("move.l\t#" + ((c.Off >> 32) & 4294967295).ToString() + "," + hi);
    g.Line("move.l\t#" + (c.Off & 4294967295).ToString() + "," + lo);
}

// A pointer value into an address register.
void LoadAddr(Gen g, int vi, string areg)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind == ValKind.Local)
    {
        var a = g.Alloca.TryGet(v.Name);
        if (a is int aoff)
        {
            g.Line("lea\t" + Frame(aoff) + "," + areg);
            return;
        }
        var home = g.Home.TryGet(v.Name);
        if (home is string homeReg)
        {
            if (homeReg != areg)
                g.Line("move.l\t" + homeReg + "," + areg);
            return;
        }
        g.Line("move.l\t" + Frame(SlotOf(g, vi)) + "," + areg);
        return;
    }
    var c = EvalConst(g, vi);
    if (c.Sym.Length > 0)
        g.Line("lea\t" + ConstText(c) + "," + areg);
    else
        g.Line("move.l\t#" + c.Off.ToString() + "," + areg);
}

// Sign- or zero-extends the low 'bits' of a data register to 32 bits.
void Extend(Gen g, string reg, int bits, bool signed)
{
    if (bits >= 32)
        return;
    if (bits == 1)
    {
        g.Line("and.l\t#1," + reg);
        if (signed)
            g.Line("neg.l\t" + reg);
        return;
    }
    if (signed)
    {
        if (bits == 8)
            g.Line("ext.w\t" + reg);
        g.Line("ext.l\t" + reg);
        return;
    }
    g.Line("and.l\t#" + (bits == 8 ? "255" : "65535") + "," + reg);
}

// Copies n bytes between two places of the frame.
void CopyFrame(Gen g, int from, int to, int n)
{
    g.Line("lea\t" + Frame(from) + ",%a0");
    g.Line("lea\t" + Frame(to) + ",%a1");
    CopyMem(g, n, true);
}

// Copies n bytes from (a0) to (a1) (both are advanced); 'even': both addresses are even.
void CopyMem(Gen g, int n, bool even)
{
    if (!even)
    {
        if (n <= 16)
        {
            for (var i = 0; i < n; i += 1)
                g.Line("move.b\t(%a0)+,(%a1)+");
            return;
        }
        string loop = g.NewLabel();
        g.Line("move.l\t#" + (n - 1).ToString() + ",%d1");
        g.Label(loop);
        g.Line("move.b\t(%a0)+,(%a1)+");
        g.Line("dbra\t%d1," + loop);
        return;
    }
    int longs = n / 4;
    if (longs <= 8)
    {
        for (var i = 0; i < longs; i += 1)
            g.Line("move.l\t(%a0)+,(%a1)+");
    }
    else
    {
        string loop = g.NewLabel();
        g.Line("move.l\t#" + (longs - 1).ToString() + ",%d1");
        g.Label(loop);
        g.Line("move.l\t(%a0)+,(%a1)+");
        g.Line("dbra\t%d1," + loop);
        if (longs > 65536)
            g.Fail("a copy of more than 256 KB");
    }
    if (n % 4 >= 2)
        g.Line("move.w\t(%a0)+,(%a1)+");
    if (n % 2 == 1)
        g.Line("move.b\t(%a0)+,(%a1)+");
}

// The suffix of a move of 'size' bytes.
string SizeSuffix(int size)
{
    return size == 1 ? ".b" : size == 2 ? ".w" : ".l";
}

// Writes the value vi of type t to memory at (off, base) (base: an address register other than a0).
void StoreValue(Gen g, int vi, int t, string baseReg, int off)
{
    var v = g.M.Vals.Get(vi);
    int size = g.L.Size(t);
    string dest = "(" + off.ToString() + "," + baseReg + ")";
    if (g.T.IsAggregate(t))
    {
        if (v.Kind == ValKind.Local)
        {
            g.Line("lea\t" + dest + ",%a1");
            g.Line("lea\t" + Frame(SlotOf(g, vi)) + ",%a0");
            CopyMem(g, size, g.L.Align(t) >= 2);
            return;
        }
        StoreConst(g, vi, t, baseReg, off);
        return;
    }
    if (size == 8)
    {
        Load64(g, vi, "%d0", "%d1");
        g.Line("move.l\t%d0," + dest);
        g.Line("move.l\t%d1,(" + (off + 4).ToString() + "," + baseReg + ")");
        return;
    }
    Load32(g, vi, "%d0");
    g.Line("move" + SizeSuffix(size) + "\t%d0," + dest);
}

// Writes a constant aggregate (or zero) of type t to (off, base).
void StoreConst(Gen g, int vi, int t, string baseReg, int off)
{
    var v = g.M.Vals.Get(vi);
    int size = g.L.Size(t);
    if (v.Kind == ValKind.Zero || v.Kind == ValKind.Null)
    {
        int pos = 0;
        bool even = g.L.Align(t) >= 2;
        while (even && pos + 4 <= size)
        {
            g.Line("clr.l\t(" + (off + pos).ToString() + "," + baseReg + ")");
            pos += 4;
        }
        while (even && pos + 2 <= size)
        {
            g.Line("clr.w\t(" + (off + pos).ToString() + "," + baseReg + ")");
            pos += 2;
        }
        while (pos < size)
        {
            g.Line("clr.b\t(" + (off + pos).ToString() + "," + baseReg + ")");
            pos += 1;
        }
        return;
    }
    if (v.Kind == ValKind.Aggregate)
    {
        var info = g.T.Info(t);
        bool isArray = g.T.Kind(t) == IrKind.Array;
        for (var i = 0; i < v.Items.Length; i += 1)
        {
            int ft = isArray ? info.Elem : info.Fields[i];
            int at = isArray ? i * g.L.Stride(ft) : g.L.FieldOffset(t, i);
            StoreValue(g, v.Items[i], ft, baseReg, off + at);
        }
        return;
    }
    if (v.Kind == ValKind.Bytes)
    {
        for (var i = 0; i < v.Text.Length; i += 1)
            g.Line("move.b\t#" + ((int)v.Text[i]).ToString() + ",(" + (off + i).ToString() + "," + baseReg + ")");
        return;
    }
    g.Fail("cannot write this constant");
}

// The result of an instruction: from d0 (and d1 for 64 bits) into its slot.
void StoreResult(Gen g, IrInst inst)
{
    var home = g.Home.TryGet(inst.Res);
    if (home is string reg)
    {
        g.Line("move.l\t%d0," + reg);
        return;
    }
    int off = g.Slot.Get(inst.Res);
    if (g.L.Size(inst.Type) == 8)
    {
        g.Line("move.l\t%d0," + Frame(off));
        g.Line("move.l\t%d1," + Frame(off + 4));
        return;
    }
    g.Line("move.l\t%d0," + Frame(off));
}

// Copies any value into a slot of the frame.
void CopyToSlot(Gen g, int vi, int t, int off)
{
    var v = g.M.Vals.Get(vi);
    if (g.T.IsAggregate(t))
    {
        if (v.Kind == ValKind.Local)
            CopyFrame(g, SlotOf(g, vi), off, SlotSize(g, t));
        else
            StoreConst(g, vi, t, "%a6", off);
        return;
    }
    if (g.L.Size(t) == 8)
    {
        Load64(g, vi, "%d0", "%d1");
        g.Line("move.l\t%d0," + Frame(off));
        g.Line("move.l\t%d1," + Frame(off + 4));
        return;
    }
    Load32(g, vi, "%d0");
    g.Line("move.l\t%d0," + Frame(off));
}

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

void GenInst(Gen g, IrFunc f, IrInst inst)
{
    string op = inst.Op;
    if (op == "add" || op == "sub" || op == "mul" || op == "and" || op == "or" || op == "xor" || op == "shl" || op == "lshr" ||
        op == "ashr" || op == "sdiv" || op == "udiv" || op == "srem" || op == "urem")
    {
        if (g.T.Kind(inst.OpType) == IrKind.Int && g.T.Bits(inst.OpType) == 64)
            GenBinary64(g, inst);
        else
            GenBinary32(g, inst);
        return;
    }
    if (op == "fadd" || op == "fsub" || op == "fmul" || op == "fdiv" || op == "frem")
    {
        GenFloatBinary(g, inst);
        return;
    }
    if (op == "icmp")
    {
        GenIcmp(g, inst);
        return;
    }
    if (op == "fcmp")
    {
        GenFcmp(g, inst);
        return;
    }
    if (op == "sext" || op == "zext" || op == "trunc" || op == "bitcast" || op == "ptrtoint" || op == "inttoptr")
    {
        GenIntCast(g, inst);
        return;
    }
    if (op == "fptrunc" || op == "fpext" || op == "sitofp" || op == "uitofp" || op == "fptosi" || op == "fptoui")
    {
        GenFloatCast(g, inst);
        return;
    }
    if ((op == "load" || op == "store") && IsLocal(g, inst.Args[op == "load" ? 0 : 1]) &&
        g.Folds.ContainsKey(g.M.Vals.Get(inst.Args[op == "load" ? 0 : 1]).Name))
    {
        // an access through an address mode (Prepare.csh)
        var fold = g.Folds.Get(g.M.Vals.Get(inst.Args[op == "load" ? 0 : 1]).Name);
        int size = g.L.Size(op == "load" ? inst.Type : inst.OpType);
        string suffix = SizeSuffix(size);
        if (op == "load")
        {
            string operand = FoldedOperand(g, fold);
            string target = size == 4 ? ResultRegister(g, inst.Res) : "";
            if (target.Length > 0)
            {
                g.Line("move.l\t" + operand + "," + target);
                return;
            }
            g.Line("move" + suffix + "\t" + operand + ",%d0");
            StoreResult(g, inst);
            return;
        }
        string src = SourceOperand(g, inst.Args[0], size * 8);
        if (src.Length == 0)
        {
            Load32(g, inst.Args[0], "%d0");
            src = "%d0";
        }
        string dest = FoldedOperand(g, fold);
        g.Line("move" + suffix + "\t" + src + "," + dest);
        return;
    }
    // a value that lives in its variable's slot (Regalloc.csh): the load and the store are that slot already
    if (op == "load" && IsLocal(g, inst.Args[0]) && g.Alloca.ContainsKey(g.M.Vals.Get(inst.Args[0]).Name))
    {
        var home = g.Home.TryGet(inst.Res);
        if (home is string slot && slot == Frame(g.Alloca.Get(g.M.Vals.Get(inst.Args[0]).Name)))
            return;
    }
    if (op == "store" && IsLocal(g, inst.Args[0]) && IsLocal(g, inst.Args[1]) && g.Alloca.ContainsKey(g.M.Vals.Get(inst.Args[1]).Name))
    {
        var home = g.Home.TryGet(g.M.Vals.Get(inst.Args[0]).Name);
        if (home is string slot && slot == Frame(g.Alloca.Get(g.M.Vals.Get(inst.Args[1]).Name)))
            return;
    }
    if (op == "load" && HomeOf(g, inst.Args[0]).Length > 0)
    {
        // a variable that lives in a register (a load that is forwarded shares it: nothing to do)
        string from = HomeOf(g, inst.Args[0]);
        var home = g.Home.TryGet(inst.Res);
        if (home is string reg)
        {
            if (reg != from)
                g.Line("move.l\t" + from + "," + reg);
            return;
        }
        g.Line("move.l\t" + from + ",%d0");
        StoreResult(g, inst);
        return;
    }
    if (op == "store" && HomeOf(g, inst.Args[1]).Length > 0)
    {
        Load32(g, inst.Args[0], HomeOf(g, inst.Args[1]));
        return;
    }
    if (op == "load")
    {
        LoadAddr(g, inst.Args[0], "%a0");
        int size = g.L.Size(inst.Type);
        int off = g.Slot.Get(inst.Res);
        if (g.T.IsAggregate(inst.Type))
        {
            g.Line("lea\t" + Frame(off) + ",%a1");
            CopyMem(g, size, g.L.Align(inst.Type) >= 2);
            return;
        }
        if (size == 8)
        {
            g.Line("move.l\t(%a0),%d0");
            g.Line("move.l\t(4,%a0),%d1");
        }
        else
            g.Line("move" + SizeSuffix(size) + "\t(%a0),%d0");
        StoreResult(g, inst);
        return;
    }
    if (op == "store")
    {
        LoadAddr(g, inst.Args[1], "%a1");
        StoreValue(g, inst.Args[0], inst.OpType, "%a1", 0);
        return;
    }
    if (op == "getelementptr")
    {
        GenGep(g, inst);
        return;
    }
    if (op == "extractvalue")
    {
        GenExtract(g, inst);
        return;
    }
    if (op == "insertvalue")
    {
        int off = g.Slot.Get(inst.Res);
        CopyToSlot(g, inst.Args[0], inst.OpType, off);
        int ft = inst.OpType;
        int at = PathOffset(g, inst.OpType, inst.Cases, ref ft);
        g.Line("lea\t" + Frame(off) + ",%a1");
        StoreValue(g, inst.Args[1], ft, "%a1", at);
        return;
    }
    if (op == "select")
    {
        string other = g.NewLabel();
        string done = g.NewLabel();
        int off = g.Slot.Get(inst.Res);
        Load32(g, inst.Args[0], "%d0");
        g.Line("tst.b\t%d0");
        g.Line("beq\t" + other);
        SelectArm(g, inst, 1, off);
        g.Line("bra\t" + done);
        g.Label(other);
        SelectArm(g, inst, 2, off);
        g.Label(done);
        return;
    }
    if (op == "br")
    {
        WritePhiCopies(g, f, inst.Labels);
        if (inst.Labels.Length == 1)
        {
            g.Line("bra\t" + g.BlockLabel.Get(inst.Labels[0]));
            return;
        }
        var cond = g.M.Vals.Get(inst.Args[0]);
        if (cond.Kind == ValKind.Int)
        {
            g.Line("bra\t" + g.BlockLabel.Get(inst.Labels[cond.Int != 0 ? 0 : 1]));
            return;
        }
        Load32(g, inst.Args[0], "%d0");
        g.Line("tst.b\t%d0");
        g.Line("bne\t" + g.BlockLabel.Get(inst.Labels[0]));
        g.Line("bra\t" + g.BlockLabel.Get(inst.Labels[1]));
        return;
    }
    if (op == "switch")
    {
        WritePhiCopies(g, f, inst.Labels);
        int bits = g.T.Bits(inst.OpType);
        if (bits == 64)
        {
            GenSwitch64(g, inst);
            return;
        }
        Load32(g, inst.Args[0], "%d0");
        string suffix = bits <= 8 ? ".b" : bits == 16 ? ".w" : ".l";
        for (var i = 0; i < inst.Cases.Length; i += 1)
        {
            int64 cv = inst.Cases[i];
            g.Line("cmp" + suffix + "\t#" + cv.ToString() + ",%d0");
            g.Line("beq\t" + g.BlockLabel.Get(inst.Labels[i + 1]));
        }
        g.Line("bra\t" + g.BlockLabel.Get(inst.Labels[0]));
        return;
    }
    if (op == "ret")
    {
        if (inst.Args.Length > 0)
        {
            int t = inst.OpType;
            if (g.T.IsAggregate(t))
            {
                g.Line("move.l\t(8,%a6),%a1");
                StoreValue(g, inst.Args[0], t, "%a1", 0);
                g.Line("move.l\t(8,%a6),%d0");
                g.Line("move.l\t%d0,%a0");
            }
            else if (g.L.Size(t) == 8)
                Load64(g, inst.Args[0], "%d0", "%d1");
            else
            {
                Load32(g, inst.Args[0], "%d0");
                g.Line("move.l\t%d0,%a0");
            }
        }
        g.Line("bra\t" + g.Fn[2]);
        return;
    }
    if (op == "unreachable")
        return;
    if (op == "call")
    {
        GenCall(g, inst);
        return;
    }
    if (op == "atomicrmw")
    {
        // one thread on the 68000 targets: a plain read-modify-write
        int t = inst.Type;
        int size = g.L.Size(t);
        LoadAddr(g, inst.Args[0], "%a1");
        g.Line("move" + SizeSuffix(size) + "\t(%a1),%d0");
        g.Line("move.l\t%d0," + SlotOperand(g, inst.Res));
        g.Line("move.l\t%a1,-(%sp)");
        Load32(g, inst.Args[1], "%d1");
        g.Line("move.l\t(%sp)+,%a1");
        string p = inst.Pred;
        if (p == "add")
            g.Line("add.l\t%d1,%d0");
        else if (p == "sub")
            g.Line("sub.l\t%d1,%d0");
        else if (p == "xchg")
            g.Line("move.l\t%d1,%d0");
        else if (p == "and")
            g.Line("and.l\t%d1,%d0");
        else if (p == "or")
            g.Line("or.l\t%d1,%d0");
        else
            g.Fail("atomicrmw " + p + " is not supported");
        g.Line("move" + SizeSuffix(size) + "\t%d0,(%a1)");
        return;
    }
    g.Fail("the instruction '" + op + "' is not supported yet");
}

// Before a branch: the values the successors' phis take from this block, into their registers (the register
// allocation keeps them free here) or their staging slots (read at the start of the successor).
void WritePhiCopies(Gen g, IrFunc f, string[] targets)
{
    foreach (var target in targets)
    {
        var phis = g.Phis.TryGet(target);
        if (phis is List<IrInst> list)
        {
            // a register that is written and also read by another copy: all through the staging slots first
            var written = HashSet<string>.Create();
            foreach (var phi in list)
            {
                string reg = PhiRegister(g, phi);
                if (reg.Length > 0 && PhiArg(g, phi) >= 0)
                    written.Add(reg);
            }
            bool clash = false;
            foreach (var phi in list)
            {
                int arg = PhiArg(g, phi);
                string from = arg >= 0 ? ValueRegister(g, arg) : "";
                if (from.Length > 0 && written.Contains(from) && from != PhiRegister(g, phi))
                    clash = true;
            }
            foreach (var phi in list)
            {
                int arg = PhiArg(g, phi);
                if (arg < 0)
                    continue;
                string reg = PhiRegister(g, phi);
                if (reg.Length > 0 && !clash)
                    Load32(g, arg, reg);
                else
                    CopyToSlot(g, arg, phi.Type, g.PhiTmp.Get(phi.Res));
            }
            if (clash)
            {
                foreach (var phi in list)
                {
                    string reg = PhiRegister(g, phi);
                    if (reg.Length > 0 && PhiArg(g, phi) >= 0)
                        g.Line("move.l\t" + Frame(g.PhiTmp.Get(phi.Res)) + "," + reg);
                }
            }
        }
    }
}

// the value a phi takes from the current block (-1: none)
int PhiArg(Gen g, IrInst phi)
{
    for (var i = 0; i < phi.Labels.Length; i += 1)
    {
        if (phi.Labels[i] == g.Fn[1])
            return phi.Args[i];
    }
    return -1;
}

// the register a value (not a variable's address) is in ("": none)
string ValueRegister(Gen g, int vi)
{
    var v = g.M.Vals.Get(vi);
    if (v.Kind != ValKind.Local || g.Alloca.ContainsKey(v.Name))
        return "";
    var home = g.Home.TryGet(v.Name);
    if (home is string reg && reg.StartsWith("%"))
        return reg;
    return "";
}

// the register of a phi's result, written by its predecessors ("": through its staging slot)
string PhiRegister(Gen g, IrInst phi)
{
    var home = g.Home.TryGet(phi.Res);
    if (home is string reg && reg.StartsWith("%"))
        return reg;
    return "";
}

// add, sub, ... on values of up to 32 bits: a in d0, b in d1.
void GenBinary32(Gen g, IrInst inst)
{
    string op = inst.Op;
    int bits = g.T.Kind(inst.OpType) == IrKind.Int ? g.T.Bits(inst.OpType) : 32;
    // add, sub, and, or, xor and shifts: straight into the result's data register, with the second operand as it is
    string target = ResultRegister(g, inst.Res);
    if (target.Length > 0 && SourceOperand(g, inst.Args[1], 32) == target)
        target = ""; // (the second operand is in the result's register: through d0)
    if (op == "add" || op == "sub" || op == "and" || op == "or" || op == "xor" || op == "shl" || op == "lshr" || op == "ashr")
    {
        string dst = target.Length > 0 ? target : "%d0";
        Load32(g, inst.Args[0], dst);
        string src = SourceOperand(g, inst.Args[1], 32);
        bool shift = op == "shl" || op == "lshr" || op == "ashr";
        if (shift)
        {
            var c = g.M.Vals.Get(inst.Args[1]);
            src = c.Kind == ValKind.Int && c.Int >= 1 && c.Int <= 8 ? "#" + c.Int.ToString() : "";
        }
        // (and/or cannot read an address register, eor and shifts only a data register or an immediate)
        if (src.Length == 0 || ((op == "xor" || shift) && !src.StartsWith("%d") && !src.StartsWith("#")) ||
            ((op == "and" || op == "or") && src.StartsWith("%a")))
        {
            Load32(g, inst.Args[1], "%d1");
            src = "%d1";
        }
        if (op == "lshr")
            Extend(g, dst, bits, false);
        else if (op == "ashr")
            Extend(g, dst, bits, true);
        string m = op == "xor" ? "eor" : op == "shl" ? "lsl" : op == "lshr" ? "lsr" : op == "ashr" ? "asr" : op;
        g.Line(m + ".l\t" + src + "," + dst);
        if (dst == "%d0")
            StoreResult(g, inst);
        return;
    }
    var divisor = g.M.Vals.Get(inst.Args[1]);
    // division by a power of two (2..2^30): shifts; signed division rounds towards zero, so a negative dividend gets
    // 2^n-1 added first
    int pow = divisor.Kind == ValKind.Int ? PowerOfTwo(divisor.Int) : -1;
    if ((op == "sdiv" || op == "srem" || op == "udiv" || op == "urem") && pow >= 1 && pow <= 30)
    {
        bool signedDiv = op == "sdiv" || op == "srem";
        int64 mask = ((int64)1 << pow) - 1;
        Load32(g, inst.Args[0], "%d0");
        Extend(g, "%d0", bits, signedDiv);
        if (op == "urem")
            g.Line("and.l\t#" + mask.ToString() + ",%d0");
        else if (op == "udiv")
            ShiftBy(g, "lsr", pow, "%d0");
        else
        {
            if (op == "srem")
                g.Line("move.l\t%d0,%d2");
            string positive = g.NewLabel();
            g.Line("tst.l\t%d0");
            g.Line("bpl\t" + positive);
            if (mask <= 8)
                g.Line("addq.l\t#" + mask.ToString() + ",%d0");
            else
                g.Line("add.l\t#" + mask.ToString() + ",%d0");
            g.Label(positive);
            ShiftBy(g, "asr", pow, "%d0");
            if (op == "srem")
            {
                // x - (x / 2^n) * 2^n
                ShiftBy(g, "lsl", pow, "%d0");
                g.Line("sub.l\t%d0,%d2");
                g.Line("move.l\t%d2,%d0");
            }
        }
        StoreResult(g, inst);
        return;
    }
    // division by a constant of 1..32767: one divs.w/divu.w; if the quotient does not fit in 16 bits (V), the helper
    if ((op == "sdiv" || op == "srem" || op == "udiv" || op == "urem") && divisor.Kind == ValKind.Int && divisor.Int >= 1 &&
        divisor.Int <= 32767)
    {
        bool signedDiv = op == "sdiv" || op == "srem";
        bool rem = op == "srem" || op == "urem";
        string slow = g.NewLabel();
        string done = g.NewLabel();
        Load32(g, inst.Args[0], "%d0");
        Extend(g, "%d0", bits, signedDiv);
        g.Line((signedDiv ? "divs.w" : "divu.w") + "\t#" + divisor.Int.ToString() + ",%d0");
        g.Line("bvs\t" + slow);
        if (rem)
            g.Line("swap\t%d0");
        if (signedDiv)
            g.Line("ext.l\t%d0");
        else
            g.Line("and.l\t#65535,%d0");
        g.Line("bra\t" + done);
        g.Label(slow);
        g.Line("move.l\t#" + divisor.Int.ToString() + ",%d1");
        g.Line("jsr\t" + (signedDiv ? "__cs68k_sdivmod" : "__cs68k_udivmod"));
        if (rem)
            g.Line("move.l\t%d1,%d0");
        g.Label(done);
        StoreResult(g, inst);
        return;
    }
    Load32(g, inst.Args[0], "%d0");
    Load32(g, inst.Args[1], "%d1");
    if (op == "add")
        g.Line("add.l\t%d1,%d0");
    else if (op == "sub")
        g.Line("sub.l\t%d1,%d0");
    else if (op == "and")
        g.Line("and.l\t%d1,%d0");
    else if (op == "or")
        g.Line("or.l\t%d1,%d0");
    else if (op == "xor")
        g.Line("eor.l\t%d1,%d0");
    else if (op == "shl")
        g.Line("lsl.l\t%d1,%d0");
    else if (op == "lshr")
    {
        Extend(g, "%d0", bits, false);
        g.Line("lsr.l\t%d1,%d0");
    }
    else if (op == "ashr")
    {
        Extend(g, "%d0", bits, true);
        g.Line("asr.l\t%d1,%d0");
    }
    else if (op == "mul")
        g.Line("jsr\t__cs68k_mul32");
    else
    {
        bool signed = op == "sdiv" || op == "srem";
        Extend(g, "%d0", bits, signed);
        Extend(g, "%d1", bits, signed);
        g.Line("jsr\t" + (signed ? "__cs68k_sdivmod" : "__cs68k_udivmod"));
        if (op == "srem" || op == "urem")
            g.Line("move.l\t%d1,%d0");
    }
    StoreResult(g, inst);
}

// n if v is 2^n (n >= 1), else -1
int PowerOfTwo(int64 v)
{
    for (var n = 1; n <= 62; n += 1)
    {
        if (v == ((int64)1 << n))
            return n;
    }
    return -1;
}

// reg shifted by n bits (an immediate count is 1..8, larger ones go through d1)
void ShiftBy(Gen g, string op, int n, string reg)
{
    if (n <= 8)
        g.Line(op + ".l\t#" + n.ToString() + "," + reg);
    else
    {
        g.Line("moveq\t#" + n.ToString() + ",%d1");
        g.Line(op + ".l\t%d1," + reg);
    }
}

// add, sub, ... on i64: a in d0:d1, b in d2:d3.
void GenBinary64(Gen g, IrInst inst)
{
    string op = inst.Op;
    if (op == "mul" || op == "sdiv" || op == "udiv" || op == "srem" || op == "urem")
    {
        string fn = op == "mul" ? "__muldi3" : op == "sdiv" ? "__divdi3" : op == "udiv" ? "__udivdi3" : op == "srem" ? "__moddi3" : "__umoddi3";
        PushArg(g, inst.Args[1], inst.OpType);
        PushArg(g, inst.Args[0], inst.OpType);
        g.Line("jsr\t" + fn);
        g.Line("lea\t(16,%sp),%sp");
        StoreResult(g, inst);
        return;
    }
    Load64(g, inst.Args[0], "%d0", "%d1");
    Load64(g, inst.Args[1], "%d2", "%d3");
    if (op == "add")
    {
        g.Line("add.l\t%d3,%d1");
        g.Line("addx.l\t%d2,%d0");
    }
    else if (op == "sub")
    {
        g.Line("sub.l\t%d3,%d1");
        g.Line("subx.l\t%d2,%d0");
    }
    else if (op == "and" || op == "or" || op == "xor")
    {
        string m = op == "xor" ? "eor" : op;
        g.Line(m + ".l\t%d2,%d0");
        g.Line(m + ".l\t%d3,%d1");
    }
    else
    {
        // shifts: one bit per step
        string loop = g.NewLabel();
        string done = g.NewLabel();
        g.Line("and.l\t#63,%d3");
        g.Line("beq\t" + done);
        g.Label(loop);
        if (op == "shl")
        {
            g.Line("add.l\t%d1,%d1");
            g.Line("addx.l\t%d0,%d0");
        }
        else
        {
            g.Line((op == "lshr" ? "lsr" : "asr") + ".l\t#1,%d0");
            g.Line("roxr.l\t#1,%d1");
        }
        g.Line("subq.l\t#1,%d3");
        g.Line("bne\t" + loop);
        g.Label(done);
    }
    StoreResult(g, inst);
}

// The condition code of an integer predicate (for the operands in the order cmp b,a => a ? b).
string Cond(string pred)
{
    switch (pred)
    {
    case "eq": return "eq";
    case "ne": return "ne";
    case "slt": return "lt";
    case "sle": return "le";
    case "sgt": return "gt";
    case "sge": return "ge";
    case "ult": return "cs";
    case "ule": return "ls";
    case "ugt": return "hi";
    case "uge": return "cc";
    default: return "eq";
    }
}

void GenIcmp(Gen g, IrInst inst)
{
    int t = inst.OpType;
    int bits = g.T.Kind(t) == IrKind.Int ? g.T.Bits(t) : 32;
    string pred = inst.Pred;
    if (bits == 64)
    {
        bool swap = pred == "sgt" || pred == "sle" || pred == "ugt" || pred == "ule";
        Load64(g, inst.Args[swap ? 1 : 0], "%d0", "%d1");
        Load64(g, inst.Args[swap ? 0 : 1], "%d2", "%d3");
        if (pred == "eq" || pred == "ne")
        {
            string done = g.NewLabel();
            g.Line("cmp.l\t%d3,%d1");
            g.Line("bne\t" + done);
            g.Line("cmp.l\t%d2,%d0");
            g.Label(done);
            g.Line("s" + pred + "\t%d0");
        }
        else
        {
            g.Line("sub.l\t%d3,%d1");
            g.Line("subx.l\t%d2,%d0");
            string c = pred == "slt" || pred == "sgt" ? "lt" : pred == "sge" || pred == "sle" ? "ge" : pred == "ult" || pred == "ugt" ? "cs" : "cc";
            g.Line("s" + c + "\t%d0");
        }
        g.Line("and.l\t#1,%d0");
        StoreResult(g, inst);
        return;
    }
    Load32(g, inst.Args[0], "%d0");
    Load32(g, inst.Args[1], "%d1");
    string suffix = bits <= 8 ? ".b" : bits == 16 ? ".w" : ".l";
    g.Line("cmp" + suffix + "\t%d1,%d0");
    g.Line("s" + Cond(pred) + "\t%d0");
    g.Line("and.l\t#1,%d0");
    StoreResult(g, inst);
}

// call {iN, i1} @llvm.[su](add|sub).with.overflow.iN(a, b) / extractvalue 0 / extractvalue 1 / br i1 flag:
// the flag only decides the branch (N <= 32, no phis in the targets).
bool IsFusableOverflow(Gen g, IrInst[] insts, int k, Dictionary<string, int> uses)
{
    var call = insts[k];
    if (call.Op != "call" || call.Res.Length == 0)
        return false;
    var callee = g.M.Vals.Get(call.Callee);
    if (callee.Kind != ValKind.Global || !callee.Name.StartsWith("llvm.") || !callee.Name.Contains(".with.overflow."))
        return false;
    int t = g.M.Vals.Get(call.Args[0]).Type;
    if (g.T.Kind(t) != IrKind.Int || g.T.Bits(t) > 32 || g.T.Bits(t) < 8)
        return false;
    if (callee.Name.Contains("mul") && (callee.Name != "llvm.smul.with.overflow.i32"))
        return false; // (the signed 32-bit multiplication only)
    var e1 = insts[k + 1];
    var e2 = insts[k + 2];
    var br = insts[k + 3];
    if (e1.Op != "extractvalue" || e2.Op != "extractvalue" || br.Op != "br" || br.Labels.Length != 2)
        return false;
    if (uses.GetOrDefault(call.Res, 0) != 2 || !IsLocal(g, e1.Args[0]) || !IsLocal(g, e2.Args[0]) ||
        g.M.Vals.Get(e1.Args[0]).Name != call.Res || g.M.Vals.Get(e2.Args[0]).Name != call.Res)
        return false;
    // which extract is the flag
    var flag = e1.Cases.Length > 0 && e1.Cases[0] == 1 ? e1 : e2;
    var value = e1.Cases.Length > 0 && e1.Cases[0] == 1 ? e2 : e1;
    if (flag.Cases.Length != 1 || flag.Cases[0] != 1 || value.Cases.Length != 1 || value.Cases[0] != 0)
        return false;
    if (!IsLocal(g, br.Args[0]) || g.M.Vals.Get(br.Args[0]).Name != flag.Res || uses.GetOrDefault(flag.Res, 0) != 1)
        return false;
    return !g.Phis.ContainsKey(br.Labels[0]) && !g.Phis.ContainsKey(br.Labels[1]);
}

void GenOverflowBranch(Gen g, IrInst[] insts, int k)
{
    var call = insts[k];
    string name = g.M.Vals.Get(call.Callee).Name;
    var e1 = insts[k + 1];
    var value = e1.Cases[0] == 0 ? e1 : insts[k + 2];
    var br = insts[k + 3];
    int bits = g.T.Bits(g.M.Vals.Get(call.Args[0]).Type);
    string suffix = bits <= 8 ? ".b" : bits == 16 ? ".w" : ".l";
    bool signed = name.StartsWith("llvm.s");
    bool add = name.Contains("add");
    if (name.Contains("mul"))
    {
        // by a power of two (2 to 256): asl sets V when the sign changes at any step, which is the overflow
        int factor = -1;
        int shift = 0;
        for (var side = 1; side >= 0 && factor < 0; side -= 1)
        {
            var cv = g.M.Vals.Get(call.Args[side]);
            if (cv.Kind != ValKind.Int)
                continue;
            for (var n = 1; n <= 8; n += 1)
            {
                if (cv.Int == ((int64)1 << n))
                {
                    factor = 1 - side;
                    shift = n;
                }
            }
        }
        if (factor >= 0)
        {
            string into = ResultRegister(g, value.Res);
            string reg = into.Length > 0 ? into : "%d0";
            Load32(g, call.Args[factor], reg);
            g.Line("asl.l\t#" + shift.ToString() + "," + reg);
            g.Line("bvs\t" + g.BlockLabel.Get(br.Labels[0]));
            if (reg == "%d0")
                g.Line("move.l\t%d0," + SlotOperand(g, value.Res));
            g.Line("bra\t" + g.BlockLabel.Get(br.Labels[1]));
            return;
        }
        // both factors in 16 bits: muls.w cannot overflow; else the helper (d0 product, d1 overflow)
        string slow = g.NewLabel();
        string ok = g.NewLabel();
        Load32(g, call.Args[0], "%d0");
        Load32(g, call.Args[1], "%d1");
        g.Line("move.w\t%d0,%d2");
        g.Line("ext.l\t%d2");
        g.Line("cmp.l\t%d0,%d2");
        g.Line("bne\t" + slow);
        var cb = g.M.Vals.Get(call.Args[1]);
        if (!(cb.Kind == ValKind.Int && cb.Int >= -32768 && cb.Int <= 32767))
        {
            g.Line("move.w\t%d1,%d2");
            g.Line("ext.l\t%d2");
            g.Line("cmp.l\t%d1,%d2");
            g.Line("bne\t" + slow);
        }
        g.Line("muls.w\t%d1,%d0");
        g.Line("bra\t" + ok);
        g.Label(slow);
        g.Line("move.l\t%d1,-(%sp)");
        g.Line("move.l\t%d0,-(%sp)");
        g.Line("jsr\t__cs68k_smul32o");
        g.Line("addq.l\t#8,%sp");
        g.Line("tst.b\t%d1");
        g.Line("bne\t" + g.BlockLabel.Get(br.Labels[0]));
        g.Label(ok);
        g.Line("move.l\t%d0," + SlotOperand(g, value.Res));
        g.Line("bra\t" + g.BlockLabel.Get(br.Labels[1]));
        return;
    }
    string target = ResultRegister(g, value.Res);
    if (target.Length > 0 && SourceOperand(g, call.Args[1], 32) == target)
        target = "";
    string dst = target.Length > 0 ? target : "%d0";
    Load32(g, call.Args[0], dst);
    string src = SourceOperand(g, call.Args[1], bits);
    if (src.Length == 0)
    {
        Load32(g, call.Args[1], "%d1");
        src = "%d1";
    }
    g.Line((add ? "add" : "sub") + suffix + "\t" + src + "," + dst);
    // the flag is true: to the first label (the panic); signed: overflow (V), unsigned: carry/borrow (C)
    g.Line((signed ? "bvs" : "bcs") + "\t" + g.BlockLabel.Get(br.Labels[0]));
    if (dst == "%d0")
        g.Line("move.l\t%d0," + SlotOperand(g, value.Res));
    g.Line("bra\t" + g.BlockLabel.Get(br.Labels[1]));
}

// icmp + br on its result (32 bits or less)
void GenCompareBranch(Gen g, IrFunc f, IrInst cmp, IrInst br)
{
    WritePhiCopies(g, f, br.Labels);
    int t = cmp.OpType;
    int bits = g.T.Kind(t) == IrKind.Int ? g.T.Bits(t) : 32;
    string suffix = bits <= 8 ? ".b" : bits == 16 ? ".w" : ".l";
    // the left operand where it is (a data register), else in d0; the right one as it is if possible
    string left = SourceOperand(g, cmp.Args[0], bits);
    if (!left.StartsWith("%d"))
    {
        Load32(g, cmp.Args[0], "%d0");
        left = "%d0";
    }
    var right = g.M.Vals.Get(cmp.Args[1]);
    if ((right.Kind == ValKind.Int || right.Kind == ValKind.Null) && right.Int == 0)
        g.Line("tst" + suffix + "\t" + left);
    else
    {
        string src = SourceOperand(g, cmp.Args[1], bits);
        if (src.Length == 0)
        {
            Load32(g, cmp.Args[1], "%d1");
            src = "%d1";
        }
        g.Line("cmp" + suffix + "\t" + src + "," + left);
    }
    g.Line("b" + Cond(cmp.Pred) + "\t" + g.BlockLabel.Get(br.Labels[0]));
    g.Line("bra\t" + g.BlockLabel.Get(br.Labels[1]));
}

void GenSwitch64(Gen g, IrInst inst)
{
    Load64(g, inst.Args[0], "%d0", "%d1");
    for (var i = 0; i < inst.Cases.Length; i += 1)
    {
        int64 cv = inst.Cases[i];
        string next = g.NewLabel();
        g.Line("cmp.l\t#" + ((cv >> 32) & 4294967295).ToString() + ",%d0");
        g.Line("bne\t" + next);
        g.Line("cmp.l\t#" + (cv & 4294967295).ToString() + ",%d1");
        g.Line("beq\t" + g.BlockLabel.Get(inst.Labels[i + 1]));
        g.Label(next);
    }
    g.Line("bra\t" + g.BlockLabel.Get(inst.Labels[0]));
}

void GenIntCast(Gen g, IrInst inst)
{
    string op = inst.Op;
    int from = inst.OpType;
    int to = inst.Type;
    int fromSize = g.L.Size(from);
    int toSize = g.L.Size(to);
    int fromBits = g.T.Kind(from) == IrKind.Int ? g.T.Bits(from) : fromSize * 8;
    if (toSize == 8 && fromSize == 8)
    {
        Load64(g, inst.Args[0], "%d0", "%d1");
        StoreResult(g, inst);
        return;
    }
    if (toSize == 8)
    {
        // widen to 64: the value in d1, its extension in d0
        Load32(g, inst.Args[0], "%d1");
        bool signed = op == "sext";
        Extend(g, "%d1", fromBits, signed);
        if (signed)
        {
            g.Line("move.l\t%d1,%d0");
            g.Line("add.l\t%d0,%d0");
            g.Line("subx.l\t%d0,%d0");
        }
        else
            g.Line("moveq\t#0,%d0");
        StoreResult(g, inst);
        return;
    }
    Load32(g, inst.Args[0], "%d0"); // from 64 bits: the low half
    if (op == "sext")
        Extend(g, "%d0", fromBits, true);
    else if (op == "zext")
        Extend(g, "%d0", fromBits, false);
    StoreResult(g, inst);
}

// The offset of an extractvalue/insertvalue path; 'ft' becomes the type at its end.
int PathOffset(Gen g, int t, int64[] path, ref int ft)
{
    int off = 0;
    int cur = t;
    foreach (var i in path)
    {
        if (g.T.Kind(cur) == IrKind.Array)
        {
            cur = g.T.Info(cur).Elem;
            off += (int)i * g.L.Stride(cur);
        }
        else
        {
            off += g.L.FieldOffset(cur, (int)i);
            cur = g.T.Info(cur).Fields[(int)i];
        }
    }
    ft = cur;
    return off;
}

void GenExtract(Gen g, IrInst inst)
{
    var agg = g.M.Vals.Get(inst.Args[0]);
    int ft = inst.OpType;
    int at = PathOffset(g, inst.OpType, inst.Cases, ref ft);
    int off = g.Slot.Get(inst.Res);
    if (agg.Kind != ValKind.Local)
    {
        // a constant aggregate: its element (zero for zeroinitializer/undef)
        if (agg.Kind == ValKind.Zero || agg.Kind == ValKind.Null)
        {
            if (g.T.IsAggregate(ft))
                StoreConst(g, inst.Args[0], ft, "%a6", off);
            else
            {
                g.Line("moveq\t#0,%d0");
                g.Line("moveq\t#0,%d1");
                StoreResult(g, inst);
            }
            return;
        }
        int item = inst.Args[0];
        foreach (var i in inst.Cases)
            item = g.M.Vals.Get(item).Items[(int)i];
        if (g.T.IsAggregate(ft))
            CopyToSlot(g, item, ft, off);
        else
        {
            if (g.L.Size(ft) == 8)
                Load64(g, item, "%d0", "%d1");
            else
                Load32(g, item, "%d0");
            StoreResult(g, inst);
        }
        return;
    }
    int src = SlotOf(g, inst.Args[0]) + at;
    int size = g.L.Size(ft);
    if (g.T.IsAggregate(ft))
    {
        g.Line("lea\t" + Frame(src) + ",%a0");
        g.Line("lea\t" + Frame(off) + ",%a1");
        CopyMem(g, size, g.L.Align(ft) >= 2 && src % 2 == 0);
        return;
    }
    if (size == 8)
    {
        g.Line("move.l\t" + Frame(src) + ",%d0");
        g.Line("move.l\t" + Frame(src + 4) + ",%d1");
    }
    else
        g.Line("move" + SizeSuffix(size) + "\t" + Frame(src) + ",%d0");
    StoreResult(g, inst);
}

// getelementptr: the base in d0, plus the constant offsets and the scaled variable indexes.
void GenGep(Gen g, IrInst inst)
{
    // computed in an address register: the result's, or a0
    string dst = "%a0";
    var home = g.Home.TryGet(inst.Res);
    if (home is string reg && reg.StartsWith("%a"))
        dst = reg;
    LoadAddr(g, inst.Args[0], dst);
    int t = inst.OpType;
    int64 constant = 0;
    for (var k = 1; k < inst.Args.Length; k += 1)
    {
        int idx = inst.Args[k];
        int stride;
        if (k == 1)
            stride = g.L.Stride(t);
        else if (g.T.Kind(t) == IrKind.Struct)
        {
            int field = (int)g.M.Vals.Get(idx).Int;
            constant += (int64)g.L.FieldOffset(t, field);
            t = g.T.Info(t).Fields[field];
            continue;
        }
        else
        {
            t = g.T.Info(t).Elem;
            stride = g.L.Stride(t);
        }
        var iv = g.M.Vals.Get(idx);
        if (iv.Kind != ValKind.Local)
        {
            var c = EvalConst(g, idx);
            int bits = g.T.Bits(iv.Type);
            int64 n = c.Off;
            if (bits < 64 && bits > 0)
            {
                // sign-extend the constant from its width
                int64 top = (int64)1 << (bits - 1);
                n = unchecked(((n & ((top << 1) - 1)) ^ top) - top);
            }
            constant += n * (int64)stride;
            continue;
        }
        Load32(g, idx, "%d1");
        int ib = g.T.Bits(iv.Type);
        if (ib < 32)
            Extend(g, "%d1", ib, true);
        ScaleD1(g, stride);
        g.Line("add.l\t%d1," + dst);
    }
    if (constant != 0)
    {
        if (constant >= -32768 && constant <= 32767)
            g.Line("lea\t(" + constant.ToString() + "," + dst + ")," + dst);
        else
            g.Line("add.l\t#" + constant.ToString() + "," + dst);
    }
    if (dst == "%a0")
    {
        g.Line("move.l\t%a0,%d0");
        StoreResult(g, inst);
    }
}

// d1 *= n (d0 and a0 kept).
void ScaleD1(Gen g, int n)
{
    if (n == 1)
        return;
    int shift = 0;
    while ((1 << shift) < n)
        shift += 1;
    if ((1 << shift) == n)
    {
        while (shift > 8)
        {
            g.Line("lsl.l\t#8,%d1");
            shift -= 8;
        }
        if (shift > 0)
            g.Line("lsl.l\t#" + shift.ToString() + ",%d1");
        return;
    }
    g.Line("move.l\t%d0,-(%sp)");
    g.Line("move.l\t%d1,%d0");
    g.Line("move.l\t#" + n.ToString() + ",%d1");
    g.Line("jsr\t__cs68k_mul32");
    g.Line("move.l\t%d0,%d1");
    g.Line("move.l\t(%sp)+,%d0");
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

// Pushes one argument (the C convention). Returns the bytes it took.
int PushArg(Gen g, int vi, int t)
{
    int size = ArgSize(g, t);
    if (g.T.IsAggregate(t))
    {
        g.Line("suba.l\t#" + size.ToString() + ",%sp");
        g.Line("move.l\t%sp,%a1");
        StoreValue(g, vi, t, "%a1", 0);
        return size;
    }
    if (size == 8)
    {
        Load64(g, vi, "%d0", "%d1");
        g.Line("move.l\t%d1,-(%sp)");
        g.Line("move.l\t%d0,-(%sp)");
        return 8;
    }
    Load32(g, vi, "%d0");
    g.Line("move.l\t%d0,-(%sp)");
    return 4;
}

void GenCall(Gen g, IrInst inst)
{
    var callee = g.M.Vals.Get(inst.Callee);
    if (callee.Kind == ValKind.Global && callee.Name.StartsWith("llvm."))
    {
        GenIntrinsic(g, inst, callee.Name);
        return;
    }
    if (callee.Kind == ValKind.Global && callee.Name.StartsWith("__amiga$"))
    {
        GenLibraryCall(g, inst, callee.Name);
        return;
    }
    if (callee.Kind == ValKind.Global && callee.Name == "__cs_len" && inst.Args.Length == 1 && g.M.FuncIndex.ContainsKey("__cs_len"))
    {
        // the length of a string or array (0 for null), inline: it is needed for every bounds check. The pointer goes
        // into the result's register first: for null that already is the 0.
        string done = g.NewLabel();
        string dst = inst.Res.Length > 0 ? ResultRegister(g, inst.Res) : "";
        if (dst.Length == 0)
            dst = "%d0";
        string from = ValueRegister(g, inst.Args[0]);
        if (from.StartsWith("%a"))
        {
            g.Line("move.l\t" + from + "," + dst);
            g.Line("beq.s\t" + done);
            g.Line("move.l\t(4," + from + ")," + dst);
        }
        else
        {
            // every move into a data register sets Z (Load32 writes nothing when the value is there already)
            if (from == dst)
                g.Line("tst.l\t" + dst);
            else
                Load32(g, inst.Args[0], dst);
            g.Line("beq.s\t" + done);
            g.Line("move.l\t" + dst + ",%a0");
            g.Line("move.l\t(4,%a0)," + dst);
        }
        g.Label(done);
        if (dst == "%d0" && inst.Res.Length > 0)
            StoreResult(g, inst);
        return;
    }
    int bytes = 0;
    for (var i = inst.Args.Length - 1; i >= 0; i -= 1)
        bytes += PushArg(g, inst.Args[i], g.M.Vals.Get(inst.Args[i]).Type);
    bool structResult = inst.Res.Length > 0 && g.T.IsAggregate(inst.Type);
    if (structResult)
    {
        g.Line("pea\t" + Frame(g.Slot.Get(inst.Res)));
        bytes += 4;
    }
    if (callee.Kind == ValKind.Global)
        g.Line("jsr\t" + Sym(g, callee.Name));
    else
    {
        LoadAddr(g, inst.Callee, "%a0");
        g.Line("jsr\t(%a0)");
    }
    if (bytes > 0)
        g.Line("lea\t(" + bytes.ToString() + ",%sp),%sp");
    if (inst.Res.Length == 0 || structResult)
        return;
    if (g.T.Kind(inst.Type) == IrKind.Ptr)
        g.Line("move.l\t%a0,%d0");
    StoreResult(g, inst);
}

// A call of an AmigaOS library function (imported from an SFD file): __amiga$<library>$<offset>$<registers>$<n|v>.
// The arguments are pushed like for C, then loaded into their registers; the library base goes to a6. With v (a
// ...Tags function) the last register gets the address of the variable arguments, which are on the stack already.
void GenLibraryCall(Gen g, IrInst inst, string name)
{
    var parts = name.Split('$');
    string library = parts[1].ToString();
    string offset = parts[2].ToString();
    var regs = parts[3].Length > 0 ? parts[3].Split('.') : new StringSlice[0];
    bool varargs = parts[4].ToString() == "v";

    // the registers to keep (the C convention keeps d2-d7/a2-a6; our frame pointer is a6)
    var saved = List<string>.Create();
    foreach (var r in regs)
    {
        string reg = r.ToString();
        if (reg != "d0" && reg != "d1" && reg != "a0" && reg != "a1" && !saved.Contains("%" + reg))
            saved.Add("%" + reg);
    }
    saved.Add("%a6");
    string savedList = string.Join("/", saved.ToArray());
    g.Line("movem.l\t" + savedList + ",-(%sp)");
    int bytes = 0;
    for (var i = inst.Args.Length - 1; i >= 0; i -= 1)
        bytes += PushArg(g, inst.Args[i], g.M.Vals.Get(inst.Args[i]).Type);
    int off = 0;
    int r = 0;
    for (var i = 0; i < inst.Args.Length && r < regs.Length; i += 1)
    {
        if (varargs && r == regs.Length - 1)
            break;
        int size = ArgSize(g, g.M.Vals.Get(inst.Args[i]).Type);
        g.Line("move.l\t(" + off.ToString() + ",%sp),%" + regs[r].ToString());
        r += 1;
        if (size == 8 && r < regs.Length)
        {
            g.Line("move.l\t(" + (off + 4).ToString() + ",%sp),%" + regs[r].ToString());
            r += 1;
        }
        off += size;
    }
    if (varargs && r == regs.Length - 1)
        g.Line("lea\t(" + off.ToString() + ",%sp),%" + regs[r].ToString());
    g.Line("move.l\t" + LibraryBase(g, library) + ",%a6");
    g.Line("jsr\t(-" + offset + ",%a6)");
    if (bytes > 0)
        g.Line("lea\t(" + bytes.ToString() + ",%sp),%sp");
    g.Line("movem.l\t(%sp)+," + savedList);
    if (inst.Res.Length > 0)
        StoreResult(g, inst);
}

// Where the base of a library is: exec's at address 4, dos.library's is opened by the runtime, the others are opened
// when the program starts (the table __cs_amiga_libs).
string LibraryBase(Gen g, string library)
{
    if (library == "exec.library")
        return "4";
    if (library == "dos.library")
        return "__cs_DOSBase";
    int index = g.Libraries.IndexOf(library);
    if (index < 0)
    {
        g.Libraries.Add(library);
        index = g.Libraries.Count() - 1;
    }
    return "__cs_lib_" + index.ToString();
}

// The table of the libraries to open: name, base, ..., 0.
string LibraryTable(Gen g)
{
    var sb = StringBuilder.Create();
    sb.Append("\t.even\n__cs_amiga_libs:\n");
    for (var i = 0; i < g.Libraries.Count(); i += 1)
        sb.Append("\t.long\t__cs_libname_" + i.ToString() + ",__cs_lib_" + i.ToString() + "\n");
    sb.Append("\t.long\t0\n");
    for (var i = 0; i < g.Libraries.Count(); i += 1)
    {
        sb.Append("__cs_lib_" + i.ToString() + ":\t.long\t0\n");
        sb.Append("__cs_libname_" + i.ToString() + ":\n\t.byte\t");
        foreach (var c in g.Libraries.Get(i))
            sb.Append(((int)c).ToString() + ",");
        sb.Append("0\n\t.even\n");
    }
    return sb.ToString();
}

void GenIntrinsic(Gen g, IrInst inst, string name)
{
    if (name.StartsWith("llvm.memcpy") || name.StartsWith("llvm.memmove") || name.StartsWith("llvm.memset"))
    {
        string fn = name.StartsWith("llvm.memcpy") ? "memcpy" : name.StartsWith("llvm.memmove") ? "memmove" : "memset";
        int bytes = 0;
        for (var i = 2; i >= 0; i -= 1)
            bytes += PushArg(g, inst.Args[i], g.M.Vals.Get(inst.Args[i]).Type);
        g.Line("jsr\t" + fn);
        g.Line("lea\t(" + bytes.ToString() + ",%sp),%sp");
        return;
    }
    if (name.Contains(".with.overflow."))
    {
        GenOverflow(g, inst, name);
        return;
    }
    if (name.StartsWith("llvm.fptosi.sat") || name.StartsWith("llvm.fptoui.sat"))
    {
        // the helper saturates; the result width is truncated by the use
        int from = g.M.Vals.Get(inst.Args[0]).Type;
        bool signed = name.StartsWith("llvm.fptosi");
        int bits = g.T.Bits(inst.Type);
        bool fromDouble = g.T.Kind(from) == IrKind.Double;
        string fn;
        if (bits == 64)
            fn = "__fix" + (signed ? "" : "uns") + (fromDouble ? "df" : "sf") + "di"; // these saturate as well
        else if (bits == 32 && !signed)
            fn = fromDouble ? "__cs68k_dtou_sat" : "__cs68k_ftou_sat";
        else
            fn = fromDouble ? "__cs68k_dtoi_sat" : "__cs68k_ftoi_sat"; // narrower unsigned types: clamped below
        PushArg(g, inst.Args[0], from);
        g.Line("jsr\t" + fn);
        g.Line("lea\t(" + ArgSize(g, from).ToString() + ",%sp),%sp");
        if (bits < 32)
        {
            // clamp to the result's range
            int64 lo = signed ? -((int64)1 << (bits - 1)) : 0;
            int64 hi = signed ? ((int64)1 << (bits - 1)) - 1 : ((int64)1 << bits) - 1;
            string ok1 = g.NewLabel();
            string ok2 = g.NewLabel();
            g.Line("cmp.l\t#" + lo.ToString() + ",%d0");
            g.Line("bge\t" + ok1);
            g.Line("move.l\t#" + lo.ToString() + ",%d0");
            g.Label(ok1);
            g.Line("cmp.l\t#" + hi.ToString() + ",%d0");
            g.Line("ble\t" + ok2);
            g.Line("move.l\t#" + hi.ToString() + ",%d0");
            g.Label(ok2);
        }
        StoreResult(g, inst);
        return;
    }
    g.Fail("the intrinsic " + name + " is not supported");
}

// llvm.{s,u}{add,sub,mul}.with.overflow.iN: { result, overflow } into the result's slot.
void GenOverflow(Gen g, IrInst inst, string name)
{
    int t = g.M.Vals.Get(inst.Args[0]).Type;
    int bits = g.T.Bits(t);
    bool signed = name.StartsWith("llvm.s");
    string kind = name.Contains("add") ? "add" : name.Contains("sub") ? "sub" : "mul";
    int off = g.Slot.Get(inst.Res);
    int flagAt = off + g.L.FieldOffset(inst.Type, 1);
    if (bits == 64)
    {
        if (kind == "mul")
        {
            PushArg(g, inst.Args[1], t);
            PushArg(g, inst.Args[0], t);
            g.Line("jsr\t" + (signed ? "__cs68k_smul64o" : "__cs68k_umul64o"));
            g.Line("lea\t(16,%sp),%sp");
            // d0:d1 = product, a0 = overflow
            g.Line("move.l\t%a0,%d2");
            g.Line("move.l\t%d0," + Frame(off));
            g.Line("move.l\t%d1," + Frame(off + 4));
            g.Line("move.b\t%d2," + Frame(flagAt));
            return;
        }
        Load64(g, inst.Args[0], "%d0", "%d1");
        Load64(g, inst.Args[1], "%d2", "%d3");
        if (kind == "add")
        {
            g.Line("add.l\t%d3,%d1");
            g.Line("addx.l\t%d2,%d0");
        }
        else
        {
            g.Line("sub.l\t%d3,%d1");
            g.Line("subx.l\t%d2,%d0");
        }
        g.Line((signed ? "svs" : "scs") + "\t%d2");
        g.Line("move.l\t%d0," + Frame(off));
        g.Line("move.l\t%d1," + Frame(off + 4));
        g.Line("and.b\t#1,%d2");
        g.Line("move.b\t%d2," + Frame(flagAt));
        return;
    }
    string suffix = bits <= 8 ? ".b" : bits == 16 ? ".w" : ".l";
    int size = g.L.Size(t);
    if (kind == "mul")
    {
        if (bits == 32 && signed)
        {
            PushArg(g, inst.Args[1], t);
            PushArg(g, inst.Args[0], t);
            g.Line("jsr\t__cs68k_smul32o");
            g.Line("addq.l\t#8,%sp");
        }
        else
        {
            // up to 16 bits: multiply the extended values in 32 bits and check that the product fits;
            // unsigned 32 bits: the full 64-bit product
            Load32(g, inst.Args[0], "%d0");
            Load32(g, inst.Args[1], "%d1");
            if (bits == 32)
            {
                g.Line("jsr\t__cs68k_umul64");
                // d0 = high, d1 = low
                g.Line("tst.l\t%d0");
                g.Line("sne\t%d2");
                g.Line("move.l\t%d1,%d0");
                g.Line("move.l\t%d2,%d1");
            }
            else
            {
                Extend(g, "%d0", bits, signed);
                Extend(g, "%d1", bits, signed);
                g.Line("jsr\t__cs68k_mul32");
                g.Line("move.l\t%d0,%d1");
                Extend(g, "%d1", bits, signed);
                g.Line("cmp.l\t%d0,%d1");
                g.Line("sne\t%d1");
            }
        }
        g.Line("move" + (size == 1 ? ".b" : size == 2 ? ".w" : ".l") + "\t%d0," + Frame(off));
        g.Line("and.b\t#1,%d1");
        g.Line("move.b\t%d1," + Frame(flagAt));
        return;
    }
    Load32(g, inst.Args[0], "%d0");
    Load32(g, inst.Args[1], "%d1");
    g.Line((kind == "add" ? "add" : "sub") + suffix + "\t%d1,%d0");
    g.Line((signed ? "svs" : "scs") + "\t%d1");
    g.Line("move" + (size == 1 ? ".b" : size == 2 ? ".w" : ".l") + "\t%d0," + Frame(off));
    g.Line("and.b\t#1,%d1");
    g.Line("move.b\t%d1," + Frame(flagAt));
}

// ---------------------------------------------------------------------------
// Floating point: calls of the soft-float helpers (the names of libgcc)
// ---------------------------------------------------------------------------

void GenFloatBinary(Gen g, IrInst inst)
{
    bool dbl = g.T.Kind(inst.OpType) == IrKind.Double;
    string op = inst.Op.Substring(1); // add, sub, mul, div, rem
    string fn = op == "rem" ? (dbl ? "fmod" : "fmodf") : "__" + op + (dbl ? "df3" : "sf3");
    PushArg(g, inst.Args[1], inst.OpType);
    PushArg(g, inst.Args[0], inst.OpType);
    g.Line("jsr\t" + fn);
    g.Line("lea\t(" + (dbl ? 16 : 8).ToString() + ",%sp),%sp");
    StoreResult(g, inst);
}

void GenFcmp(Gen g, IrInst inst)
{
    // __cs68k_fcmp_d / _f: -1, 0, 1 (a < b, a == b, a > b), 2 if unordered (NaN)
    bool dbl = g.T.Kind(inst.OpType) == IrKind.Double;
    PushArg(g, inst.Args[1], inst.OpType);
    PushArg(g, inst.Args[0], inst.OpType);
    g.Line("jsr\t" + (dbl ? "__cs68k_fcmp_d" : "__cs68k_fcmp_f"));
    g.Line("lea\t(" + (dbl ? 16 : 8).ToString() + ",%sp),%sp");
    string p = inst.Pred;
    // unordered compares true for "u.." predicates and une
    bool unorderedTrue = p.StartsWith("u");
    string rel = p.Length == 3 ? p.Substring(1) : p;
    string yes = g.NewLabel();
    string done = g.NewLabel();
    g.Line("cmp.l\t#2,%d0");
    g.Line("beq\t" + (unorderedTrue ? yes : done + "_false"));
    string cc = rel == "eq" ? "eq" : rel == "ne" ? "ne" : rel == "lt" ? "lt" : rel == "le" ? "le" : rel == "gt" ? "gt" : rel == "ge" ? "ge" : "t";
    if (rel == "rd")
        cc = "t"; // ord: not unordered
    if (rel == "no")
        cc = "f";
    g.Line("tst.l\t%d0");
    g.Line("s" + cc + "\t%d0");
    g.Line("bra\t" + done);
    g.Label(yes);
    g.Line("moveq\t#1,%d0");
    g.Line("bra\t" + done);
    g.Label(done + "_false");
    g.Line("moveq\t#0,%d0");
    g.Label(done);
    g.Line("and.l\t#1,%d0");
    StoreResult(g, inst);
}

void GenFloatCast(Gen g, IrInst inst)
{
    string op = inst.Op;
    int from = inst.OpType;
    int to = inst.Type;
    bool fromDouble = g.T.Kind(from) == IrKind.Double;
    bool toDouble = g.T.Kind(to) == IrKind.Double;
    string fn;
    if (op == "fptrunc")
        fn = "__truncdfsf2";
    else if (op == "fpext")
        fn = "__extendsfdf2";
    else if (op == "sitofp" || op == "uitofp")
    {
        bool from64 = g.T.Bits(from) == 64;
        string u = op == "uitofp" ? "un" : "";
        fn = "__float" + u + (from64 ? "di" : "si") + (toDouble ? "df" : "sf");
        if (!from64 && g.T.Bits(from) < 32)
        {
            // extend first
            Load32(g, inst.Args[0], "%d0");
            Extend(g, "%d0", g.T.Bits(from), op == "sitofp");
            g.Line("move.l\t%d0,-(%sp)");
            g.Line("jsr\t" + fn);
            g.Line("addq.l\t#4,%sp");
            StoreResult(g, inst);
            return;
        }
    }
    else
    {
        bool to64 = g.T.Bits(to) == 64;
        string u = op == "fptoui" ? "uns" : "";
        fn = "__fix" + u + (fromDouble ? "df" : "sf") + (to64 ? "di" : "si");
    }
    int bytes = PushArg(g, inst.Args[0], from);
    g.Line("jsr\t" + fn);
    g.Line("lea\t(" + bytes.ToString() + ",%sp),%sp");
    StoreResult(g, inst);
}
