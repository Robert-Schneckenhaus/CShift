← [Language guide](README.md)

# Constants and global variables

## `const`

A constant is declared at the top level of a file or inside a function, and must always be initialized:

```csharp
const int MaxPlayers = 8;
const double Pi = 3.14159;
const string Greeting = "Hello, " + "World!";     // string concatenation is allowed
const Color Favorite = Color.Green;                 // enum members too
const int Doubled = MaxPlayers * 2;                  // other constants, operators, casts
```

Only numbers, `bool`, `char`, `string` and enums are allowed as a constant's type. A local constant (inside a
function) has no storage — its value is inlined wherever it's used, and assigning to it is an error. A top-level
constant may be used before its own declaration in the file, and is checked even if nothing ever uses it.

**The compiler evaluates every constant at compile time**, following the exact same rules the generated code would
use at run time (literal types, promotion of small integers, checked arithmetic, shifts, comparisons, casts that
saturate floating-point values, string concatenation). The difference is that overflow, division by zero, and
similar problems are reported as **compile errors**, not runtime panics:

```csharp
const int Broken = 2147483647 + 1;   // compile error: integer overflow in a constant expression
```

The same rules apply to enum member values (`B = A * 2`, `C = sizeof(int64)` are both fine).

A constant always names its type: `const var` is an error.

### Constant slices

A constant can also hold several values, as a `ReadOnlySlice<T>` of numbers, `bool`, `char`, `string` or enums,
written as a [collection expression](arrays-strings-collections.md#collection-expressions) that may spread other
constant slices:

```csharp
const ReadOnlySlice<int> Primes = [2, 3, 5, 7];
const ReadOnlySlice<int> More = [..Primes, 11, 13];
const ReadOnlySlice<string> Names = ["Red", "Green", "Blue"];

const int Largest = More[^1];                  // indexing, ^n, slicing and Length work in constants too
const int Count = Primes[1..].Length;          // 3
const int Letters = "hello".Length;            // (also for constant strings)
```

* **Arrays and `Slice<T>` cannot be constants**, because their elements can be changed; the error suggests
  `ReadOnlySlice<T>`. A constant slice cannot be changed at all (it is [read-only](arrays-strings-collections.md#slices)),
  `ToArray()` gives a normal copy.
* The elements are stored once in static memory: using a constant slice copies and allocates nothing.
* An index or a range outside the slice is a compile error.
* A `thread` function may read global constants, constant slices included (slices still cannot be *parameters* of a
  thread).
* [`Enum<T>.Values` and `Enum<T>.Names`](enums.md#enumt-facts-about-an-enum) are constant slices as well.

### Embedded files: `embed`

`embed("file")` reads a file when the program is compiled and makes its content a string constant - for shaders,
translations, version files and the like:

```csharp
const string Shader = embed("shaders/sprite.glsl");
const string Version = embed("version.txt");
```

* **Only like this:** `embed(...)` is the whole initializer of a `const string` (top level or local). It does not exist
  at run time, cannot be part of a larger expression, and its argument must be a string literal.
* **Exact content:** the constant holds the file's text unchanged - quotes, backslashes, `\r\n` and `\n` stay as they
  are (only a UTF-8 byte order mark is dropped), so `File.WriteAllText(path, Shader)` writes the same content. The file
  must be UTF-8 text.
* **Where the file is searched:** an absolute path is used as it is. Otherwise the path is relative to the source file
  that contains `embed`, and if the file is not there, relative to the project folder (the folder of `cshift.json`).
  A missing file is a compile error that lists where it was looked for.
* The file is read on every build, so a change to it is picked up the next time the program is compiled.
* `embed` is a keyword, so it cannot be used as a name.

## Global variables

A global variable is declared at the top level, with any type, with or without an initializer:

```csharp
int RequestCount;                          // starts at 0 (the zero value)
List<string> Log = List<string>.Create();   // an arbitrary initializer expression

void RecordRequest()
{
    RequestCount += 1;
    Log.Add("request " + RequestCount.ToString());
}
```

Initializers run before `Main`, in declaration order (and, across files, in the order the files are given to the
compiler). **The compiler checks that order:** an initializer must not read a global that's initialized later, or
itself — including indirectly, through a function it calls:

```csharp
int First = Second + 1;   // compile error: uses Second before it is initialized
int Second = 5;
```

A global with no initializer can be read at any time, since its zero value is already well-defined. Globals are
ordinary lvalues — assign to them, pass with `ref`, take their address in `unsafe`, call methods on them, modify
their fields — and name resolution follows the same rules as for constants (the file's namespace, `using`, or
qualified as `Ns.Counter`). Values that own heap memory (strings, arrays, lists, …) are released once `Main`
returns. There's no `var` for a global (the type has to be written out), and reference counts aren't atomic, so
globals aren't safe to share across threads.

Next: [C interop (FFI)](ffi-and-interop.md).
