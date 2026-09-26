// A collection expression becomes an array, a slice or a struct with Create() and Add(T); Dictionary.Add takes two values.
// expect-error: a collection expression cannot become 'System.Dictionary<string,int32>': it needs 'static System.Dictionary<string,int32> Create()' and 'Add(T)'

using System;

int Main()
{
    Dictionary<string, int> ages = ["ann"];
    return 0;
}
