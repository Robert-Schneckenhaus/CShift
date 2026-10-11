// dict[key] for a key that is not present panics (TryGet asks without panicking).
// expect-exit: 101
// expect-stderr: the key is not present in the Dictionary

using System;

int Main()
{
    var ages = Dictionary<string, int>.Create();
    ages["Ann"] = 41;
    return ages["Bob"];
}
