# Debugging with gdb and lldb

`cshiftc -g` (or `"debug": true` in `cshift.json`) adds debug information to the program: for every function its
name and source file, and for every instruction its line and column. gdb and lldb can then stop on a line or a
function, step through the code line by line and show the call stack with files and lines. The information is in
DWARF, the format of every Linux and MinGW debugger.

```
cshiftc -g -O0 prog.csh -o prog
gdb ./prog
(gdb) break prog.csh:15          a line
(gdb) break Square               a function
(gdb) break Counter.Add          a method (struct name, dot, method name)
(gdb) run
(gdb) bt                         where the program is: Square at prog.csh:15, called from Main at prog.csh:25
(gdb) next / step / finish       the next line / into a call / out of the function
```

With lldb: `breakpoint set -f prog.csh -l 15`, `breakpoint set -n Square`, `run`, `bt`, `next`, `step`.

* **Optimization:** with `-O2` the optimizer moves and merges code, so the debugger jumps between lines. For debugging,
  use `-O0` (`"optimize": 0` in `cshift.json`).
* **Names:** functions in a namespace keep it (`CShift.CodeGen.EmitBlock`); gdb finds them with
  `break 'CShift.CodeGen.EmitBlock'`, by file and line, or with `rbreak EmitBlock`. Generic functions are named with
  their type arguments: `System.List<int32>.Add`.
* **The standard library** is compiled into the program from the copy inside `cshiftc`; its functions appear as
  `<stdlib>/list.csh` without source text (with `--stdlib <dir>` the debugger finds the files).
* **Panics:** `break __cs_panic_at` (and `__cs_panic_index`, `__cs_panic`) stops before the program ends with a panic;
  `bt` then shows where it happened.
* Code that the compiler adds itself (reference counting helpers, the start of threads, the initialization of
  globals) has no lines.
* **Not yet:** the values of variables and parameters (`print x`, `info locals`), and Windows PDB files for the
  Visual Studio debugger. The m68k backend (AmigaOS) ignores `-g`.
