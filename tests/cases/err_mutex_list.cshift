// Mutex<T> copies its value in and out, so T must be copyable between threads (no arrays or containers).
// expect-error: Mutex<T> needs a value that can be copied between threads

using System;

int Main()
{
    var m = Mutex<List<int>>.Create(List<int>.Create());
    return 0;
}
