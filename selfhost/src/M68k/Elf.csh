// The output of the assembler as an ELF object for m68k Linux (big endian, relocations with addends): for testing the
// backend with GNU ld and qemu, since everything the assembler writes can be linked and run there.

namespace CShift.M68k;

using System;

void Put8(List<uint8> b, int v)
{
    unchecked
    {
        b.Add((uint8)v);
    }
}

void Put16(List<uint8> b, int v)
{
    unchecked
    {
        b.Add((uint8)(v >> 8));
        b.Add((uint8)v);
    }
}

void Put32(List<uint8> b, int v)
{
    unchecked
    {
        b.Add((uint8)(v >> 24));
        b.Add((uint8)(v >> 16));
        b.Add((uint8)(v >> 8));
        b.Add((uint8)v);
    }
}

void PadTo(List<uint8> b, int align)
{
    while (b.Count() % align != 0)
        b.Add(0);
}

// the offset of name in a string table (added if new)
int StrIndex(List<uint8> table, Dictionary<string, int> known, string name)
{
    var found = known.TryGet(name);
    if (found is int at)
        return at;
    int offset = table.Count();
    foreach (var c in Encoding.UTF8().GetBytes(name))
        table.Add(c);
    table.Add(0);
    known.Set(name, offset);
    return offset;
}

uint8[] WriteElfObject(AsmObject obj)
{
    // symbols: 0 null, 1 .text, 2 .data (locals), then the globals and the undefined ones
    var strtab = List<uint8>.Create();
    strtab.Add(0);
    var strings = Dictionary<string, int>.Create();
    var symtab = List<uint8>.Create();
    for (var i = 0; i < 16; i += 1)
        symtab.Add(0);
    for (var s = 1; s <= 2; s += 1)
    {
        Put32(symtab, 0);
        Put32(symtab, 0);
        Put32(symtab, 0);
        Put8(symtab, 3); // local, section
        Put8(symtab, 0);
        Put16(symtab, s);
    }
    var symIndex = Dictionary<string, int>.Create();
    int next = 3;
    // the local labels (not .L...): names for debuggers and profilers
    foreach (var entry in obj.Symbols.Entries())
    {
        if (entry.Value.Global || entry.Key.StartsWith("."))
            continue;
        Put32(symtab, StrIndex(strtab, strings, entry.Key));
        Put32(symtab, entry.Value.Offset);
        Put32(symtab, 0);
        Put8(symtab, 0); // local, no type
        Put8(symtab, 0);
        Put16(symtab, entry.Value.Section + 1);
        next += 1;
    }
    int firstGlobal = next;
    foreach (var entry in obj.Symbols.Entries())
    {
        if (!entry.Value.Global)
            continue;
        Put32(symtab, StrIndex(strtab, strings, entry.Key));
        Put32(symtab, entry.Value.Offset);
        Put32(symtab, 0);
        Put8(symtab, 16); // global, no type
        Put8(symtab, 0);
        Put16(symtab, entry.Value.Section + 1);
        symIndex.Set(entry.Key, next);
        next += 1;
    }
    foreach (var name in obj.Externals)
    {
        Put32(symtab, StrIndex(strtab, strings, name));
        Put32(symtab, 0);
        Put32(symtab, 0);
        Put8(symtab, 16);
        Put8(symtab, 0);
        Put16(symtab, 0);
        symIndex.Set(name, next);
        next += 1;
    }

    // relocations: a defined target is its section's symbol plus its offset
    var relas = new List<uint8>[2];
    for (var s = 0; s < 2; s += 1)
    {
        var rela = List<uint8>.Create();
        foreach (var r in obj.Sections[s].Relocs)
        {
            int sym;
            int64 addend = r.Addend;
            var def = obj.Symbols.TryGet(r.Sym);
            if (def is AsmSymbol d)
            {
                sym = d.Section + 1;
                addend += (int64)d.Offset;
            }
            else
                sym = symIndex.Get(r.Sym);
            Put32(rela, r.Offset);
            Put32(rela, (sym << 8) | 1); // R_68K_32
            Put32(rela, unchecked((int)addend));
        }
        relas[s] = rela;
    }

    var shstr = List<uint8>.Create();
    shstr.Add(0);
    var shNames = Dictionary<string, int>.Create();
    string[] names = [".text", ".data", ".rela.text", ".rela.data", ".symtab", ".strtab", ".shstrtab"];
    var nameAt = new int[names.Length];
    for (var i = 0; i < names.Length; i += 1)
        nameAt[i] = StrIndex(shstr, shNames, names[i]);

    // the file: header, the section contents, the section headers
    var f = List<uint8>.Create();
    for (var i = 0; i < 52; i += 1)
        f.Add(0);
    var contents = new List<uint8>[7];
    contents[0] = obj.Sections[0].Bytes;
    contents[1] = obj.Sections[1].Bytes;
    contents[2] = relas[0];
    contents[3] = relas[1];
    contents[4] = symtab;
    contents[5] = strtab;
    contents[6] = shstr;
    var offsets = new int[7];
    for (var i = 0; i < 7; i += 1)
    {
        PadTo(f, 4);
        offsets[i] = f.Count();
        foreach (var x in contents[i].ToArray())
            f.Add(x);
    }
    PadTo(f, 4);
    int shoff = f.Count();
    for (var i = 0; i < 40; i += 1)
        f.Add(0); // the null section
    int[] types = [1, 1, 4, 4, 2, 3, 3];
    int[] flags = [6, 3, 64, 64, 0, 0, 0];
    int[] links = [0, 0, 5, 5, 6, 0, 0];
    int[] infos = [0, 0, 1, 2, firstGlobal, 0, 0];
    int[] aligns = [2, 2, 4, 4, 4, 1, 1];
    int[] entsizes = [0, 0, 12, 12, 16, 0, 0];
    for (var i = 0; i < 7; i += 1)
    {
        Put32(f, nameAt[i]);
        Put32(f, types[i]);
        Put32(f, flags[i]);
        Put32(f, 0);
        Put32(f, offsets[i]);
        Put32(f, contents[i].Count());
        Put32(f, links[i]);
        Put32(f, infos[i]);
        Put32(f, aligns[i]);
        Put32(f, entsizes[i]);
    }

    // the header
    var h = List<uint8>.Create();
    h.Add(127);
    h.Add(69);
    h.Add(76);
    h.Add(70);
    Put8(h, 1); // 32 bit
    Put8(h, 2); // big endian
    Put8(h, 1); // version
    for (var i = 0; i < 9; i += 1)
        h.Add(0);
    Put16(h, 1);  // relocatable
    Put16(h, 4);  // EM_68K
    Put32(h, 1);
    Put32(h, 0);  // entry
    Put32(h, 0);  // program headers
    Put32(h, shoff);
    Put32(h, 0);  // flags
    Put16(h, 52);
    Put16(h, 0);
    Put16(h, 0);
    Put16(h, 40);
    Put16(h, 8);  // sections
    Put16(h, 7);  // .shstrtab
    var bytes = f.ToArray();
    var header = h.ToArray();
    for (var i = 0; i < header.Length; i += 1)
        bytes[i] = header[i];
    return bytes;
}
