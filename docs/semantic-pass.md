# The semantic pass

A pass that checks names and types before any code is written, so that the compiler reports every error of a program
in one run instead of stopping at the first one. It is built step by step; after every step the compiler works as
before, only with better error reports. This document is the plan and the record of where the work is.

## Why

Code generation (`selfhost/src/CodeGen`) checks while it writes IR, in one walk over the syntax tree. An error
(`Fail`) prints its message and ends the compiler, because the walk cannot continue without a value to write. A
separate pass that only computes types can continue: after an error the expression gets the *unknown type*, and
everything that involves an unknown type is not checked any further, so one mistake gives one message.

The same pass later allows what the one-walk design cannot do:

* checking the body of a generic function once, against its constraints, instead of once per instantiation (and not
  at all while nothing instantiates it);
* inferring type arguments from lambdas (`list.Select(x => x.Name)`) and lambda parameters from a declared type;
* tools that need to know what a name means without generating code (hover, go to definition).

## Design

**Where it runs.** `CompileProgram` (CodeGen/Module.csh) first registers and checks the declarations (constants,
globals, struct layouts) as before, then calls `CheckProgram` (`selfhost/src/Check`), which walks the body of every
function and method of the program. If the checker reported errors, the compiler stops there; otherwise code generation
runs as before.

**One set of rules.** The checker must never reject a program that code generation accepts, and it must report the
same message. So the rules are not written twice: where code generation decides something (the result type of `a + b`,
whether a value converts, which overload is called), that decision is a function that returns a result or the error
message instead of failing, and both the checker and code generation call it. Code generation still fails on the
message; the checker reports it and continues. Moving the decisions out of the `Emit...` functions is also the step
towards the end state, in which code generation only reads what the checker found.

**Values without code.** The checker computes `Value`s like code generation does (type, lvalue, `const`, literal
information), with an empty operand, so the shared decision functions (`ConversionCost`, `ResolveOverload`, ...) work on
them unchanged. Helpers of code generation that write a little IR while they look something up (a load of a `ref`
parameter, a string literal) run with a scratch `IrWriter`, so the checker never changes the real output.

**Scopes.** The checker opens and closes scopes at exactly the places code generation does, with the same list of
variables (`FnState.Vars`), so name lookup is the same function in both. Where the checker does not follow a rule
exactly yet, it errs on the side of accepting: a pattern variable may be visible a little longer, a construct it does
not know yet has the unknown type.

**The unknown type** (`TypeKind.Unknown`) is never shown to the user. The checker gives it to every expression it
cannot type yet and to every expression that had an error; an operation with an unknown operand has an unknown result
and reports nothing. A type name that does not exist is the unknown type too, wherever it is written (a field, a
parameter, a constant, a global, a local variable, a type argument): a type made of it (`Foo[]`, `List<Foo>`,
`Func<Foo, int>`) is unknown, a value converts to and from it, and a constant of it has an unknown value
(`ConstKind.Unknown`). A message of the checker that would name the unknown type is left out, and the same message at
the same place is printed once.

**Declarations.** The declarations are registered and checked before the checker runs, in a mode in which their errors
are reported and the compiler goes on (`Recover`, while `CgState.Recovering` is set, from the start until the checker
has run): names defined twice (the first one stays), types that cannot be resolved (`RecoverType`: unknown names,
wrong type arguments, `void` where a value is needed; the type is unknown), fields declared twice or hiding an
inherited one (left out), struct bases, enum bases and members, union members and interfaces, parameters, `thread`
signatures, the size of `Fixed<T, N>`, constant initializers that are not constant and errors in constant values
(overflow, a division by zero, an operator that does not apply; `ConstError`, the value is unknown). The initializers
of globals are checked by the checker like function bodies and generated after it. Every struct and union of the
program is checked, also if nothing uses it. The checker then runs as well, and the compiler stops after it if anything
was reported; only a syntax error stops it right after parsing. Code generation after the checker never sees the
unknown type; there `Recover` ends the compiler like `Fail`.

**Generic bodies.** Every generic function and every method of a generic struct of the program is checked once, also
if nothing instantiates it: its type parameters are the unknown type. What depends on a type parameter (a call of a
method of `T`, `==` on `T`, a conversion to `T`) is not checked there but when the body is instantiated (code
generation, as before); everything else is (names, the other types, missing returns, ...). One thing that depends on
a type parameter is checked: a method called on a parameter or variable declared with a type parameter `T` must belong
to one of the interfaces of `T`'s constraints (or be `ToString`), like in C#. A method of a generic
struct is checked with the checker's own instance of the struct (`GetCheckingStructType`: the type arguments are the
unknown type), which is never verified against constraints or interfaces and whose methods are never generated; a
generic struct with a generic base struct is left to its instantiations for now. Messages name these functions with
their type parameters (`Max<T>`, `Box<T>.Get`).

**Lambdas.** A lambda passed as a `Func<..., R>` gives `R` to the inference of type arguments (`InferTypeArgs`,
`InferFromLambdas`) once its parameter types are known from the other arguments (or other lambdas):
`LambdaResultType` checks the body with those parameter types and returns the type of its expression or of its first
`return x`. The inference is shared with code generation, so this runs while a function is being written: on copies of
the function's state and with scratch IR buffers, and it reports nothing (`CgState.Muted`); if the body has an error, the
message of the failed inference names it.

**Tooling.** `cshiftc check` runs the front end (declarations and the checker, `CgState.FrontEndOnly`) and reports the
errors without generating anything. `cshiftc query --at <file> <line> <col>` does the same with the symbol index
(`CgState.Indexing`, `Check/Index.csh`): every name the checker resolves (locals, parameters, fields, constants,
globals, functions and methods, the functions the language provides, types, enum members; variables, parameters and
functions also where they are declared) is recorded with its place, the place of its declaration and a hover text, and the answer for the position is written as JSON (`{"hover": ..., "definition": {"file", "line",
"col"}}`). `--references` adds every place where the name is written (`"references"`: the entries with the same
declaration), `--members` what can follow `name.` (`"members"`: fields, methods, enum members, from the type the index
records for the name), and `--outline <file>` instead of `--at` answers with the declarations of a file
(`"symbols"`). `--overlay <file> <text file>` replaces a source with the unsaved text of an editor. Columns count bytes
(UTF-8), like the error messages.

**Errors that still stop the compiler.** Everything that is not moved into the checker or `Recover` yet still fails
in code generation or in the declaration checks, as before; the errors reported until then have been printed. The number of
errors is limited (50); after that the compiler stops.

## Steps

| Step | Contents | State |
|---|---|---|
| 1 | Unknown type, error limit, the checker for statements and scopes, names, literals, operators, assignments, conditions, variable declarations, `return`, calls of functions and methods by name, fields | done |
| 2 | Member calls of every kind (static, namespaces, builtins like `Console`, strings, arrays), `new`, struct initializers, indexing and slices | done |
| 3 | Patterns (`is`, `switch`), unions, `Error<T>`/`Optional<T>`/`try`, lambdas and collection expressions, casts, interfaces, threads | done: `is`, `switch` labels, patterns and exhaustiveness, `try`, `error(...)`, casts, calls through interfaces and unions, the bodies of lambdas, missing returns and fall-through (structural reachability), collection expressions (element types, spreads, `Fixed<T, N>` sizes, builder structs, also as arguments), `start` and `Thread.Cancelled`. The signatures of `thread` functions are checked with the other declarations (step 4); that a thread does not reach a global variable needs the call graph of the generated code (step 5) |
| 4 | Declarations with recovery: constants, globals, struct fields and signatures (also of `thread` functions) report and continue | done: see *Declarations* above |
| 5 | Code generation reads the checker's results (types, chosen overloads, conversions) and its own checks go away | in progress: the initializers of globals are checked by the checker (and generated after it), errors in constant values recover (`ConstError`: the value is unknown). Every error of the test cases is reported by the checker (all in one run) except those that need the whole program or its call graph: the order of the global initializers, a thread that reaches a global, the missing entry point (`cshiftc check` of a library file must not report it) and the inference of type arguments from a lambda with an error |
| 6 | Generic bodies checked once against their constraints; type arguments inferred from lambdas | done: generic bodies are checked once (see *Generic bodies*), type arguments are inferred from lambdas (see *Lambdas*), and a method called on a variable whose declared type is a type parameter must be a method of one of its constraints (or `ToString`; `TypeParamMethodError`) |
| 7 | Tooling on top of the checker's results | done: `cshiftc check` and `cshiftc query` with the symbol index (see *Tooling*), used by the VS Code extension for errors, hover, go to definition, find all references, the outline and completion after `.`; renaming and completion of names (not only members) can follow |

Tests: a case can list several `// expect-error:` lines; all of them must be in the compiler's output
(`tests/cases/err_several_*.csh`).
