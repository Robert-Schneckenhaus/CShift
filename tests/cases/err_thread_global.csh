// A 'thread' function may not touch global state, even through a function it calls.
// skip-target: wasm32 (WebAssembly has no threads)
// expect-error: a thread can only see its parameters and return value

using System;

int counter = 0;

void Bump()
{
    counter += 1;
}

thread void Bad()
{
    Bump();
}

void Main()
{
    start Bad();
}
