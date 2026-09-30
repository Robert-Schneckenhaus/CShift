// Reads the LLVM IR that CShift's code generator writes (CodeGen/, Emit/IrWriter.csh) into a module the 68000 backend
// translates. Only the subset CShift produces is understood: one instruction per line (a switch spans several), named
// struct types, globals with constant initializers, internal and external functions.
//
// The module keeps the text of its operands; types are indexes into IrTypes (named struct types are resolved lazily,
// they may be used before they are defined).

namespace CShift.M68k;

using System;

enum IrKind : uint8
{
    Void,
    Int,
    Float,
    Double,
    Ptr,
    Struct,
    Array,
    Label,
    Unknown
}

struct IrTypeInfo
{
    IrKind Kind;
    int Bits;       // Int
    int[] Fields;   // Struct
    int Elem;       // Array
    int Count;      // Array
    string Name;    // a named struct type ("" otherwise)
    bool Defined;   // a named struct whose body was read
}

struct IrTypes
{
    List<IrTypeInfo> Infos;
    Dictionary<string, int> ByText;   // "i32", "{ ptr, i32 }", "%\"Name\"" ...
    int Void;
    int I1;
    int I8;
    int I16;
    int I32;
    int I64;
    int Ptr;
    int Float;
    int Double;
    int Label;

    static IrTypes Create()
    {
        var t = IrTypes { Infos = List<IrTypeInfo>.Create(), ByText = Dictionary<string, int>.Create() };
        t.Void = t.Add(IrTypeInfo { Kind = IrKind.Void, Name = "" }, "void");
        t.I1 = t.IntType(1);
        t.I8 = t.IntType(8);
        t.I16 = t.IntType(16);
        t.I32 = t.IntType(32);
        t.I64 = t.IntType(64);
        t.Ptr = t.Add(IrTypeInfo { Kind = IrKind.Ptr, Name = "" }, "ptr");
        t.Float = t.Add(IrTypeInfo { Kind = IrKind.Float, Name = "" }, "float");
        t.Double = t.Add(IrTypeInfo { Kind = IrKind.Double, Name = "" }, "double");
        t.Label = t.Add(IrTypeInfo { Kind = IrKind.Label, Name = "" }, "label");
        return t;
    }

    int Add(IrTypeInfo info, string text)
    {
        if (info.Fields == null)
            info.Fields = new int[0];
        Infos.Add(info);
        int id = Infos.Count() - 1;
        ByText.Set(text, id);
        return id;
    }

    int IntType(int bits)
    {
        string text = "i" + bits.ToString();
        var found = ByText.TryGet(text);
        if (found is int id)
            return id;
        return Add(IrTypeInfo { Kind = IrKind.Int, Bits = bits, Name = "" }, text);
    }

    // The type of a name (%"X" or %X), created as an empty struct until its definition is read.
    int Named(string name)
    {
        string text = "%" + name;
        var found = ByText.TryGet(text);
        if (found is int id)
            return id;
        return Add(IrTypeInfo { Kind = IrKind.Struct, Name = name }, text);
    }

    int StructOf(int[] fields)
    {
        var sb = StringBuilder.Create();
        sb.Append("{");
        foreach (var f in fields)
            sb.Append(" " + f.ToString());
        sb.Append(" }");
        string text = sb.ToString();
        var found = ByText.TryGet(text);
        if (found is int id)
            return id;
        return Add(IrTypeInfo { Kind = IrKind.Struct, Fields = fields, Name = "", Defined = true }, text);
    }

    int ArrayOf(int count, int elem)
    {
        string text = "[" + count.ToString() + " x " + elem.ToString() + "]";
        var found = ByText.TryGet(text);
        if (found is int id)
            return id;
        return Add(IrTypeInfo { Kind = IrKind.Array, Count = count, Elem = elem, Name = "" }, text);
    }

    void Define(int named, int[] fields)
    {
        var info = Infos.Get(named);
        info.Fields = fields;
        info.Defined = true;
        Infos.Set(named, info);
    }

    IrTypeInfo Info(int t) { return Infos.Get(t); }
    IrKind Kind(int t) { return Infos.Get(t).Kind; }
    int Bits(int t) { return Infos.Get(t).Bits; }
    bool IsInt(int t) { return Kind(t) == IrKind.Int; }
    bool IsAggregate(int t) { return Kind(t) == IrKind.Struct || Kind(t) == IrKind.Array; }

    string Text(int t)
    {
        var i = Infos.Get(t);
        switch (i.Kind)
        {
        case IrKind.Void: return "void";
        case IrKind.Int: return "i" + i.Bits.ToString();
        case IrKind.Ptr: return "ptr";
        case IrKind.Float: return "float";
        case IrKind.Double: return "double";
        case IrKind.Label: return "label";
        case IrKind.Array: return "[" + i.Count.ToString() + " x " + Text(i.Elem) + "]";
        case IrKind.Struct:
        {
            if (i.Name.Length > 0)
                return "%\"" + i.Name + "\"";
            var sb = StringBuilder.Create();
            sb.Append("{");
            for (var k = 0; k < i.Fields.Length; k += 1)
                sb.Append((k == 0 ? " " : ", ") + Text(i.Fields[k]));
            sb.Append(" }");
            return sb.ToString();
        }
        default: return "?";
        }
    }
}

// ---------------------------------------------------------------------------
// Operands
// ---------------------------------------------------------------------------

enum ValKind : uint8
{
    Local,      // %name
    Global,     // @name
    Int,        // integer constant (also true/false)
    FloatBits,  // floating point constant: the IEEE bits of a double (a float constant is written as a double)
    Null,       // null
    Zero,       // zeroinitializer (also undef/poison)
    Aggregate,  // { ... } or [ ... ] constant
    Bytes,      // c"..."
    Expr        // constant expression: ptrtoint/inttoptr/trunc/bitcast/getelementptr (...)
}

struct IrVal
{
    ValKind Kind;
    int Type;
    string Name;      // Local/Global
    int64 Int;        // Int, FloatBits
    int[] Items;      // Aggregate: element values; Expr: operands
    string Text;      // Bytes: the bytes; Expr: the operator
    int ExprType;     // Expr: gep source element type / cast target type
}

// ---------------------------------------------------------------------------
// Instructions and functions
// ---------------------------------------------------------------------------

struct IrInst
{
    string Op;         // add, load, store, call, br, ... ("cast" ops keep their name: sext, zext, trunc, ...)
    string Res;        // the result's name ("" if none)
    int Type;          // the result type (void for none)
    int OpType;        // the type of the operation (operands of add/icmp, stored/loaded value, gep source type, alloca type)
    int[] Args;        // operand values
    string Pred;       // icmp/fcmp predicate, atomicrmw operation
    string[] Labels;   // br targets, switch default + cases, phi incoming blocks
    int64[] Cases;     // switch case values
    int Callee;        // call: the called value (-1 for none)
    bool Volatile;
}

struct IrBlock
{
    string Label;
    List<IrInst> Insts;
}

struct IrParam
{
    int Type;
    string Name;
}

struct IrFunc
{
    string Name;
    int Ret;
    IrParam[] Params;
    bool Varargs;
    bool Defined;
    bool Internal;     // internal/private linkage: not visible outside the module
    List<IrBlock> Blocks;
}

struct IrGlobal
{
    string Name;
    int Type;
    int Init;          // value index, -1 for an external global
    bool Constant;
}

struct IrModule
{
    IrTypes Types;
    List<IrVal> Vals;
    List<IrGlobal> Globals;
    List<IrFunc> Funcs;
    Dictionary<string, int> FuncIndex;
    Dictionary<string, int> GlobalIndex;

    int AddVal(IrVal v)
    {
        if (v.Items == null)
            v.Items = new int[0];
        if (v.Name == null)
            v.Name = "";
        if (v.Text == null)
            v.Text = "";
        Vals.Add(v);
        return Vals.Count() - 1;
    }
}

// ---------------------------------------------------------------------------
// The reader
// ---------------------------------------------------------------------------

enum Tok : uint8
{
    End,
    Local,     // %name (Text without the %)
    Global,    // @name
    Word,      // keywords, types (i32, ptr, ...), numbers
    Str,       // c"..." (Text: the bytes)
    Punct      // ( ) [ ] { } , = * < > :
}

struct Token
{
    Tok Kind;
    string Text;
}

// Splits one line of IR into tokens.
List<Token> Tokenize(StringSlice line)
{
    var result = List<Token>.Create();
    int i = 0;
    int n = line.Length;
    while (i < n)
    {
        char c = line[i];
        if (c == ' ' || c == '\t' || c == '\r')
        {
            i += 1;
            continue;
        }
        if (c == ';')
            break; // comment
        if (c == '%' || c == '@')
        {
            i += 1;
            string name;
            if (i < n && line[i] == '"')
            {
                int start = i + 1;
                int end = start;
                while (end < n && line[end] != '"')
                    end += 1;
                name = line[start..end].ToString();
                i = end + 1;
            }
            else
            {
                int start = i;
                while (i < n && IsNameChar(line[i]))
                    i += 1;
                name = line[start..i].ToString();
            }
            result.Add(Token { Kind = c == '%' ? Tok.Local : Tok.Global, Text = name });
            continue;
        }
        if (c == 'c' && i + 1 < n && line[i + 1] == '"')
        {
            var sb = StringBuilder.Create();
            i += 2;
            while (i < n && line[i] != '"')
            {
                if (line[i] == '\\' && i + 2 < n)
                {
                    sb.Append((char)(HexValue(line[i + 1]) * 16 + HexValue(line[i + 2])));
                    i += 3;
                }
                else
                {
                    sb.Append(line[i]);
                    i += 1;
                }
            }
            i += 1;
            result.Add(Token { Kind = Tok.Str, Text = sb.ToString() });
            continue;
        }
        if (IsNameChar(c) || c == '-')
        {
            int start = i;
            i += 1;
            while (i < n && (IsNameChar(line[i]) || ((line[i] == '+' || line[i] == '-') && (line[i - 1] == 'e' || line[i - 1] == 'E'))))
                i += 1;
            result.Add(Token { Kind = Tok.Word, Text = line[start..i].ToString() });
            continue;
        }
        result.Add(Token { Kind = Tok.Punct, Text = c.ToString() });
        i += 1;
    }
    result.Add(Token { Kind = Tok.End, Text = "" });
    return result;
}

bool IsNameChar(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '$';
}

int HexValue(char c)
{
    if (c >= '0' && c <= '9')
        return (int)c - 48;
    if (c >= 'a' && c <= 'f')
        return (int)c - 87;
    if (c >= 'A' && c <= 'F')
        return (int)c - 55;
    return 0;
}

// A cursor over the tokens of a line (a struct with its position in an array, passed by ref).
struct Cursor
{
    List<Token> Toks;
    int Pos;
    int LineNo;

    Token Peek() { return Toks.Get(Pos); }
    Token PeekAt(int k) { return Pos + k < Toks.Count() ? Toks.Get(Pos + k) : Toks.Get(Toks.Count() - 1); }
    Token Next()
    {
        var t = Toks.Get(Pos);
        if (t.Kind != Tok.End)
            Pos += 1;
        return t;
    }
    bool Is(string text) { return Toks.Get(Pos).Text == text && Toks.Get(Pos).Kind != Tok.Str; }
    bool Accept(string text)
    {
        if (!Is(text))
            return false;
        Pos += 1;
        return true;
    }
}

struct ReadError
{
    string Message;
}

// Reads a whole module. Returns an error message for something outside the subset.
Error<IrModule> ReadModule(string text)
{
    var m = IrModule { Types = IrTypes.Create(), Vals = List<IrVal>.Create(), Globals = List<IrGlobal>.Create(), Funcs = List<IrFunc>.Create(),
                       FuncIndex = Dictionary<string, int>.Create(), GlobalIndex = Dictionary<string, int>.Create() };
    var lines = text.Split('\n');
    int li = 0;
    while (li < lines.Length)
    {
        var raw = lines[li];
        li += 1;
        var line = raw.Trim();
        if (line.Length == 0 || line[0] == ';')
            continue;
        var c = Cursor { Toks = Tokenize(line), Pos = 0, LineNo = li };
        var first = c.Peek();
        if (first.Kind == Tok.Word && (first.Text == "target" || first.Text == "attributes" || first.Text == "source_filename"))
            continue;
        if (first.Kind == Tok.Local)
        {
            // %"Name" = type { ... }
            c.Next();
            if (!c.Accept("=") || !c.Accept("type"))
                return error(Where(li) + "expected a type definition");
            int named = m.Types.Named(first.Text);
            var body = try ReadTypeFrom(ref m, ref c, li);
            m.Types.Define(named, m.Types.Info(body).Fields);
            continue;
        }
        if (first.Kind == Tok.Global)
        {
            try ReadGlobal(ref m, ref c, li);
            continue;
        }
        if (first.Kind == Tok.Word && first.Text == "declare")
        {
            var f = try ReadSignature(ref m, ref c, li, false);
            AddFunc(ref m, f);
            continue;
        }
        if (first.Kind == Tok.Word && first.Text == "define")
        {
            var f = try ReadSignature(ref m, ref c, li, true);
            // the body: blocks until the closing brace
            var block = IrBlock { Label = "entry", Insts = List<IrInst>.Create() };
            bool open = false; // the entry block has no label line when the first line is an instruction
            while (li < lines.Length)
            {
                var bodyRaw = lines[li];
                li += 1;
                var bl = bodyRaw.Trim();
                if (bl.Length == 0)
                    continue;
                if (bl == "}")
                    break;
                if (bl == "{")
                    continue;
                if (bl[bl.Length - 1] == ':')
                {
                    if (open || block.Insts.Count() > 0)
                        f.Blocks.Add(block);
                    string label = bl[..(bl.Length - 1)].ToString();
                    if (label.Length > 1 && label[0] == '"')
                        label = label[1..(label.Length - 1)].ToString();
                    block = IrBlock { Label = label, Insts = List<IrInst>.Create() };
                    open = true;
                    continue;
                }
                string full = bl.ToString();
                if (bl.StartsWith("switch ") || bl.Contains("= switch "))
                {
                    // switch ... [ newline case lines ... ]
                    var sb = StringBuilder.Create();
                    sb.Append(full);
                    while (!full.EndsWith("]") && li < lines.Length)
                    {
                        full = lines[li].Trim().ToString();
                        li += 1;
                        sb.Append(" " + full);
                    }
                    full = sb.ToString();
                }
                var ic = Cursor { Toks = Tokenize(full), Pos = 0, LineNo = li };
                var read = ReadInst(ref m, ref ic, li);
                if (read is error bad)
                    return error(bad.Message + " (in '" + full + "')");
                if (read is IrInst inst)
                    block.Insts.Add(inst);
            }
            f.Blocks.Add(block);
            AddFunc(ref m, f);
            continue;
        }
        return error(Where(li) + "cannot read '" + line.ToString() + "'");
    }
    return m;
}

string Where(int line)
{
    return "IR line " + line.ToString() + ": ";
}

void AddFunc(ref IrModule m, IrFunc f)
{
    var found = m.FuncIndex.TryGet(f.Name);
    if (found is int index)
    {
        if (f.Defined)
            m.Funcs.Set(index, f);
        return;
    }
    m.Funcs.Add(f);
    m.FuncIndex.Set(f.Name, m.Funcs.Count() - 1);
}

// Skips linkage words, attributes and the like that do not matter for the code.
bool IsDecoration(string w)
{
    return w == "internal" || w == "private" || w == "external" || w == "dso_local" || w == "noundef" || w == "signext" ||
           w == "zeroext" || w == "noinline" || w == "noreturn" || w == "nounwind" || w == "local_unnamed_addr" ||
           w == "unnamed_addr" || w == "readonly" || w == "nocapture" || w == "inbounds" || w == "tail" || w == "musttail" ||
           w == "fastcc" || w == "ccc" || w == "hidden" || w == "thread_local" || w == "nuw" || w == "nsw" || w == "exact" ||
           w == "nnan" || w == "ninf" || w == "fast";
}

// declare/define <ret> @name(<params>) [attributes]
Error<IrFunc> ReadSignature(ref IrModule m, ref Cursor c, int li, bool define)
{
    c.Next(); // declare / define
    bool internal = false;
    while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
    {
        var w = c.Next().Text;
        internal = internal || w == "internal" || w == "private";
    }
    int ret = try ReadTypeFrom(ref m, ref c, li);
    var nameTok = c.Next();
    if (nameTok.Kind != Tok.Global)
        return error(Where(li) + "expected a function name");
    if (!c.Accept("("))
        return error(Where(li) + "expected '('");
    var ps = List<IrParam>.Create();
    bool varargs = false;
    while (!c.Is(")") && c.Peek().Kind != Tok.End)
    {
        if (c.Accept("..."))
        {
            varargs = true;
            continue;
        }
        int pt = try ReadTypeFrom(ref m, ref c, li);
        while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
            c.Next();
        string pname = "";
        if (c.Peek().Kind == Tok.Local)
            pname = c.Next().Text;
        ps.Add(IrParam { Type = pt, Name = pname });
        c.Accept(",");
    }
    c.Accept(")");
    return IrFunc { Name = nameTok.Text, Ret = ret, Params = ps.ToArray(), Varargs = varargs, Defined = define, Internal = internal, Blocks = List<IrBlock>.Create() };
}

// @name = [linkage] global|constant <type> <init>   or   @name = external global <type>
Error<void> ReadGlobal(ref IrModule m, ref Cursor c, int li)
{
    string name = c.Next().Text;
    if (!c.Accept("="))
        return error(Where(li) + "expected '='");
    bool external = false;
    while (c.Peek().Kind == Tok.Word && (IsDecoration(c.Peek().Text) || c.Peek().Text == "external"))
    {
        if (c.Peek().Text == "external")
            external = true;
        c.Next();
    }
    bool constant = c.Peek().Text == "constant";
    if (!c.Accept("global") && !c.Accept("constant"))
        return error(Where(li) + "expected 'global' or 'constant'");
    int t = try ReadTypeFrom(ref m, ref c, li);
    int init = -1;
    if (!external)
        init = try ReadConst(ref m, ref c, li, t);
    m.Globals.Add(IrGlobal { Name = name, Type = t, Init = init, Constant = constant });
    m.GlobalIndex.Set(name, m.Globals.Count() - 1);
    return;
}

// A type: iN, ptr, float, double, void, label, %Name, { ... }, [N x T]
Error<int> ReadTypeFrom(ref IrModule m, ref Cursor c, int li)
{
    var t = c.Next();
    if (t.Kind == Tok.Local)
        return m.Types.Named(t.Text);
    if (t.Kind == Tok.Punct && t.Text == "{")
    {
        var fields = List<int>.Create();
        while (!c.Is("}") && c.Peek().Kind != Tok.End)
        {
            fields.Add(try ReadTypeFrom(ref m, ref c, li));
            c.Accept(",");
        }
        c.Accept("}");
        return m.Types.StructOf(fields.ToArray());
    }
    if (t.Kind == Tok.Punct && t.Text == "[")
    {
        int count = (int)ParseInt(c.Next().Text);
        if (!c.Accept("x"))
            return error(Where(li) + "expected 'x' in an array type");
        int elem = try ReadTypeFrom(ref m, ref c, li);
        c.Accept("]");
        return m.Types.ArrayOf(count, elem);
    }
    if (t.Kind == Tok.Word)
    {
        if (t.Text == "ptr")
            return m.Types.Ptr;
        if (t.Text == "void")
            return m.Types.Void;
        if (t.Text == "float")
            return m.Types.Float;
        if (t.Text == "double")
            return m.Types.Double;
        if (t.Text == "label")
            return m.Types.Label;
        if (t.Text.Length > 1 && t.Text[0] == 'i' && t.Text[1] >= '0' && t.Text[1] <= '9')
            return m.Types.IntType((int)ParseInt(t.Text[1..].ToString()));
    }
    return error(Where(li) + "unknown type '" + t.Text + "'");
}

int64 ParseInt(string s)
{
    int64 v = 0;
    bool neg = false;
    int i = 0;
    if (s.Length > 0 && s[0] == '-')
    {
        neg = true;
        i = 1;
    }
    for (; i < s.Length; i += 1)
    {
        char ch = s[i];
        if (ch < '0' || ch > '9')
            break;
        v = unchecked(v * 10 + (int64)((int)ch - 48));
    }
    return neg ? unchecked(-v) : v;
}

int64 ParseHex(string s)
{
    uint64 v = 0;
    for (var i = 2; i < s.Length; i += 1)
        v = unchecked(v * 16ul + (uint64)HexValue(s[i]));
    return unchecked((int64)v);
}

// A constant of a known type: numbers, null, zeroinitializer, undef, true/false, @global, c"...", { ... }, [ ... ],
// and constant expressions (ptrtoint (...), getelementptr (...), trunc (...), bitcast (...), inttoptr (...)).
Error<int> ReadConst(ref IrModule m, ref Cursor c, int li, int type)
{
    var t = c.Peek();
    if (t.Kind == Tok.Global)
    {
        c.Next();
        return m.AddVal(IrVal { Kind = ValKind.Global, Type = type, Name = t.Text });
    }
    if (t.Kind == Tok.Local)
    {
        c.Next();
        return m.AddVal(IrVal { Kind = ValKind.Local, Type = type, Name = t.Text });
    }
    if (t.Kind == Tok.Str)
    {
        c.Next();
        return m.AddVal(IrVal { Kind = ValKind.Bytes, Type = type, Text = t.Text });
    }
    if (t.Kind == Tok.Punct && (t.Text == "{" || t.Text == "["))
    {
        c.Next();
        string close = t.Text == "{" ? "}" : "]";
        var items = List<int>.Create();
        while (!c.Is(close) && c.Peek().Kind != Tok.End)
        {
            int et = try ReadTypeFrom(ref m, ref c, li);
            items.Add(try ReadConst(ref m, ref c, li, et));
            c.Accept(",");
        }
        c.Accept(close);
        return m.AddVal(IrVal { Kind = ValKind.Aggregate, Type = type, Items = items.ToArray() });
    }
    if (t.Kind == Tok.Word)
    {
        string w = t.Text;
        c.Next();
        if (w == "null")
            return m.AddVal(IrVal { Kind = ValKind.Null, Type = type });
        if (w == "zeroinitializer" || w == "undef" || w == "poison")
            return m.AddVal(IrVal { Kind = ValKind.Zero, Type = type });
        if (w == "true" || w == "false")
            return m.AddVal(IrVal { Kind = ValKind.Int, Type = type, Int = w == "true" ? 1 : 0 });
        if (w.StartsWith("0x"))
        {
            int64 bits = ParseHex(w);
            return m.AddVal(IrVal { Kind = ValKind.FloatBits, Type = type, Int = bits });
        }
        if ((w[0] >= '0' && w[0] <= '9') || w[0] == '-')
        {
            if (w.Contains(".") || w.Contains("e"))
                return m.AddVal(IrVal { Kind = ValKind.FloatBits, Type = type, Int = DecimalBits(w) });
            return m.AddVal(IrVal { Kind = ValKind.Int, Type = type, Int = ParseInt(w) });
        }
        if (w == "ptrtoint" || w == "inttoptr" || w == "trunc" || w == "bitcast" || w == "zext" || w == "sext")
        {
            // op (T value to U)
            if (!c.Accept("("))
                return error(Where(li) + "expected '(' after " + w);
            int from = try ReadTypeFrom(ref m, ref c, li);
            int inner = try ReadConst(ref m, ref c, li, from);
            if (!c.Accept("to"))
                return error(Where(li) + "expected 'to'");
            int to = try ReadTypeFrom(ref m, ref c, li);
            c.Accept(")");
            return m.AddVal(IrVal { Kind = ValKind.Expr, Type = type, Text = w, Items = new int[] { inner }, ExprType = to });
        }
        if (w == "getelementptr")
        {
            // getelementptr [inbounds] (T, ptr base, idx...)
            while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
                c.Next();
            if (!c.Accept("("))
                return error(Where(li) + "expected '(' after getelementptr");
            int source = try ReadTypeFrom(ref m, ref c, li);
            var ops = List<int>.Create();
            while (c.Accept(","))
            {
                int ot = try ReadTypeFrom(ref m, ref c, li);
                ops.Add(try ReadConst(ref m, ref c, li, ot));
            }
            c.Accept(")");
            return m.AddVal(IrVal { Kind = ValKind.Expr, Type = type, Text = "getelementptr", Items = ops.ToArray(), ExprType = source });
        }
    }
    return error(Where(li) + "cannot read the constant '" + t.Text + "'");
}

// "T value" (a typed operand)
Error<int> ReadTypedOperand(ref IrModule m, ref Cursor c, int li)
{
    int t = try ReadTypeFrom(ref m, ref c, li);
    while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
        c.Next();
    return try ReadConst(ref m, ref c, li, t);
}

// One instruction.
Error<IrInst> ReadInst(ref IrModule m, ref Cursor c, int li)
{
    var types = m.Types;
    var inst = IrInst { Op = "", Res = "", Type = types.Void, OpType = types.Void, Args = new int[0], Pred = "", Labels = new string[0], Cases = new int64[0],
                        Callee = -1 };
    if (c.Peek().Kind == Tok.Local && c.PeekAt(1).Text == "=")
    {
        inst.Res = c.Next().Text;
        c.Next();
    }
    while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
        c.Next();
    string op = c.Next().Text;
    inst.Op = op;
    var args = List<int>.Create();

    if (op == "add" || op == "sub" || op == "mul" || op == "sdiv" || op == "udiv" || op == "srem" || op == "urem" || op == "and" ||
        op == "or" || op == "xor" || op == "shl" || op == "lshr" || op == "ashr" || op == "fadd" || op == "fsub" || op == "fmul" ||
        op == "fdiv" || op == "frem")
    {
        while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
            c.Next();
        int t = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, t));
        c.Accept(",");
        args.Add(try ReadConst(ref m, ref c, li, t));
        inst.Type = t;
        inst.OpType = t;
    }
    else if (op == "icmp" || op == "fcmp")
    {
        while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
            c.Next();
        inst.Pred = c.Next().Text;
        int t = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, t));
        c.Accept(",");
        args.Add(try ReadConst(ref m, ref c, li, t));
        inst.Type = types.I1;
        inst.OpType = t;
    }
    else if (op == "sext" || op == "zext" || op == "trunc" || op == "bitcast" || op == "ptrtoint" || op == "inttoptr" || op == "fptrunc" ||
             op == "fpext" || op == "sitofp" || op == "uitofp" || op == "fptosi" || op == "fptoui")
    {
        int from = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, from));
        if (!c.Accept("to"))
            return error(Where(li) + "expected 'to'");
        inst.Type = try ReadTypeFrom(ref m, ref c, li);
        inst.OpType = from;
    }
    else if (op == "load")
    {
        if (c.Accept("atomic"))
            inst.Volatile = true;
        if (c.Accept("volatile"))
            inst.Volatile = true;
        inst.Type = try ReadTypeFrom(ref m, ref c, li);
        inst.OpType = inst.Type;
        c.Accept(",");
        args.Add(try ReadTypedOperand(ref m, ref c, li));
    }
    else if (op == "store")
    {
        if (c.Accept("volatile"))
            inst.Volatile = true;
        int vt = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, vt));
        c.Accept(",");
        args.Add(try ReadTypedOperand(ref m, ref c, li));
        inst.OpType = vt;
    }
    else if (op == "alloca")
    {
        inst.OpType = try ReadTypeFrom(ref m, ref c, li);
        inst.Type = types.Ptr;
    }
    else if (op == "getelementptr")
    {
        while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
            c.Next();
        inst.OpType = try ReadTypeFrom(ref m, ref c, li);
        while (c.Accept(","))
            args.Add(try ReadTypedOperand(ref m, ref c, li));
        inst.Type = types.Ptr;
    }
    else if (op == "extractvalue" || op == "insertvalue")
    {
        int at = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, at));
        if (op == "insertvalue")
        {
            c.Accept(",");
            args.Add(try ReadTypedOperand(ref m, ref c, li));
        }
        var idx = List<int64>.Create();
        while (c.Accept(","))
            idx.Add(ParseInt(c.Next().Text));
        inst.Cases = idx.ToArray();
        inst.OpType = at;
        inst.Type = op == "insertvalue" ? at : FieldTypeAt(types, at, inst.Cases);
    }
    else if (op == "select")
    {
        args.Add(try ReadTypedOperand(ref m, ref c, li));
        c.Accept(",");
        int t = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, t));
        c.Accept(",");
        try ReadTypeFrom(ref m, ref c, li); // the type again
        args.Add(try ReadConst(ref m, ref c, li, t));
        inst.Type = t;
        inst.OpType = t;
    }
    else if (op == "phi")
    {
        int t = try ReadTypeFrom(ref m, ref c, li);
        var labels = List<string>.Create();
        while (c.Accept("["))
        {
            args.Add(try ReadConst(ref m, ref c, li, t));
            c.Accept(",");
            labels.Add(c.Next().Text);
            c.Accept("]");
            c.Accept(",");
        }
        inst.Labels = labels.ToArray();
        inst.Type = t;
        inst.OpType = t;
    }
    else if (op == "br")
    {
        if (c.Accept("label"))
            inst.Labels = new string[] { c.Next().Text };
        else
        {
            args.Add(try ReadTypedOperand(ref m, ref c, li));
            c.Accept(",");
            c.Accept("label");
            string a = c.Next().Text;
            c.Accept(",");
            c.Accept("label");
            string b = c.Next().Text;
            inst.Labels = new string[] { a, b };
        }
    }
    else if (op == "switch")
    {
        int t = try ReadTypeFrom(ref m, ref c, li);
        args.Add(try ReadConst(ref m, ref c, li, t));
        c.Accept(",");
        c.Accept("label");
        var labels = List<string>.Create();
        labels.Add(c.Next().Text);
        var cases = List<int64>.Create();
        c.Accept("[");
        while (!c.Is("]") && c.Peek().Kind != Tok.End)
        {
            c.Next(); // the type
            var v = c.Next().Text;
            cases.Add(v == "true" ? 1 : v == "false" ? 0 : ParseInt(v));
            c.Accept(",");
            c.Accept("label");
            labels.Add(c.Next().Text);
        }
        inst.Labels = labels.ToArray();
        inst.Cases = cases.ToArray();
        inst.OpType = t;
    }
    else if (op == "ret")
    {
        if (!c.Accept("void"))
        {
            int t = try ReadTypeFrom(ref m, ref c, li);
            args.Add(try ReadConst(ref m, ref c, li, t));
            inst.OpType = t;
        }
    }
    else if (op == "unreachable")
    {
    }
    else if (op == "call")
    {
        while (c.Peek().Kind == Tok.Word && IsDecoration(c.Peek().Text))
            c.Next();
        inst.Type = try ReadTypeFrom(ref m, ref c, li);
        // a variadic call names the function type: ret (fixed params, ...) @callee(...)
        if (c.Is("("))
        {
            int depth = 0;
            while (c.Peek().Kind != Tok.End)
            {
                var tk = c.Next();
                if (tk.Text == "(")
                    depth += 1;
                else if (tk.Text == ")")
                {
                    depth -= 1;
                    if (depth == 0)
                        break;
                }
            }
        }
        inst.Callee = try ReadConst(ref m, ref c, li, types.Ptr);
        if (!c.Accept("("))
            return error(Where(li) + "expected '(' in a call");
        while (!c.Is(")") && c.Peek().Kind != Tok.End)
        {
            args.Add(try ReadTypedOperand(ref m, ref c, li));
            c.Accept(",");
        }
        c.Accept(")");
    }
    else if (op == "atomicrmw")
    {
        if (c.Accept("volatile"))
            inst.Volatile = true;
        inst.Pred = c.Next().Text; // add, sub, xchg ...
        args.Add(try ReadTypedOperand(ref m, ref c, li));
        c.Accept(",");
        args.Add(try ReadTypedOperand(ref m, ref c, li));
        inst.Type = m.Vals.Get(args.Get(1)).Type;
        inst.OpType = inst.Type;
    }
    else
        return error(Where(li) + "the m68k backend does not know the instruction '" + op + "'");
    inst.Args = args.ToArray();
    return inst;
}

// The type reached by extractvalue/insertvalue indexes.
int FieldTypeAt(IrTypes types, int t, int64[] path)
{
    int cur = t;
    foreach (var i in path)
    {
        var info = types.Info(cur);
        cur = info.Kind == IrKind.Array ? info.Elem : info.Fields[(int)i];
    }
    return cur;
}

// The IEEE bits of a decimal constant ("0.0", "1.5", "2.5e+00": LLVM writes decimals only for values that are exact).
int64 DecimalBits(string w)
{
    double value = 0;
    double scale = 1;
    bool negative = false;
    bool fraction = false;
    int exponent = 0;
    int i = 0;
    if (w.Length > 0 && (w[0] == '-' || w[0] == '+'))
    {
        negative = w[0] == '-';
        i = 1;
    }
    for (; i < w.Length; i += 1)
    {
        char ch = w[i];
        if (ch == '.')
            fraction = true;
        else if (ch >= '0' && ch <= '9')
        {
            value = value * 10 + (double)((int)ch - 48);
            if (fraction)
                scale *= 10;
        }
        else if (ch == 'e' || ch == 'E')
        {
            exponent = (int)ParseInt(w.Substring(i + 1).Replace("+", ""));
            break;
        }
    }
    value = value / scale;
    for (; exponent > 0; exponent -= 1)
        value *= 10;
    for (; exponent < 0; exponent += 1)
        value /= 10;
    if (negative)
        value = -value;
    uint64 bits = 0;
    unsafe
    {
        double copy = value;
        bits = *(uint64*)&copy;
    }
    return unchecked((int64)bits);
}
