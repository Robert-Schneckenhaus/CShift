# Expressions

## Precedence

From the lowest to the highest precedence:

| Level | Operators | Associativity |
|---|---|---|
| 1 | `=` `+=` `-=` `*=` `/=` `%=` `&=` `\|=` `^=` `<<=` `>>=` `??=` | right |
| 2 | `? :` | right |
| 3 | `??` | right |
| 4 | `\|\|` | left |
| 5 | `&&` | left |
| 6 | `\|` | left |
| 7 | `^` | left |
| 8 | `&` | left |
| 9 | `==` `!=` | left |
| 10 | `<` `>` `<=` `>=` `is` | left |
| 11 | `<<` `>>` | left |
| 12 | `+` `-` | left |
| 13 | `*` `/` `%` | left |
| 14 | unary `-` `+` `!` `~` `*` `&`, cast `(T)x`, `try`, `ref`, `start` | right |
| 15 | `.` `->` `()` `[]` `[..]`, initializer `T { ... }` | left |

The order is that of C#. The operands of a binary operator are evaluated from left to right, and so are the arguments
of a call. There is no `++`, `--`, `?.`, `as`, `typeof` or `checked`.

## Primary expressions

| Expression | Meaning |
|---|---|
| a literal | see [lexical structure](lexical.md#literals) |
| `Name`, `Ns.Name` | a variable, parameter, constant, function or type ([name lookup](programs.md#name-lookup)) |
| `this` | in a method: the struct value the method is called on |
| `(e)` | grouping |
| `$"..."` | an [interpolated string](#interpolated-strings) |
| `[a, ..b]` | a [collection expression](#collection-expressions) |
| `x => e`, `(a, b) => { ... }` | a [lambda](#lambdas) |
| `new ...`, `T { ... }` | [creating values](#creating-values) |
| `error(...)` | an [error value](#error-values) |
| `sizeof(T)` | the size of `T` in bytes, an `int` constant |
| `default(T)` | the [default value](types.md#default-values) of `T` |
| `unchecked(e)` | `e` with [unchecked arithmetic](#integer-arithmetic) |
| `embed(...)`, `embed_filenames(...)`, `embed_lines(...)` | [files as constants](#embed) |

## Member access and calls

`x.M` is a field, method or property-like member (`Length`) of the value `x`, or a static member, nested name or
enum member of the type or namespace `x`. `p->M` is `(*p).M` for a pointer `p` (unsafe).

A call `f(a, b)` calls a function, a method, or a value of a function type. The arguments convert to the parameter
types implicitly; for a `ref` parameter the argument is written `ref x` and must be a variable, field, element or
`ref` parameter of the same type. Overloads are chosen as described in [declarations](declarations.md#functions);
type arguments are written (`F<int>(x)`) or inferred from the arguments.

## Indexing and slicing

| Expression | Of | Result |
|---|---|---|
| `a[i]` | array, `Slice<T>`, `ReadOnlySlice<T>`, `Fixed<T, N>` | the element (an lvalue, except for read-only slices) |
| `s[i]` | `string`, `StringSlice` | the byte, a `char` (read-only) |
| `a[^i]` | the same | the element `Length - i` |
| `a[i..j]`, `a[..j]`, `a[i..]`, `a[..]`, with `^` | arrays, strings, slices, `Fixed` | a slice of the elements `i` to `j - 1` |
| `p[i]` | a pointer (unsafe) | `*(p + i)` |
| `x[k]` | a struct with `Get(k)` | `x.Get(k)`; `x[k] = v` is `x.Set(k, v)`, `x[k] += v` both |

Indexes and ranges are checked: an index outside `0 .. Length - 1` or a range outside `0 <= i <= j <= Length` panics
(with the index and the length); a constant index into a `Fixed` or a constant slice is checked when the program is
compiled. The index is an integer of any type. Slicing a `Fixed` gives a `Slice<T>` of the variable's elements.

## Arithmetic

`+ - * / %` take numbers. If both operands have the same type, that is the type of the result; otherwise the smaller
type converts to the larger one (an integer to the floating-point type, `float` to `double`), and two integer types
of different signedness widen to a signed type that holds both, if there is one (otherwise a cast is needed:
`uint64 + int64` is a compile error). Integer literals take the type of the other operand when they fit. The
operators on `bool`, strings (except `+`), enums (except the bitwise ones) and structs are compile errors.

| Operator | Integers | Floating point |
|---|---|---|
| `/` | truncates towards zero (`-7 / 2` is `-3`); division by 0 panics | IEEE: `1.0 / 0` is infinity |
| `%` | the sign of the dividend (`-7 % 2` is `-1`); by 0 panics | IEEE remainder of the truncated division |
| `+ - *` | checked: an overflow panics (see below) | IEEE |
| unary `-` | checked (`-int.MinValue` panics) | |

### Integer arithmetic

Integer `+ - * / %` and unary `-` are **checked**: a result that does not fit the type ends the program with a panic
(`integer overflow`), and so does `MinValue / -1`. In `unchecked { ... }`, `unchecked(e)`, or with the compiler option
`--unchecked` (or `"unchecked": true` in `cshift.json`), they wrap around instead. Division by zero panics always. Casts
never panic (they truncate, see [types](types.md#casts)).

**The target type.** An integer expression that is used as a value of a known integer type `T` is computed in `T`, if
every operand converts to `T` implicitly: the type of a declared variable, the target of an assignment or compound
assignment, a `return` value, a field in an initializer, an element in `new T[] { ... }`, a constant, and an argument
when all overloads with that many parameters have the same type there. So `uint8 sum = a + b;` with `uint8 a, b` is
computed (and checked) in `uint8`, and `int64 big = count * 1000;` with an `int count` is computed in `int64`. The
branches of `?:` in such a place are computed in `T` as well. Without a target type, or when an operand does not
convert to it, the operands are widened as in C#: types smaller than `int` become `int` (`var v = a + b;` is an `int`).
A compound assignment whose value is wider than the target narrows the result, checked (`int16 x; x += someInt;`).

### Shifts and bitwise operators

`<< >>` shift an integer by an integer count; the count is taken modulo the number of bits of the type (`1 << 33` is
`2` for an `int`). `>>` is arithmetic for signed types and logical for unsigned ones. `& | ^ ~` work on integers, on
enums (the result has the enum's type) and `& | ^` also on `bool` (without short-circuit). Shifts and bitwise
operators never panic.

## Comparisons

`== != < > <= >=` compare numbers (also of mixed signedness, by value: `-1 < 1u` is `true`), `char`s and enums;
`== !=` also `bool`, strings and string slices (by their bytes), function values, pointers, and `Optional<T>`,
strings, arrays, slices, function values and pointers with `null`. Structs, arrays, unions and `Error<T>` cannot be
compared with `==` (compare fields, or implement `Equals`). The result is `bool`.

## Logical operators

`!`, `&&` and `||` take `bool` only; `&&` and `||` evaluate the right operand only if it can change the result.

## The `??` operator

`a ?? b` is the value of the `Optional<T>` `a` if it has one, otherwise `b`; `b` is only evaluated when `a` has no
value. If `b` converts to `T`, the result is a `T` (`name ?? "guest"` is a `string`, `counts.TryGet(k) ?? 0` an
`int`); if `b` is an `Optional<T>` (or `null`), the result is an `Optional<T>` (`first ?? second`). `b` is used as a
value of `T` (a typeless `new { ... }`, a collection expression, `T`'s arithmetic for an integer `T`). `??` is
right-associative (`a ?? b ?? 0` is `a ?? (b ?? 0)`) and binds less tightly than `||` and more tightly than `?:`
(`a ?? 1 + 2` is `a ?? (1 + 2)`). The left side must be an `Optional<T>`: an `Error<T>` says why it has no value, and
`is` or a `switch` handles that.

## Conditional operator

`c ? a : b` takes a `bool` condition and evaluates one of the branches. The type is the type of `a` if `b` converts to
it, otherwise the type of `b` if `a` converts to it (`c ? 1 : 2.5` is a `double`, `c ? "a" : null` a `string`); with a
target type, both branches convert to it.

## Assignment

`x = v` stores `v` (converted to the type of `x`) in `x`, which must be a variable, a parameter, a field, an element, a
`*p` or an indexer (`x[k] = v` calls `Set`). Assigning a struct copies it; assigning a reference type shares it. The
value of an assignment is the stored value (`a = b = 5`). `x op= v` is `x = x op v` with `x` evaluated once. A
constant, a `const ref` parameter, a read-only slice element, a string's byte and a pattern variable cannot be
assigned.

`x ??= v` assigns `v` to the `Optional<T>` `x` only if `x` has no value; then `v` (a `T` or an `Optional<T>`, like the
right side of `??`) is evaluated, otherwise not. `x` is a variable, a parameter, a field or an element of an array or
slice, evaluated once; the indexer of a struct (`x[k]` with `Get` and `Set`) cannot be the target.

## Patterns: `is`

```ebnf
IsExpression = Expression 'is' [ 'not' ] ( Type [ Identifier ] | 'null' | 'error' [ Identifier ] ) ;
```

| Pattern | Matches |
|---|---|
| `x is T v` | `x` is an `Optional<T>` with a value, an `Error<T>` that succeeded, a finished `Thread<T>`, a union holding a `T`, an interface parameter of struct `T`, or an `Error<T, E>` that failed with a code (`T` = `E`); binds the value to `v` |
| `x is error e` | `x` (an `Error<...>`) failed; binds the whole result to `e` (`e.Message`, `e.Code`) |
| `x is T` / `x is error` | the same without a binding |
| `x is null`, `x is not null` | `x == null`, `x != null` |
| `x is not P` | the pattern `P` does not match |

`is` is only defined for these kinds of values (`3 is int` is a compile error), and a pattern that would always match
(`r is Error<T> x`) is one too. The value of an `is` is a `bool`; the binding of a pattern is a new variable that is
only defined where the pattern is known to have matched: in the `then` branch of an `if` and its `&&` chain, in the
body of a `while`, after `if (x is not T v) return;` (the `else` branch and after the `if` when the branch cannot
complete). A `not` pattern with a binding is only allowed as the whole condition of an `if`.

## try

`try e` takes an `Error<T>` and gives its value; if it failed, the enclosing function returns the same error at once
(after the `using` resources of the function are disposed). The function must return a compatible result:
`Error<U>`, or `Error<U, E>` for an `Error<T, E>`. `try` does not work on `Optional<T>`. In `Error<int> Main()`, a
failure ends the program with exit code 1.

## Error values

```ebnf
ErrorValue = 'error' '(' Expression [ ',' Expression ] ')' ;
```

`error("message")`, `error("message", code)` and `error(E.X)` make a failed result; they convert to any `Error<T>`.
The code is an `int` (0 if none is given), or a member of the error enum `E` for an `Error<T, E>` (where an `int` code
is a compile error). `error(E.X)` has the member's name as its message.

## start

`start f(args)` starts a [thread function](declarations.md#thread-functions) on a new thread and gives its handle
(`Thread` or `Thread<T>`) at once. `start` must be followed directly by a call of a thread function; a thread function
cannot be called any other way. The arguments are copied for the new thread (see [memory](memory.md#threads)).

## Creating values

| Expression | Result |
|---|---|
| `T { F = a, G = b }` | a struct with the named fields set, the others with their default |
| `new T { F = a }` | the same |
| `new T()` | a struct with all fields at their default (there are no constructors) |
| `new { F = a }`, `new()` | the same, with `T` taken from the target type (a declaration with a type, an assignment, a `return`, an argument, a field) |
| `new T[n]` | an array of `n` default elements; `new T[n][]` an array of `n` null arrays |
| `new T[] { a, b }` | an array of the listed elements |

A field can be set only once in an initializer; a private field (`_x`) only inside the struct's own methods.

### Collection expressions

```ebnf
Collection = '[' [ Element { ',' Element } [ ',' ] ] ']' ;
Element    = Expression | '..' Expression ;
```

`[a, b, ..c]` lists elements; `..c` spreads an array, a slice or a collection with `ToArray()`. It has no type of its
own; it becomes the type it is used as:

| Target | Result |
|---|---|
| `T[]` | a new array of exactly these elements |
| `Slice<T>`, `ReadOnlySlice<T>` | a new array, as a slice (in a constant: static data) |
| `Fixed<T, N>` | the elements in place; their number must be `N` |
| a struct with `static Create()` and `Add(T)` | `Create()`, then `Add` for every element (`List<T>`, `HashSet<T>`, ...) |
| `Optional<T>`, `Error<T>` | the `T`, wrapped |
| no target (`var x = [1.5, 2.0];`) | an array of the first element's type |

The elements convert to the element type like in an assignment.

## Lambdas

```ebnf
Lambda       = LambdaParams '=>' ( Expression | Block ) ;
LambdaParams = Identifier | '(' [ Identifier { ',' Identifier } | Param { ',' Param } ] ')' ;
```

A lambda is a function written as an expression. It has no type of its own: it converts to the `Action`/`Func` type
it is used as, which gives its parameter and result types (written parameter types must match). It **captures a copy**
of every variable of the enclosing function it uses, when it is created; the copies are read-only in the lambda. In
a method, it works on a copy of `this`. A lambda without captures is a plain function (also for C); one with captures
carries a reference-counted block. For generic functions, a lambda's result type can give a type argument
(`list.Select(x => x.Name)`). `var f = x => x;` is a compile error.

## Interpolated strings

`$"text {e} text"` is the concatenation of the text and the values, each converted to text like with `+`: strings and
string slices as they are, numbers as the shortest text that reads back as the same value, `bool` as `true`/`false`,
`char` as the character, enums as the name of their member, structs by their `string ToString()` method. A hole
`{e,n}` pads the text with spaces to `n` bytes (on the left; on the right with `-n`), `{e:F}` formats a number with a
[number format](../stdlib.md) (checked when the program is compiled), `{e,n:F}` does both. An interpolated string
without format and alignment is a constant expression if its holes are.

## embed

`embed("file")` is the content of a file as a `string` constant, read when the program is compiled;
`embed("*.txt")` (with `*` or `?` in the file name) the contents of the matching files as a `ReadOnlySlice<string>`,
sorted by name, and `embed_filenames(...)` their names; `embed_lines("file")` the lines of one file as a
`ReadOnlySlice<string>`, without their line ends. It is only allowed as the whole initializer of a constant, with
a string literal; the rules for finding the file are in [constants](../language/constants-and-globals.md#embedded-files-embed-embed_filenames-and-embed_lines).

## Constant expressions

A constant expression is computed when the program is compiled. It may contain literals, constants, enum members,
`sizeof(T)`, casts between numbers, enums and `char`, the arithmetic, bitwise, shift, comparison and logical
operators, `?:`, string concatenation (also with numbers, `bool`, `char` and enums), interpolated strings without
formats, `Length`, indexing and slicing of constant strings and slices, collection expressions of constants (with
spreads), `Enum<T>.Count`/`Min`/`Max`/`Values`/`Names`, and `embed`. The computation follows the rules of the code
that would run, but an overflow, a division by zero or an index out of range is a compile error. Constant expressions
are required for constants and the values of enum members.
