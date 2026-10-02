namespace System;

/// The kind of a [JsonValue].
enum JsonKind : uint8
{
    /// `null`.
    Null = 0,
    /// `true` or `false`.
    Bool = 1,
    /// A number (a `double`).
    Number = 2,
    /// A string.
    String = 3,
    /// An array of values.
    Array = 4,
    /// An object: keys and their values, in the order in which they were added.
    Object = 5
}

/// The errors of [Json.Parse]; the message says where the problem is (line and column).
error JsonError
{
    /// The text is not valid JSON.
    InvalidSyntax = 1,
    /// More than 512 nested arrays and objects.
    TooDeep = 2
}

/// Reading (Json.Parse), building and writing (JsonValue.ToString / ToIndentedString).
///
/// ```
/// var doc = try Json.Parse("{\"name\": \"Ann\", \"tags\": [\"a\", \"b\"], \"age\": 30}");
/// string name = doc["name"].AsString();          // "Ann"
/// int age = doc["age"].AsInt();                    // 30
/// foreach (var tag in doc["tags"].Items())         // the elements of an array
///     Console.WriteLine(tag.AsString());
///
/// var o = JsonValue.NewObject();
/// o.Set("ok", JsonValue.Bool(true));
/// o.Set("list", JsonValue.NewArray());
/// o["list"].Add(JsonValue.Number(1.5));
/// Console.WriteLine(o.ToString());                 // {"ok":true,"list":[1.5]}
/// ```
///
/// A JsonValue is a small struct: copies of an array or object share its elements (like List<T>). Objects keep the
/// order in which their keys were added. Numbers are doubles. Asking a missing key of an object gives a JSON null, so
/// chains like doc["a"]["b"] need no checks in between; AsString(), AsInt(), ... end the program with a panic if the
/// value has another kind (check it with IsString(), Kind, ...).
struct JsonValue
{
    /// The kind of the value: null, bool, number, string, array or object.
    JsonKind Kind;
    bool _bool;
    double _number;
    string _string;
    List<JsonValue> _items;                  // an array
    List<string> _keys;                      // an object: the keys in their order
    Dictionary<string, JsonValue> _fields;   // an object: the values

    /// The JSON value `null`.
    static JsonValue Null()
    {
        return JsonValue { Kind = JsonKind.Null };
    }

    /// The JSON value `true` or `false`.
    static JsonValue Bool(bool value)
    {
        return JsonValue { Kind = JsonKind.Bool, _bool = value };
    }

    /// A JSON number.
    static JsonValue Number(double value)
    {
        return JsonValue { Kind = JsonKind.Number, _number = value };
    }

    /// A JSON string.
    static JsonValue String(string value)
    {
        return JsonValue { Kind = JsonKind.String, _string = value };
    }

    /// A new, empty array ([JsonValue.Add] appends elements).
    static JsonValue NewArray()
    {
        return JsonValue { Kind = JsonKind.Array, _items = List<JsonValue>.Create() };
    }

    /// A new, empty object ([JsonValue.Set] adds members).
    static JsonValue NewObject()
    {
        return JsonValue { Kind = JsonKind.Object, _keys = List<string>.Create(), _fields = Dictionary<string, JsonValue>.Create() };
    }

    /// Whether the value is `null` (also a missing member of an object).
    bool IsNull() { return Kind == JsonKind.Null; }
    /// Whether the value is `true` or `false`.
    bool IsBool() { return Kind == JsonKind.Bool; }
    /// Whether the value is a number.
    bool IsNumber() { return Kind == JsonKind.Number; }
    /// Whether the value is a string.
    bool IsString() { return Kind == JsonKind.String; }
    /// Whether the value is an array.
    bool IsArray() { return Kind == JsonKind.Array; }
    /// Whether the value is an object.
    bool IsObject() { return Kind == JsonKind.Object; }

    /// The value of a bool.
    /// @panics when the value is not a bool.
    bool AsBool()
    {
        _Expect(JsonKind.Bool, "AsBool");
        return _bool;
    }

    /// The value of a number.
    /// @panics when the value is not a number.
    double AsNumber()
    {
        _Expect(JsonKind.Number, "AsNumber");
        return _number;
    }

    /// The value of a number as an `int`.
    /// @panics when the value is not a number, not a whole number or not in the range of `int`.
    int AsInt()
    {
        _Expect(JsonKind.Number, "AsInt");
        if (_number != Math.Floor(_number) || _number < -2147483648.0 || _number > 2147483647.0)
            Environment.Panic("JsonValue.AsInt: " + _number.ToString() + " is not a whole number in the range of int");
        return (int)_number;
    }

    /// The value of a number as an `int64`.
    /// @panics when the value is not a number, not a whole number or not in the range of `int64`.
    int64 AsInt64()
    {
        _Expect(JsonKind.Number, "AsInt64");
        if (_number != Math.Floor(_number) || _number < -9223372036854775808.0 || _number >= 9223372036854775808.0)
            Environment.Panic("JsonValue.AsInt64: " + _number.ToString() + " is not a whole number in the range of int64");
        return (int64)_number;
    }

    /// The text of a string.
    /// @panics when the value is not a string.
    string AsString()
    {
        _Expect(JsonKind.String, "AsString");
        return _string;
    }

    void _Expect(JsonKind kind, string method)
    {
        if (Kind != kind)
            Environment.Panic("JsonValue." + method + ": the value is " + _KindName(Kind) + ", not " + _KindName(kind));
    }

    static string _KindName(JsonKind kind)
    {
        switch (kind)
        {
        case JsonKind.Null: return "null";
        case JsonKind.Bool: return "a bool";
        case JsonKind.Number: return "a number";
        case JsonKind.String: return "a string";
        case JsonKind.Array: return "an array";
        default: return "an object";
        }
    }

    /// The number of elements of an array or members of an object (0 for the other kinds).
    int Count()
    {
        if (Kind == JsonKind.Array)
            return _items.Count();
        if (Kind == JsonKind.Object)
            return _keys.Count();
        return 0;
    }

    // ---- arrays ----

    /// Element `index` of an array (also `value[index]`).
    /// @panics when the value is not an array or `index` is outside of it.
    JsonValue Get(int index)
    {
        _Expect(JsonKind.Array, "Get(int)");
        if (index < 0 || index >= _items.Count())
            Environment.Panic("JsonValue.Get: index " + index.ToString() + " is outside the array (" + _items.Count().ToString() + " elements)");
        return _items.Get(index);
    }

    /// Replaces element `index` of an array (also `value[index] = x`).
    /// @panics when the value is not an array or `index` is outside of it.
    void Set(int index, JsonValue value)
    {
        _Expect(JsonKind.Array, "Set(int)");
        if (index < 0 || index >= _items.Count())
            Environment.Panic("JsonValue.Set: index " + index.ToString() + " is outside the array (" + _items.Count().ToString() + " elements)");
        _items.Set(index, value);
    }

    /// Appends `value` to an array.
    /// @panics when the value is not an array.
    void Add(JsonValue value)
    {
        _Expect(JsonKind.Array, "Add");
        _items.Add(value);
    }

    /// The elements of an array (none for the other kinds).
    JsonValue[] Items()
    {
        if (Kind != JsonKind.Array)
            return new JsonValue[0];
        return _items.ToArray();
    }

    // ---- objects ----

    /// The member `key` of an object (also `value["key"]`).
    /// @returns the JSON `null` if there is no such member (also for the other kinds), so chains like `doc["a"]["b"]`
    /// need no checks in between.
    JsonValue Get(string key)
    {
        if (Kind != JsonKind.Object)
            return JsonValue.Null();
        var found = _fields.TryGet(key);
        if (found is JsonValue v)
            return v;
        return JsonValue.Null();
    }

    /// Whether an object has the member `key` (`false` for the other kinds).
    bool Has(string key)
    {
        return Kind == JsonKind.Object && _fields.ContainsKey(key);
    }

    /// Adds or replaces the member `key` of an object (also `value["key"] = x`).
    /// @panics when the value is not an object.
    void Set(string key, JsonValue value)
    {
        _Expect(JsonKind.Object, "Set(string)");
        if (!_fields.ContainsKey(key))
            _keys.Add(key);
        _fields.Set(key, value);
    }

    /// Removes the member `key` of an object (nothing happens if it has none).
    /// @panics when the value is not an object.
    void Remove(string key)
    {
        _Expect(JsonKind.Object, "Remove");
        if (!_fields.ContainsKey(key))
            return;
        _fields.Remove(key);
        _keys.RemoveAt(_keys.IndexOf(key));
    }

    /// The keys of an object in their order (none for the other kinds).
    string[] Keys()
    {
        if (Kind != JsonKind.Object)
            return new string[0];
        return _keys.ToArray();
    }

    // ---- text ----

    /// The value as compact JSON text: `{"ok":true,"list":[1.5]}`.
    string ToString()
    {
        var sb = StringBuilder.Create();
        _Write(sb, -1, 0);
        return sb.ToString();
    }

    /// The value as JSON text with line breaks and `indent` spaces per level.
    string ToIndentedString(int indent)
    {
        var sb = StringBuilder.Create();
        _Write(sb, indent < 0 ? 0 : indent, 0);
        return sb.ToString();
    }

    /// The value as JSON text with line breaks and 2 spaces per level.
    string ToIndentedString()
    {
        return ToIndentedString(2);
    }

    // indent < 0: compact
    void _Write(StringBuilder sb, int indent, int level)
    {
        switch (Kind)
        {
        case JsonKind.Null:
            sb.Append("null");
            break;
        case JsonKind.Bool:
            sb.Append(_bool ? "true" : "false");
            break;
        case JsonKind.Number:
            _WriteNumber(sb, _number);
            break;
        case JsonKind.String:
            _WriteString(sb, _string);
            break;
        case JsonKind.Array:
        {
            int n = _items.Count();
            if (n == 0)
            {
                sb.Append("[]");
                break;
            }
            sb.Append('[');
            for (var i = 0; i < n; i += 1)
            {
                if (i > 0)
                    sb.Append(',');
                _NewLine(sb, indent, level + 1);
                _items.Get(i)._Write(sb, indent, level + 1);
            }
            _NewLine(sb, indent, level);
            sb.Append(']');
            break;
        }
        default:
        {
            int n = _keys.Count();
            if (n == 0)
            {
                sb.Append("{}");
                break;
            }
            sb.Append('{');
            for (var i = 0; i < n; i += 1)
            {
                if (i > 0)
                    sb.Append(',');
                _NewLine(sb, indent, level + 1);
                string key = _keys.Get(i);
                _WriteString(sb, key);
                sb.Append(indent >= 0 ? ": " : ":");
                _fields.Get(key)._Write(sb, indent, level + 1);
            }
            _NewLine(sb, indent, level);
            sb.Append('}');
            break;
        }
        }
    }

    static void _NewLine(StringBuilder sb, int indent, int level)
    {
        if (indent < 0)
            return;
        sb.Append('\n');
        for (var i = 0; i < indent * level; i += 1)
            sb.Append(' ');
    }

    // NaN and the infinities have no JSON form: null
    static void _WriteNumber(StringBuilder sb, double v)
    {
        if (v != v || v - v != 0.0)
        {
            sb.Append("null");
            return;
        }
        sb.Append(v.ToString());
    }

    static void _WriteString(StringBuilder sb, string s)
    {
        sb.Append('"');
        for (var i = 0; i < s.Length; i += 1)
        {
            char c = s[i];
            int code = (int)c;
            if (c == '"')
                sb.Append("\\\"");
            else if (c == '\\')
                sb.Append("\\\\");
            else if (c == '\n')
                sb.Append("\\n");
            else if (c == '\r')
                sb.Append("\\r");
            else if (c == '\t')
                sb.Append("\\t");
            else if (code < 32)
            {
                sb.Append("\\u00");
                sb.Append(_HexDigit(code >> 4));
                sb.Append(_HexDigit(code & 15));
            }
            else
                sb.Append(c); // UTF-8 bytes as they are
        }
        sb.Append('"');
    }

    static char _HexDigit(int d)
    {
        return d < 10 ? (char)(48 + d) : (char)(87 + d);
    }
}

/// Reading JSON text: see [Json.Parse] and [JsonValue].
struct Json
{
    /// Reads JSON text (RFC 8259): objects, arrays, strings (with `\u` escapes), numbers, `true`, `false` and `null`.
    /// @error JsonError.InvalidSyntax the text is not valid JSON; the message says where (line and column).
    /// @error JsonError.TooDeep more than 512 nested arrays and objects.
    static JsonError<JsonValue> Parse(StringSlice text)
    {
        var p = _JsonParser { Text = text, Pos = 0 };
        p.SkipSpace();
        var value = try p.ParseDocument();
        p.SkipSpace();
        if (p.Pos < text.Length)
            return p.Fail("unexpected text after the value");
        return value;
    }
}

struct _JsonParser
{
    StringSlice Text;
    int Pos;

    JsonError<JsonValue> Fail(string what)
    {
        return error(Where(what), JsonError.InvalidSyntax);
    }

    // the message for an error at the position
    string Where(string what)
    {
        // line and column of the position (1-based, columns in bytes)
        int line = 1;
        int col = 1;
        for (var i = 0; i < Pos && i < Text.Length; i += 1)
        {
            if (Text[i] == '\n')
            {
                line += 1;
                col = 1;
            }
            else
                col += 1;
        }
        return "invalid JSON at line " + line.ToString() + ", column " + col.ToString() + ": " + what;
    }

    void SkipSpace()
    {
        while (Pos < Text.Length)
        {
            char c = Text[Pos];
            if (c != ' ' && c != '\t' && c != '\n' && c != '\r')
                return;
            Pos += 1;
        }
    }

    bool Literal(string word)
    {
        if (Pos + word.Length > Text.Length)
            return false;
        for (var i = 0; i < word.Length; i += 1)
        {
            if (Text[Pos + i] != word[i])
                return false;
        }
        Pos += word.Length;
        return true;
    }

    // The document: an explicit stack of the open arrays and objects (no recursion, so the nesting does not depend on
    // the size of the program's stack).
    JsonError<JsonValue> ParseDocument()
    {
        var open = List<JsonValue>.Create();   // the arrays and objects that are not closed yet
        var keys = List<string>.Create();      // per open object: the key of the value that comes next
        while (true)
        {
            SkipSpace();
            if (Pos >= Text.Length)
                return Fail(open.Count() > 0 ? "a value is missing (the text ends)" : "a value is missing");
            char c = Text[Pos];
            JsonValue value;
            if (c == '{' || c == '[')
            {
                if (open.Count() >= 512)
                    return error("invalid JSON: more than 512 nested arrays and objects", JsonError.TooDeep);
                Pos += 1;
                var container = c == '{' ? JsonValue.NewObject() : JsonValue.NewArray();
                SkipSpace();
                char close = c == '{' ? '}' : ']';
                if (Pos < Text.Length && Text[Pos] == close)
                {
                    Pos += 1;
                    value = container; // empty
                }
                else
                {
                    open.Add(container);
                    keys.Add("");
                    if (c == '{')
                    {
                        var key = try ParseKey();
                        keys.Set(keys.Count() - 1, key);
                    }
                    continue; // the first element
                }
            }
            else if (c == '"')
            {
                var text = try ParseString();
                value = JsonValue.String(text);
            }
            else if (c == '-' || (c >= '0' && c <= '9'))
                value = try ParseNumber();
            else if (Literal("true"))
                value = JsonValue.Bool(true);
            else if (Literal("false"))
                value = JsonValue.Bool(false);
            else if (Literal("null"))
                value = JsonValue.Null();
            else
                return Fail("unexpected character '" + c.ToString() + "'");

            // the value is complete: it goes into the innermost open array or object; closing brackets complete those
            while (true)
            {
                int n = open.Count();
                if (n == 0)
                    return value;
                var top = open.Get(n - 1);
                if (top.IsArray())
                    top.Add(value);
                else
                    top.Set(keys.Get(n - 1), value);
                SkipSpace();
                if (Pos >= Text.Length)
                    return Fail(top.IsArray() ? "the array is not closed (']' is missing)" : "the object is not closed ('}' is missing)");
                char next = Text[Pos];
                if (next == ',')
                {
                    Pos += 1;
                    if (!top.IsArray())
                    {
                        var key = try ParseKey();
                        keys.Set(n - 1, key);
                    }
                    break; // the next element
                }
                if ((next == ']' && top.IsArray()) || (next == '}' && !top.IsArray()))
                {
                    Pos += 1;
                    open.RemoveAt(n - 1);
                    keys.RemoveAt(n - 1);
                    value = top;
                    continue;
                }
                return Fail(top.IsArray() ? "',' or ']' expected in the array" : "',' or '}' expected in the object");
            }
        }
    }

    // "key": in an object (moved past the ':')
    JsonError<string> ParseKey()
    {
        SkipSpace();
        if (Pos >= Text.Length || Text[Pos] != '"')
            return error(Where("a key (a string) expected in the object"), JsonError.InvalidSyntax);
        var key = try ParseString();
        SkipSpace();
        if (Pos >= Text.Length || Text[Pos] != ':')
            return error(Where("':' expected after the key"), JsonError.InvalidSyntax);
        Pos += 1;
        return key;
    }

    JsonError<string> ParseString()
    {
        int start = Pos;
        Pos += 1; // "
        var sb = StringBuilder.Create();
        while (true)
        {
            if (Pos >= Text.Length)
            {
                Pos = start;
                return error(Where("the string is not closed"), JsonError.InvalidSyntax);
            }
            char c = Text[Pos];
            if (c == '"')
            {
                Pos += 1;
                return sb.ToString();
            }
            if ((int)c < 32)
                return error(Where("a control character in a string (write it as \\n, \\t, \\u00XX, ...)"), JsonError.InvalidSyntax);
            if (c != '\\')
            {
                sb.Append(c);
                Pos += 1;
                continue;
            }
            if (Pos + 1 >= Text.Length)
                return error(Where("the string is not closed"), JsonError.InvalidSyntax);
            char e = Text[Pos + 1];
            Pos += 2;
            switch (e)
            {
            case '"': sb.Append('"'); break;
            case '\\': sb.Append('\\'); break;
            case '/': sb.Append('/'); break;
            case 'b': sb.Append((char)8); break;
            case 'f': sb.Append((char)12); break;
            case 'n': sb.Append('\n'); break;
            case 'r': sb.Append('\r'); break;
            case 't': sb.Append('\t'); break;
            case 'u':
            {
                int code = Hex4();
                if (code < 0)
                    return error(Where("\\u needs four hex digits"), JsonError.InvalidSyntax);
                if (code >= 0xD800 && code < 0xDC00)
                {
                    // a surrogate pair: 😀
                    if (Pos + 1 < Text.Length && Text[Pos] == '\\' && Text[Pos + 1] == 'u')
                    {
                        Pos += 2;
                        int low = Hex4();
                        if (low < 0xDC00 || low > 0xDFFF)
                            return error(Where("a high surrogate (\\uD800-\\uDBFF) must be followed by a low one"),
                                         JsonError.InvalidSyntax);
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                    }
                    else
                        return error(Where("a high surrogate (\\uD800-\\uDBFF) must be followed by a low one"),
                                     JsonError.InvalidSyntax);
                }
                else if (code >= 0xDC00 && code < 0xE000)
                    return error(Where("a low surrogate without a high one"), JsonError.InvalidSyntax);
                AppendUtf8(sb, code);
                break;
            }
            default:
                Pos -= 2;
                return error(Where("unknown escape '\\" + e.ToString() + "'"), JsonError.InvalidSyntax);
            }
        }
    }

    // four hex digits at the position (moved past them); -1 if they are not there
    int Hex4()
    {
        if (Pos + 4 > Text.Length)
            return -1;
        int v = 0;
        for (var i = 0; i < 4; i += 1)
        {
            int d = Char.HexValue(Text[Pos + i]);
            if (d < 0)
                return -1;
            v = v * 16 + d;
        }
        Pos += 4;
        return v;
    }

    static void AppendUtf8(StringBuilder sb, int code)
    {
        if (code < 0x80)
            sb.Append((char)code);
        else if (code < 0x800)
        {
            sb.Append((char)(0xC0 | (code >> 6)));
            sb.Append((char)(0x80 | (code & 0x3F)));
        }
        else if (code < 0x10000)
        {
            sb.Append((char)(0xE0 | (code >> 12)));
            sb.Append((char)(0x80 | ((code >> 6) & 0x3F)));
            sb.Append((char)(0x80 | (code & 0x3F)));
        }
        else
        {
            sb.Append((char)(0xF0 | (code >> 18)));
            sb.Append((char)(0x80 | ((code >> 12) & 0x3F)));
            sb.Append((char)(0x80 | ((code >> 6) & 0x3F)));
            sb.Append((char)(0x80 | (code & 0x3F)));
        }
    }

    // -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?
    JsonError<JsonValue> ParseNumber()
    {
        int start = Pos;
        if (Text[Pos] == '-')
            Pos += 1;
        if (Pos >= Text.Length || Text[Pos] < '0' || Text[Pos] > '9')
            return Fail("a digit expected");
        if (Text[Pos] == '0')
            Pos += 1;
        else
            Digits();
        if (Pos < Text.Length && Text[Pos] >= '0' && Text[Pos] <= '9')
            return Fail("a number cannot start with 0");
        if (Pos < Text.Length && Text[Pos] == '.')
        {
            Pos += 1;
            if (Digits() == 0)
                return Fail("digits expected after '.'");
        }
        if (Pos < Text.Length && (Text[Pos] == 'e' || Text[Pos] == 'E'))
        {
            Pos += 1;
            if (Pos < Text.Length && (Text[Pos] == '+' || Text[Pos] == '-'))
                Pos += 1;
            if (Digits() == 0)
                return Fail("digits expected in the exponent");
        }
        var parsed = Text[start..Pos].ToString().ParseDouble();
        if (parsed is double v)
            return JsonValue.Number(v);
        Pos = start;
        return Fail("the number is out of range");
    }

    int Digits()
    {
        int n = 0;
        while (Pos < Text.Length && Text[Pos] >= '0' && Text[Pos] <= '9')
        {
            Pos += 1;
            n += 1;
        }
        return n;
    }
}
