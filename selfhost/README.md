# selfhost: the CShift compiler in CShift

Goal: write the compiler (`compiler/`, C++ with LLVM) in CShift itself, so that it eventually compiles itself.

**Status:** the lexer and parser are complete and verified against the C++ compiler. The code generator covers almost
the whole language (structs, arrays, `Error<T>`/`Optional<T>`, generics, interfaces, enums, `switch`, pointers/`unsafe`,
function pointers, global variables and constants with a compile-time evaluator, the standard library as a prelude,
FFI); all 80 test cases in `tests/cases` pass with `cshc`. `tests/test.csh` behaves identically with `cshc` and with
the C++ compiler, and **`cshc` compiles itself** (`selfhost/bootstrap.sh`: stage 1 and stage 2 produce identical
LLVM IR). What's still open is tracked in [../Todo.md](../Todo.md) (in short: generating `.ffi` files from a C header
still needs the C++ compiler's libclang, and `cshc` doesn't yet find a bundled `toolchain/` next to itself).

```
selfhost/
├── cshift.json              project "cshc" (build with: cshiftc build selfhost)
├── src/
│   ├── Driver/              command line: Build.csh (options, build/run/new, clang), Project.csh (cshift.json), Json.csh,
│   │                        Ffi.csh (loading .ffi files), EmbeddedStdlib.csh (the stdlib embedded via EmbedTexts)
│   ├── Main.csh             command line: cshc [options] file.csh ... | --tokens | --ast
│   ├── Syntax/              namespace CShift.Syntax
│   │   ├── Location.csh     SourceLoc, Diagnostics
│   │   ├── Token.csh, Lexer.csh      the lexer (a port of compiler/src/Lexer.cpp)
│   │   ├── Ast.csh          the syntax tree: node types and the arenas (struct Ast)
│   │   ├── Parser.csh       the parser (a port of compiler/src/Parser.cpp)
│   │   └── TokenDump.csh, AstDump.csh    text dumps for comparing against the C++ compiler
│   ├── Sema/                namespace CShift.Sema
│   │   └── Types.csh        the type table: types are integers (ids), interned types compare with ==
│   ├── Emit/                namespace CShift.Emit
│   │   └── IrWriter.csh     writes LLVM IR as text (blocks, instructions, constants, declarations)
│   └── CodeGen/             namespace CShift.CodeGen
│       ├── Compiler.csh     compiler state, declarations, type resolution, function instances (CodeGen.cpp)
│       ├── Values.csh       values, reference counting, conversions (the first half of CodeGenExpr.cpp)
│       ├── Expr.csh         expressions (CodeGenExpr.cpp)
│       ├── Call.csh         calls, overload resolution, Console/Environment (CodeGenCall.cpp)
│       ├── Structs.csh      structs: layout, fields, methods, initializers, inheritance, retain/release per struct
│       ├── Arrays.csh       arrays: new T[], indexers, foreach, Array.Copy, Clone, release per array type
│       ├── Errors.csh       Error<T>/Optional<T>: error(...), is-patterns, try, retain/release of the result types
│       ├── Switch.csh       switch with constant and pattern labels
│       ├── Enums.csh        enums and constant integer expressions
│       ├── Generics.csh     type arguments, inference, interfaces, constraints, using/IDisposable
│       ├── Pointers.csh     pointers: *, &, arithmetic, casts
│       ├── FuncPtrs.csh     function pointers: Action/Func, method groups, indirect calls
│       ├── Layout.csh       sizes/alignment, layout of C structs (FFI)
│       ├── ConstEval.csh    the compile-time evaluator for constants, enum values, sizeof(T)
│       ├── Stmt.csh         statements, scopes, function bodies (CodeGenStmt.cpp)
│       ├── Runtime.csh      the runtime as IR text: strings, ARC, panics (CodeGenRuntime.cpp)
│       └── Module.csh       compiling the whole program, the entry point
├── compare.sh               front end: compares cshc against the C++ compiler (tokens and syntax tree)
├── status.sh, passing.txt   code generator: which cases in tests/cases pass
├── bootstrap.sh             cshc builds itself; stage 1 and 2 must produce the same IR
├── projects.sh              build tests/projects with cshc (cshc build/run/new)
└── DEPENDENCIES.md          analysis: what the new compiler needs at runtime and what can be dropped
```

## Building and using it

```
cshiftc build selfhost                                  # -> selfhost/bin/cshc
selfhost/bin/cshc hello.csh -o hello                    # write .ll, clang optimizes/compiles/links it
selfhost/bin/cshc --emit-llvm hello.csh -o hello.ll     # just the IR
selfhost/bin/cshc --tokens file.csh | --ast file.csh    # dumps (compare with cshiftc --dump-tokens / --dump-ast)
```

`cshc` writes **LLVM IR as text** (`.ll`) and calls `clang` (from `PATH` or `--cc`), which optimizes it, generates
machine code and links it. That way `cshc` itself needs no LLVM (no 100 MB link, no `unsafe` wrapper around the
LLVM-C API); like the C++ compiler, it produces the same kind of IR (as a reference: `cshiftc --emit-llvm`).

## Verifying it

* **Front end:** `bash selfhost/compare.sh <cshiftc> selfhost/bin/cshc` — the token and syntax-tree dumps, including
  error messages, must match the C++ compiler's for all 110 `.csh` files of the repository (including `selfhost/`'s
  own sources).
* **Code generator:** `bash selfhost/status.sh selfhost/bin/cshc -v` compiles `tests/cases/*.csh` with `cshc` and
  sorts the results into *pass*, *unsupported* (`cshc does not support …`, a feature not ported yet) and *FAIL* (an
  actual difference). The passing cases are listed in `passing.txt`; `status.sh --check` (part of
  `tests/run_tests.sh`) fails if one of them no longer passes. Newly-passing cases are added there (`status.sh -v`
  prints the list).

## Design decisions

* **The syntax tree lives in arenas.** CShift has no classes with reference semantics, and a struct cannot contain
  itself. So every kind of node has its own `List<...>` in `struct Ast`; nodes refer to each other through small
  handles (`Expr`, `Stmt`, `TypeRef`). The zero value (everything 0) means "no node". `ast.GetCall(e)` returns the
  `CallExpr`.
* **Types are integers.** A type is an id in `TypeContext`; as in C++, every type exists exactly once (interned), and
  type equality is `==`. Declarations (functions, structs, …) are indices into lists on `Compiler`.
* **The compiler is a handle.** Structs can't be split across files, so the C++ member functions of `CodeGen` become
  free functions `Emit…(Compiler cg, …)` spread across several files. All mutable state lives in lists, dictionaries
  and small arrays (`cg.St[0]`, `cg.Fn[0]`), so copies of `Compiler` see the same state (reassigning a field on a
  copy has no effect on the others).
* **Only one error.** `Fail(...)` prints the first error and stops. The parser uses `Error<T>` and `try` instead of
  exceptions (backtracking restores the position).
* **Code that has to be filled in later.** `IrWriter.Mark()/TakeSince()/AppendCode()` cut generated code out and
  reinsert it later (for `?:`, whose branches only know the common conversion type once both are finished).

## Gaps found along the way (fixed)

While porting, these things turned out to be missing from the language or the standard library; they now exist:

* `int Main(string[] args)`, `string.FromCStr(char*)`, `Console.WriteError(Line)`
* `Char.*`, `StringBuilder` (with `Substring`/`Truncate`), `HashSet<T>`, `Process.Run`
* FFI: `ffiApi` in the project file (umbrella header), `char*` accepting a `const char*` parameter

Known inconveniences (no blockers so far): a pattern variable's scope ends with the `if`; list elements can only be
retrieved as a copy (`Get`/`Set`); a large struct can't be split across several files; `Dictionary` and `List` are
structs (no `null`, "no environment" is an empty dictionary).
