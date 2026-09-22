// Source positions and error reporting.

namespace CShift.Syntax;

using System;

// Position in a source file (1-based line and column).
struct SourceLoc
{
    int File;
    int Line;
    int Col;

    // Errors are Error<T> values. Their integer code carries the position (the file is known to the reporter).
    int Pack()
    {
        int col = Col > 4095 ? 4095 : Col;
        return Line * 4096 + col;
    }

    static SourceLoc Unpack(int file, int code)
    {
        return SourceLoc { File = file, Line = code / 4096, Col = code % 4096 };
    }
}

// Collects the names of the source files and counts errors. Copies share the same state (like List<T>).
struct Diagnostics
{
    List<string> Files;
    int[] _errors;

    static Diagnostics Create()
    {
        return Diagnostics { Files = List<string>.Create(), _errors = new int[1] };
    }

    int AddFile(string name)
    {
        Files.Add(name);
        return Files.Count() - 1;
    }

    int ErrorCount()
    {
        return _errors[0];
    }

    bool HasErrors()
    {
        return _errors[0] > 0;
    }

    // Prints "file:line:col: error: text" to stderr.
    void ReportAt(SourceLoc loc, string message)
    {
        _errors[0] += 1;
        Console.WriteErrorLine(Location(loc) + "error: " + message);
    }

    // Reports a failed Error<T> whose code was created with SourceLoc.Pack().
    void Report(int file, string message, int code)
    {
        ReportAt(SourceLoc.Unpack(file, code), message);
    }

    string Location(SourceLoc loc)
    {
        if (loc.Line <= 0 || loc.File < 0 || loc.File >= Files.Count())
            return "";
        return Files.Get(loc.File) + ":" + loc.Line.ToString() + ":" + loc.Col.ToString() + ": ";
    }
}
