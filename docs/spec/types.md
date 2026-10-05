# Types

```ebnf
Type        = NamedType { '*' | '[' ']' } ;
NamedType   = QualifiedName [ '<' TypeArg { ',' TypeArg } '>' ] ;
TypeArg     = Type | IntegerLiteral ;       (* a number only for the size of Fixed<T, N> *)
```

`T*` is a pointer to `T`, `T[]` an array of `T`; both can be repeated (`int[][]`, `char**`). Generic types take their
type arguments in angle brackets.

## Kinds of types

| Kind | Examples | Semantics |
|---|---|---|
| [Numbers](#primitive-types) | `int`, `uint8`, `double`, `nint` | value |
| [`bool`](#bool) | `true`, `false` | value |
| [`char`](#char) | `'a'` | value |
| [`string`](#string) | `"text"` | reference (ARC), immutable |
| [Arrays](#arrays) | `int[]`, `string[][]` | reference (ARC) |
| [Slices](#slices) | `Slice<T>`, `ReadOnlySlice<T>`, `StringSlice` | value (a view of an array or string) |
| [Fixed-size arrays](#fixed-size-arrays) | `Fixed<int, 16>` | value (elements inline) |
| [Structs](#structs) | `Vec2`, `List<T>` | value |
| [Unions](#unions) | `union Shape { Circle, Rect }` | value |
| [Enums](#enums), [error enums](#error-enums) | `enum Color : uint8`, `error IoError` | value |
| [`Optional<T>`](#optional), [`Error<T>`](#error) | `Optional<User>`, `IoError<string>` | value (holds a `T`) |
| [Function types](#function-types) | `Action<int>`, `Func<int, int>` | reference (ARC for closures) |
| [Pointers](#pointers) | `int*`, `void*` | value (unmanaged) |
| [`SharedPtr<T>`](#sharedptr), [`Thread`](#thread) | `SharedPtr<int>`, `Thread<int>` | reference (atomic ARC) |
| [Interfaces](#interfaces) | `IShape` | not a value type: constraints and `ref` parameters only |
| `void` | | no value: the result of a function that returns nothing |

**Value** types are copied by assignment, by passing and by returning. **Reference** types share their storage: a
copy refers to the same block, which is freed when the last reference goes (automatic reference counting, see
[memory](memory.md)).

## Primitive types

| Type | Also | Size | Range |
|---|---|---|---|
| `int8` | | 1 | -128 .. 127 |
| `int16` | | 2 | -32768 .. 32767 |
| `int32` | `int` | 4 | -2^31 .. 2^31-1 |
| `int64` | | 8 | -2^63 .. 2^63-1 |
| `uint8` | | 1 | 0 .. 255 |
| `uint16` | | 2 | 0 .. 65535 |
| `uint32` | `uint` | 4 | 0 .. 2^32-1 |
| `uint64` | | 8 | 0 .. 2^64-1 |
| `nint` | | 8 or 4 | a signed integer of the size of a pointer on the target |
| `nuint` | | 8 or 4 | an unsigned integer of the size of a pointer |
| `float32` | `float` | 4 | IEEE 754 single precision |
| `float64` | `double` | 8 | IEEE 754 double precision |
| `bool` | | 1 | `true`, `false` |
| `char` | | 1 | a byte of UTF-8 text, 0 .. 255 |

The integer types have the static fields `MinValue` and `MaxValue`; the floating-point types also `Epsilon`, `NaN`,
`PositiveInfinity` and `NegativeInfinity`. All numbers, `bool` and `char` have `ToString()` (numbers also
`ToString(format)`), `Equals`, `CompareTo` (not `bool`) and `GetHashCode`, and implement `IEquatable<T>`,
`IComparable<T>` and `IHashable` (see the [built-in types](../../stdlib/builtin/numbers.csh)).

### bool

`bool` is the type of conditions: `if`, `while`, `for`, `?:`, `!`, `&&` and `||` take only `bool`. Nothing converts
to `bool` (not a number, a pointer, an `Error<T>` or an `Optional<T>`), and `bool` converts to nothing; even a cast
between `bool` and a number is a compile error.

### char

`char` is one byte of UTF-8 text. It is a type of its own: it converts implicitly to and from `uint8` and to the larger
integer types; arithmetic on a `char` gives an `int` (`'a' + 1` is `98`), so `c = c + 1` needs a cast. `s[i]` of a
string is a `char`, and the namespace `Char` classifies characters.

## string

A `string` is immutable UTF-8 text, a reference to a reference-counted block (or `null`). `null` behaves like the empty
string: its `Length` is 0, it compares equal to `""` and it can be concatenated. `s.Length` is the length in bytes,
`s[i]` the byte at `i` (a `char`; the index is checked), `s[i..j]` a [`StringSlice`](#slices). `==` and `!=` compare the
bytes; `<` and `>` are not defined for strings (use `CompareTo`). `+` joins strings, and a string joined with a number,
`bool`, `char`, enum, slice or a struct with `string ToString()` converts that value to text. The methods of strings
are in the namespace [`String`](../stdlib.md).

## Arrays

`T[]` is a reference to a reference-counted block of `Length` elements of `T`. An array is created with `new T[n]`
(zeroed elements), `new T[] { a, b }` or a [collection expression](expressions.md#collection-expressions); its length
never changes. `a[i]` checks the index (a panic outside `0 .. Length - 1`), `a[^i]` counts from the end, and
`a[i..j]` is a `Slice<T>`. A `null` array has the length 0. `a.Clone()` copies the elements into a new array;
`Array.Copy` copies between arrays.

## Slices

A slice is a view of consecutive elements of an array or a string: a small value (the block, the first element, the
length) that keeps the whole block alive. Nothing is copied when a slice is made.

| Type | Of | Writable |
|---|---|---|
| `Slice<T>` | an array (or a part of one) | yes: `s[i] = x` writes the array |
| `ReadOnlySlice<T>` | an array, a `Slice<T>`, or constant data | no |
| `StringSlice` | a string (or a part of one) | no |

Slices have `Length`, `s[i]`, `s[^i]`, `s[i..j]` (another slice), `foreach`, `ToArray()` (`ToString()` for a
`StringSlice`), and in `unsafe` code `Ptr()`. A `StringSlice` compares with `==` to strings and other string slices
by its bytes and can be joined to text. [Constant slices](declarations.md#constants) are `ReadOnlySlice<T>`.
Text converts to its characters, `ReadOnlySlice<char>`, without a copy (never back: the characters need not be
UTF-8); `s.AsBytes()` of a `string` or `StringSlice` is the same view as `ReadOnlySlice<uint8>`, for functions that
take bytes.

## Fixed-size arrays

`Fixed<T, N>` is `N` elements of `T` stored inline, in the variable or in the struct that has the field: a value, with
no allocation. `N` is an integer literal or an integer constant. Indexing is checked (a constant index outside
`0 .. N-1` is a compile error), `Length` is the constant `N`, `foreach` and slicing work, `ToArray()` copies into a
new array. There is no conversion between `Fixed<T, N>` and arrays or slices in either direction; a collection
expression (`[..values]`) copies elements in.

## Structs

A struct is a value made of fields (see [declarations](declarations.md#structs)). Its size is the size of its fields
with the alignment of C, so a struct can be passed to C. A struct cannot contain itself, directly or through other
structs (an array or a `List` of it is fine). Generic structs (`List<T>`) are separate types for every type argument.

## Interfaces

An interface (see [declarations](declarations.md#interfaces)) is **not a value type**: there are no variables,
fields, results, elements or type arguments of an interface type. An interface is used as

* a **constraint** of a type parameter (`where T : IComparable<T>`): the calls are direct, and
* the type of a **`ref` or `const ref` parameter** (`void Draw(const ref IShape s)`): the function takes any struct
  that implements the interface, and calls its methods through a method table. Nothing is allocated.

## Unions

A `union` holds one value of one of its member types, stored inline with a tag (see
[declarations](declarations.md#unions)). A member type converts implicitly to the union; `u is T v` and `switch`
take it out again. The default value of a union is empty: no `is` matches, and calling an interface method panics.

## Enums

An enum is an integer type of its own with named values (see [declarations](declarations.md#enums)). It converts to
and from integers only with a cast (`(int)c`, `(Color)1`); a value without a name is allowed. Enums support `==`,
`!=`, `<`, `>`, `<=`, `>=` and `& | ^ ~`, and become text as the name of their member (`$"{c}"` is `Green`; a value
without a member prints its number).

## Error enums

An error enum (`error IoError { ... }`) is an enum with base type `int32` whose values are error codes, counting from
1. A value converts implicitly to `int` (but not to a result type). `E<T>` is short for `Error<T, E>`.

## Optional

`Optional<T>` is a `T` or nothing (`null`). A `T` and `null` convert to it implicitly. It is not a condition: test it
with `x is T v`, `x == null` / `x != null` or `switch`. Its default value is `null`. `T` cannot be an `Optional`, an
`Error` or `void`.

## Error

`Error<T>` is a value of type `T` (a success) or an error with a message (`string`) and a code (`int`): the result of
something that can fail. `Error<T, E>` (also written `E<T>`) has codes of the error enum `E`. `T` and `error(...)`
convert to it implicitly; `try` unwraps it (see [expressions](expressions.md#try)). It is not a condition; test it with
`is T v` or `is error e`. `Error<void>` is a result without a value. Its default value is a failure with an empty
message and the code 0.

Of the nestings of `Optional` and `Error`, only `Error<Optional<T>>` is allowed: a result that can fail or find
nothing. `Error<Error<T>>`, `Optional<Error<T>>` and `Optional<Optional<T>>` are compile errors, and so is
`Error<E>` for an error enum `E`.

## Function types

`Action<T1, ..., Tn>` is a function with the parameters `T1 ... Tn` and no result; `Func<T1, ..., Tn, R>` one with the
result `R` (n from 0 to 8). A value of a function type is a function, a `static` method, a lambda or `null`. It is
called like a function (`f(x)`, also `f.Invoke(x)`); calling `null` panics. Function values compare with `==` and
`!=`. Without captured variables, a function value is a C function pointer; a lambda with captures carries a
reference-counted block with copies of them. Function types have no `ref` parameters.

## Pointers

`T*` points to a `T`, `void*` to anything. Pointers are unmanaged: nothing is freed or counted. A pointer type can be
written anywhere, but everything that reads or writes through a pointer (`*p`, `p->F`, `p[i]`, `&x`, pointer
arithmetic, casts between pointers and integers, `Memory.Allocate`) needs [`unsafe`](memory.md#unsafe). `null`
converts to every pointer type and `T*` to `void*`; the other direction needs a cast.

## SharedPtr

`SharedPtr<T>` is a reference-counted box for one `T` whose count is atomic, so it can be passed between threads (see
[memory](memory.md#threads)). `SharedPtr<T>.Create(v)`, `Get()`, `IsNull()`, `Ptr()` (`unsafe`).

## Thread

`Thread` and `Thread<T>` are the handles of running [thread functions](declarations.md#thread-functions): `Join()`,
`Cancel()`, `CancelAndWait()`, `IsCompleted()`, `IsCancelled()`, and `t is T v` for a finished `Thread<T>`.

## null

`null` is a value of the types string, array, slice, `Optional<T>`, `Error<Optional<T>>` (a success with nothing),
function type, pointer and `SharedPtr<T>`. Other types have no `null`.

## Default values

Every type has a default (zero) value: what a variable without an initializer, a field that an initializer does not
set, a new array's elements and `default(T)` have.

| Type | Default |
|---|---|
| numbers, `char` | 0 |
| `bool` | `false` |
| enums | the value 0 (which may have no name) |
| string, arrays, slices, pointers, function types, `SharedPtr<T>`, `Optional<T>` | `null` |
| structs, `Fixed<T, N>` | every field / element has its default |
| unions | empty |
| `Error<T>` | a failure with the message `""` and the code 0 |

## Conversions

### Implicit conversions

A value converts implicitly where a value of another type is expected (an assignment, an argument, a `return`, an
initializer, an operand) in these cases:

| From | To |
|---|---|
| an integer type | a larger integer type of the same signedness, or a larger signed type (`uint8` to `int16`; never signed to unsigned) |
| `int32` and smaller | `nint` (signed or smaller unsigned) / `nuint` (unsigned) |
| `nint` / `nuint` | `int64` / `uint64` |
| `char` | `uint8` and larger unsigned and signed types; `uint8` to `char` |
| an integer type | `float` and `double` |
| `float` | `double` |
| an integer literal | any numeric type its value fits (`uint8 b = 200;`, `double d = 1;`) |
| a `double` literal | `float` |
| an error enum value | `int` and larger integer types |
| `T` | `Optional<T>`, `Error<T>`, `Error<T, E>`, `Error<Optional<T>>` |
| `null` | the types in [null](#null) |
| `error(...)` | a result type (`error(E.X)` only to `Error<T>` and `Error<T, E>`) |
| `Error<T, E>` | `Error<T>` |
| `string` | `StringSlice` |
| `string`, `StringSlice` | `ReadOnlySlice<char>` (the same bytes; a `string` prefers `StringSlice` in overload resolution) |
| `T[]` | `Slice<T>`, `ReadOnlySlice<T>` |
| `Slice<T>` | `ReadOnlySlice<T>` |
| a struct | its base struct (and their bases): the base part is copied |
| a member type of a union | the union |
| `T*` | `void*` |
| a function or `static` method name, a lambda | a matching function type |
| a [collection expression](expressions.md#collection-expressions) | an array, a slice, `Fixed<T, N>`, or a struct with `static Create()` and `Add(T)` |

Everything else needs a cast or a method (`ToString()`, `ToArray()`). In particular there is no implicit conversion
from a larger to a smaller number, between signed and unsigned types of the same size, from a floating-point type
to an integer, between `bool` and numbers, between an enum and its base type, from a slice to an array or string, or
from a base struct to a derived one.

### Casts

```ebnf
Cast = '(' Type ')' UnaryExpression ;
```

A cast converts explicitly:

* **Between numeric types and `char`:** integers are truncated to the target's bits (`(uint8)300` is 44); a
  floating-point value is truncated towards zero and saturates (`(int)1e20` is `int.MaxValue`, `NaN` becomes 0);
  `double` to `float` rounds. Casts never panic, also when the arithmetic is checked.
* **Between an enum and an integer type** (in both directions).
* **Between pointers, and between pointers and `nint`/`nuint` or other integers** (in `unsafe` code).
* Whatever converts implicitly also converts with a cast.

A cast between other types (`(bool)1`, `(Dog)animal`) is a compile error.
