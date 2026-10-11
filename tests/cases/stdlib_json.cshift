// JSON: Json.Parse (strings with escapes, numbers, nesting, errors with line and column), JsonValue built in code,
// compact and indented text, objects in the order of their keys.
// expect-stdout: Ann 30 -1500 true
// expect-stdout: tags a,b
// expect-stdout: {"name":"Ann","tags":["a","b"],"age":30,"x":-1500,"u":"ä😀\n","n":null,"t":true}
// expect-stdout: missing null true, has name true
// expect-stdout: {
// expect-stdout:   "ok": true,
// expect-stdout:   "list": [
// expect-stdout:     1.5,
// expect-stdout:     "q\"uote"
// expect-stdout:   ],
// expect-stdout:   "empty": {}
// expect-stdout: }
// expect-stdout: keys ok,empty count 2
// expect-stdout: round trip true
// expect-stdout: invalid JSON at line 1, column 4: unexpected character ']'
// expect-stdout: invalid JSON at line 2, column 6: ':' expected after the key
// expect-stdout: invalid JSON at line 1, column 2: a number cannot start with 0
// expect-stdout: invalid JSON at line 1, column 1: the string is not closed
// expect-stdout: invalid JSON at line 1, column 5: unexpected text after the value
// expect-stdout: invalid JSON at line 1, column 2: unknown escape '\x'
// expect-stdout: too deep TooDeep
using System;

int Main()
{
    var doc = try Json.Parse("{\"name\": \"Ann\", \"tags\": [\"a\", \"b\"], \"age\": 30, \"x\": -1.5e3, " +
                             "\"u\": \"\\u00e4\\ud83d\\ude00\\n\", \"n\": null, \"t\": true}");
    Console.WriteLine(doc["name"].AsString() + " " + doc["age"].AsInt().ToString() + " " + doc["x"].AsNumber().ToString() + " " +
                      doc["t"].AsBool().ToString());
    var tags = List<string>.Create();
    foreach (var tag in doc["tags"].Items())
        tags.Add(tag.AsString());
    Console.WriteLine("tags " + string.Join(",", tags.ToArray()));
    Console.WriteLine(doc.ToString());
    Console.WriteLine("missing " + doc["missing"]["deeper"].Kind.ToString().ToLower() + " " + doc["n"].IsNull().ToString() +
                      ", has name " + doc.Has("name").ToString());

    var o = JsonValue.NewObject();
    o.Set("ok", JsonValue.Bool(true));
    o.Set("list", JsonValue.NewArray());
    o["list"].Add(JsonValue.Number(1.5));
    o["list"].Add(JsonValue.String("q\"uote"));
    o.Set("gone", JsonValue.Null());
    o.Set("empty", JsonValue.NewObject());
    o.Remove("gone");
    Console.WriteLine(o.ToIndentedString());
    o.Remove("list");
    Console.WriteLine("keys " + string.Join(",", o.Keys()) + " count " + o.Count().ToString());

    var again = try Json.Parse(doc.ToIndentedString(4));
    Console.WriteLine("round trip " + (again.ToString() == doc.ToString()).ToString());

    string[] bad = ["[1,]", "{\"a\": 1,\n \"b\" 2}", "01", "\"abc", "[1] x", "\"\\x\""];
    foreach (var b in bad)
    {
        if (Json.Parse(b) is error e)
            Console.WriteLine(e.Message);
    }
    var deep = StringBuilder.Create();
    for (var i = 0; i < 600; i += 1)
        deep.Append('[');
    switch (Json.Parse(deep.ToString()))
    {
    case JsonValue v:
        Console.WriteLine("parsed?");
        break;
    case JsonError.TooDeep:
        Console.WriteLine("too deep TooDeep");
        break;
    case error e:
        Console.WriteLine(e.Message);
        break;
    }
    return 0;
}
