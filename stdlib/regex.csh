// Regular expressions: matching, searching, replacing and splitting text.
//
//     var re = try Regex.Create("(?<year>\\d{4})-(\\d{2})-(\\d{2})");
//     if (re.Match("due 2026-10-01!") is RegexMatch m)
//         Console.WriteLine(m.Value + " " + m.Group("year") + " " + m.Group(2));   // 2026-10-01 2026 10
//     string s = re.Replace("2026-10-01", "$3.$2.${year}");                        // 01.10.2026
//     foreach (var word in (try Regex.Create("\\s*,\\s*")).Split("a , b,c"))         // a b c
//         Console.WriteLine(word);
//
// The syntax (a subset of .NET's and Perl's):
//   x            a character; \. \* \\ ... a character that is special otherwise; \n \r \t \f \v \0 \xHH \uHHHH
//   .            any character but '\n'
//   [abc] [a-z] [^0-9]   a character of the set, or not of it ([\d_], [\w-] work too)
//   \d \w \s     a digit, a word character [A-Za-z0-9_], white space; \D \W \S the opposite
//   ^ $          the start and end of the text (of each line with (?m)); \A \z always of the text
//   \b \B        a word boundary, not a word boundary
//   (x)          a group (numbered from 1); (?<name>x) a named group; (?:x) a group that captures nothing
//   x|y          x or y
//   x* x+ x? x{n} x{n,} x{n,m}   repetition; with a '?' after it (x*?, x+?, ...) as few times as possible
//   (?i) (?m) (?im)   at the start of the pattern: ignore case (ASCII letters), ^ and $ match at line breaks
// Backreferences (\1) and lookaround are not supported. The text is UTF-8: '.', a set and \w etc. match one character
// (code point), positions and lengths are in bytes. The matcher is a backtracking one that remembers which states it
// has tried, so a search takes at most (pattern size) x (text length) steps, also for patterns like (a*)*.

namespace System;

// Regex.Create: the pattern is not valid (the message says what and where).
error RegexError
{
    InvalidPattern = 1
}

// A match: where it is, its text and the text of its groups.
struct RegexMatch
{
    int Index;        // the position of the match in the text (bytes)
    int Length;       // its length (bytes)
    string Value;     // the matched text
    string Text;          // the text that was searched
    int[] Captures;       // the start and end of every group (-1: it did not take part), group 0 first
    string[] GroupNames;  // the names of the groups ("" for unnamed ones), group 0 first

    // the number of groups of the pattern (without group 0, the whole match)
    int GroupCount()
    {
        return Captures.Length / 2 - 1;
    }

    // the text of group n (0: the whole match); "" if the group did not take part in the match
    string Group(int n)
    {
        if (n < 0 || n * 2 >= Captures.Length)
            Environment.Panic("RegexMatch.Group: there is no group " + n.ToString() + " (the pattern has " + GroupCount().ToString() + ")");
        if (Captures[n * 2] < 0)
            return "";
        return Text.Substring(Captures[n * 2], Captures[n * 2 + 1] - Captures[n * 2]).ToString();
    }

    // the text of the group (?<name>...)
    string Group(string name)
    {
        return Group(GroupNumber(name));
    }

    // the number of the group (?<name>...)
    int GroupNumber(string name)
    {
        for (var i = 0; i < GroupNames.Length; i += 1)
        {
            if (GroupNames[i] == name)
                return i;
        }
        Environment.Panic("RegexMatch.Group: the pattern has no group '" + name + "'");
        return -1;
    }

    // false if group n did not take part in the match (an alternative that was not taken, x? without x)
    bool GroupMatched(int n)
    {
        return n >= 0 && n * 2 < Captures.Length && Captures[n * 2] >= 0;
    }

    // the position of group n in the text (-1 if it did not take part)
    int GroupIndex(int n)
    {
        if (n < 0 || n * 2 >= Captures.Length)
            return -1;
        return Captures[n * 2];
    }
}

enum _ROp : uint8
{
    Char = 0,      // A: the character
    Any = 1,       // any character but '\n'
    Class = 2,     // A: the set
    Split = 3,     // go on at A; if that fails, at B
    Jmp = 4,       // go on at A
    Save = 5,      // A: the slot of a group's start or end
    Match = 6,
    Bol = 7,
    Eol = 8,
    WordB = 9,
    NotWordB = 10,
    Start = 11,
    End = 12
}

struct _RInst
{
    _ROp Op;
    int A;
    int B;
}

// a set of characters: pairs of first and last code point
struct _RClass
{
    int[] Ranges;
    bool Negated;
}

struct Regex
{
    string Pattern;
    _RInst[] _prog;
    _RClass[] _classes;
    string[] _names;     // per group (0 = the whole match): its name or ""
    bool _ignoreCase;
    bool _multiline;

    // The pattern compiled; an error says what is wrong with it.
    static RegexError<Regex> Create(string pattern)
    {
        var p = _RegexParser.Create(pattern);
        int root = p.ParseAll();
        if (p.Error.Length > 0)
            return error("invalid regular expression '" + pattern + "' at " + (p.ErrorPos + 1).ToString() + ": " + p.Error,
                         RegexError.InvalidPattern);
        var prog = List<_RInst>.Create();
        prog.Add(_RInst { Op = _ROp.Save, A = 0 });
        if (!p.Emit(prog, root))
            return error("invalid regular expression '" + pattern + "': it is too large (repetitions like x{1000} multiply it)",
                         RegexError.InvalidPattern);
        prog.Add(_RInst { Op = _ROp.Save, A = 1 });
        prog.Add(_RInst { Op = _ROp.Match });
        return Regex { Pattern = pattern, _prog = prog.ToArray(), _classes = p.Classes.ToArray(), _names = p.Names.ToArray(),
                       _ignoreCase = p.IgnoreCase, _multiline = p.Multiline };
    }

    // true if the pattern occurs somewhere in the text
    bool IsMatch(string text)
    {
        var caps = _NewCaps();
        return _Search(text, 0, caps, _NewVisited(text));
    }

    // the first match in the text, or null
    Optional<RegexMatch> Match(string text)
    {
        return Match(text, 0);
    }

    // the first match at 'start' (a byte position) or after it, or null
    Optional<RegexMatch> Match(string text, int start)
    {
        if (start < 0 || start > text.Length)
            Environment.Panic("Regex.Match: start " + start.ToString() + " is outside the text (length " + text.Length.ToString() + ")");
        var caps = _NewCaps();
        if (!_Search(text, start, caps, _NewVisited(text)))
            return null;
        return _MakeMatch(text, caps);
    }

    // every match, from left to right, without overlaps
    RegexMatch[] Matches(string text)
    {
        var result = List<RegexMatch>.Create();
        var visited = _NewVisited(text);
        int pos = 0;
        while (pos <= text.Length)
        {
            var caps = _NewCaps();
            _ClearVisited(visited);
            if (!_Search(text, pos, caps, visited))
                break;
            result.Add(_MakeMatch(text, caps));
            pos = caps[1] > caps[0] ? caps[1] : _NextChar(text, caps[1]);
        }
        return result.ToArray();
    }

    // The text with every match replaced: in the replacement $0 is the match, $1 ... $9 and ${n} its groups,
    // ${name} a named group, $$ a '$'.
    string Replace(string text, string replacement)
    {
        var sb = StringBuilder.Create();
        int last = 0;
        foreach (var m in Matches(text))
        {
            sb.Append(text[last..m.Index]);
            _Expand(sb, m, replacement);
            last = m.Index + m.Length;
        }
        sb.Append(text[last..]);
        return sb.ToString();
    }

    // The parts of the text between the matches (empty matches do not split).
    string[] Split(string text)
    {
        var parts = List<string>.Create();
        int last = 0;
        foreach (var m in Matches(text))
        {
            if (m.Length == 0)
                continue;
            parts.Add(text[last..m.Index].ToString());
            last = m.Index + m.Length;
        }
        parts.Add(text[last..].ToString());
        return parts.ToArray();
    }

    void _Expand(StringBuilder sb, RegexMatch m, string r)
    {
        int i = 0;
        while (i < r.Length)
        {
            char c = r[i];
            if (c != '$' || i + 1 >= r.Length)
            {
                sb.Append(c);
                i += 1;
                continue;
            }
            char d = r[i + 1];
            if (d == '$')
            {
                sb.Append('$');
                i += 2;
            }
            else if (d >= '0' && d <= '9')
            {
                int n = (int)d - 48;
                if (n <= m.GroupCount())
                    sb.Append(m.Group(n));
                i += 2;
            }
            else if (d == '{')
            {
                int close = r.IndexOf('}', i + 2);
                if (close < 0)
                {
                    sb.Append(c);
                    i += 1;
                    continue;
                }
                string name = r.Substring(i + 2, close - i - 2).ToString();
                if (name.ParseInt() is int n)
                {
                    if (n >= 0 && n <= m.GroupCount())
                        sb.Append(m.Group(n));
                }
                else
                {
                    for (var k = 0; k < _names.Length; k += 1)
                    {
                        if (_names[k] == name)
                            sb.Append(m.Group(k));
                    }
                }
                i = close + 1;
            }
            else
            {
                sb.Append(c);
                i += 1;
            }
        }
    }

    int[] _NewCaps()
    {
        var caps = new int[_names.Length * 2];
        for (var i = 0; i < caps.Length; i += 1)
            caps[i] = -1;
        return caps;
    }

    // one bit per (instruction, text position): the states that were tried
    uint32[] _NewVisited(string text)
    {
        int64 bits = (int64)_prog.Length * (int64)(text.Length + 1);
        if (bits > 2000000000l)
            Environment.Panic("Regex: the text is too long for this pattern (" + text.Length.ToString() + " bytes)");
        return new uint32[(int)((bits + 31) / 32)];
    }

    static void _ClearVisited(uint32[] visited)
    {
        for (var i = 0; i < visited.Length; i += 1)
            visited[i] = 0u;
    }

    RegexMatch _MakeMatch(string text, int[] caps)
    {
        return RegexMatch { Index = caps[0], Length = caps[1] - caps[0], Value = text.Substring(caps[0], caps[1] - caps[0]).ToString(),
                            Text = text, Captures = caps, GroupNames = _names };
    }

    // the position after the character at pos
    static int _NextChar(string text, int pos)
    {
        pos += 1;
        while (pos < text.Length && ((int)text[pos] & 0xC0) == 0x80)
            pos += 1;
        return pos;
    }

    // a match starting at 'start' or later: true and the groups in 'caps'
    bool _Search(string text, int start, int[] caps, uint32[] visited)
    {
        int len = text.Length;
        int width = len + 1;
        var stack = List<int>.Create(); // triples: kind (0 = try pc at pos, 1 = restore caps[a] = b), a, b
        int s = start;
        while (s <= len)
        {
            for (var i = 0; i < caps.Length; i += 1)
                caps[i] = -1;
            stack.Clear();
            stack.Add(0);
            stack.Add(0);
            stack.Add(s);
            while (stack.Count() > 0)
            {
                int n = stack.Count();
                int kind = stack.Get(n - 3);
                int pc = stack.Get(n - 2);
                int pos = stack.Get(n - 1);
                stack.RemoveAt(n - 1);
                stack.RemoveAt(n - 2);
                stack.RemoveAt(n - 3);
                if (kind == 1)
                {
                    caps[pc] = pos;
                    continue;
                }
                while (true)
                {
                    int bit = pc * width + pos;
                    uint32 mask = 1u << (bit & 31);
                    if ((visited[bit >> 5] & mask) != 0u)
                        break;
                    visited[bit >> 5] = visited[bit >> 5] | mask;
                    var inst = _prog[pc];
                    if (inst.Op == _ROp.Char || inst.Op == _ROp.Any || inst.Op == _ROp.Class)
                    {
                        if (pos >= len)
                            break;
                        int size = 1;
                        int c = _RegexDecode(text, pos, ref size);
                        bool ok;
                        if (inst.Op == _ROp.Char)
                            ok = c == inst.A || (_ignoreCase && _Fold(c) == _Fold(inst.A));
                        else if (inst.Op == _ROp.Any)
                            ok = c != 10;
                        else
                            ok = _InClass(inst.A, c);
                        if (!ok)
                            break;
                        pos += size;
                        pc += 1;
                        continue;
                    }
                    if (inst.Op == _ROp.Split)
                    {
                        stack.Add(0);
                        stack.Add(inst.B);
                        stack.Add(pos);
                        pc = inst.A;
                        continue;
                    }
                    if (inst.Op == _ROp.Jmp)
                    {
                        pc = inst.A;
                        continue;
                    }
                    if (inst.Op == _ROp.Save)
                    {
                        stack.Add(1);
                        stack.Add(inst.A);
                        stack.Add(caps[inst.A]);
                        caps[inst.A] = pos;
                        pc += 1;
                        continue;
                    }
                    if (inst.Op == _ROp.Match)
                        return true;
                    bool holds;
                    if (inst.Op == _ROp.Bol)
                        holds = pos == 0 || (_multiline && text[pos - 1] == '\n');
                    else if (inst.Op == _ROp.Eol)
                        holds = pos == len || (_multiline && text[pos] == '\n');
                    else if (inst.Op == _ROp.Start)
                        holds = pos == 0;
                    else if (inst.Op == _ROp.End)
                        holds = pos == len;
                    else
                    {
                        bool before = pos > 0 && _IsWordByte(text[pos - 1]);
                        bool after = pos < len && _IsWordByte(text[pos]);
                        holds = (before != after) == (inst.Op == _ROp.WordB);
                    }
                    if (!holds)
                        break;
                    pc += 1;
                }
            }
            if (s >= len)
                break;
            s = _NextChar(text, s);
        }
        return false;
    }

    static bool _IsWordByte(char c)
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
    }

    static int _Fold(int c)
    {
        return c >= 'A' && c <= 'Z' ? c + 32 : c;
    }

    bool _InClass(int index, int c)
    {
        var cls = _classes[index];
        bool found = _InRanges(cls.Ranges, c);
        if (!found && _ignoreCase)
        {
            if (c >= 'a' && c <= 'z')
                found = _InRanges(cls.Ranges, c - 32);
            else if (c >= 'A' && c <= 'Z')
                found = _InRanges(cls.Ranges, c + 32);
        }
        return found != cls.Negated;
    }

    static bool _InRanges(int[] ranges, int c)
    {
        for (var i = 0; i + 1 < ranges.Length; i += 2)
        {
            if (c >= ranges[i] && c <= ranges[i + 1])
                return true;
        }
        return false;
    }
}

// the code point at pos (a byte that is not valid UTF-8: that byte); its length in 'size'
int _RegexDecode(string text, int pos, ref int size)
{
    int b = (int)text[pos];
    size = 1;
    if (b < 0x80)
        return b;
    int need = b >= 0xF0 ? 3 : b >= 0xE0 ? 2 : b >= 0xC0 ? 1 : 0;
    if (need == 0 || pos + need > text.Length - 1)
        return b;
    int c = b & (need == 1 ? 0x1F : need == 2 ? 0x0F : 0x07);
    for (var k = 1; k <= need; k += 1)
    {
        int cb = (int)text[pos + k];
        if ((cb & 0xC0) != 0x80)
            return b;
        c = (c << 6) | (cb & 0x3F);
    }
    size = need + 1;
    return c;
}

// ---------------------------------------------------------------------------
// The pattern: parsed into a tree, then compiled into the instructions of Regex
// ---------------------------------------------------------------------------

enum _RKind : uint8
{
    Empty = 0,
    Char = 1,
    Any = 2,
    Class = 3,
    Concat = 4,
    Alt = 5,
    Group = 6,     // Value: the group number
    Repeat = 7,    // Min, Max (-1: no limit), Lazy
    Assert = 8     // Value: the _ROp of the assertion
}

struct _RNode
{
    _RKind Kind;
    int Value;
    int Min;
    int Max;
    bool Lazy;
    List<int> Kids;
}

struct _RegexParser
{
    string Pattern;
    int Pos;
    List<_RNode> Nodes;
    List<_RClass> Classes;
    List<string> Names;
    bool IgnoreCase;
    bool Multiline;
    string Error;
    int ErrorPos;

    static _RegexParser Create(string pattern)
    {
        var p = _RegexParser { Pattern = pattern, Nodes = List<_RNode>.Create(), Classes = List<_RClass>.Create(),
                               Names = List<string>.Create(), Error = "" };
        p.Names.Add(""); // group 0
        return p;
    }

    int ParseAll()
    {
        // inline flags at the start: (?i) (?m) (?im)
        if (Pattern.StartsWith("(?"))
        {
            int k = 2;
            bool flags = false;
            bool ic = false;
            bool ml = false;
            while (k < Pattern.Length && (Pattern[k] == 'i' || Pattern[k] == 'm'))
            {
                if (Pattern[k] == 'i')
                    ic = true;
                else
                    ml = true;
                k += 1;
                flags = true;
            }
            if (flags && k < Pattern.Length && Pattern[k] == ')')
            {
                IgnoreCase = ic;
                Multiline = ml;
                Pos = k + 1;
            }
        }
        int root = ParseAlt();
        if (Error.Length == 0 && Pos < Pattern.Length)
            Fail(Pattern[Pos] == ')' ? "')' without '('" : "unexpected '" + Pattern[Pos].ToString() + "'");
        return root;
    }

    void Fail(string message)
    {
        if (Error.Length == 0)
        {
            Error = message;
            ErrorPos = Pos;
        }
    }

    int Add(_RKind kind, int value)
    {
        Nodes.Add(_RNode { Kind = kind, Value = value, Kids = List<int>.Create() });
        return Nodes.Count() - 1;
    }

    int ParseAlt()
    {
        int first = ParseConcat();
        if (Pos >= Pattern.Length || Pattern[Pos] != '|')
            return first;
        int alt = Add(_RKind.Alt, 0);
        Nodes.Get(alt).Kids.Add(first);
        while (Error.Length == 0 && Pos < Pattern.Length && Pattern[Pos] == '|')
        {
            Pos += 1;
            Nodes.Get(alt).Kids.Add(ParseConcat());
        }
        return alt;
    }

    int ParseConcat()
    {
        int concat = Add(_RKind.Concat, 0);
        while (Error.Length == 0 && Pos < Pattern.Length && Pattern[Pos] != '|' && Pattern[Pos] != ')')
            Nodes.Get(concat).Kids.Add(ParseRepeat());
        return concat;
    }

    int ParseRepeat()
    {
        int atom = ParseAtom();
        while (Error.Length == 0 && Pos < Pattern.Length)
        {
            char c = Pattern[Pos];
            int min = -1;
            int max = -1;
            if (c == '*')
            {
                min = 0;
                Pos += 1;
            }
            else if (c == '+')
            {
                min = 1;
                Pos += 1;
            }
            else if (c == '?')
            {
                min = 0;
                max = 1;
                Pos += 1;
            }
            else if (c == '{' && Counted(ref min, ref max))
            {
            }
            else
                return atom;
            if (Error.Length > 0)
                return atom;
            bool lazy = false;
            if (Pos < Pattern.Length && Pattern[Pos] == '?')
            {
                lazy = true;
                Pos += 1;
            }
            int r = Add(_RKind.Repeat, 0);
            var node = Nodes.Get(r);
            node.Min = min;
            node.Max = max;
            node.Lazy = lazy;
            node.Kids.Add(atom);
            Nodes.Set(r, node);
            atom = r;
        }
        return atom;
    }

    // {n} {n,} {n,m} at the position (moved past it); false (and nothing moved) if it is a plain '{'
    bool Counted(ref int min, ref int max)
    {
        int k = Pos + 1;
        int a = Number(ref k);
        if (a < 0)
            return false;
        int b = a;
        if (k < Pattern.Length && Pattern[k] == ',')
        {
            k += 1;
            b = Number(ref k);
            if (b < 0)
                b = -1; // {n,}
        }
        if (k >= Pattern.Length || Pattern[k] != '}')
            return false;
        Pos = k + 1;
        if (a > 1000 || b > 1000)
        {
            Fail("a repetition count above 1000");
            return true;
        }
        if (b >= 0 && b < a)
        {
            Fail("{n,m} with m < n");
            return true;
        }
        min = a;
        max = b;
        return true;
    }

    int Number(ref int k)
    {
        int start = k;
        int v = 0;
        while (k < Pattern.Length && Pattern[k] >= '0' && Pattern[k] <= '9' && k - start < 6)
        {
            v = v * 10 + ((int)Pattern[k] - 48);
            k += 1;
        }
        return k == start ? -1 : v;
    }

    int ParseAtom()
    {
        char c = Pattern[Pos];
        if (c == '(')
        {
            Pos += 1;
            int group = -1;
            if (Pattern.Substring(Pos).StartsWith("?:"))
                Pos += 2;
            else if (Pattern.Substring(Pos).StartsWith("?<") || Pattern.Substring(Pos).StartsWith("?P<"))
            {
                Pos += Pattern[Pos + 1] == 'P' ? 3 : 2;
                int close = Pattern.IndexOf('>', Pos);
                if (close < 0)
                {
                    Fail("the group name is not closed ('>')");
                    return Add(_RKind.Empty, 0);
                }
                string name = Pattern.Substring(Pos, close - Pos).ToString();
                if (name.Length == 0 || Names.Contains(name))
                {
                    Fail(name.Length == 0 ? "a group name is empty" : "the group name '" + name + "' is used twice");
                    return Add(_RKind.Empty, 0);
                }
                Pos = close + 1;
                group = Names.Count();
                Names.Add(name);
            }
            else if (Pos < Pattern.Length && Pattern[Pos] == '?')
            {
                Fail("(? is only supported as (?:...), (?<name>...) and flags (?i)/(?m) at the start");
                return Add(_RKind.Empty, 0);
            }
            else
            {
                group = Names.Count();
                Names.Add("");
            }
            int inner = ParseAlt();
            if (Error.Length > 0)
                return inner;
            if (Pos >= Pattern.Length || Pattern[Pos] != ')')
            {
                Fail("the group is not closed (')' is missing)");
                return inner;
            }
            Pos += 1;
            if (group < 0)
                return inner;
            int g = Add(_RKind.Group, group);
            Nodes.Get(g).Kids.Add(inner);
            return g;
        }
        if (c == '*' || c == '+' || c == '?')
        {
            Fail("'" + c.ToString() + "' has nothing to repeat");
            return Add(_RKind.Empty, 0);
        }
        if (c == '[')
            return ParseClass();
        if (c == '.')
        {
            Pos += 1;
            return Add(_RKind.Any, 0);
        }
        if (c == '^')
        {
            Pos += 1;
            return Add(_RKind.Assert, (int)_ROp.Bol);
        }
        if (c == '$')
        {
            Pos += 1;
            return Add(_RKind.Assert, (int)_ROp.Eol);
        }
        if (c == '\\')
            return ParseEscape();
        return Add(_RKind.Char, NextLiteral());
    }

    // a character of the pattern (decoded from UTF-8)
    int NextLiteral()
    {
        int size = 1;
        int cp = _RegexDecode(Pattern, Pos, ref size);
        Pos += size;
        return cp;
    }

    int ParseEscape()
    {
        Pos += 1; // '\'
        if (Pos >= Pattern.Length)
        {
            Fail("'\\' at the end of the pattern");
            return Add(_RKind.Empty, 0);
        }
        char e = Pattern[Pos];
        switch (e)
        {
        case 'b': Pos += 1; return Add(_RKind.Assert, (int)_ROp.WordB);
        case 'B': Pos += 1; return Add(_RKind.Assert, (int)_ROp.NotWordB);
        case 'A': Pos += 1; return Add(_RKind.Assert, (int)_ROp.Start);
        case 'z': Pos += 1; return Add(_RKind.Assert, (int)_ROp.End);
        default: break;
        }
        var ranges = List<int>.Create();
        bool negated = false;
        if (ShorthandClass(e, ranges, ref negated))
        {
            Pos += 1;
            Classes.Add(_RClass { Ranges = ranges.ToArray(), Negated = negated });
            return Add(_RKind.Class, Classes.Count() - 1);
        }
        int cp = EscapedChar();
        if (cp < 0)
            return Add(_RKind.Empty, 0);
        return Add(_RKind.Char, cp);
    }

    // \d \w \s \D \W \S: the ranges, and whether the set is the opposite
    static bool ShorthandClass(char e, List<int> ranges, ref bool negated)
    {
        char lower = e >= 'A' && e <= 'Z' ? (char)((int)e + 32) : e;
        if (lower != 'd' && lower != 'w' && lower != 's')
            return false;
        negated = e != lower;
        if (lower == 'd' || lower == 'w')
        {
            ranges.Add('0');
            ranges.Add('9');
        }
        if (lower == 'w')
        {
            ranges.Add('A');
            ranges.Add('Z');
            ranges.Add('a');
            ranges.Add('z');
            ranges.Add('_');
            ranges.Add('_');
        }
        if (lower == 's')
        {
            ranges.Add(9);   // \t \n \v \f \r
            ranges.Add(13);
            ranges.Add(' ');
            ranges.Add(' ');
        }
        return true;
    }

    // the character of an escape at the position (after the '\'; moved past it); -1 after an error
    int EscapedChar()
    {
        char e = Pattern[Pos];
        Pos += 1;
        switch (e)
        {
        case 'n': return 10;
        case 'r': return 13;
        case 't': return 9;
        case 'f': return 12;
        case 'v': return 11;
        case '0': return 0;
        case 'x': return HexEscape(2);
        case 'u': return HexEscape(4);
        default: break;
        }
        if (e >= '1' && e <= '9')
        {
            Pos -= 1;
            Fail("backreferences (\\1, ...) are not supported");
            return -1;
        }
        if ((e >= 'a' && e <= 'z') || (e >= 'A' && e <= 'Z'))
        {
            Pos -= 1;
            Fail("unknown escape '\\" + e.ToString() + "'");
            return -1;
        }
        Pos -= 1;
        return NextLiteral(); // \. \* \\ \/ ... and any other non-letter: the character itself
    }

    int HexEscape(int digits)
    {
        if (Pos + digits > Pattern.Length)
        {
            Fail("\\x needs 2 and \\u 4 hex digits");
            return -1;
        }
        int v = 0;
        for (var i = 0; i < digits; i += 1)
        {
            int d = Char.HexValue(Pattern[Pos + i]);
            if (d < 0)
            {
                Fail("\\x needs 2 and \\u 4 hex digits");
                return -1;
            }
            v = v * 16 + d;
        }
        Pos += digits;
        return v;
    }

    int ParseClass()
    {
        int open = Pos;
        Pos += 1; // [
        bool negated = false;
        if (Pos < Pattern.Length && Pattern[Pos] == '^')
        {
            negated = true;
            Pos += 1;
        }
        var ranges = List<int>.Create();
        bool first = true;
        while (true)
        {
            if (Pos >= Pattern.Length)
            {
                Pos = open;
                Fail("the set is not closed (']' is missing)");
                return Add(_RKind.Empty, 0);
            }
            char c = Pattern[Pos];
            if (c == ']' && !first)
            {
                Pos += 1;
                break;
            }
            first = false;
            int lo;
            if (c == '\\')
            {
                Pos += 1;
                if (Pos >= Pattern.Length)
                    continue;
                bool inner = false;
                var shorthand = List<int>.Create();
                if (ShorthandClass(Pattern[Pos], shorthand, ref inner))
                {
                    Pos += 1;
                    var add = inner ? Complement(shorthand) : shorthand;
                    foreach (var r in add)
                        ranges.Add(r);
                    continue;
                }
                if (Pattern[Pos] == 'b')
                {
                    Pos += 1;
                    lo = 8; // backspace in a set
                }
                else
                    lo = EscapedChar();
                if (lo < 0)
                    return Add(_RKind.Empty, 0);
            }
            else
                lo = NextLiteral();
            int hi = lo;
            if (Pos + 1 < Pattern.Length && Pattern[Pos] == '-' && Pattern[Pos + 1] != ']')
            {
                Pos += 1;
                if (Pattern[Pos] == '\\')
                {
                    Pos += 1;
                    hi = EscapedChar();
                    if (hi < 0)
                        return Add(_RKind.Empty, 0);
                }
                else
                    hi = NextLiteral();
                if (hi < lo)
                {
                    Fail("the range of a set is backwards");
                    return Add(_RKind.Empty, 0);
                }
            }
            ranges.Add(lo);
            ranges.Add(hi);
        }
        Classes.Add(_RClass { Ranges = ranges.ToArray(), Negated = negated });
        return Add(_RKind.Class, Classes.Count() - 1);
    }

    // the code points that are not in the ranges (for \D, \W, \S inside a set)
    static List<int> Complement(List<int> ranges)
    {
        // sort the pairs by their start (they are few)
        var pairs = List<int>.Create();
        foreach (var r in ranges)
            pairs.Add(r);
        for (var i = 0; i + 2 < pairs.Count(); i += 2)
        {
            for (var j = i + 2; j + 1 < pairs.Count(); j += 2)
            {
                if (pairs.Get(j) < pairs.Get(i))
                {
                    int a = pairs.Get(i);
                    int b = pairs.Get(i + 1);
                    pairs.Set(i, pairs.Get(j));
                    pairs.Set(i + 1, pairs.Get(j + 1));
                    pairs.Set(j, a);
                    pairs.Set(j + 1, b);
                }
            }
        }
        var result = List<int>.Create();
        int next = 0;
        for (var i = 0; i + 1 < pairs.Count(); i += 2)
        {
            if (pairs.Get(i) > next)
            {
                result.Add(next);
                result.Add(pairs.Get(i) - 1);
            }
            if (pairs.Get(i + 1) + 1 > next)
                next = pairs.Get(i + 1) + 1;
        }
        result.Add(next);
        result.Add(0x10FFFF);
        return result;
    }

    // ---- instructions ----

    // appends the code of node n; false if the program grows too large
    bool Emit(List<_RInst> prog, int n)
    {
        if (prog.Count() > 200000)
            return false;
        var node = Nodes.Get(n);
        switch (node.Kind)
        {
        case _RKind.Empty:
            return true;
        case _RKind.Char:
            prog.Add(_RInst { Op = _ROp.Char, A = node.Value });
            return true;
        case _RKind.Any:
            prog.Add(_RInst { Op = _ROp.Any });
            return true;
        case _RKind.Class:
            prog.Add(_RInst { Op = _ROp.Class, A = node.Value });
            return true;
        case _RKind.Assert:
            prog.Add(_RInst { Op = (_ROp)node.Value });
            return true;
        case _RKind.Concat:
        {
            for (var i = 0; i < node.Kids.Count(); i += 1)
            {
                if (!Emit(prog, node.Kids.Get(i)))
                    return false;
            }
            return true;
        }
        case _RKind.Group:
            prog.Add(_RInst { Op = _ROp.Save, A = node.Value * 2 });
            if (!Emit(prog, node.Kids.Get(0)))
                return false;
            prog.Add(_RInst { Op = _ROp.Save, A = node.Value * 2 + 1 });
            return true;
        case _RKind.Alt:
        {
            var jumps = List<int>.Create();
            int count = node.Kids.Count();
            for (var i = 0; i < count; i += 1)
            {
                if (i < count - 1)
                {
                    int split = prog.Count();
                    prog.Add(_RInst { Op = _ROp.Split, A = split + 1 });
                    if (!Emit(prog, node.Kids.Get(i)))
                        return false;
                    jumps.Add(prog.Count());
                    prog.Add(_RInst { Op = _ROp.Jmp });
                    Patch(prog, split, split + 1, prog.Count());
                }
                else if (!Emit(prog, node.Kids.Get(i)))
                    return false;
            }
            foreach (var j in jumps)
                Patch(prog, j, prog.Count(), 0);
            return true;
        }
        default:
        {
            // repetition: the required copies, then a loop (no limit) or optional copies
            int kid = node.Kids.Get(0);
            for (var i = 0; i < node.Min; i += 1)
            {
                if (!Emit(prog, kid))
                    return false;
            }
            if (node.Max < 0)
            {
                int loop = prog.Count();
                prog.Add(_RInst { Op = _ROp.Split });
                if (!Emit(prog, kid))
                    return false;
                prog.Add(_RInst { Op = _ROp.Jmp, A = loop });
                int after = prog.Count();
                if (node.Lazy)
                    Patch(prog, loop, after, loop + 1);
                else
                    Patch(prog, loop, loop + 1, after);
                return true;
            }
            var splits = List<int>.Create();
            for (var i = node.Min; i < node.Max; i += 1)
            {
                splits.Add(prog.Count());
                prog.Add(_RInst { Op = _ROp.Split });
                if (!Emit(prog, kid))
                    return false;
            }
            int end = prog.Count();
            foreach (var sp in splits)
            {
                if (node.Lazy)
                    Patch(prog, sp, end, sp + 1);
                else
                    Patch(prog, sp, sp + 1, end);
            }
            return true;
        }
        }
    }

    static void Patch(List<_RInst> prog, int at, int a, int b)
    {
        var inst = prog.Get(at);
        inst.A = a;
        if (inst.Op == _ROp.Split)
            inst.B = b;
        prog.Set(at, inst);
    }
}
