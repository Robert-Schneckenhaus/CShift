// cshiftc query: names where they are declared, the functions the language provides, types in a generic body.
// query: 20 6 => "hover": "void Load<T>(ref T slot, string name)"
// query: 20 20 => "hover": "(parameter) ref T slot"
// query: 20 33 => "hover": "(parameter) string name"
// query: 22 9 => "hover": "int32 x"
// query: 23 5 => "hover": "(parameter) ref T slot"
// query: 23 5 => "line": 20
// query: 24 5 => "hover": "static class Console"
// query: 24 13 => "hover": "static void Console.WriteLine(string)"
// query: 24 48 => "hover": "string int32.ToString()"
// query: 30 9 => "hover": "int32 Box.Twice(int32 factor)"
// query: 30 19 => "hover": "(parameter) int32 factor"
// query: 33 5 => "hover": "int32 Main()"
// query: 35 9 => "hover": "int32 count"
// query: 37 18 => "hover": "int32 item"
// query: 40 25 => "hover": "StringSlice String.Trim(StringSlice s)"
// query: 40 40 => "hover": "string int32.ToString()"
using System;

void Load<T>(ref T slot, string name)
{
    int x = 0;
    slot = default(T);
    Console.WriteLine("not found: " + name + x.ToString());
}

struct Box
{
    int Value;
    int Twice(int factor) { return Value * factor; }
}

int Main()
{
    int count = 5;
    var list = List<int>.Create();
    foreach (var item in list)
        count += item;
    string s = " a ";
    Console.WriteLine(s.Trim() + count.ToString());
    Load<int>(ref count, "x");
    return 0;
}
