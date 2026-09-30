// Importing an AmigaOS library from its SFD file (the NDK's description of a library: the offsets, registers and C
// prototypes of its functions): "using Gfx from "graphics_lib.sfd";". The SFD is turned into an .ffi file like a C
// header; every function gets a symbol that tells the m68k backend how to call it:
//
//     __amiga$graphics.library$288$a0.d0.d1.d2.d3$n     library, offset (negative), registers, n / v (varargs)
//
// The backend passes the arguments in these registers and calls the library through its base in a6; the libraries
// that are used are opened when the program starts (stdlib/amiga/libc.csh). Types: pointers become void* (and
// CONST_STRPTR a string parameter), the integer typedefs of exec/types.h their CShift types.

namespace CShift.Driver;

using System;

struct SfdFunction
{
    string Name;
    string Returns;
    List<string> ParamNames;
    List<string> ParamTypes;
    List<bool> ParamCStrings;
    int Offset;
    string Regs;
    bool Varargs;
}

// The SFD file for an import: next to the importing file, or in the NDK (<ndk>/SFD).
Error<string> FindSfd(string header, string baseDir, string ndk)
{
    string local = IsAbsolutePath(header) ? header : Path.Combine(baseDir, header);
    if (File.Exists(local))
        return local;
    if (ndk.Length > 0)
    {
        string inNdk = Path.Combine(Path.Combine(ndk, "SFD"), header);
        if (File.Exists(inNdk))
            return inNdk;
        return error("cannot find '" + header + "' (looked for '" + local + "' and '" + inNdk + "')");
    }
    return error("cannot find '" + header + "' (looked for '" + local + "'; set the NDK with --ndk <dir>, \"ndk\" in cshift.json or CSHIFT_NDK)");
}

Error<void> GenerateSfdFfi(string name, string sfdPath, string ffiPath)
{
    var read = File.ReadAllText(sfdPath);
    string text = "";
    if (read is string content)
        text = content;
    else
        return error("cannot read '" + sfdPath + "'");
    string libName = "";
    int bias = 30;
    bool alias = false;
    bool varargs = false;
    bool isPrivate = false;
    int lastOffset = 0;
    var functions = List<SfdFunction>.Create();
    var acc = StringBuilder.Create();
    foreach (var rawLine in text.Split('\n'))
    {
        string line = rawLine.TrimEnd('\r').ToString();
        if (acc.Length() == 0)
        {
            if (line.StartsWith("==libname"))
            {
                libName = line.Substring(9).Trim().ToString();
                continue;
            }
            if (line.StartsWith("==bias"))
            {
                bias = SfdInt(line.Substring(6).ToString(), bias);
                continue;
            }
            if (line.StartsWith("==reserve"))
            {
                bias += 6 * SfdInt(line.Substring(9).ToString(), 0);
                continue;
            }
            if (line.StartsWith("==varargs"))
            {
                alias = true;
                varargs = true;
                continue;
            }
            if (line.StartsWith("==alias"))
            {
                alias = true;
                continue;
            }
            if (line.StartsWith("==private"))
            {
                isPrivate = true;
                continue;
            }
            if (line.StartsWith("==public"))
            {
                isPrivate = false;
                continue;
            }
            if (line.StartsWith("==end"))
                break;
            if (line.StartsWith("==") || line.StartsWith("*") || line.Trim().Length == 0)
                continue;
        }
        acc.Append(' ');
        acc.Append(line.Trim());
        string proto = acc.ToString().Trim().ToString();
        if (!proto.EndsWith(")") || !HasRegisterList(proto))
            continue;
        acc.Clear();
        int offset = alias ? lastOffset : bias;
        if (!alias)
        {
            lastOffset = bias;
            bias += 6;
        }
        var parsed = ParseSfdPrototype(proto, offset, varargs);
        alias = false;
        varargs = false;
        if (parsed is SfdFunction f && !isPrivate)
            functions.Add(f);
    }
    if (libName.Length == 0)
        return error("'" + sfdPath + "' has no ==libname");

    // the .ffi file
    var sb = StringBuilder.Create();
    sb.Append("{\n  \"format\": 2,\n  \"namespace\": \"" + name + "\",\n  \"header\": \"" + JsonEscape(sfdPath) + "\",\n");
    sb.Append("  \"target\": \"\",\n  \"flags\": [],\n  \"generator\": \"sfd\",\n  \"dependencies\": [],\n");
    sb.Append("  \"headerPath\": \"" + JsonEscape(Path.GetFullPath(sfdPath)) + "\",\n");
    sb.Append("  \"constants\": [],\n  \"enums\": [],\n  \"structs\": [],\n  \"functions\": [\n");
    var seen = HashSet<string>.Create();
    bool first = true;
    foreach (var f in functions.ToArray())
    {
        if (seen.Contains(f.Name))
            continue;
        seen.Add(f.Name);
        if (!first)
            sb.Append(",\n");
        first = false;
        string symbol = "__amiga$" + libName + "$" + f.Offset.ToString() + "$" + f.Regs.Replace(",", ".") + "$" + (f.Varargs ? "v" : "n");
        sb.Append("    {\n      \"name\": \"" + f.Name + "\",\n      \"symbol\": \"" + symbol + "\",\n");
        sb.Append("      \"returns\": \"" + f.Returns + "\",\n");
        if (f.Varargs)
            sb.Append("      \"variadic\": true,\n");
        sb.Append("      \"params\": [");
        for (var i = 0; i < f.ParamNames.Count(); i += 1)
        {
            sb.Append(i == 0 ? "\n" : ",\n");
            sb.Append("        { \"name\": \"" + f.ParamNames.Get(i) + "\", \"type\": \"" + f.ParamTypes.Get(i) + "\"" +
                      (f.ParamCStrings.Get(i) ? ", \"cstring\": true" : "") + " }");
        }
        sb.Append(f.ParamNames.Count() > 0 ? "\n      ]\n    }" : "]\n    }");
    }
    sb.Append("\n  ]\n}\n");
    var wrote = File.WriteAllText(ffiPath, sb.ToString());
    if (wrote is error failed)
        return error("cannot write '" + ffiPath + "': " + failed.Message);
    return;
}

string JsonEscape(string s)
{
    return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
}

// "... ) (a0,d0)" or "... ) ()": the prototype ends with the register list
bool HasRegisterList(string proto)
{
    int close = proto.Length - 1;
    int open = proto.LastIndexOf('(');
    if (open < 0)
        return false;
    string inner = proto.Substring(open + 1, close - open - 1).Trim().ToString().ToLower(); // graphics_lib.sfd: (A1)
    foreach (var r in inner.Split(','))
    {
        string reg = r.Trim().ToString();
        if (reg.Length == 0)
            continue;
        foreach (var part in reg.Split('/'))
        {
            string one = part.Trim().ToString();
            if (one.Length != 2 || (one[0] != 'd' && one[0] != 'a') || one[1] < '0' || one[1] > '7')
                return false;
        }
    }
    // there must be a parameter list before it
    return proto.Substring(0, open).TrimEnd().EndsWith(")");
}

Optional<SfdFunction> ParseSfdPrototype(string proto, int offset, bool varargs)
{
    int regOpen = proto.LastIndexOf('(');
    string regs = proto.Substring(regOpen + 1, proto.Length - regOpen - 2).Trim().Replace("/", ",").Replace(" ", "").ToLower();
    string head = proto.Substring(0, regOpen).TrimEnd().ToString();
    // the parameter list: from the '(' that matches the last ')'
    int depth = 0;
    int paramOpen = -1;
    for (var i = head.Length - 1; i >= 0; i -= 1)
    {
        if (head[i] == ')')
            depth += 1;
        else if (head[i] == '(')
        {
            depth -= 1;
            if (depth == 0)
            {
                paramOpen = i;
                break;
            }
        }
    }
    if (paramOpen < 0)
        return null;
    string before = head.Substring(0, paramOpen).TrimEnd().ToString();
    int nameStart = before.Length;
    while (nameStart > 0 && IsIdentChar(before[nameStart - 1]))
        nameStart -= 1;
    string name = before.Substring(nameStart).ToString();
    string retType = before.Substring(0, nameStart).Trim().ToString();
    string paramText = head.Substring(paramOpen + 1, head.Length - paramOpen - 2).Trim().ToString();

    var f = SfdFunction { Name = name, Returns = SfdType(retType, false), ParamNames = List<string>.Create(), ParamTypes = List<string>.Create(),
                          ParamCStrings = List<bool>.Create(), Offset = offset, Regs = regs, Varargs = varargs };
    int regCount = regs.Length == 0 ? 0 : regs.Split(',').Length;
    var parts = SplitParams(paramText);
    int fixedCount = varargs ? regCount - 1 : parts.Length;
    for (var i = 0; i < parts.Length && i < fixedCount; i += 1)
    {
        string p = parts[i];
        if (p == "..." || p == "VOID" || p == "void" || p.Length == 0)
            continue;
        string pname = ParamName(p, i);
        int at = LastIndexOfText(p, pname);
        string ptype = pname.StartsWith("arg") && at < 0 ? p : p.Substring(0, at >= 0 ? at : p.Length).Trim().ToString();
        if (p.Contains("(*"))
            ptype = "(*)";
        bool cstring = IsConstString(ptype);
        f.ParamNames.Add(SafeParamName(pname, i));
        f.ParamTypes.Add(cstring ? "string" : SfdType(ptype, true));
        f.ParamCStrings.Add(cstring);
    }
    return f;
}

int SfdInt(string s, int fallback)
{
    var r = s.Trim().ParseInt();
    if (r is int v)
        return v;
    return fallback;
}

int LastIndexOfText(string s, string part)
{
    for (var i = s.Length - part.Length; i >= 0; i -= 1)
    {
        if (s.Substring(i, part.Length) == part)
            return i;
    }
    return -1;
}

bool IsIdentChar(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

string[] SplitParams(string text)
{
    var parts = List<string>.Create();
    int depth = 0;
    int start = 0;
    for (var i = 0; i < text.Length; i += 1)
    {
        char c = text[i];
        if (c == '(')
            depth += 1;
        else if (c == ')')
            depth -= 1;
        else if (c == ',' && depth == 0)
        {
            parts.Add(text.Substring(start, i - start).Trim().ToString());
            start = i + 1;
        }
    }
    string last = text.Substring(start).Trim().ToString();
    if (last.Length > 0)
        parts.Add(last);
    return parts.ToArray();
}

// the name of a parameter: the last identifier ("(*hook)()": the one after the '*')
string ParamName(string p, int index)
{
    int star = p.IndexOf("(*");
    if (star >= 0)
    {
        int e = star + 2;
        while (e < p.Length && IsIdentChar(p[e]))
            e += 1;
        return p.Substring(star + 2, e - star - 2).ToString();
    }
    int end = p.Length;
    while (end > 0 && (p[end - 1] == ' ' || p[end - 1] == ']' || p[end - 1] == '['))
        end -= 1;
    int start = end;
    while (start > 0 && IsIdentChar(p[start - 1]))
        start -= 1;
    string name = p.Substring(start, end - start).ToString();
    // a parameter without a name ("ULONG"): its type is all there is
    if (start == 0)
        return "arg" + index.ToString();
    return name;
}

string SafeParamName(string name, int index)
{
    switch (name)
    {
    case "string":
    case "object":
    case "class":
    case "base":
    case "ref":
    case "out":
    case "in":
    case "is":
    case "var":
    case "params":
    case "default":
    case "new":
    case "event":
    case "operator":
    case "lock":
    case "char":
    case "int":
    case "float":
    case "double":
        return name + "_";
    default:
        return name.Length == 0 ? "arg" + index.ToString() : name;
    }
}

bool IsConstString(string t)
{
    string s = t.Replace(" ", "");
    return s == "CONST_STRPTR" || s == "CONSTSTRPTR" || s == "constchar*" || s == "CONSTchar*" || s == "CONSTUBYTE*" || s == "constUBYTE*" ||
           s == "CONSTTEXT*";
}

// A C type of an SFD prototype as a CShift type.
string SfdType(string t, bool param)
{
    string s = t.Replace("CONST ", "").Replace("const ", "").Replace("struct ", "").Replace("union ", "").Trim().ToString();
    if (t.Contains("(*"))
        return "void*";
    if (s.Contains("*"))
        return "void*";
    switch (s)
    {
    case "":
    case "VOID":
    case "void":
        return "void";
    case "LONG":
    case "int":
    case "BPTR":
    case "BSTR":
    case "LONGBITS":
        return "int32";
    case "ULONG":
    case "Tag":
    case "ULONGBITS":
    case "unsigned":
    case "unsigned int":
        return "uint32";
    case "WORD":
    case "SHORT":
    case "BOOL":
    case "short":
        return "int16";
    case "UWORD":
    case "USHORT":
    case "WORDBITS":
    case "UWORDBITS":
        return "uint16";
    case "BYTE":
        return "int8";
    case "UBYTE":
    case "TEXT":
    case "BYTEBITS":
    case "UBYTEBITS":
        return "uint8";
    case "FLOAT":
    case "float":
        return "float";
    case "DOUBLE":
    case "double":
        return "double";
    default:
        break;
    }
    // APTR, STRPTR, PLANEPTR, ... and handles
    if (s.EndsWith("PTR") || s.EndsWith("Handle") || s.EndsWith("Ptr"))
        return "void*";
    return "int32";
}
