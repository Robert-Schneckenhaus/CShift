# Statements

Statements appear in the bodies of functions, methods and lambdas.

```ebnf
Statement = Block | ';' | LocalDecl | ConstDecl | ExpressionStatement
          | IfStatement | WhileStatement | DoStatement | ForStatement | ForeachStatement | SwitchStatement
          | 'break' ';' | 'continue' ';' | 'return' [ Expression ] ';'
          | UsingStatement | UsingDecl | UnsafeStatement | UncheckedBlock ;
```

## Blocks and scopes

```ebnf
Block = '{' { Statement } '}' ;
```

A block is a scope: a variable declared in it is visible from its declaration to the end of the block. A name can be
declared only once in a block: a second local variable, local constant or pattern variable with the same name in the
same block is a compile error, and so are two parameters with the same name. A declaration in an inner block may
reuse the name of a variable of an enclosing block (or a parameter); the inner variable hides the outer one until the
inner block ends. The bodies of `if`, the loops, `switch` sections and `using (...)` are scopes of their own, also
when they are a single statement.

`;` alone is the empty statement.

## Local declarations

```ebnf
LocalDecl = ( Type | 'var' ) Identifier [ '=' Expression ] ';' ;
```

A local variable has a type, or `var` and an initializer whose type it takes (`var` without an initializer is a compile
error). A variable without an initializer starts with its [default value](types.md#default-values). One declaration
declares one variable (`int a, b;` is not allowed).

A local constant (`const int N = 4;`) is described in [declarations](declarations.md#constants). There are no `ref`
locals: a reference to another variable is only a [`ref` parameter](memory.md#ref-and-const-ref).

## Expression statements

```ebnf
ExpressionStatement = Expression ';' ;
```

Any expression can be a statement; its value is discarded. Typically it is a call or an
[assignment](expressions.md#assignment). Discarding an `Error<T>` result is allowed; use `try` (or check it) to react
to a failure.

## `if`

```ebnf
IfStatement = 'if' '(' Expression ')' Body [ 'else' ( IfStatement | Body ) ] ;
Body        = Statement ;   (* but not a control statement, see below *)
```

The condition must be a `bool` (there is no conversion of numbers, pointers or strings to `bool`). An `else` belongs to
the nearest `if`. Pattern variables of the condition (`if (x is int v)`) are visible in the statement after it where
the pattern has matched (see [expressions](expressions.md#patterns-is)).

**Nested control statements need braces.** The body of `if`, `else`, a loop or `using (...)` may be a single statement,
but not an `if`, `while`, `do`, `for`, `foreach`, `switch` or `using (...)` (a compile error); write a block around it.
`else if` is allowed.

```csharp
foreach (var item in items)
    if (item.Done)          // error: a nested 'if' needs braces
        Count();
```

## Loops

```ebnf
WhileStatement   = 'while' '(' Expression ')' Body ;
DoStatement      = 'do' Body 'while' '(' Expression ')' ';' ;
ForStatement     = 'for' '(' [ LocalDecl-or-Expression ] ';' [ Expression ] ';' [ Expression { ',' Expression } ] ')' Body ;
ForeachStatement = 'foreach' '(' ( Type | 'var' ) Identifier 'in' Expression ')' Body ;
```

`while` tests the condition before every iteration, `do` after it (the body runs at least once). The conditions are
`bool`s.

**`for`**: the initializer (one declaration or one expression) runs once; its variable is visible in the whole loop
and not after it. The condition is tested before every iteration (none means `true`). The iterators, separated by
commas, run after every iteration and after `continue`. There is no `++`; write `i += 1`.

**`foreach`** runs the body once for each element of:

| Collection | Element |
|---|---|
| an array `T[]`, a `Slice<T>`, a `ReadOnlySlice<T>`, a `Fixed<T, N>` | `T` |
| a `string` | `char`: the **bytes** of the UTF-8 text (a character outside ASCII is several bytes) |
| a struct with the methods `int Count()` and `T Get(int index)` (`List<T>`, `Stack<T>`, ...) | `T`, the result of `Get` |

The collection expression is evaluated once, before the first iteration. The loop variable gets a **copy** of each
element: assigning to it (or to its fields) does not change the collection. With an explicit type, the element must
convert implicitly to it. A struct collection is read with `Get(0)` to `Get(Count() - 1)`, calling `Count()` before
every iteration.

## `break` and `continue`

`break` ends the innermost loop or `switch`; `continue` goes to the next iteration of the innermost loop (in a `for`,
to its iterators). Both are compile errors outside of a loop (`break` also in a `switch`). There are no labels; to
leave several loops, use a `return` or a flag.

## `return`

`return;` ends a `void` function (or an `Error<void>` one, with success). `return e;` ends a function with the value
`e`, which must convert implicitly to the result type; for a result type `Error<T>`, a `T` is a success and an
[error value](expressions.md#error-values) a failure. A function with a result must not reach the end of its body
(see [declarations](declarations.md#functions)). In a lambda, `return` ends the lambda.

## `switch`

```ebnf
SwitchStatement = 'switch' '(' Expression ')' '{' { SwitchSection } '}' ;
SwitchSection   = CaseLabel { CaseLabel } { Statement } ;
CaseLabel       = 'case' Expression ':' | 'case' Type Identifier ':' | 'default' ':' ;
```

The subject is evaluated once. The labels are tested in the order of the program; the section of the first label
that matches runs. If no label matches, the `default` section runs, or nothing. A switch has at most one `default`.

**Value labels** (`case 1:`, `case Color.Red:`, `case "text":`, `case null:`) compare the subject with `==`; the value
is any expression that can be compared with the subject (usually a constant). **Pattern labels** take values apart:

| Subject | Label | Matches |
|---|---|---|
| a [union](declarations.md#unions) | `case Circle c:` | the union holds a `Circle`; `c` is a copy of it |
| `Error<T>`, `Optional<T>` | `case T v:` | a success / a value; `v` is it |
| `Optional<T>` | `case null:` | no value |
| `Error<T>` | `case error e:` | a failure; `e` is the `Error` |
| `Error<T, E>` | `case E.Member:` | a failure with that code |
| `Error<T, E>` | `case E code:` | a failure; `code` is its code |

The name of a pattern label is visible in its section. A label that declares a name should have a section of its own.

**No fall-through.** The end of a section must not be reachable: every section ends with `break`, `return`,
`continue`, a call that does not return (`Environment.Panic`, `Environment.Exit`) or another statement that leaves
it (a compile error otherwise, also for the last section).

**Exhaustiveness.** A `switch` without `default` over an enum must have a label for every member (members with the
same value count together); over a union, a label for every member type; over an `Error<T, E>` with code labels and
without `case error e`, a label for every code. A missing case is a compile error that names it.

```csharp
switch (LoadLevel(n))
{
case Level level:
    Play(level);
    break;
case LoadError.NotFound:
    Console.WriteLine("no such level");
    break;
case error e:
    Console.WriteLine(e.Message);
    break;
}
```

## `using`

```ebnf
UsingStatement = 'using' '(' ( Type | 'var' ) Identifier '=' Expression ')' Body ;
UsingDecl      = 'using' [ Type | 'var' ] Identifier '=' Expression ';' ;
```

The variable's type must be a struct that implements `IDisposable`. `using (...) body` calls `Dispose()` on the
variable when the body is left; `using var x = ...;` (or `using x = ...;`, or with a type) when the enclosing block is
left. "Left" includes `break`, `continue`, `return` and a failure passed on by `try`; several variables are disposed in
the reverse order of their declarations. A [panic](runtime.md#panics) ends the program without disposing.

At the top level of a file, `using N;` is a [namespace import](programs.md#using), not this statement.

## `unsafe`

```ebnf
UnsafeStatement = 'unsafe' Block | 'unsafe' Statement ;
```

`unsafe { ... }` makes a block an [unsafe context](memory.md#unsafe): pointers can be used in it. `unsafe` before a
single statement makes only that statement unsafe, without a scope of its own, so a declaration in it stays visible
afterwards:

```csharp
unsafe int* p = &x;
unsafe Console.WriteLine(*p);
```

## `unchecked`

```ebnf
UncheckedBlock = 'unchecked' Block ;
```

In an `unchecked` block, integer arithmetic and conversions wrap around instead of panicking on an overflow (see
[expressions](expressions.md#integer-arithmetic)). Division by zero and index checks stay. `unchecked(e)` does the
same for one expression.
