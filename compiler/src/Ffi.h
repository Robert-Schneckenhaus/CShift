#pragma once

// FFI: importing C headers into CShift (see FFI.md).
//
//   using Sqlite3 from "sqlite3.h";
//
// A header is parsed with libclang once and turned into a .ffi file (JSON) that lists its functions, structs,
// enums and constants with CShift types. The compiler reads only the .ffi file; it is regenerated when the header
// (or a header it includes) changes.

#include <string>
#include <vector>

#include "AST.h"

struct FfiOptions
{
    std::string target;                     // target triple the header is parsed for
    std::vector<std::string> includePaths;  // -I
    std::vector<std::string> defines;       // -D
    std::vector<std::string> apiPaths;      // headers whose path contains one of these texts belong to the API even if they are system headers
    std::string clang;                      // path of the clang executable (libclang is looked up next to it)
    bool verbose = false;
};

struct FfiImportRequest
{
    std::string name;     // namespace name
    std::string header;   // as written: "sqlite3.h" or "bindings/sqlite3.ffi"
    std::string baseDir;  // directory of the importing source file
    std::string cacheDir; // where generated .ffi files are stored
    SourceLoc loc;
};

struct FfiResult
{
    std::string ffiPath;
    std::vector<std::string> shimSources; // generated C files to compile and link (functions that take structs by value)
    bool regenerated = false;
};

// The format version of .ffi files. Files with another version are regenerated.
constexpr int kFfiFormat = 2; // 2: function pointers are Action/Func types

// Returns an up-to-date .ffi file for the request: the cached one if nothing changed, otherwise it is generated.
bool prepareFfi(const FfiImportRequest& request, const FfiOptions& options, FfiResult& result, std::string& error);

// Reads a .ffi file and creates the declarations of namespace 'name' (functions, structs, enums, constants).
std::unique_ptr<CompilationUnit> loadFfiUnit(const std::string& ffiPath, const std::string& name, Diagnostics& diag,
                                             std::string& error);

// Generates a .ffi file from a C header with libclang (FfiGenerator.cpp).
bool generateFfi(const FfiImportRequest& request, const FfiOptions& options, const std::string& ffiPath,
                 std::string& error);

// Helpers shared by the import and the generator.
std::string ffiHashFile(const std::string& path, bool& ok);
std::vector<std::string> ffiFlags(const FfiOptions& options);
