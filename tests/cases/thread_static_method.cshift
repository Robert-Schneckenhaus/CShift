// 'thread' on a static struct method.
// skip-target: wasm32 (WebAssembly has no threads)
// skip-target: m68k (the 68000 backend has no atomic operations: AmigaOS has no threads)
// expect-exit: 0
// expect-stdout: 99

using System;

struct Calculator
{
    static thread int AddOne(int x)
    {
        return x + 1;
    }
}

void Main()
{
    Thread<int> t = start Calculator.AddOne(98);
    Console.WriteLine(t.Join());
}
