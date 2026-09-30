// The assembler of the 68000 backend: turns the assembly text of Gen.csh (GNU as syntax, the subset that Gen and
// Runtime.csh write) into machine code, in two sections (code and data) with 32-bit absolute relocations. Written out
// as an AmigaOS executable (Hunk.csh) or, for tests on Linux, as an ELF object (Elf.csh).
//
// Choices of its own (like GNU as): add/sub #1..8 become addq/subq, move.l #-128..127 to a data register moveq,
// (0,An) is (An); branches to labels are short (8-bit) where the distance allows, otherwise 16-bit.

namespace CShift.M68k;

using System;

enum OpMode : uint8
{
    None,
    Dn,
    An,
    Ind,      // (An)
    PostInc,  // (An)+
    PreDec,   // -(An)
    Disp,     // (d16,An)
    Index,    // (d8,An,Xn)
    Abs,      // an address: a symbol or a number
    Imm,      // #value or #symbol
    RegList,  // movem
}

struct AsmOperand
{
    OpMode Mode;
    int Reg;
    int IndexReg;   // 0-7 d0-d7, 8-15 a0-a7
    bool IndexLong;
    int64 Value;
    string Sym;     // "" for a plain number
}

enum ItemKind : uint8
{
    Instr,
    Label,
    Bytes,
    Words,
    Longs,
    Space,
    Even,
    Section,
}

struct AsmItem
{
    ItemKind Kind;
    string Op;        // the mnemonic without the size (instructions), the name (labels)
    int Size;         // 1, 2, 4; 0 without a suffix
    bool ForceShort;  // bra.s
    AsmOperand[] Ops;
    int64[] Values;   // .byte/.word/.long numbers, .space count, .section index
    string[] Syms;    // .long symbols ("" for numbers)
    int Line;
    int Section;
    int Offset;
    bool Long;        // a branch that needs a 16-bit displacement
}

struct AsmReloc
{
    int Offset;
    string Sym;
    int64 Addend;
}

struct AsmSection
{
    List<uint8> Bytes;
    List<AsmReloc> Relocs;
}

struct AsmSymbol
{
    int Section;
    int Offset;
    bool Global;
}

struct AsmObject
{
    AsmSection[] Sections;                // [0] code, [1] data
    Dictionary<string, AsmSymbol> Symbols;
    List<string> Externals;               // referenced but not defined
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

struct AsmParser
{
    List<AsmItem> Items;
    List<string> Errors;
    HashSet<string> Globals;
    int[] State;   // [0] the current section
}

Error<AsmObject> Assemble(string text)
{
    var p = AsmParser { Items = List<AsmItem>.Create(), Errors = List<string>.Create(), Globals = HashSet<string>.Create(), State = new int[1] };
    var lines = text.Split('\n');
    for (var i = 0; i < lines.Length; i += 1)
        ParseAsmLine(p, lines[i].ToString(), i + 1);
    if (p.Errors.Count() > 0)
        return error(string.Join("\n", p.Errors.ToArray()));
    return AsmLayout(p);
}

void AsmError(AsmParser p, int line, string message)
{
    if (p.Errors.Count() < 20)
        p.Errors.Add("assembler, line " + line.ToString() + ": " + message);
}

AsmItem NewItem(AsmParser p, ItemKind kind, int line)
{
    return AsmItem { Kind = kind, Op = "", Size = 0, ForceShort = false, Ops = new AsmOperand[0], Values = new int64[0], Syms = new string[0],
                     Line = line, Section = p.State[0], Offset = 0, Long = false };
}

void ParseAsmLine(AsmParser p, string raw, int line)
{
    string s = raw.Trim().ToString();
    if (s.Length == 0)
        return;
    // labels: "name:" at the start of the line
    if (!raw.StartsWith("\t") && !raw.StartsWith(" "))
    {
        int colon = s.IndexOf(':');
        if (colon > 0)
        {
            var item = NewItem(p, ItemKind.Label, line);
            item.Op = s.Substring(0, colon).ToString();
            p.Items.Add(item);
            s = s.Substring(colon + 1).Trim().ToString();
            if (s.Length == 0)
                return;
        }
    }
    string op = s;
    string rest = "";
    int split = AsmFirstSpace(s);
    if (split >= 0)
    {
        op = s.Substring(0, split).ToString();
        rest = s.Substring(split + 1).Trim().ToString();
    }
    if (op.StartsWith("."))
    {
        ParseDirective(p, op, rest, line);
        return;
    }
    var instr = NewItem(p, ItemKind.Instr, line);
    int dot = op.IndexOf('.');
    string mnemonic = op;
    if (dot > 0)
    {
        mnemonic = op.Substring(0, dot).ToString();
        string suffix = op.Substring(dot + 1).ToString();
        if (suffix == "b")
            instr.Size = 1;
        else if (suffix == "w")
            instr.Size = 2;
        else if (suffix == "l")
            instr.Size = 4;
        else if (suffix == "s")
            instr.ForceShort = true;
        else
            AsmError(p, line, "unknown size '." + suffix + "'");
    }
    instr.Op = mnemonic;
    var ops = List<AsmOperand>.Create();
    if (rest.Length > 0)
    {
        foreach (var part in SplitOperands(rest))
        {
            var parsed = ParseOperand(part);
            if (parsed is AsmOperand o)
                ops.Add(o);
            else
                AsmError(p, line, "cannot read the operand '" + part + "'");
        }
    }
    instr.Ops = ops.ToArray();
    p.Items.Add(instr);
}

int AsmFirstSpace(string s)
{
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == ' ' || s[i] == '\t')
            return i;
    }
    return -1;
}

void ParseDirective(AsmParser p, string op, string rest, int line)
{
    if (op == ".text" || op == ".data")
    {
        p.State[0] = op == ".text" ? 0 : 1;
        return;
    }
    if (op == ".globl" || op == ".global")
    {
        p.Globals.Add(rest);
        return;
    }
    if (op == ".even" || op == ".align")
    {
        p.Items.Add(NewItem(p, ItemKind.Even, line));
        return;
    }
    if (op == ".space" || op == ".skip")
    {
        var item = NewItem(p, ItemKind.Space, line);
        item.Values = [AsmNumber(rest)];
        p.Items.Add(item);
        return;
    }
    if (op == ".byte" || op == ".word" || op == ".short" || op == ".long")
    {
        var item = NewItem(p, op == ".byte" ? ItemKind.Bytes : (op == ".long" ? ItemKind.Longs : ItemKind.Words), line);
        var values = List<int64>.Create();
        var syms = List<string>.Create();
        foreach (var part in rest.Split(','))
        {
            string v = part.Trim().ToString();
            var e = ParseExpr(v);
            if (e is AsmOperand o)
            {
                values.Add(o.Value);
                syms.Add(o.Sym);
                if (o.Sym.Length > 0 && item.Kind != ItemKind.Longs)
                    AsmError(p, line, "a symbol needs 32 bits");
            }
            else
                AsmError(p, line, "cannot read '" + v + "'");
        }
        item.Values = values.ToArray();
        item.Syms = syms.ToArray();
        p.Items.Add(item);
        return;
    }
    AsmError(p, line, "unknown directive '" + op + "'");
}

// "a,(4,%a6),%d0": the commas outside of parentheses split
string[] SplitOperands(string s)
{
    var parts = List<string>.Create();
    int depth = 0;
    int start = 0;
    for (var i = 0; i < s.Length; i += 1)
    {
        char c = s[i];
        if (c == '(')
            depth += 1;
        else if (c == ')')
            depth -= 1;
        else if (c == ',' && depth == 0)
        {
            parts.Add(s.Substring(start, i - start).Trim().ToString());
            start = i + 1;
        }
    }
    parts.Add(s.Substring(start).Trim().ToString());
    return parts.ToArray();
}

// %d0..%d7 -> 0..7, %a0..%a7/%sp/%fp -> 8..15, -1 otherwise
int ParseRegister(string s)
{
    if (s == "%sp")
        return 15;
    if (s == "%fp")
        return 14;
    if (s.Length == 3 && s[0] == '%' && s[2] >= '0' && s[2] <= '7')
    {
        int n = (int)s[2] - 48;
        if (s[1] == 'd')
            return n;
        if (s[1] == 'a')
            return 8 + n;
    }
    return -1;
}

AsmOperand PlainOperand(OpMode mode, int reg)
{
    return AsmOperand { Mode = mode, Reg = reg, IndexReg = 0, IndexLong = false, Value = 0, Sym = "" };
}

Optional<AsmOperand> ParseOperand(string s)
{
    int r = ParseRegister(s);
    if (r >= 0)
        return PlainOperand(r < 8 ? OpMode.Dn : OpMode.An, r & 7);
    if (s.StartsWith("#"))
    {
        var e = ParseExpr(s.Substring(1).ToString());
        if (e is AsmOperand imm)
        {
            imm.Mode = OpMode.Imm;
            return imm;
        }
        return null;
    }
    if (s.StartsWith("-(") && s.EndsWith(")"))
    {
        int a = ParseRegister(s.Substring(2, s.Length - 3).ToString());
        if (a < 8)
            return null;
        return PlainOperand(OpMode.PreDec, a & 7);
    }
    if (s.StartsWith("(") && s.EndsWith(")+"))
    {
        int a = ParseRegister(s.Substring(1, s.Length - 3).ToString());
        if (a < 8)
            return null;
        return PlainOperand(OpMode.PostInc, a & 7);
    }
    if (s.StartsWith("(") && s.EndsWith(")"))
    {
        var inner = s.Substring(1, s.Length - 2).Split(',');
        if (inner.Length == 1)
        {
            int a = ParseRegister(inner[0].Trim().ToString());
            if (a < 8)
                return null;
            return PlainOperand(OpMode.Ind, a & 7);
        }
        var disp = ParseExpr(inner[0].Trim().ToString());
        int b = ParseRegister(inner[1].Trim().ToString());
        if (disp is AsmOperand d && d.Sym.Length == 0 && b >= 8)
        {
            if (inner.Length == 2)
            {
                if (d.Value == 0)
                    return PlainOperand(OpMode.Ind, b & 7);
                var o = PlainOperand(OpMode.Disp, b & 7);
                o.Value = d.Value;
                return o;
            }
            if (inner.Length == 3)
            {
                string x = inner[2].Trim().ToString();
                bool isLong = true;
                if (x.EndsWith(".w") || x.EndsWith(".l"))
                {
                    isLong = x.EndsWith(".l");
                    x = x.Substring(0, x.Length - 2).ToString();
                }
                int xr = ParseRegister(x);
                if (xr < 0)
                    return null;
                var o = PlainOperand(OpMode.Index, b & 7);
                o.Value = d.Value;
                o.IndexReg = xr;
                o.IndexLong = isLong;
                return o;
            }
        }
        return null;
    }
    if (s.StartsWith("%"))
    {
        // a register list: %d2-%d3/%a2
        int mask = 0;
        foreach (var part in s.Split('/'))
        {
            var range = part.Split('-');
            int first = ParseRegister(range[0].ToString());
            int last = range.Length > 1 ? ParseRegister(range[1].ToString()) : first;
            if (first < 0 || last < first)
                return null;
            for (var k = first; k <= last; k += 1)
                mask = mask | (1 << k);
        }
        var o = PlainOperand(OpMode.RegList, 0);
        o.Value = (int64)mask;
        return o;
    }
    var abs = ParseExpr(s);
    if (abs is AsmOperand absolute)
    {
        absolute.Mode = OpMode.Abs;
        return absolute;
    }
    return null;
}

// a number, a symbol, or symbol+number / symbol-number
Optional<AsmOperand> ParseExpr(string s)
{
    if (s.Length == 0)
        return null;
    char c = s[0];
    if ((c >= '0' && c <= '9') || c == '-')
    {
        var n = TryAsmNumber(s);
        if (n is int64 value)
        {
            var o = PlainOperand(OpMode.Abs, 0);
            o.Value = value;
            return o;
        }
        return null;
    }
    int cut = -1;
    for (var i = 1; i < s.Length; i += 1)
    {
        if (s[i] == '+' || s[i] == '-')
        {
            cut = i;
            break;
        }
    }
    string sym = cut < 0 ? s : s.Substring(0, cut).ToString();
    int64 addend = 0;
    if (cut >= 0)
    {
        var n = TryAsmNumber(s.Substring(s[cut] == '+' ? cut + 1 : cut).ToString());
        if (n is int64 value)
            addend = value;
        else
            return null;
    }
    var o = PlainOperand(OpMode.Abs, 0);
    o.Sym = sym;
    o.Value = addend;
    return o;
}

Optional<int64> TryAsmNumber(string s)
{
    bool negative = s.StartsWith("-");
    string digits = negative ? s.Substring(1).ToString() : s;
    if (digits.Length == 0)
        return null;
    int64 v = 0;
    unchecked
    {
        if (digits.StartsWith("0x"))
        {
            for (var i = 2; i < digits.Length; i += 1)
            {
                int h = Char.HexValue(digits[i]);
                if (h < 0)
                    return null;
                v = v * 16 + (int64)h;
            }
        }
        else
        {
            for (var i = 0; i < digits.Length; i += 1)
            {
                char c = digits[i];
                if (c < '0' || c > '9')
                    return null;
                v = v * 10 + (int64)((int)c - 48);
            }
        }
        return negative ? -v : v;
    }
}

int64 AsmNumber(string s)
{
    var n = TryAsmNumber(s);
    if (n is int64 v)
        return v;
    return 0;
}

// ---------------------------------------------------------------------------
// Layout: sizes and addresses, with branch relaxation
// ---------------------------------------------------------------------------

struct Encoder
{
    AsmSection[] Sections;
    Dictionary<string, AsmSymbol> Labels;
    List<string> Errors;
    bool[] Final;        // [0] the last pass: errors are reported
}

Error<AsmObject> AsmLayout(AsmParser p)
{
    var labels = Dictionary<string, AsmSymbol>.Create();
    var items = p.Items;
    var enc = Encoder { Sections = new AsmSection[2], Labels = labels, Errors = List<string>.Create(), Final = new bool[1] };
    for (var pass = 0; pass < 50; pass += 1)
    {
        // addresses with the current branch sizes
        enc.Sections[0] = AsmSection { Bytes = List<uint8>.Create(), Relocs = List<AsmReloc>.Create() };
        enc.Sections[1] = AsmSection { Bytes = List<uint8>.Create(), Relocs = List<AsmReloc>.Create() };
        bool changed = false;
        for (var i = 0; i < items.Count(); i += 1)
        {
            var item = items.Get(i);
            var sec = enc.Sections[item.Section];
            item.Offset = sec.Bytes.Count();
            if (item.Kind == ItemKind.Label)
            {
                var old = labels.TryGet(item.Op);
                if (old is AsmSymbol prev && pass == 0)
                    AsmError(p, item.Line, "the label '" + item.Op + "' is defined twice");
                labels.Set(item.Op, AsmSymbol { Section = item.Section, Offset = item.Offset, Global = p.Globals.Contains(item.Op) });
            }
            else
                EncodeItem(enc, ref item);
            items.Set(i, item);
        }
        // branches whose target is too far for 8 bits
        for (var i = 0; i < items.Count(); i += 1)
        {
            var item = items.Get(i);
            if (item.Kind != ItemKind.Instr || item.Long || !IsBranch(item.Op) || item.ForceShort)
                continue;
            if (item.Ops.Length == 1 && item.Ops[0].Mode == OpMode.Abs)
            {
                var target = labels.TryGet(item.Ops[0].Sym);
                bool fits = false;
                if (target is AsmSymbol t && t.Section == item.Section)
                {
                    int64 disp = (int64)t.Offset + item.Ops[0].Value - (int64)(item.Offset + 2);
                    fits = disp >= -128 && disp <= 127 && disp != 0 && disp != -1;
                }
                if (!fits)
                {
                    item.Long = true;
                    items.Set(i, item);
                    changed = true;
                }
            }
        }
        if (!changed)
            break;
    }
    // the final encoding: every label is known
    enc.Final[0] = true;
    enc.Sections[0] = AsmSection { Bytes = List<uint8>.Create(), Relocs = List<AsmReloc>.Create() };
    enc.Sections[1] = AsmSection { Bytes = List<uint8>.Create(), Relocs = List<AsmReloc>.Create() };
    for (var i = 0; i < items.Count(); i += 1)
    {
        var item = items.Get(i);
        if (item.Kind != ItemKind.Label)
            EncodeItem(enc, ref item);
    }
    foreach (var e in enc.Errors)
        p.Errors.Add(e);
    if (p.Errors.Count() > 0)
        return error(string.Join("\n", p.Errors.ToArray()));
    var externals = List<string>.Create();
    var seen = HashSet<string>.Create();
    foreach (var sec in enc.Sections)
    {
        foreach (var r in sec.Relocs)
        {
            if (!labels.ContainsKey(r.Sym) && !seen.Contains(r.Sym))
            {
                seen.Add(r.Sym);
                externals.Add(r.Sym);
            }
        }
    }
    return AsmObject { Sections = enc.Sections, Symbols = labels, Externals = externals };
}

bool IsBranch(string op)
{
    return op == "bra" || op == "bsr" || (op.Length == 3 && op[0] == 'b' && CondCode(op.Substring(1).ToString()) >= 2);
}

// the condition field of Bcc/Scc/DBcc, -1 if the text is none
int CondCode(string c)
{
    switch (c)
    {
    case "t":
    case "ra":
        return 0;
    case "f":
    case "sr":
        return 1;
    case "hi":
        return 2;
    case "ls":
        return 3;
    case "cc":
    case "hs":
        return 4;
    case "cs":
    case "lo":
        return 5;
    case "ne":
        return 6;
    case "eq":
        return 7;
    case "vc":
        return 8;
    case "vs":
        return 9;
    case "pl":
        return 10;
    case "mi":
        return 11;
    case "ge":
        return 12;
    case "lt":
        return 13;
    case "gt":
        return 14;
    case "le":
        return 15;
    default:
        return -1;
    }
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

void EmitWord(AsmSection sec, int w)
{
    unchecked
    {
        sec.Bytes.Add((uint8)(w >> 8));
        sec.Bytes.Add((uint8)w);
    }
}

void LongValue(AsmSection sec, int64 v)
{
    unchecked
    {
        int x = (int)v;
        EmitWord(sec, x >> 16);
        EmitWord(sec, x);
    }
}

// a 32-bit field: a number, or a symbol (relocated) plus a number
void LongField(AsmSection sec, int64 value, string sym)
{
    if (sym.Length > 0)
        sec.Relocs.Add(AsmReloc { Offset = sec.Bytes.Count(), Sym = sym, Addend = value });
    LongValue(sec, sym.Length > 0 ? 0 : value);
}

void EncError(Encoder enc, AsmItem item, string message)
{
    if (enc.Final[0] && enc.Errors.Count() < 20)
        enc.Errors.Add("assembler, line " + item.Line.ToString() + ": " + message + " ('" + item.Op + "')");
}

// the 6-bit effective address field (mode << 3 | register)
int EaField(AsmOperand o)
{
    switch (o.Mode)
    {
    case OpMode.Dn:
        return o.Reg;
    case OpMode.An:
        return 8 | o.Reg;
    case OpMode.Ind:
        return 16 | o.Reg;
    case OpMode.PostInc:
        return 24 | o.Reg;
    case OpMode.PreDec:
        return 32 | o.Reg;
    case OpMode.Disp:
        return 40 | o.Reg;
    case OpMode.Index:
        return 48 | o.Reg;
    case OpMode.Abs:
        return 57; // absolute long
    case OpMode.Imm:
        return 60;
    default:
        return 0;
    }
}

// the extension words of an effective address
void EaExtension(Encoder enc, AsmItem item, AsmSection sec, AsmOperand o, int size)
{
    unchecked
    {
        switch (o.Mode)
        {
        case OpMode.Disp:
            if (o.Value < -32768 || o.Value > 32767)
                EncError(enc, item, "the displacement " + o.Value.ToString() + " does not fit in 16 bits");
            EmitWord(sec, (int)o.Value);
            break;
        case OpMode.Index:
            if (o.Value < -128 || o.Value > 127)
                EncError(enc, item, "the displacement " + o.Value.ToString() + " does not fit in 8 bits");
            EmitWord(sec, ((o.IndexReg & 15) << 12) | (o.IndexLong ? 2048 : 0) | ((int)o.Value & 255));
            break;
        case OpMode.Abs:
            LongField(sec, o.Value, o.Sym);
            break;
        case OpMode.Imm:
            if (size == 4)
                LongField(sec, o.Value, o.Sym);
            else
            {
                if (o.Sym.Length > 0)
                    EncError(enc, item, "a symbol needs 32 bits");
                EmitWord(sec, size == 1 ? (int)o.Value & 255 : (int)o.Value & 65535);
            }
            break;
        default:
            break;
        }
    }
}

int SizeBits(int size)
{
    // the usual size field: 00 byte, 01 word, 10 long
    return size == 1 ? 0 : (size == 2 ? 1 : 2);
}

bool IsQuick(AsmOperand o)
{
    return o.Mode == OpMode.Imm && o.Sym.Length == 0 && o.Value >= 1 && o.Value <= 8;
}

void EncodeItem(Encoder enc, ref AsmItem item)
{
    var sec = enc.Sections[item.Section];
    switch (item.Kind)
    {
    case ItemKind.Even:
        if ((sec.Bytes.Count() & 1) != 0)
            sec.Bytes.Add(0);
        return;
    case ItemKind.Space:
        for (var i = 0; i < item.Values[0]; i += 1)
            sec.Bytes.Add(0);
        return;
    case ItemKind.Bytes:
        unchecked
        {
            foreach (var v in item.Values)
                sec.Bytes.Add((uint8)v);
        }
        return;
    case ItemKind.Words:
        foreach (var v in item.Values)
            EmitWord(sec, unchecked((int)v));
        return;
    case ItemKind.Longs:
        for (var i = 0; i < item.Values.Length; i += 1)
            LongField(sec, item.Values[i], item.Syms[i]);
        return;
    default:
        break;
    }
    EncodeInstruction(enc, ref item, sec);
}

void EncodeInstruction(Encoder enc, ref AsmItem item, AsmSection sec)
{
    string op = item.Op;
    var ops = item.Ops;
    int size = item.Size == 0 ? 4 : item.Size;
    int n = ops.Length;
    AsmOperand a = n > 0 ? ops[0] : PlainOperand(OpMode.None, 0);
    AsmOperand b = n > 1 ? ops[1] : PlainOperand(OpMode.None, 0);

    switch (op)
    {
    case "rts":
        EmitWord(sec, 20085);
        return;
    case "nop":
        EmitWord(sec, 20081);
        return;
    case "move":
        if (b.Mode == OpMode.An)
        {
            if (size == 1)
                EncError(enc, item, "movea.b does not exist");
            EmitWord(sec, ((size == 4 ? 2 : 3) << 12) | (b.Reg << 9) | (1 << 6) | EaField(a));
            EaExtension(enc, item, sec, a, size);
            return;
        }
        if (size == 4 && a.Mode == OpMode.Imm && a.Sym.Length == 0 && b.Mode == OpMode.Dn && a.Value >= -128 && a.Value <= 127)
        {
            EmitWord(sec, 28672 | (b.Reg << 9) | ((int)a.Value & 255)); // moveq
            return;
        }
        {
            int sz = size == 1 ? 1 : (size == 4 ? 2 : 3);
            int dst = EaField(b);
            EmitWord(sec, (sz << 12) | ((dst & 7) << 9) | ((dst >> 3) << 6) | EaField(a));
            EaExtension(enc, item, sec, a, size);
            EaExtension(enc, item, sec, b, size);
        }
        return;
    case "moveq":
        EmitWord(sec, 28672 | (b.Reg << 9) | ((int)a.Value & 255));
        return;
    case "movem":
    {
        // a single register is a list of one
        bool toRegs = !(a.Mode == OpMode.RegList || a.Mode == OpMode.Dn || a.Mode == OpMode.An);
        var list = toRegs ? b : a;
        var ea = toRegs ? a : b;
        int mask = (int)list.Value;
        if (list.Mode == OpMode.Dn)
            mask = 1 << list.Reg;
        else if (list.Mode == OpMode.An)
            mask = 1 << (8 + list.Reg);
        if (ea.Mode == OpMode.PreDec)
        {
            // reversed: bit 0 is a7
            int rev = 0;
            for (var k = 0; k < 16; k += 1)
            {
                if ((mask & (1 << k)) != 0)
                    rev = rev | (1 << (15 - k));
            }
            mask = rev;
        }
        EmitWord(sec, 18560 | (toRegs ? 1024 : 0) | (size == 4 ? 64 : 0) | EaField(ea));
        EmitWord(sec, mask);
        EaExtension(enc, item, sec, ea, size);
        return;
    }
    case "lea":
        EmitWord(sec, 16832 | (b.Reg << 9) | EaField(a));
        EaExtension(enc, item, sec, a, 4);
        return;
    case "pea":
        EmitWord(sec, 18496 | EaField(a));
        EaExtension(enc, item, sec, a, 4);
        return;
    case "link":
        EmitWord(sec, 20048 | a.Reg);
        EmitWord(sec, (int)b.Value);
        return;
    case "unlk":
        EmitWord(sec, 20056 | a.Reg);
        return;
    case "jsr":
    case "jmp":
        EmitWord(sec, (op == "jsr" ? 20096 : 20160) | EaField(a));
        EaExtension(enc, item, sec, a, 4);
        return;
    case "swap":
        EmitWord(sec, 18496 | a.Reg);
        return;
    case "ext":
        EmitWord(sec, (size == 4 ? 18624 : 18560) | a.Reg);
        return;
    case "clr":
    case "neg":
    case "negx":
    case "not":
    case "tst":
    {
        int baseOp = op == "clr" ? 16896 : (op == "neg" ? 17408 : (op == "negx" ? 16384 : (op == "not" ? 17920 : 18944)));
        EmitWord(sec, baseOp | (SizeBits(size) << 6) | EaField(a));
        EaExtension(enc, item, sec, a, size);
        return;
    }
    case "addq":
    case "subq":
        EmitWord(sec, 20480 | (((int)a.Value & 7) << 9) | (op == "subq" ? 256 : 0) | (SizeBits(size) << 6) | EaField(b));
        EaExtension(enc, item, sec, b, size);
        return;
    case "cmpm":
        EmitWord(sec, 45320 | (b.Reg << 9) | (SizeBits(size) << 6) | a.Reg);
        return;
    case "addx":
    case "subx":
        EmitWord(sec, (op == "addx" ? 53504 : 37120) | (b.Reg << 9) | (SizeBits(size) << 6) | a.Reg);
        return;
    case "mulu":
    case "muls":
    case "divu":
    case "divs":
    {
        if (a.Mode == OpMode.An)
            EncError(enc, item, "an address register cannot be a factor or divisor");
        int baseOp = op == "mulu" ? 49344 : (op == "muls" ? 49600 : (op == "divu" ? 32960 : 33216));
        EmitWord(sec, baseOp | (b.Reg << 9) | EaField(a));
        EaExtension(enc, item, sec, a, 2);
        return;
    }
    case "add":
    case "sub":
    case "adda":
    case "suba":
    case "addi":
    case "subi":
        EncodeAddSub(enc, ref item, sec, op.StartsWith("add"), a, b, size);
        return;
    case "and":
    case "or":
    case "andi":
    case "ori":
        EncodeLogic(enc, ref item, sec, op.StartsWith("and") ? 49152 : 32768, op.StartsWith("and") ? 512 : 0, a, b, size);
        return;
    case "eor":
    case "eori":
        if (a.Mode == OpMode.Imm)
        {
            EmitWord(sec, 2560 | (SizeBits(size) << 6) | EaField(b));
            EaExtension(enc, item, sec, a, size);
            EaExtension(enc, item, sec, b, size);
            return;
        }
        EmitWord(sec, 45312 | (a.Reg << 9) | (SizeBits(size) << 6) | EaField(b));
        EaExtension(enc, item, sec, b, size);
        return;
    case "cmp":
    case "cmpa":
    case "cmpi":
        if (b.Mode == OpMode.An)
        {
            EmitWord(sec, 45056 | (b.Reg << 9) | ((size == 4 ? 7 : 3) << 6) | EaField(a));
            EaExtension(enc, item, sec, a, size);
            return;
        }
        if (a.Mode == OpMode.Imm)
        {
            EmitWord(sec, 3072 | (SizeBits(size) << 6) | EaField(b));
            EaExtension(enc, item, sec, a, size);
            EaExtension(enc, item, sec, b, size);
            return;
        }
        EmitWord(sec, 45056 | (b.Reg << 9) | (SizeBits(size) << 6) | EaField(a));
        EaExtension(enc, item, sec, a, size);
        return;
    case "asl":
    case "asr":
    case "lsl":
    case "lsr":
    case "roxl":
    case "roxr":
    case "rol":
    case "ror":
    {
        bool left = op.EndsWith("l");
        int type = op.StartsWith("as") ? 0 : (op.StartsWith("ls") ? 1 : (op.StartsWith("rox") ? 2 : 3));
        if (n == 1)
        {
            // a memory operand, shifted by one (word size)
            EmitWord(sec, 57536 | (type << 9) | (left ? 256 : 0) | EaField(a));
            EaExtension(enc, item, sec, a, 2);
            return;
        }
        if (a.Mode == OpMode.Imm)
        {
            if (a.Value < 1 || a.Value > 8)
                EncError(enc, item, "a shift count must be 1..8");
            EmitWord(sec, 57344 | (((int)a.Value & 7) << 9) | (left ? 256 : 0) | (SizeBits(size) << 6) | (type << 3) | b.Reg);
            return;
        }
        EmitWord(sec, 57344 | (a.Reg << 9) | (left ? 256 : 0) | (SizeBits(size) << 6) | 32 | (type << 3) | b.Reg);
        return;
    }
    case "btst":
    case "bchg":
    case "bclr":
    case "bset":
    {
        int kind = op == "btst" ? 0 : (op == "bchg" ? 1 : (op == "bclr" ? 2 : 3));
        if (a.Mode == OpMode.Imm)
        {
            EmitWord(sec, 2048 | (kind << 6) | EaField(b));
            EmitWord(sec, (int)a.Value & 255);
        }
        else
            EmitWord(sec, 256 | (a.Reg << 9) | (kind << 6) | EaField(b));
        EaExtension(enc, item, sec, b, 1);
        return;
    }
    default:
        break;
    }

    // Bcc, Scc, DBcc
    if (op.StartsWith("db"))
    {
        int cond = op == "dbra" ? 1 : CondCode(op.Substring(2).ToString());
        if (cond >= 0)
        {
            EmitWord(sec, 20680 | (cond << 8) | a.Reg);
            EmitWord(sec, (int)BranchDisplacement(enc, item, b, item.Offset + 2, true));
            return;
        }
    }
    if (op.StartsWith("b"))
    {
        int cond = op == "bra" ? 0 : (op == "bsr" ? 1 : CondCode(op.Substring(1).ToString()));
        if (cond >= 0)
        {
            int64 disp = BranchDisplacement(enc, item, a, item.Offset + 2, item.Long);
            if (item.Long)
            {
                EmitWord(sec, 24576 | (cond << 8));
                EmitWord(sec, (int)disp);
            }
            else
                EmitWord(sec, 24576 | (cond << 8) | ((int)disp & 255));
            return;
        }
    }
    if (op.StartsWith("s") && op.Length <= 3)
    {
        int cond = CondCode(op.Substring(1).ToString());
        if (cond >= 0)
        {
            EmitWord(sec, 20672 | (cond << 8) | EaField(a));
            EaExtension(enc, item, sec, a, 1);
            return;
        }
    }
    EncError(enc, item, "unknown instruction");
}

// the distance from 'from' to the target label (0 until the label is known)
int64 BranchDisplacement(Encoder enc, AsmItem item, AsmOperand target, int from, bool wide)
{
    var t = enc.Labels.TryGet(target.Sym);
    if (t is AsmSymbol label && label.Section == item.Section)
    {
        int64 disp = (int64)label.Offset + target.Value - (int64)from;
        if (wide && (disp < -32768 || disp > 32767))
            EncError(enc, item, "the branch target is too far away");
        if (!wide && (disp < -128 || disp > 127 || disp == 0))
            EncError(enc, item, "the branch target is too far away for a short branch");
        return disp;
    }
    if (enc.Final[0])
        EncError(enc, item, "the branch target '" + target.Sym + "' is not a label in the same section");
    return 0;
}

void EncodeAddSub(Encoder enc, ref AsmItem item, AsmSection sec, bool add, AsmOperand a, AsmOperand b, int size)
{
    int baseOp = add ? 53248 : 36864;
    if (IsQuick(a))
    {
        EmitWord(sec, 20480 | (((int)a.Value & 7) << 9) | (add ? 0 : 256) | (SizeBits(size) << 6) | EaField(b));
        EaExtension(enc, item, sec, b, size);
        return;
    }
    if (b.Mode == OpMode.An)
    {
        // adda/suba
        EmitWord(sec, baseOp | (b.Reg << 9) | ((size == 4 ? 7 : 3) << 6) | EaField(a));
        EaExtension(enc, item, sec, a, size);
        return;
    }
    if (a.Mode == OpMode.Imm)
    {
        // addi/subi
        EmitWord(sec, (add ? 1536 : 1024) | (SizeBits(size) << 6) | EaField(b));
        EaExtension(enc, item, sec, a, size);
        EaExtension(enc, item, sec, b, size);
        return;
    }
    if (b.Mode == OpMode.Dn)
    {
        EmitWord(sec, baseOp | (b.Reg << 9) | (SizeBits(size) << 6) | EaField(a));
        EaExtension(enc, item, sec, a, size);
        return;
    }
    // Dn to memory
    EmitWord(sec, baseOp | (a.Reg << 9) | 256 | (SizeBits(size) << 6) | EaField(b));
    EaExtension(enc, item, sec, b, size);
}

// and/or: baseOp for <ea>,Dn; immediate: immOp (andi = 0x0200, ori = 0x0000)
void EncodeLogic(Encoder enc, ref AsmItem item, AsmSection sec, int baseOp, int immOp, AsmOperand a, AsmOperand b, int size)
{
    if (a.Mode == OpMode.An || b.Mode == OpMode.An)
        EncError(enc, item, "and/or cannot use an address register");
    if (a.Mode == OpMode.Imm)
    {
        EmitWord(sec, immOp | (SizeBits(size) << 6) | EaField(b));
        EaExtension(enc, item, sec, a, size);
        EaExtension(enc, item, sec, b, size);
        return;
    }
    if (b.Mode == OpMode.Dn)
    {
        EmitWord(sec, baseOp | (b.Reg << 9) | (SizeBits(size) << 6) | EaField(a));
        EaExtension(enc, item, sec, a, size);
        return;
    }
    EmitWord(sec, baseOp | (a.Reg << 9) | 256 | (SizeBits(size) << 6) | EaField(b));
    EaExtension(enc, item, sec, b, size);
}
