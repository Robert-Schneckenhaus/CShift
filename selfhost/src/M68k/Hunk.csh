// The output of the assembler as an AmigaOS executable (the hunk format of LoadSeg): a code hunk and a data hunk,
// each with its 32-bit relocations and, with -g, its symbols (the names of the functions and globals, for debuggers
// and profilers). Every symbol must be defined: there is no linker after this.

namespace CShift.M68k;

using System;

const int HunkHeader = 1011;  // 0x3F3
const int HunkCode = 1001;    // 0x3E9
const int HunkData = 1002;    // 0x3EA
const int HunkReloc32 = 1004; // 0x3EC
const int HunkSymbol = 1008;  // 0x3F0
const int HunkEnd = 1010;     // 0x3F2

// 'symbols': with HUNK_SYMBOL, under the names in 'names' where it has one (CShift's names of the functions, see
// FunctionNames).
Error<uint8[]> WriteHunkExecutable(AsmObject obj, bool symbols, Dictionary<string, string> names)
{
    if (obj.Externals.Count() > 0)
    {
        var names = obj.Externals.ToArray();
        return error("undefined symbol(s) on AmigaOS: " + string.Join(", ", names) +
                     (names.Length == 1 ? "" : "") + " (functions of the C library that the AmigaOS runtime does not have)");
    }
    var f = List<uint8>.Create();
    var longs = new int[2];
    for (var s = 0; s < 2; s += 1)
        longs[s] = (obj.Sections[s].Bytes.Count() + 3) / 4;
    Put32(f, HunkHeader);
    Put32(f, 0);        // no resident libraries
    Put32(f, 2);        // hunks
    Put32(f, 0);        // first
    Put32(f, 1);        // last
    Put32(f, longs[0]);
    Put32(f, longs[1]);
    for (var s = 0; s < 2; s += 1)
    {
        var sec = obj.Sections[s];
        var bytes = sec.Bytes.ToArray();
        // the relocated fields hold the offset in the target hunk
        var byHunk = new List<int>[2];
        byHunk[0] = List<int>.Create();
        byHunk[1] = List<int>.Create();
        foreach (var r in sec.Relocs)
        {
            var target = obj.Symbols.Get(r.Sym);
            int value = unchecked((int)((int64)target.Offset + r.Addend));
            unchecked
            {
                bytes[r.Offset] = (uint8)(value >> 24);
                bytes[r.Offset + 1] = (uint8)(value >> 16);
                bytes[r.Offset + 2] = (uint8)(value >> 8);
                bytes[r.Offset + 3] = (uint8)value;
            }
            byHunk[target.Section].Add(r.Offset);
        }
        Put32(f, s == 0 ? HunkCode : HunkData);
        Put32(f, longs[s]);
        foreach (var b in bytes)
            f.Add(b);
        for (var i = bytes.Length; i < longs[s] * 4; i += 1)
            f.Add(0);
        if (byHunk[0].Count() + byHunk[1].Count() > 0)
        {
            Put32(f, HunkReloc32);
            for (var t = 0; t < 2; t += 1)
            {
                if (byHunk[t].Count() == 0)
                    continue;
                Put32(f, byHunk[t].Count());
                Put32(f, t);
                foreach (var offset in byHunk[t])
                    Put32(f, offset);
            }
            Put32(f, 0);
        }
        if (symbols)
            WriteHunkSymbols(f, obj, s, names);
        Put32(f, HunkEnd);
    }
    return f.ToArray();
}

// HUNK_SYMBOL: the symbols of section 's' (not the local labels .L...), each as its name in longs, the name (padded
// with zeros) and its offset in the hunk
void WriteHunkSymbols(List<uint8> f, AsmObject obj, int s, Dictionary<string, string> names)
{
    var written = 0;
    foreach (var name in obj.Symbols.Keys())
    {
        var sym = obj.Symbols.Get(name);
        if (sym.Section != s || name.StartsWith(".L"))
            continue;
        if (written == 0)
            Put32(f, HunkSymbol);
        written += 1;
        var shown = names.TryGet(name);
        var bytes = (shown is string known ? known : name).AsBytes();
        int length = bytes.Length > 1020 ? 1020 : bytes.Length;
        int longs = (length + 3) / 4;
        Put32(f, longs);
        for (var i = 0; i < longs * 4; i += 1)
            f.Add(i < length ? bytes[i] : (uint8)0);
        Put32(f, sym.Offset);
    }
    if (written > 0)
        Put32(f, 0);
}

// The CShift names of the functions in the assembly of the backend: the comment line before a function's label
// ("| function: Name(params)", see GenFunction) names it.
Dictionary<string, string> FunctionNames(string asm)
{
    const string Marker = "| function: ";
    var names = Dictionary<string, string>.Create();
    string pending = "";
    foreach (var line in asm.Split('\n'))
    {
        if (line.StartsWith(Marker))
            pending = line[Marker.Length..].ToString();
        else if (pending.Length > 0 && line.Length > 1 && line[line.Length - 1] == ':' && line[0] != '\t')
        {
            names.Set(line[..^1].ToString(), pending);
            pending = "";
        }
    }
    return names;
}
