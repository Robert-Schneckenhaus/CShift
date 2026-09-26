# Language status

← [Language guide](README.md)

What is implemented, and the decisions that the [design document](../language-design.md) leaves open. Features
marked *(self-hosted)* exist only in the self-hosted compiler (`cshiftc` since the C++ compiler was frozen, see
[../compiler.md](../compiler.md)).

## Implemented

| Area | Status |
|---|---|
| Namespaces (`namespace A.B;`), `using`, multiple files, global symbol resolution | ✔ |
| Global variables (zero value or an initializer, running before `Main`) | ✔ |
| Structs (value semantics), initializers, `new T()`, methods, `static` methods, nested structs | ✔ |
| Visibility via a `_` prefix (private) for fields and methods | ✔ |
| Struct inheritance (one base, the base comes first in the layout), upcasting, hiding methods | ✔ |
| Interfaces (methods), several per struct, checking the implementation | ✔ |
| Interfaces as `ref`/`const ref` parameters: dynamic dispatch through a method table, no allocation, `x is S s` | ✔ (self-hosted, [interfaces](interfaces-and-generics.md#interface-parameters-dynamic-dispatch-without-allocation)) |
| Generics: structs and functions, monomorphization, type inference, explicit type arguments | ✔ |
| Constraints (`where T : IComparable<T>`), checked at compile time | ✔ |
| Enums with a mandatory base type and explicit values | ✔ |
| ARC for strings and arrays (reference semantics, `Clone()`), including inside structs/`Error`/`Optional` | ✔ |
| Strings: UTF-8, immutable, `+`, `==`, `[i]`, `Length`, `Substring`, `CStr()` | ✔ |
| `Error<T>` / `Optional<T>`, bool semantics, `is T x`, `switch` patterns, `try`; nesting only as `Error<Optional<T>>` (never a bare condition) | ✔ ([error handling](error-handling.md)) |
| `IDisposable` + `using` (declaration and block form; also on `return`/`break`/`continue`/`try`) | ✔ |
| `ref` / `const ref` (value, read-only alias, alias) | ✔ |
| Primitive types with aliases (`int`=`int32`, …), `bool`, `char` (= `uint8`), `nint`/`nuint` (pointer-sized) | ✔ |
| Checked integer arithmetic (overflow, division by zero, array/string bounds → panic), `unchecked` | ✔ |
| Operators and precedence like C# (without `++`/`--`), `?:`, casts, `sizeof` | ✔ |
| `if`/`while`/`do`/`for`/`foreach` (arrays, strings)/`switch`/`break`/`continue`/`return` | ✔ |
| Function overloading | ✔ |
| C FFI: `extern "C"`, variadic functions (`printf`), `link "lib"`, pointers | ✔ |
| Function values `Action<…>`/`Func<…,R>`, C-compatible | ✔ (extension) |
| Lambdas and closures (captures are read-only copies) | ✔ (self-hosted, [functions](functions-and-delegates.md#lambdas-and-closures)) |
| String interpolation `$"a {x} b"` (concatenation; `string ToString()` of structs) | ✔ (self-hosted, [strings](arrays-strings-collections.md)) |
| Indexers: `x[k]` calls `Get(k)`, `x[k] = v` calls `Set(k, v)` (`List`, `Dictionary`, own structs) | ✔ (self-hosted) |
| Importing C headers: `using Name from "header.h";` (libclang, a `.ffi` cache), `nint`/`nuint`, structs by value | ✔ (see [../ffi.md](../ffi.md)) |
| `unsafe`: pointers, `&`, `*`, pointer arithmetic, `Memory.Allocate/Free` | ✔ |
| Entry point: `int Main()`, `void Main()`, `Error<int> Main()` | ✔ |
| `Error<void>` (a result with no value; `return;` or falling off the end of the function = success) | ✔ (extension) |
| Top-level `const`, `default(T)`, `foreach` over structs with `Count()`/`Get(int)` | ✔ (extension) |
| Standard library: `List<T>`, `Dictionary<K,V>`, `File`, `Directory`, `Path`, `Encoding`, `Math`, `Random`, string helpers | ✔ (see [../stdlib.md](../stdlib.md)) |
| Real OS threads: `thread` functions (only callable via `start`), `Thread`/`Thread<T>` (`Join`/`Cancel`/`is`), `SharedPtr<T>`; strings copied into threads, `Mutex<T>` | ✔ (extension, see [threading.md](threading.md); strings and `Mutex<T>` self-hosted) |

## Interpretation and extensions beyond the design

The design document leaves a number of things open; these are the decisions that were made:

* **Creating errors:** `return error("text");` or `error("text", code)`; `Error<T>` has `.Message` and `.Code`.
* **Implicit conversion** `T → Error<T>` / `T → Optional<T>`; `null` stands for "no value" (`Optional`).
* **Bool semantics** of `Error`/`Optional` apply in conditions and with `!`, `&&`, `||`, but not as an argument for a
  `bool` parameter (use `x is T` instead).
* **`is`/`case` patterns:** `x is int v` binds the value; `x is error e` matches a failure and binds the whole result (a pattern of the value's own type would always match and is an error). Pattern
  variables are scoped to the `if`/`while`, or to the `case`.
* **`try` in `int Main()`:** in the design's target picture, `try` is used in an `int` function. There, an error
  prints `error: <text>` to stderr and ends the program with exit code 1.
* **Integer arithmetic** works like in C#: types smaller than 32 bits are widened to `int`; a literal adapts to the
  other operand (`uint8 x = 200; int y = x * 3;` gives 600). Explicit casts never abort (they wrap/saturate); only
  `+ - * / %` are checked.
* **Interfaces are not value types** (a value would need a hidden allocation): they are generic constraints and the
  types of `ref`/`const ref` parameters (a pointer to the struct and its method table). For `const ref` the caller
  passes a copy on its stack.
* **`Error<Optional<T>>`** is the only allowed nesting. It cannot be used as a condition (`if (r)`, `!r`): write
  `r is T v` (succeeded with a value) or `r is Optional<T> o` (succeeded).
* **Contextual keywords:** `thread` and `where` are only keywords where they start a thread function or a
  constraint; elsewhere they are ordinary names.
* **"Color Color":** a variable or field may have the name of its own type; `Color.Green` then means the type unless
  `Green` is a member of the value (C#'s rule).
* **Floats as text** are the shortest text that reads back as the same value (`0.1`, `0.30000000000000004`), at run
  time and in constants.
* **Methods on `const ref` objects** operate on a copy (like C#'s `in`), so the read-only guarantee holds.
* **Built in** (generated directly by the compiler as IR, no runtime library): `Console.Write/WriteLine`,
  `Memory.Allocate/Free`, `Environment.Exit/Panic`, `Array.Copy`, `string.FromBytes`,
  `ToString()`/`CompareTo()`/`Equals()`/`GetHashCode()` on numbers, `int.MaxValue/MinValue`,
  `EmbedText("file")`/`EmbedNames("folder", ".ext")`/`EmbedTexts("folder", ".ext")` (files are embedded into the
  program at compile time; paths are relative to the source file, and only string literals are accepted as
  arguments). Everything else is in the [standard library](../stdlib.md) or comes via `extern "C"`.
* **`Error<void>`:** `Error<void> Save() { ... return; }`. `try Save();` only checks for an error; there is no
  `Optional<void>`.
* **Constants:** `const int MyConst = 5;` at the top level or inside functions. Numbers, `bool`, `char`, enums and
  `string` are allowed; a constant must always be initialized, and the initializer consists only of literals,
  operators, casts, enum values and other constants (`const Color Fav = Color.Green;`,
  `const Flags Rw = Flags.Read | Flags.Write;`, `const int Sum = A * 2 + 1;`). Top-level constants may be used before
  their declaration and are always checked, even if nothing uses them; they can also be accessed qualified
  (`Math.PI`). Local constants have no storage (assigning to one is an error) and may shadow a name from an
  enclosing block. **The compiler computes constants at compile time**
  (`compiler/src/ConstEval.cpp`, in `cshc`: `ConstEval.csh`), following the same rules as the code that would be
  generated for the expression at run time (the type of literals, promotion of small integers, shifts, comparisons,
  casts that saturate floating-point values, string concatenation with numbers, `sizeof(T)`), but it reports
  overflow (`2147483647 + 1`), division by zero, and `MIN / -1` as compile errors. The same expressions are allowed
  for the values of enum members (`B = A * 2`, `C = sizeof(int64)`); `&&`/`||` only evaluate the right side when it
  can change the result.
* **Global variables:** `int Counter;`, `string Name = "x";`, `List<string> Names = List<string>.Create();` at the
  top level, of any type. Without an initializer, the variable starts at its zero value. Initializers are arbitrary
  expressions; they run before `Main`, in the order of the declarations (files in the order they're given to the
  compiler). **The order is checked:** an initializer must not use a global that's initialized later (or itself) —
  not even through functions it calls (function pointers it creates count too). A global with no initializer (zero
  value) can be read at any time. Name resolution works like for constants (the file's namespace, `using`,
  qualified as `Ns.Counter`). Globals are ordinary lvalues (assign to them, `ref`, `&` in `unsafe`, modify
  fields/elements, call methods; a function-pointer global calls like a function). Values that own heap blocks
  (strings, arrays, lists, …) are released once `Main` returns. No `var` (the type must be written out). A
  `thread` function may never read or write a global, even through a function it calls (checked at compile time).
* **`foreach` over structs:** works for any struct with `int Count()` and `T Get(int index)` (e.g. `List<T>`).
* **Name resolution** works like in C#: the current file's namespaces and the global namespace win over `using`
  namespaces.
* **Function values:** `Action`, `Action<T1, …>` (no result) and `Func<R>`, `Func<T1, …, R>` (the last type is the
  result) are built-in types like in C#, with up to 8 parameters. They hold a function or a lambda
  ([closures](functions-and-delegates.md#lambdas-and-closures)); you can assign the name of a free function or a `static` method
  (`Func<int, int> f = Square;`, `var g = Add;`, `Handlers.Triple`). The signature must match exactly; for overloads
  and generic functions (`Identity<int>`, or inferred from the target type), the target type picks the match. Call
  with `f(x)`, `obj.Callback(x)` (a field), `table[i](x)`, or `f.Invoke(x)`. `null` is allowed; calling `null` is a
  panic. Compare with `==`/`!=`. Function pointers are ordinary values (fields, arrays, parameters, return values,
  type arguments). There are no `ref` parameters, and instance methods can't be assigned. They're C-compatible:
  passed to C (see [../ffi.md](../ffi.md)), C calls the CShift function directly; a function pointer returned from C can be
  called directly. `(void*)` casts need `unsafe`.
* Extra syntax allowed: `cond ? a : b`, `new int[3][]` (jagged arrays), `new T[] { ... }`, `sizeof(T)`.
