// A small JSON reader for project files (cshift.json). Values live in an arena (a list of nodes) and are referred to
// by their index, because a struct cannot contain itself.

namespace CShift.Driver;

using System;

enum JsonKind : int32 { Null, Bool, Number, String, Array, Object }

struct JsonNode
{
    JsonKind Kind;
    string Text;         // String: the value, Number: the digits as written
    bool Flag;           // Bool
    List<int> Items;     // Array: the elements; Object: the values
    List<string> Keys;   // Object: the keys (same order as Items)
}

struct Json
{
    List<JsonNode> Nodes;
    string Source;
    int[] Pos;            // the reader position (a cell so that copies share it)

    static Json Create(string source)
    {
        return Json { Nodes = List<JsonNode>.Create(), Source = source, Pos = new int[1] };
    }

    JsonKind KindOf(int node)
    {
        return Nodes.Get(node).Kind;
    }

    // The value of a key of an object, -1 if there is none.
    int Get(int node, string key)
    {
        var n = Nodes.Get(node);
        if (n.Kind != JsonKind.Object)
            return -1;
        for (var i = 0; i < n.Keys.Count(); i += 1)
            if (n.Keys.Get(i) == key)
                return n.Items.Get(i);
        return -1;
    }

    string Text(int node)
    {
        return Nodes.Get(node).Text;
    }

    // ---- reading ----

    string Where()
    {
        int line = 1;
        int col = 1;
        for (var i = 0; i < Pos[0] && i < Source.Length; i += 1)
        {
            if (Source[i] == '\n')
            {
                line += 1;
                col = 1;
            }
            else
            {
                col += 1;
            }
        }
        return "line " + line.ToString() + ", column " + col.ToString();
    }

    void SkipSpace()
    {
        while (Pos[0] < Source.Length)
        {
            char c = Source[Pos[0]];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
                Pos[0] += 1;
            else
                break;
        }
    }

    Error<int> ParseDocument()
    {
        SkipSpace();
        int root = try ParseValue();
        SkipSpace();
        if (Pos[0] < Source.Length)
            return error("unexpected text after the value at " + Where());
        return root;
    }

    int Add(JsonNode node)
    {
        Nodes.Add(node);
        return Nodes.Count() - 1;
    }

    bool Match(string word)
    {
        if (Pos[0] + word.Length > Source.Length)
            return false;
        if (Source.Substring(Pos[0], word.Length) != word)
            return false;
        Pos[0] += word.Length;
        return true;
    }

    Error<int> ParseValue()
    {
        SkipSpace();
        if (Pos[0] >= Source.Length)
            return error("unexpected end of the text");
        char c = Source[Pos[0]];
        if (c == '{')
            return ParseObject();
        if (c == '[')
            return ParseArray();
        if (c == '"')
        {
            string s = try ParseString();
            return Add(JsonNode { Kind = JsonKind.String, Text = s });
        }
        if (Match("true"))
            return Add(JsonNode { Kind = JsonKind.Bool, Flag = true });
        if (Match("false"))
            return Add(JsonNode { Kind = JsonKind.Bool });
        if (Match("null"))
            return Add(JsonNode { Kind = JsonKind.Null });
        if (c == '-' || (c >= '0' && c <= '9'))
        {
            int start = Pos[0];
            Pos[0] += 1;
            while (Pos[0] < Source.Length)
            {
                char d = Source[Pos[0]];
                if ((d >= '0' && d <= '9') || d == '.' || d == 'e' || d == 'E' || d == '+' || d == '-')
                    Pos[0] += 1;
                else
                    break;
            }
            return Add(JsonNode { Kind = JsonKind.Number, Text = Source.Substring(start, Pos[0] - start) });
        }
        return error("unexpected character '" + c.ToString() + "' at " + Where());
    }

    Error<int> ParseObject()
    {
        Pos[0] += 1; // {
        var node = JsonNode { Kind = JsonKind.Object, Items = List<int>.Create(), Keys = List<string>.Create() };
        SkipSpace();
        if (Pos[0] < Source.Length && Source[Pos[0]] == '}')
        {
            Pos[0] += 1;
            return Add(node);
        }
        while (true)
        {
            SkipSpace();
            if (Pos[0] >= Source.Length || Source[Pos[0]] != '"')
                return error("a string (the key) is expected at " + Where());
            string key = try ParseString();
            SkipSpace();
            if (Pos[0] >= Source.Length || Source[Pos[0]] != ':')
                return error("':' is expected at " + Where());
            Pos[0] += 1;
            int value = try ParseValue();
            node.Keys.Add(key);
            node.Items.Add(value);
            SkipSpace();
            if (Pos[0] < Source.Length && Source[Pos[0]] == ',')
            {
                Pos[0] += 1;
                continue;
            }
            if (Pos[0] < Source.Length && Source[Pos[0]] == '}')
            {
                Pos[0] += 1;
                return Add(node);
            }
            return error("',' or '}' is expected at " + Where());
        }
        return error("unreachable");
    }

    Error<int> ParseArray()
    {
        Pos[0] += 1; // [
        var node = JsonNode { Kind = JsonKind.Array, Items = List<int>.Create() };
        SkipSpace();
        if (Pos[0] < Source.Length && Source[Pos[0]] == ']')
        {
            Pos[0] += 1;
            return Add(node);
        }
        while (true)
        {
            int value = try ParseValue();
            node.Items.Add(value);
            SkipSpace();
            if (Pos[0] < Source.Length && Source[Pos[0]] == ',')
            {
                Pos[0] += 1;
                continue;
            }
            if (Pos[0] < Source.Length && Source[Pos[0]] == ']')
            {
                Pos[0] += 1;
                return Add(node);
            }
            return error("',' or ']' is expected at " + Where());
        }
        return error("unreachable");
    }

    static int HexValue(char c)
    {
        if (c >= '0' && c <= '9')
            return (int)c - 48;
        if (c >= 'a' && c <= 'f')
            return (int)c - 87;
        if (c >= 'A' && c <= 'F')
            return (int)c - 55;
        return -1;
    }

    Error<string> ParseString()
    {
        Pos[0] += 1; // the opening quote
        var sb = StringBuilder.Create();
        while (Pos[0] < Source.Length)
        {
            char c = Source[Pos[0]];
            Pos[0] += 1;
            if (c == '"')
                return sb.ToString();
            if (c != '\\')
            {
                sb.Append(c);
                continue;
            }
            if (Pos[0] >= Source.Length)
                break;
            char e = Source[Pos[0]];
            Pos[0] += 1;
            if (e == 'n')
                sb.Append('\n');
            else if (e == 't')
                sb.Append('\t');
            else if (e == 'r')
                sb.Append('\r');
            else if (e == 'b')
                sb.Append((char)8);
            else if (e == 'f')
                sb.Append((char)12);
            else if (e == 'u')
            {
                // only the characters up to U+00FF are kept as one byte, others become '?'
                if (Pos[0] + 4 > Source.Length)
                    break;
                int code = 0;
                for (var k = 0; k < 4; k += 1)
                {
                    int h = HexValue(Source[Pos[0] + k]);
                    if (h < 0)
                        return error("invalid \\u escape at " + Where());
                    code = code * 16 + h;
                }
                Pos[0] += 4;
                sb.Append(code < 256 ? (char)code : '?');
            }
            else
                sb.Append(e); // \" \\ \/
        }
        return error("the string is not terminated at " + Where());
    }
}
