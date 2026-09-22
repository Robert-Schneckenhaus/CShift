← [Language guide](README.md)

# C interop (FFI)

CShift's primary external ABI is the C ABI, and calling C code is meant to feel native.

## Hand-written declarations

```csharp
extern "C" int strlen(char* str);
extern "C" void* malloc(uint64 size);

link "m";   // link against a system library (here, libm)
```

`extern "C"` declares a C function; `link "name"` tells the linker to pull in a library (`-l<name>`).

## Importing a whole header

For a real library, hand-writing every declaration doesn't scale. `using Name from "header.h";` imports a C header's
functions, structs, enums and constants as a namespace, with the types mapped automatically (`const char*` →
`string`, `size_t` → `nuint`, a pointer parameter → `ref T`, and so on):

```csharp
using Zlib from "zlib.h";

int Main()
{
    Console.WriteLine(Zlib.zlibVersion());        // const char* -> string
    Console.WriteLine(Zlib.Z_BEST_COMPRESSION);    // a macro -> a constant
    return 0;
}
```

```
cshiftc prog.csh -lz          # still need to link the actual library
```

Structs passed *by value* to and from C, and C callbacks, both work — a CShift function can be handed to a C
function expecting a callback, using the [function pointer types](functions-and-delegates.md) `Action`/`Func`:

```csharp
using Mfb from "MiniFB.h";

void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed && key == Mfb.mfb_key.KB_KEY_ESCAPE)
        Mfb.mfb_close(window);
}

Mfb.mfb_set_keyboard_callback(window, OnKey);
```

This is a large enough topic to have [its own document](../../FFI.md): the full type mapping table, how pointers and
`nint`/`nuint` map, `ffiApi` for umbrella headers, and the current limitations (no C++, no unions/bit fields, no
`long double`, …). The `demo/` project is a complete, runnable example that imports a real C library this way.

Next: [Projects](projects.md).
