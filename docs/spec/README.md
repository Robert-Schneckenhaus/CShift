# CShift language reference

The complete and precise description of the language: what a program may contain and what it means. The
[language guide](../language/README.md) teaches the same language with examples; the
[reference of the standard library](../stdlib.md) (and the website's reference pages) describes the library.

| Chapter | Contents |
|---|---|
| [Lexical structure](lexical.md) | source text, comments, identifiers, keywords, literals, operators |
| [Programs and names](programs.md) | files, namespaces, `using`, C imports, the entry point, name lookup |
| [Types](types.md) | every kind of type, their values, defaults, sizes, and the conversions between them |
| [Declarations](declarations.md) | structs, interfaces, unions, enums, error enums, functions, constants, globals, generics |
| [Expressions](expressions.md) | operators and their precedence, arithmetic, patterns, calls, initializers, lambdas |
| [Statements](statements.md) | blocks, declarations, control flow, `switch`, `using`, `unsafe`, `unchecked` |
| [Memory](memory.md) | value and reference semantics, ARC, `ref`, pointers, thread isolation |
| [Run time](runtime.md) | program start and end, exit codes, panics, checked arithmetic, targets |
| [Grammar](grammar.md) | the complete syntax in EBNF |

## Notation

The syntax is written in EBNF:

| Notation | Meaning |
|---|---|
| `'if'`, `';'` | the word or symbol itself |
| `Name` | another rule |
| `a b` | `a` followed by `b` |
| `a \| b` | `a` or `b` |
| `[ a ]` | `a` or nothing |
| `{ a }` | `a` repeated zero or more times |
| `( a )` | grouping |

"A compile error" means that the compiler rejects the program with a message; "a panic" means that the program stops
when it runs (see [run-time errors](runtime.md)). Where the language differs from C# - which it resembles closely -
the reference says so.
