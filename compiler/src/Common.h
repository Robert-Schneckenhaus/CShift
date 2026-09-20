#pragma once

#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

// Position in a source file (1-based line and column).
struct SourceLoc
{
    int file = 0;
    int line = 0;
    int col = 0;
};

// Thrown to abort the declaration/statement currently being processed.
// It is caught at statement level, reported and compilation continues.
struct CompileError
{
    SourceLoc loc;
    std::string message;
};

class Diagnostics
{
public:
    int addFile(const std::string& name)
    {
        files.push_back(name);
        return (int)files.size() - 1;
    }

    void error(SourceLoc loc, const std::string& message)
    {
        errors += 1;
        std::cerr << location(loc) << "error: " << message << "\n";
    }

    void error(const CompileError& e) { error(e.loc, e.message); }

    void note(const std::string& message) { std::cerr << "note: " << message << "\n"; }

    bool hasErrors() const { return errors > 0; }

    std::vector<std::string> files;
    int errors = 0;

private:
    std::string location(SourceLoc loc) const
    {
        if (loc.line <= 0 || loc.file < 0 || loc.file >= (int)files.size())
            return "";
        return files[loc.file] + ":" + std::to_string(loc.line) + ":" + std::to_string(loc.col) + ": ";
    }
};

[[noreturn]] inline void fail(SourceLoc loc, const std::string& message)
{
    throw CompileError{loc, message};
}
