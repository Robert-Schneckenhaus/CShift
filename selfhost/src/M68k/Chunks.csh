// The hand-written assembly (the startup code of AmigaOS with its stubs, runtime.s) in pieces, so that a program
// contains only the pieces it uses: a piece starts at a global label and ends before the next one. A piece of code
// whose last instruction can go on falls through into the next piece and needs it; a branch to a local label of
// another piece (memmove into memcpy) needs that piece as well. Data is one piece from its first label on (the
// variables of the startup code are read by index from __cs_Vars).

namespace CShift.M68k;

using System;

struct AsmChunk
{
    string Text;
    bool Data;         // in the data section
    List<int> Needs;   // the pieces this piece needs whenever it is used
}

struct AsmChunks
{
    List<AsmChunk> Pieces;
    Dictionary<string, int> ByLabel;   // global and local labels -> the piece that defines them
    HashSet<int> Kept;

    static AsmChunks Create()
    {
        return AsmChunks { Pieces = List<AsmChunk>.Create(), ByLabel = Dictionary<string, int>.Create(), Kept = HashSet<int>.Create() };
    }

    // Splits the text into pieces; returns the index of its first piece (-1: nothing in it).
    int Add(string text)
    {
        int first = Pieces.Count();
        var pending = StringBuilder.Create();   // comments and directives before the next label or instruction
        var current = StringBuilder.Create();
        bool started = false;                   // the current piece has a label or an instruction
        bool dataSection = false;
        bool currentData = false;
        bool fallsThrough = false;              // the last instruction of the current piece can go on
        var locals = List<string>.Create();     // the local labels the current piece refers to
        var allLocals = List<List<string>>.Create();
        foreach (var raw in text.Split('\n'))
        {
            string line = raw.ToString();
            string body = line;
            int bar = body.IndexOf('|');
            if (bar >= 0)
                body = body.Substring(0, bar).ToString();
            string trimmed = body.Trim().ToString();
            string op = ChunkMnemonic(trimmed);
            if (trimmed.Length == 0 || IsLayoutDirective(op))
            {
                if (op == ".text" || op == ".section")
                    dataSection = false;
                else if (op == ".data" || op == ".bss")
                    dataSection = true;
                pending.Append(line);
                pending.Append('\n');
                continue;
            }
            string label = line.Length > 0 && line[0] != '\t' && line[0] != ' ' && line[0] != '.' ? LineLabel(body) : "";
            if (label.Length > 0 && started && (!dataSection || !currentData))
            {
                // a new piece; the previous one needs this one if it falls through
                FinishChunk(current, currentData, locals, allLocals, fallsThrough && !currentData ? Pieces.Count() + 1 : -1);
                current = StringBuilder.Create();
                locals = List<string>.Create();
                started = false;
            }
            if (!started)
            {
                started = true;
                currentData = dataSection;
            }
            current.Append(pending.ToString());
            pending = StringBuilder.Create();
            current.Append(line);
            current.Append('\n');
            if (label.Length > 0)
                ByLabel.Set(label, Pieces.Count());
            else if (trimmed.StartsWith(".L") && trimmed.EndsWith(":"))
                ByLabel.Set(trimmed.Substring(0, trimmed.Length - 1).ToString(), Pieces.Count());
            string rest = label.Length > 0 ? body.Substring(body.IndexOf(':') + 1).ToString().Trim().ToString() : trimmed;
            if (rest.Length > 0 && !rest.StartsWith(".L"))
            {
                string mnemonic = ChunkMnemonic(rest);
                fallsThrough = !(mnemonic == "rts" || mnemonic == "rte" || mnemonic == "rtr" || mnemonic.StartsWith("bra") ||
                                 mnemonic.StartsWith("jmp") || mnemonic.StartsWith("jra"));
                LocalRefs(rest, locals);
            }
        }
        if (started || pending.Length() > 0)
        {
            current.Append(pending.ToString());
            FinishChunk(current, currentData, locals, allLocals, -1);
        }
        // the local labels of other pieces
        for (var i = first; i < Pieces.Count(); i += 1)
        {
            foreach (var name in allLocals.Get(i - first).ToArray())
            {
                var owner = ByLabel.TryGet(name);
                if (owner is int o && o != i)
                    Pieces.Get(i).Needs.Add(o);
            }
        }
        return Pieces.Count() > first ? first : -1;
    }

    void FinishChunk(StringBuilder text, bool data, List<string> locals, List<List<string>> allLocals, int next)
    {
        var needs = List<int>.Create();
        if (next >= 0)
            needs.Add(next);
        Pieces.Add(AsmChunk { Text = text.ToString(), Data = data, Needs = needs });
        allLocals.Add(locals);
    }

    // Keeps the piece that defines the label (and what it needs); the texts of the pieces that are new are added to
    // 'found' (their symbols are needed as well).
    void Use(string label, List<string> found)
    {
        var index = ByLabel.TryGet(label);
        if (index is int i)
            Keep(i, found);
    }

    void Keep(int index, List<string> found)
    {
        var work = List<int>.Create();
        work.Add(index);
        while (work.Count() > 0)
        {
            int i = work.Get(work.Count() - 1);
            work.RemoveAt(work.Count() - 1);
            if (Kept.Contains(i))
                continue;
            Kept.Add(i);
            var piece = Pieces.Get(i);
            found.Add(piece.Text);
            foreach (var n in piece.Needs.ToArray())
                work.Add(n);
        }
    }

    // The kept pieces from 'first' up to (not including) 'end', each in its section; the text starts and ends in the
    // text section.
    string Text(int first, int end)
    {
        var sb = StringBuilder.Create();
        bool data = false;
        for (var i = first; i >= 0 && i < end; i += 1)
        {
            if (!Kept.Contains(i))
                continue;
            var piece = Pieces.Get(i);
            if (piece.Data != data)
            {
                sb.Append(piece.Data ? "\t.data\n" : "\t.text\n");
                data = piece.Data;
            }
            sb.Append(piece.Text);
        }
        if (data)
            sb.Append("\t.text\n");
        return sb.ToString();
    }
}

// The first word of a line without its label ("" for none).
string ChunkMnemonic(string text)
{
    int end = 0;
    while (end < text.Length && text[end] != ' ' && text[end] != '\t')
        end += 1;
    return text.Substring(0, end).ToString();
}

// Directives that do not belong to the code or data before them: they go with the next piece.
bool IsLayoutDirective(string op)
{
    return op == ".text" || op == ".data" || op == ".bss" || op == ".section" || op == ".even" || op == ".globl" ||
           op == ".global" || op == ".align";
}

// The label at the start of a line ("name:" or "name:<tab>..."), or "".
string LineLabel(string line)
{
    int colon = line.IndexOf(':');
    if (colon <= 0)
        return "";
    for (var i = 0; i < colon; i += 1)
    {
        if (!IsSymbolChar(line[i]))
            return "";
    }
    return line.Substring(0, colon).ToString();
}

// The local labels (.L...) an instruction refers to.
void LocalRefs(string text, List<string> found)
{
    int i = text.IndexOf(".L");
    while (i >= 0)
    {
        int e = i + 2;
        while (e < text.Length && IsSymbolChar(text[e]))
            e += 1;
        bool prevOk = i == 0 || !IsSymbolChar(text[i - 1]);
        if (prevOk)
            found.Add(text.Substring(i, e - i).ToString());
        i = e < text.Length ? text.IndexOf(".L", e) : -1;
    }
}
