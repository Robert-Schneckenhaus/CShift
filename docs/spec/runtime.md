# Run time

## Program start and end

A program runs in these steps:

1. The global variables are initialized, in the order of the files and of their declarations (see
   [declarations](declarations.md#global-variables)).
2. `Main` runs, with the command-line arguments (without the program's name) if it takes `string[] args`.
3. The program ends when `Main` returns, when `Environment.Exit(code)` is called or with a panic.

| End | Exit code |
|---|---|
| `void Main()` returns | 0 |
| an integer `Main` returns `n` | `n` |
| `Error<int> Main()` returns a value `n` | `n` |
| `Error<int> Main()` returns a failure | 1, after writing `error: <message>` to stderr |
| `Environment.Exit(code)` | `code` |
| a panic | 101 |

When `Main` returns, the global variables are released and buffered output is written. `Environment.Exit` and a panic
end the program right away: nothing is released and no `Dispose` runs, but buffered output is still written. Threads
that are still running when the program ends are stopped.

## Panics

A **panic** ends the program because of a bug. It writes `panic: <reason>` and the place to stderr and exits with code
101:

```text
panic: array index out of range (index 5, length 3)
  at src/Game/World.csh:482:21 in World.GetTile
```

The place is the file (as the compiler was given it; in a project, relative to the project folder), line, column and
function. When a function of the standard library panics because of its arguments, the line `called from ...` shows
where the program called it. A panic cannot be caught; errors that a program is expected to handle are
[`Error<T>`](types.md#error) results.

These checks panic:

| Reason | When |
|---|---|
| `integer overflow` | an integer operation or conversion whose result does not fit, in checked code (see below) |
| `division by zero` | an integer `/` or `%` by 0 (also in unchecked code) |
| `array index out of range`, `string index out of range`, `slice index out of range`, `fixed array index out of range` | an index outside of `0 .. Length - 1` (also in unchecked code); the message shows the index and the length |
| `slice range out of bounds` | a range `a[i..j]` that is not inside of the array or string |
| `negative array length` | `new T[n]` with `n < 0` |
| `call of a null function` | calling an `Action`/`Func` that is `null` |
| `SharedPtr.Get(): the pointer is null` | `Get()` or `Ptr()` of a `null` `SharedPtr` |
| `the union 'U' holds no value` | calling an interface method on a union that holds no value (its default value; `is` and `switch` simply match no member) |
| `the collection for 'Fixed<T, N>' does not have N elements` | converting a collection of another length to a `Fixed` |
| `out of memory` | an allocation failed |
| `cannot create a thread` | `start` could not create an OS thread |
| the message of `Environment.Panic(message)` | always |

`null` strings and arrays are empty, not errors: their `Length` is 0, and indexing them panics with an index out of
range. Reading a pointer, a stack overflow or an infinite recursion is not checked.

### Checked and unchecked arithmetic

By default, integer arithmetic (`+ - *`, unary `-`, the compound assignments) and integer conversions with a cast
are **checked**: a result that does not fit in the type panics with `integer overflow`. In **unchecked** code they
wrap around (modulo 2^n), like in C. Unchecked code is:

* an `unchecked { }` block or an `unchecked(e)` expression;
* a whole program compiled with `--unchecked`, or a project with `"unchecked": true` in `cshift.json` (`--checked`
  turns it back on for one build). This applies to the program's own files; the standard library stays checked.

Division by zero and index checks are made in unchecked code too. Shifts never panic: the count is masked (see
[expressions](expressions.md#shifts-and-bitwise-operators)). Floating-point arithmetic follows IEEE 754 and never panics (`1.0 / 0` is
infinity, `0.0 / 0` NaN).

## Targets

The compiler generates native code for:

| Target | Pointer size (`nint`) | Notes |
|---|---|---|
| Linux x64 | 8 | via LLVM / clang |
| Windows x64 | 8 | via LLVM / clang, MinGW-w64 |
| AmigaOS, `--target m68k-amigaos` | 4 | CShift's own 68000 backend; AmigaOS libraries from NDK SFD files |
| WebAssembly, `--target wasm32-wasi` | 4 | via LLVM / clang with wasi-libc; no threads, no other programs ([WebAssembly](../wasm.md)) |

The sizes of the other types (`int` is always `int32`, `long` always `int64`, ...) do not depend on the target, and
integers are stored in the target's byte order (little-endian on x64, big-endian on the 68000). The `Amiga` namespace of the
standard library exists only for AmigaOS. The compiler options and the toolchain are described in the
[README](https://github.com/Robert-Schneckenhaus/CShift#readme).
