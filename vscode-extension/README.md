# CShift for VS Code

Support for **CShift** (`.csh`), the native, C#-like systems language of this repository:

* **Errors while you type**: the whole program is checked (with `cshiftc check`) when a file is opened, saved, and
  after a short pause in typing; all errors of the program are shown in the editor and in *Problems*, also those of
  files that are not open. Unsaved changes are included.
* **Hover**: the type of a variable, parameter, field or constant (also where it is declared), the signature of a
  function or method (also where it is declared, and of those the language provides, like `Console.WriteLine` or
  `x.ToString()`), what a type is (`struct Person`, `enum Color`, ...), the value of an enum member or constant (for a constant from `embed("file")`, the first lines of the file). In a
  generic function the types are shown as written (`ref T slot`). Namespaces show what they are (`namespace Math`,
  `namespace Glfw (imported from "GLFW/glfw3.h")`), fields with a function type (also C function pointers) show the
  signature they are called with.
* **Go to definition** (F12, Ctrl+click) for the same names: into the file where they are declared; for a name
  imported from a C header, into the header at the line it is declared in.
* Syntax highlighting (keywords, types, generics, numbers with suffixes, strings, comments, `link`, `namespace`/`using`),
  bracket pairs, auto-indent, comment toggling, `// region` folding, snippets (`main`, `struct`, `fn`, `foreach`,
  `switch`, `try`, `ifis`, `dict`, …) and a schema for `cshift.json`.

Errors, hover and go to definition come from the compiler itself (`cshiftc` 0.11 or later), so they always match
what the build reports.

## Installation

Every CShift release has the extension as `cshift-vscode-<version>.vsix`:

```
code --install-extension cshift-vscode-0.11.vsix
```

`cshiftc` must be in `PATH`, or set **CShift: Compiler Path** (`cshift.compilerPath`) to it, e.g.
`C:\cshift-0.11-windows-x64\cshiftc.exe`.

To build the package yourself: `cd vscode-extension`, then `npx @vscode/vsce package --allow-missing-repository`.

## Settings

| Setting | Default | |
|---|---|---|
| `cshift.compilerPath` | `""` | the `cshiftc` to use (empty: `cshiftc` from `PATH`) |
| `cshift.checkWhileTyping` | `true` | check after a pause in typing, not only on open and save |
| `cshift.checkDelay` | `700` | the pause in milliseconds |

The command **CShift: Check the program of the current file** checks on demand.

## Which program a file belongs to

The extension reads the `cshift.json` files of the workspace. A file belongs to the project whose `sources` contain it
(a source folder contains its files and subfolders; the nearest project wins if several do). A file outside every
project is checked alone.

## How it works

`extension.js` connects VS Code to `lib.js`, which runs `cshiftc check <project>` (errors on stderr, as
`file:line:col: error: text`) and `cshiftc query --at <file> <line> <col> <project>` (the name at the position, as
JSON). The texts of unsaved documents are passed as `--overlay <file> <temporary file>`. Positions are converted
between VS Code's characters and the compiler's UTF-8 byte columns.

Tests: `CSHIFTC=path/to/cshiftc node --test test/lib.test.js test/extension.test.js` (also run by
`tests/run_tests.sh`). `extension.test.js` runs the extension against a small stand-in for the `vscode` module.

The grammar is a TextMate grammar (`syntaxes/cshift.tmLanguage.json`); *Developer: Inspect Editor Tokens and Scopes*
shows the scopes under the cursor.
