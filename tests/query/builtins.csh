// cshiftc query: the members that the language provides (a hover, no definition).
// query: 14 28 => "hover": "int32 int32[].Length"
// query: 14 54 => "hover": "int32 string.Length"
// query: 14 76 => "hover": "int32 Fixed<int32, 3>.Length = 3"
// query: 15 46 => "hover": "string Error<int32>.Message"
// query: 14 28 => {"hover": "int32 int32[].Length"}

using System;

int Main()
{
    int[] nums = [1, 2];
    Fixed<int, 3> f = [1, 2, 3];
    Console.WriteLine(nums.Length.ToString() + "Ann".Length.ToString() + f.Length.ToString());
    Error<int> r = error("no"); string m = r.Message;
    return m.Length;
}
