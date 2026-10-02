// cshiftc query: the members that the language provides (a hover with the doc comment of stdlib/builtin, no definition).
// query: 16 28 => "hover": "int32 int32[].Length"
// query: 16 54 => "hover": "int32 string.Length"
// query: 16 76 => "hover": "int32 Fixed<int32, 3>.Length = 3"
// query: 17 46 => "hover": "string Error<int32>.Message"
// query: 16 28 => {"hover": "int32 int32[].Length", "doc": "The number of elements."}
// query: 16 54 => "doc": "The length in bytes (not in characters: UTF-8 uses 1 to 4 bytes per character)."
// query: 17 46 => "doc": "The message of the error."

using System;

int Main()
{
    int[] nums = [1, 2];
    Fixed<int, 3> f = [1, 2, 3];
    Console.WriteLine(nums.Length.ToString() + "Ann".Length.ToString() + f.Length.ToString());
    Error<int> r = error("no"); string m = r.Message;
    return m.Length;
}
