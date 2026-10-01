// Debug information (-g): the source location of every instruction, and a subprogram for every function of the
// program and the standard library. LLVM turns the metadata into DWARF, so gdb and lldb can set breakpoints on lines,
// step through the code and show where a program is (the call stack with files and lines). The metadata itself is
// written by Emit/IrWriter.csh; this file connects it with the source files and locations of the code generator.
//
// Functions the code generator makes up (the initializers of the globals, thread trampolines, the C entry point, the
// runtime helpers) have no subprogram: a debugger shows them without a line.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Emit;

// The location of what is being written: for the message of a panic, and for the debug information.
void SetLoc(Compiler cg, SourceLoc loc)
{
    cg.St[0].Loc = loc;
    // a location in another file (an expression from a declaration elsewhere) would get the wrong file
    if (cg.Ir.Debug && loc.File == cg.Fn[0].File)
        cg.Ir.SetDebugLoc(loc.Line, loc.Col);
}

// The file node of a source file: the full path for files on disk, the name for the embedded standard library.
string DebugFileOf(Compiler cg, int file)
{
    string path = cg.Diag.Files.Get(file);
    if (path.StartsWith("<"))
        return cg.Ir.DebugFile("", path);
    string full = Path.GetFullPath(path);
    return cg.Ir.DebugFile(Path.GetDirectory(full), Path.GetFileName(full));
}

// The compile unit, named after the first source file of the program.
string DebugUnitOf(Compiler cg)
{
    int file = 0;
    foreach (var f in cg.Files.ToArray())
    {
        if (!f.IsPrelude)
        {
            file = f.FileId;
            break;
        }
    }
    return cg.Ir.DebugUnit(DebugFileOf(cg, file));
}
