# Debugging with gdb and lldb

`cshiftc -g` (or `"debug": true` in `cshift.json`) adds debug information to the program:

* every function with its name and source file, every instruction with its line and column;
* parameters, local variables and global variables with their types: numbers, `bool`, `char`, enums (shown by
  name), structs with their fields, `Optional<T>`, `Error<T>`, unions, `Fixed<T, N>`, strings, arrays, slices and the
  collections.

gdb and lldb can then stop on a line or a function, step through the code, show the call stack with files and lines,
and print variables. The information is in DWARF, the format of every Linux and MinGW debugger.

```
cshiftc -g -O0 prog.csh -o prog
gdb ./prog
(gdb) break prog.csh:15          a line
(gdb) break Square               a function
(gdb) break Counter.Add          a method (struct name, dot, method name)
(gdb) run
(gdb) bt                         where the program is: Square (x=3) at prog.csh:15, called from Main at prog.csh:25
(gdb) info args                  the parameters
(gdb) info locals                the variables of the function
(gdb) print person               {Name = "Ann", Age = 42, Home = {X = 3, Y = 4}, Favorite = Green, Lucky = 7}
(gdb) print person.Home.X        a field
(gdb) next / step / finish       the next line / into a call / out of the function
```

## VS Code

With the CShift extension and [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)
(`vadimcn.vscode-lldb`), **F5** in a `.csh` file builds its program with `-g -O0` (into `bin/debug/`, next to the
normal build) and runs it under lldb: breakpoints in the editor, stepping, the call stack, and the variables with the
pretty printers below. CodeLLDB brings its own lldb, also on Windows, so nothing else has to be installed. A launch
configuration (`"type": "cshift"`) can name the project and the program's arguments, see the
[extension's README](../vscode-extension/README.md#debugging).

## gdb and lldb

With lldb: `breakpoint set -f prog.csh -l 15`, `breakpoint set -n Square`, `run`, `bt`, `frame variable`,
`frame variable person.Home`, `next`, `step`.

## Strings, arrays and collections

A string or an array is a reference to a block in memory (`{ refcount, length, elements }`); the debugger alone would
show its address. The **pretty printers** in `tools/debug` show the contents instead:

```
(gdb) info locals
name = "Ann"
numbers = int32[] of length 3 = {1, 2, 3}
words = List with 2 elements = {"one", "two"}
ages = Dictionary with 1 entries = {["Ann"] = 42}
part = Slice<int32> of length 2 = {2, 3}
text = "el"                       (a StringSlice)
lucky = 7                         (Optional<int32>; null when it has no value)
shape = Circle: {R = 1.5}         (a union: the member it holds)
```

* **gdb:** every program built with `-g` carries the printers itself (in its section `.debug_gdb_scripts`). gdb loads
  them when the program's folder is allowed; the first time it explains how. Allow your projects once in
  `~/.gdbinit`:

  ```
  add-auto-load-safe-path /home/me/projects
  ```

  Or load them by hand: `source <cshift>/tools/debug/cshift_gdb.py`.
* **lldb:** `command script import <cshift>/tools/debug/cshift_lldb.py` (or put the line into `~/.lldbinit`).
  lldb shows an array's first elements in its summary (`length 3 [1, 2, 3]`), `frame variable numbers[1]` one element.

Covered: `string`, arrays, `Slice<T>`/`ReadOnlySlice<T>`/`StringSlice`, `List<T>`, `Stack<T>`, `Queue<T>`,
`Dictionary<K, V>`, `HashSet<T>`, `StringBuilder`, `Optional<T>`, `SharedPtr<T>` and unions. Without the printers the
fields can still be read: `print *name` shows `{refcount, length, chars}`, `print numbers->items[1]@2` two
elements.

## Good to know

* **Optimization:** with `-O2` the optimizer moves and merges code, keeps variables in registers and removes them, so
  the debugger jumps between lines and shows `<optimized out>`. For debugging, use `-O0` (`"optimize": 0`).
* **Names:** functions in a namespace keep it (`CShift.CodeGen.EmitBlock`); gdb finds them with
  `break 'CShift.CodeGen.EmitBlock'`, by file and line, or with `rbreak EmitBlock`. Generic functions are named with
  their type arguments: `System.List<int32>.Add`.
* **Blocks:** a variable is only visible in the block (`{ }`, loop) it is declared in; two variables with the same
  name in different blocks do not mix.
* **`ref` parameters and `this`** are pointers: `print *count`, `print this->Value` (or `print *this`).
* **The standard library** is compiled into the program from the copy inside `cshiftc`; its functions appear as
  `<stdlib>/list.csh` without source text (with `--stdlib <dir>` the debugger finds the files).
* **Panics:** `break __cs_panic_at` (and `__cs_panic_index`, `__cs_panic`) stops before the program ends with a panic;
  `bt` then shows where it happened.
* Code that the compiler adds itself (reference counting helpers, the start of threads, the initialization of
  globals) has no lines.
* **Windows:** the programs are MinGW programs with DWARF debug information, for gdb and lldb, not for the Visual
  Studio debugger (which reads PDB files). The release contains no debugger: use VS Code with CodeLLDB, or install lldb
  (part of LLVM, `winget install LLVM.LLVM`) or gdb (MSYS2: `pacman -S mingw-w64-ucrt-x86_64-gdb`). The gdb printers
  are not in Windows programs (that needs an ELF section); load them with `source`.
* **Global variables** are found by their name (`print Counter`, `info variables Counter`); constants are not
  variables and have no debug information.
* The m68k backend (AmigaOS) writes no line information: with `-g` an executable has the names of its functions and
  globals (HUNK_SYMBOL), for Amiga debuggers and [tools/amiga/profile.py](amiga.md#where-the-time-goes-toolsamigaprofilepy).
