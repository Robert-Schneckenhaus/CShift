// Errors in members, static calls, string and number methods, indexing, slices, 'new' and initializers, all in one run.
// expect-error: err_several_members.csh:30:28: error: struct 'Point' has no field 'Z'
// expect-error: err_several_members.csh:31:21: error: enum 'Color' has no member 'Blue'
// expect-error: err_several_members.csh:32:25: error: struct 'Point' has no field 'Width'
// expect-error: err_several_members.csh:33:13: error: Console has no function 'Print'
// expect-error: err_several_members.csh:35:15: error: type 'string' has no method 'Lenght'
// expect-error: err_several_members.csh:36:16: error: no matching function for call 'Contains(string, bool)': argument 2: cannot convert 'bool' to 'char'
// expect-error: err_several_members.csh:37:21: error: 'Point.Sum' is an instance method and needs an object
// expect-error: err_several_members.csh:38:34: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_members.csh:39:23: error: an index must be an integer, not 'string'
// expect-error: err_several_members.csh:40:17: error: cannot slice a value of type 'int32' (only arrays, strings and slices)
// expect-error: err_several_members.csh:41:15: error: 'new' can only create structs and arrays, not 'int32'
// expect-error: err_several_members.csh:42:29: error: the number format 'X2' is only for integers

using System;

enum Color : uint8 { Red, Green }

struct Point
{
    int X;
    int Y;

    static Point Origin() { return Point { }; }
    int Sum() { return X + Y; }
}

int Main()
{
    var p = Point { X = 1, Z = 2 };
    Color c = Color.Blue;
    Console.WriteLine(p.Width);
    Console.Print("x");
    string s = "text";
    int n = s.Lenght();
    bool b = s.Contains(true);
    Point q = Point.Sum();
    int[] items = new int[] { 1, "two" };
    int first = items["0"];
    var part = n[1..2];
    var obj = new int();
    string t = 3.5.ToString("X2");
    return p.X;
}
