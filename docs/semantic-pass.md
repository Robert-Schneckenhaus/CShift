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
and reports nothing.

**Errors that still stop the compiler.** Everything that is not moved into the checker yet still fails in code
generation or in the declaration checks, as before; the errors reported until then have been printed. The number of
errors is limited (50); after that the compiler stops.

## Steps

| Step | Contents | State |
|---|---|---|
| 1 | Unknown type, error limit, the checker for statements and scopes, names, literals, operators, assignments, conditions, variable declarations, `return`, calls of functions and methods by name, fields | done |
| 2 | Member calls of every kind (static, namespaces, builtins like `Console`, strings, arrays), `new`, struct initializers, indexing and slices | done |
| 3 | Patterns (`is`, `switch`), unions, `Error<T>`/`Optional<T>`/`try`, lambdas and collection expressions, casts, interfaces, threads | in progress: `is` on results, `switch` labels and patterns (also on unions), `try`, `error(...)`, casts and the bodies of lambdas are done; interfaces, collection expressions and threads follow |
| 4 | Declarations with recovery: constants, globals, struct fields and signatures report and continue | |
| 5 | Code generation reads the checker's results (types, chosen overloads, conversions) and its own checks go away | |
| 6 | Generic bodies checked once against their constraints; type arguments inferred from lambdas | |
| 7 | Tooling on top of the checker's results | |

Tests: a case can list several `// expect-error:` lines; all of them must be in the compiler's output
(`tests/cases/err_several_*.csh`).
