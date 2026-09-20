// Generation of .ffi files from C headers with libclang.
//
// libclang is loaded at run time (next to the clang executable), so cshiftc itself does not depend on it and
// only needs it when a header has to be (re)parsed.

#include "Ffi.h"

#ifndef CSHIFT_HAVE_LIBCLANG

bool generateFfi(const FfiImportRequest&, const FfiOptions&, const std::string&, std::string& error)
{
    error = "this cshiftc was built without libclang support; use a pre-generated .ffi file instead";
    return false;
}

#else

#include <algorithm>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <map>
#include <set>

#include <clang-c/Index.h>

#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/FormatVariadic.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/raw_ostream.h>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace fs = llvm::sys::fs;
namespace path = llvm::sys::path;

namespace
{
// ---------------------------------------------------------------------------
// libclang loaded at run time
// ---------------------------------------------------------------------------

#define CLANG_FUNCTIONS(X)                                                                                                \
    X(clang_createIndex) X(clang_disposeIndex) X(clang_parseTranslationUnit) X(clang_disposeTranslationUnit)             \
    X(clang_getTranslationUnitCursor) X(clang_visitChildren) X(clang_getCursorKind) X(clang_getCursorSpelling)           \
    X(clang_getCString) X(clang_disposeString) X(clang_getCursorType) X(clang_getCanonicalType)                          \
    X(clang_getPointeeType) X(clang_getResultType) X(clang_getNumArgTypes) X(clang_getArgType)                           \
    X(clang_isFunctionTypeVariadic) X(clang_getTypeDeclaration) X(clang_getTypedefDeclUnderlyingType)                    \
    X(clang_Type_getNamedType) X(clang_Type_getModifiedType) X(clang_Type_getSizeOf) X(clang_Type_getAlignOf)           \
    X(clang_Cursor_getOffsetOfField) X(clang_Cursor_isBitField) X(clang_isConstQualifiedType)                            \
    X(clang_getEnumConstantDeclValue) X(clang_getEnumConstantDeclUnsignedValue) X(clang_getEnumDeclIntegerType)         \
    X(clang_getCursorLocation) X(clang_getFileLocation) X(clang_getFileName) X(clang_Location_isInSystemHeader)         \
    X(clang_getLocation) X(clang_getInclusions) X(clang_Cursor_isAnonymous) X(clang_getCursorDefinition)                 \
    X(clang_getCanonicalCursor) X(clang_hashCursor) X(clang_getNullCursor) X(clang_equalCursors)                        \
    X(clang_Cursor_isNull) X(clang_Cursor_getArgument) X(clang_Cursor_getStorageClass) X(clang_getTypeSpelling)         \
    X(clang_Cursor_isMacroFunctionLike) X(clang_Cursor_isMacroBuiltin) X(clang_getCursorExtent) X(clang_tokenize)        \
    X(clang_getTokenKind) X(clang_getTokenSpelling) X(clang_disposeTokens) X(clang_isInvalidDeclaration)                 \
    X(clang_getNumDiagnostics) X(clang_getDiagnostic) X(clang_getDiagnosticSeverity) X(clang_formatDiagnostic)           \
    X(clang_defaultDiagnosticDisplayOptions) X(clang_disposeDiagnostic) X(clang_getClangVersion)                         \
    X(clang_getIncludedFile) X(clang_getArrayElementType)

struct ClangApi
{
    llvm::sys::DynamicLibrary library;
#define DECLARE(name) decltype(&name) name = nullptr;
    CLANG_FUNCTIONS(DECLARE)
#undef DECLARE

    bool load(const std::string& clangExe, std::string& error)
    {
        std::vector<std::string> candidates;
        if (const char* env = std::getenv("CSHIFT_LIBCLANG"))
            candidates.push_back(env);

        std::string binDir = clangExe.empty() ? "" : std::string(path::parent_path(clangExe));
        if (!binDir.empty())
        {
            candidates.push_back(binDir + "/libclang.dll");
            std::string libDir = std::string(path::parent_path(binDir)) + "/lib";
            candidates.push_back(libDir + "/libclang.so");
            candidates.push_back(libDir + "/libclang.dylib");
            std::error_code ec;
            for (fs::directory_iterator it(libDir, ec), end; !ec && it != end; it.increment(ec))
            {
                std::string name = std::string(path::filename(it->path()));
                if (name.rfind("libclang", 0) == 0 && name.find("cpp") == std::string::npos &&
                    (name.find(".so") != std::string::npos || name.find(".dylib") != std::string::npos))
                    candidates.push_back(it->path());
            }
        }
        candidates.push_back("libclang.dll");
        candidates.push_back("libclang.so");
        candidates.push_back("libclang.dylib");

        std::string lastError;
        for (const std::string& file : candidates)
        {
            bool isPath = file.find('/') != std::string::npos || file.find('\\') != std::string::npos;
            if (isPath && !fs::exists(file))
                continue;
#ifdef _WIN32
            // The DLL's own dependencies (libc++.dll, ...) live next to it.
            if (isPath)
                SetDllDirectoryA(std::string(path::parent_path(file)).c_str());
#endif
            library = llvm::sys::DynamicLibrary::getPermanentLibrary(file.c_str(), &lastError);
            if (library.isValid())
                break;
        }
        if (!library.isValid())
        {
            error = "libclang was not found (looked next to '" + clangExe + "'; set CSHIFT_LIBCLANG to its path)" +
                    (lastError.empty() ? "" : ": " + lastError);
            return false;
        }

        std::string missing;
#define LOAD(name)                                                                                                     \
    name = reinterpret_cast<decltype(name)>(library.getAddressOfSymbol(#name));                                        \
    if (!name)                                                                                                         \
        missing += std::string(missing.empty() ? "" : ", ") + #name;
        CLANG_FUNCTIONS(LOAD)
#undef LOAD
        if (!missing.empty())
        {
            error = "this libclang is too old or incompatible, missing: " + missing;
            return false;
        }
        return true;
    }
};

ClangApi api;

std::string cx(CXString s)
{
    const char* c = api.clang_getCString(s);
    std::string result = c ? c : "";
    api.clang_disposeString(s);
    return result;
}

std::string slash(std::string p)
{
    for (char& c : p)
        if (c == '\\')
            c = '/';
    return p;
}

// ---------------------------------------------------------------------------
// The exported model
// ---------------------------------------------------------------------------

struct FField
{
    std::string name;
    std::string type;
    int64_t offset = 0;
};

struct FStruct
{
    std::string name;
    std::string kind; // "struct" or "union"
    uint64_t size = 0;
    uint64_t align = 1;
    bool opaque = false;
    std::vector<FField> fields;
};

struct FInt
{
    long long value = 0;
    bool isUnsigned = false; // value holds the bit pattern of an unsigned number
};

struct FEnum
{
    std::string name;
    std::string base;
    std::vector<std::pair<std::string, FInt>> members;
};

struct FConst
{
    std::string name;
    std::string type;
    enum Kind { Integer, Float, String } kind = Integer;
    FInt integer;
    double number = 0;
    std::string text;
};

struct FParam
{
    std::string name;
    std::string type;
    std::string ref = "none"; // none | ref | constref
    bool nullable = false;
    bool cstring = false;
};

struct FFunc
{
    std::string name;
    std::string returns = "void";
    std::vector<FParam> params;
    bool variadic = false;
    std::string symbol;
    bool retCString = false;
    bool retOut = false;
    std::string cType;
};

struct FSkip
{
    std::string name;
    std::string reason;
};

const char* nativeIntegerName(const std::string& typedefName)
{
    static const std::map<std::string, const char*> names = {
        {"size_t", "nuint"},     {"uintptr_t", "nuint"},   {"SIZE_T", "nuint"},     {"UINT_PTR", "nuint"},
        {"ULONG_PTR", "nuint"},  {"DWORD_PTR", "nuint"},   {"ssize_t", "nint"},     {"ptrdiff_t", "nint"},
        {"intptr_t", "nint"},    {"SSIZE_T", "nint"},      {"INT_PTR", "nint"},     {"LONG_PTR", "nint"},
        {"__size_t", "nuint"},   {"__ssize_t", "nint"},    {"rsize_t", "nuint"},
    };
    auto it = names.find(typedefName);
    return it == names.end() ? nullptr : it->second;
}

// ---------------------------------------------------------------------------
// The generator
// ---------------------------------------------------------------------------

class Generator
{
public:
    Generator(const FfiImportRequest& request, const FfiOptions& options) : request(request), options(options) {}

    bool run(const std::string& ffiPath, std::string& error);

private:
    // libclang helpers
    std::vector<std::string> compilerArgs() const;
    const std::vector<std::string>& systemIncludes() const;
    mutable std::vector<std::string> systemIncludeCache;
    mutable bool systemIncludesKnown = false;
    bool parse();
    bool isApiCursor(CXCursor c);
    bool isApiFile(CXFile file);
    void visit(CXCursor c, const std::function<void(CXCursor)>& f);
    static CXChildVisitResult trampoline(CXCursor cursor, CXCursor parent, CXClientData data);

    // types
    CXType peel(CXType t, std::string* nativeName);
    std::string typeString(CXType t, std::string& why);
    std::string rawPointerString(CXType pointer, std::string& why);
    std::string functionTypeString(CXType function);
    bool mapParam(CXType t, FParam& out, bool& byValueRecord, std::string& why);
    bool isPlainChar(CXType t);
    bool isComplete(CXCursor recordDecl);
    std::string recordName(CXCursor decl);
    std::string enumName(CXCursor decl);
    void needRecord(CXCursor decl);
    void needEnum(CXCursor decl);

    // export
    void exportRecord(CXCursor decl);
    void exportEnum(CXCursor decl);
    void exportFunction(CXCursor c);
    void collectMacros(std::vector<std::pair<std::string, std::vector<std::pair<int, std::string>>>>& macros);
    void exportMacros();
    bool writeJson(const std::string& ffiPath, std::string& error);

    const FfiImportRequest& request;
    const FfiOptions& options;

    CXIndex index = nullptr;
    CXTranslationUnit tu = nullptr;
    std::string wrapperFile;
    std::string wrapperText;
    std::string mainDir;        // directory of the requested header
    bool mainIsSystem = false;  // the requested header lives in a system include directory
    std::set<std::string> systemApiFiles; // then: the header and the files it includes with quotes
    std::string mainHeaderPath; // the requested header as found by libclang (absolute)
    std::vector<std::string> dependencies;
    std::map<void*, bool> apiFiles;

    std::map<unsigned, std::string> typedefNames; // record/enum declaration -> typedef name
    std::map<unsigned, std::string> recordNames;
    std::map<unsigned, std::string> enumNames;
    std::set<unsigned> exportedTypes;
    std::vector<std::pair<CXCursor, bool>> typeQueue; // (declaration, isEnum)

    std::vector<FStruct> structs;
    std::vector<FEnum> enums;
    std::vector<FConst> constants;
    std::vector<FFunc> functions;
    std::vector<FSkip> skipped;
    std::set<std::string> constantNames;
    std::set<std::string> functionNames;
    std::string shimText;
    std::string clangVersion;
};

CXChildVisitResult Generator::trampoline(CXCursor cursor, CXCursor, CXClientData data)
{
    (*static_cast<std::function<void(CXCursor)>*>(data))(cursor);
    return CXChildVisit_Continue;
}

void Generator::visit(CXCursor c, const std::function<void(CXCursor)>& f)
{
    std::function<void(CXCursor)> copy = f;
    api.clang_visitChildren(c, &Generator::trampoline, &copy);
}

// libclang does not know where the C library headers (stddef.h, stdint.h, ...) of the installation are, so ask the
// clang driver, which does: "clang -E -x c -v -" lists its include search path on stderr.
const std::vector<std::string>& Generator::systemIncludes() const
{
    if (systemIncludesKnown)
        return systemIncludeCache;
    systemIncludesKnown = true;
    if (options.clang.empty())
        return systemIncludeCache;

    llvm::SmallString<128> logFile;
    if (fs::createTemporaryFile("cshift-ffi", "log", logFile))
        return systemIncludeCache;
    std::vector<std::string> args = {options.clang, "-E", "-x", "c", "-v"};
    if (!options.target.empty())
    {
        args.push_back("-target");
        args.push_back(options.target);
    }
    args.push_back("-");
    std::vector<llvm::StringRef> refs(args.begin(), args.end());
    std::optional<llvm::StringRef> redirects[] = {llvm::StringRef(""), llvm::StringRef(""), llvm::StringRef(logFile)};
    llvm::sys::ExecuteAndWait(options.clang, refs, std::nullopt, redirects);

    if (auto buffer = llvm::MemoryBuffer::getFile(logFile))
    {
        bool inList = false;
        llvm::StringRef text = (*buffer)->getBuffer();
        while (!text.empty())
        {
            auto split = text.split('\n');
            llvm::StringRef line = split.first.rtrim("\r");
            text = split.second;
            if (line.starts_with("#include <...> search starts here"))
                inList = true;
            else if (line.starts_with("End of search list"))
                break;
            else if (inList && line.starts_with(" "))
            {
                std::string dir = line.trim().str();
                // "(framework directory)" entries only exist on macOS and cannot be used with -isystem.
                if (dir.find(" (") == std::string::npos)
                    systemIncludeCache.push_back(dir);
            }
        }
    }
    fs::remove(logFile);
    return systemIncludeCache;
}

std::vector<std::string> Generator::compilerArgs() const
{
    std::vector<std::string> args = {"-x", "c", "-I" + slash(request.baseDir.empty() ? "." : request.baseDir)};
    if (!options.target.empty())
    {
        args.push_back("-target");
        args.push_back(options.target);
    }
    for (const std::string& dir : systemIncludes())
        args.push_back("-isystem" + slash(dir));
    for (const std::string& f : ffiFlags(options))
        args.push_back(f);
    return args;
}

bool Generator::parse()
{
    index = api.clang_createIndex(0, 0);
    llvm::SmallString<256> base(request.baseDir.empty() ? "." : request.baseDir);
    fs::make_absolute(base);
    llvm::SmallString<256> wrapper(base);
    path::append(wrapper, "__cshift_ffi_wrapper.c");
    wrapperFile = slash(std::string(wrapper.str()));
    wrapperText = "#include \"" + request.header + "\"\n";

    CXUnsavedFile unsaved;
    unsaved.Filename = wrapperFile.c_str();
    unsaved.Contents = wrapperText.c_str();
    unsaved.Length = (unsigned long)wrapperText.size();

    std::vector<std::string> args = compilerArgs();
    std::vector<const char*> argv;
    for (const auto& a : args)
        argv.push_back(a.c_str());

    unsigned flags = CXTranslationUnit_DetailedPreprocessingRecord | CXTranslationUnit_SkipFunctionBodies |
                     CXTranslationUnit_KeepGoing;
    tu = api.clang_parseTranslationUnit(index, wrapperFile.c_str(), argv.data(), (int)argv.size(), &unsaved, 1, flags);
    return tu != nullptr;
}

bool Generator::isApiFile(CXFile file)
{
    if (!file)
        return false;
    auto it = apiFiles.find(file);
    if (it != apiFiles.end())
        return it->second;
    std::string name = slash(cx(api.clang_getFileName(file)));
    bool system = api.clang_Location_isInSystemHeader(api.clang_getLocation(tu, file, 1, 1)) != 0;
    bool underMain = !mainDir.empty() && name.compare(0, mainDir.size(), mainDir) == 0;
    bool result = name != wrapperFile && (!system || (mainIsSystem ? systemApiFiles.count(name) != 0 : underMain));
    apiFiles[file] = result;
    return result;
}

bool Generator::isApiCursor(CXCursor c)
{
    CXFile file = nullptr;
    unsigned line = 0, col = 0, offset = 0;
    api.clang_getFileLocation(api.clang_getCursorLocation(c), &file, &line, &col, &offset);
    return isApiFile(file);
}

// ---- types --------------------------------------------------------------

// Removes typedefs and other sugar. A typedef of a pointer-sized integer (size_t, ...) stops the peeling and reports
// its native type name.
CXType Generator::peel(CXType t, std::string* nativeName)
{
    for (int depth = 0; depth < 32; depth += 1)
    {
        switch (t.kind)
        {
        case CXType_Typedef:
        {
            CXCursor decl = api.clang_getTypeDeclaration(t);
            if (nativeName)
            {
                if (const char* n = nativeIntegerName(cx(api.clang_getCursorSpelling(decl))))
                {
                    *nativeName = n;
                    return t;
                }
            }
            t = api.clang_getTypedefDeclUnderlyingType(decl);
            continue;
        }
        case CXType_Elaborated: t = api.clang_Type_getNamedType(t); continue;
        case CXType_Attributed: t = api.clang_Type_getModifiedType(t); continue;
        case CXType_Unexposed:
        {
            CXType canonical = api.clang_getCanonicalType(t);
            if (canonical.kind == CXType_Unexposed)
                return canonical;
            t = canonical;
            continue;
        }
        default: return t;
        }
    }
    return api.clang_getCanonicalType(t);
}

bool Generator::isPlainChar(CXType t)
{
    return t.kind == CXType_Char_S || t.kind == CXType_Char_U;
}

bool Generator::isComplete(CXCursor decl)
{
    CXCursor def = api.clang_getCursorDefinition(decl);
    return !api.clang_Cursor_isNull(def) && api.clang_Type_getSizeOf(api.clang_getCursorType(def)) >= 0;
}

static bool looksAnonymous(const std::string& name)
{
    return name.empty() || name.find('(') != std::string::npos || name.find("unnamed") != std::string::npos ||
           name.find("anonymous") != std::string::npos;
}

// The CShift name of a struct/union/enum: the tag, or the typedef name for anonymous types and for tags that start with
// an underscore (typedef struct _SDL_Window SDL_Window).
std::string Generator::recordName(CXCursor decl)
{
    CXCursor canonical = api.clang_getCanonicalCursor(decl);
    unsigned key = api.clang_hashCursor(canonical);
    auto it = recordNames.find(key);
    if (it != recordNames.end())
        return it->second;
    std::string tag = cx(api.clang_getCursorSpelling(decl));
    if (looksAnonymous(tag))
        tag.clear();
    std::string td = typedefNames.count(key) ? typedefNames[key] : "";
    // The typedef name is the public one (z_stream, not z_stream_s; FILE, not _iobuf).
    std::string name = td.empty() ? tag : td;
    recordNames[key] = name;
    return name;
}

std::string Generator::enumName(CXCursor decl)
{
    CXCursor canonical = api.clang_getCanonicalCursor(decl);
    unsigned key = api.clang_hashCursor(canonical);
    auto it = enumNames.find(key);
    if (it != enumNames.end())
        return it->second;
    std::string tag = cx(api.clang_getCursorSpelling(decl));
    if (looksAnonymous(tag))
        tag.clear();
    std::string td = typedefNames.count(key) ? typedefNames[key] : "";
    // The typedef name is the public one (z_stream, not z_stream_s; FILE, not _iobuf).
    std::string name = td.empty() ? tag : td;
    enumNames[key] = name;
    return name;
}

void Generator::needRecord(CXCursor decl)
{
    unsigned key = api.clang_hashCursor(api.clang_getCanonicalCursor(decl));
    if (exportedTypes.insert(key).second)
        typeQueue.push_back({decl, false});
}

void Generator::needEnum(CXCursor decl)
{
    unsigned key = api.clang_hashCursor(api.clang_getCanonicalCursor(decl));
    if (exportedTypes.insert(key).second)
        typeQueue.push_back({decl, true});
}

// The CShift type of a C type, or "" (with a reason) if it cannot be represented. Pointers become raw pointer types.
std::string Generator::typeString(CXType t, std::string& why)
{
    std::string native;
    CXType p = peel(t, &native);
    if (!native.empty())
        return native;

    switch (p.kind)
    {
    case CXType_Void: return "void";
    case CXType_Bool: return "bool";
    case CXType_Char_U:
    case CXType_Char_S: return "char";
    case CXType_SChar: return "int8";
    case CXType_UChar: return "uint8";
    case CXType_Short: return "int16";
    case CXType_UShort: return "uint16";
    case CXType_Int: return "int32";
    case CXType_UInt: return "uint32";
    case CXType_Long: return api.clang_Type_getSizeOf(p) == 8 ? "int64" : "int32";
    case CXType_ULong: return api.clang_Type_getSizeOf(p) == 8 ? "uint64" : "uint32";
    case CXType_LongLong: return "int64";
    case CXType_ULongLong: return "uint64";
    case CXType_WChar: return api.clang_Type_getSizeOf(p) == 2 ? "uint16" : "uint32";
    case CXType_Char16: return "uint16";
    case CXType_Char32: return "uint32";
    case CXType_Float: return "float32";
    case CXType_Double: return "float64";
    case CXType_Pointer: return rawPointerString(p, why);
    case CXType_Record:
    {
        CXCursor decl = api.clang_getTypeDeclaration(p);
        needRecord(decl);
        std::string name = recordName(decl);
        if (name.empty())
        {
            why = "anonymous struct or union";
            return "";
        }
        return name;
    }
    case CXType_Enum:
    {
        CXCursor decl = api.clang_getTypeDeclaration(p);
        std::string name = enumName(decl);
        if (name.empty())
            return typeString(api.clang_getEnumDeclIntegerType(decl), why); // anonymous enum: plain integer
        needEnum(decl);
        return name;
    }
    case CXType_ConstantArray:
    case CXType_IncompleteArray:
    case CXType_VariableArray: why = "array type"; return "";
    case CXType_FunctionProto:
    case CXType_FunctionNoProto: why = "function type"; return "";
    case CXType_LongDouble: why = "long double"; return "";
    case CXType_Int128:
    case CXType_UInt128: why = "128-bit integer"; return "";
    case CXType_Complex: why = "complex number"; return "";
    case CXType_Vector: why = "vector type"; return "";
    default: why = "unsupported type '" + cx(api.clang_getTypeSpelling(t)) + "'"; return "";
    }
}

std::string Generator::rawPointerString(CXType pointer, std::string& why)
{
    CXType pointee = peel(api.clang_getPointeeType(pointer), nullptr);
    switch (pointee.kind)
    {
    case CXType_Void:
    case CXType_FunctionNoProto: return "void*";
    case CXType_FunctionProto: return functionTypeString(pointee);
    default: break;
    }
    std::string inner = typeString(pointee, why);
    if (inner.empty() || inner == "void")
    {
        why.clear();
        return "void*"; // pointer to something we cannot represent
    }
    return inner + "*";
}

// A C function pointer type becomes Action<...> / Func<..., R>. Parameters and result are raw values: a callback
// receives the C types unchanged (const char* is a char*, pointers to structs are raw pointers), so only scalars,
// enums and pointers are possible. Anything else (structs by value, variadic functions, long double) stays a
// plain void*.
std::string Generator::functionTypeString(CXType function)
{
    if (api.clang_isFunctionTypeVariadic(function))
        return "void*";
    int count = api.clang_getNumArgTypes(function);
    if (count < 0 || count > 8)
        return "void*";

    auto mapType = [&](CXType t) -> std::string {
        std::string native;
        CXType p = peel(t, &native);
        if (native.empty() && p.kind == CXType_Record)
            return ""; // struct by value
        if (native.empty() && (p.kind == CXType_ConstantArray || p.kind == CXType_IncompleteArray))
            return ""; // decays to a pointer in C, rare in callbacks
        std::string why;
        return typeString(t, why);
    };

    std::vector<std::string> params;
    for (int i = 0; i < count; i += 1)
    {
        std::string s = mapType(api.clang_getArgType(function, (unsigned)i));
        if (s.empty() || s == "void")
            return "void*";
        params.push_back(s);
    }
    std::string result = mapType(api.clang_getResultType(function));
    if (result.empty())
        return "void*";

    std::string name = result == "void" ? "Action" : "Func";
    std::string args;
    for (const std::string& p : params)
        args += (args.empty() ? "" : ", ") + p;
    if (result != "void")
        args += (args.empty() ? "" : ", ") + result;
    return args.empty() ? name : name + "<" + args + ">";
}

// Maps a function parameter. Pointers to values become ref/const ref (that accept null), const char* becomes a
// string, everything else stays a raw pointer.
bool Generator::mapParam(CXType t, FParam& out, bool& byValueRecord, std::string& why)
{
    byValueRecord = false;
    CXType p = peel(t, nullptr);
    std::string nativeName;
    peel(t, &nativeName);

    if (p.kind == CXType_Record && nativeName.empty())
    {
        out.type = typeString(p, why);
        if (out.type.empty())
            return false;
        out.ref = "constref"; // structs by value are passed through a generated shim
        byValueRecord = true;
        return true;
    }
    // An array parameter (char* argv[]) is a pointer to its first element in C.
    if (p.kind == CXType_ConstantArray || p.kind == CXType_IncompleteArray || p.kind == CXType_VariableArray)
    {
        std::string element = typeString(api.clang_getArrayElementType(p), why);
        if (element.empty() || element == "void")
            return false;
        out.type = element + "*";
        return true;
    }
    if (p.kind != CXType_Pointer || !nativeName.empty())
    {
        out.type = typeString(t, why);
        return !out.type.empty();
    }

    CXType pointeeSugar = api.clang_getPointeeType(p);
    bool isConst = api.clang_isConstQualifiedType(pointeeSugar) != 0;
    CXType pointee = peel(pointeeSugar, nullptr);

    if (isPlainChar(pointee))
    {
        if (isConst)
        {
            out.type = "string";
            out.cstring = true;
            return true;
        }
        out.type = "char*";
        return true;
    }
    switch (pointee.kind)
    {
    case CXType_Void:
    case CXType_FunctionNoProto: out.type = "void*"; return true;
    case CXType_FunctionProto: out.type = functionTypeString(pointee); return true;
    case CXType_Pointer:
    {
        std::string inner = rawPointerString(pointee, why);
        out.type = inner;
        out.ref = "ref";
        out.nullable = true;
        return true;
    }
    case CXType_Record:
    {
        CXCursor decl = api.clang_getTypeDeclaration(pointee);
        std::string name = recordName(decl);
        needRecord(decl);
        if (name.empty() || !isComplete(decl))
        {
            out.type = name.empty() ? "void*" : name + "*"; // opaque handle
            return true;
        }
        out.type = name;
        out.ref = isConst ? "constref" : "ref";
        out.nullable = true;
        return true;
    }
    default: break;
    }

    std::string inner = typeString(pointee, why);
    if (inner.empty() || inner == "void")
    {
        why.clear();
        out.type = "void*";
        return true;
    }
    out.type = inner;
    out.ref = isConst ? "constref" : "ref";
    out.nullable = true;
    return true;
}

// ---- export -------------------------------------------------------------

void Generator::exportRecord(CXCursor decl)
{
    std::string name = recordName(decl);
    if (name.empty())
        return;
    CXCursor def = api.clang_getCursorDefinition(decl);
    FStruct s;
    s.name = name;
    s.kind = api.clang_getCursorKind(decl) == CXCursor_UnionDecl ? "union" : "struct";

    if (api.clang_Cursor_isNull(def))
    {
        s.opaque = true;
        structs.push_back(std::move(s));
        return;
    }
    CXType type = api.clang_getCursorType(def);
    long long size = api.clang_Type_getSizeOf(type);
    long long align = api.clang_Type_getAlignOf(type);
    if (size < 0)
    {
        s.opaque = true;
        structs.push_back(std::move(s));
        return;
    }
    s.size = (uint64_t)size;
    s.align = align > 0 ? (uint64_t)align : 1;

    // Unions overlap their members: they are imported as a blob of the right size and alignment.
    if (s.kind == "struct")
    {
        visit(def, [&](CXCursor field) {
            if (api.clang_getCursorKind(field) != CXCursor_FieldDecl)
                return;
            std::string fieldName = cx(api.clang_getCursorSpelling(field));
            if (fieldName.empty() || api.clang_Cursor_isBitField(field))
                return; // anonymous members and bit fields are padding
            long long bits = api.clang_Cursor_getOffsetOfField(field);
            if (bits < 0 || bits % 8 != 0)
                return;
            std::string why;
            std::string ft = typeString(api.clang_getCursorType(field), why);
            if (ft.empty() || ft == "void")
                return; // arrays, long double, ... are padding
            s.fields.push_back({fieldName, ft, bits / 8});
        });
    }
    structs.push_back(std::move(s));
}

void Generator::exportEnum(CXCursor decl)
{
    CXCursor def = api.clang_getCursorDefinition(decl);
    if (api.clang_Cursor_isNull(def))
        return;
    std::string why;
    std::string base = typeString(api.clang_getEnumDeclIntegerType(def), why);
    if (base.empty())
        base = "int32";
    bool isUnsigned = base.rfind("uint", 0) == 0;
    std::string name = enumName(decl);

    FEnum e;
    e.name = name;
    e.base = base;
    visit(def, [&](CXCursor member) {
        if (api.clang_getCursorKind(member) != CXCursor_EnumConstantDecl)
            return;
        std::string memberName = cx(api.clang_getCursorSpelling(member));
        FInt value;
        value.isUnsigned = isUnsigned;
        value.value = isUnsigned ? (long long)api.clang_getEnumConstantDeclUnsignedValue(member)
                                 : api.clang_getEnumConstantDeclValue(member);
        e.members.push_back({memberName, value});

        // C code uses the enumerators as plain constants.
        if (constantNames.insert(memberName).second)
        {
            FConst c;
            c.name = memberName;
            c.type = name.empty() ? base : name;
            c.kind = FConst::Integer;
            c.integer = value;
            constants.push_back(std::move(c));
        }
    });
    if (!name.empty())
        enums.push_back(std::move(e));
}

void Generator::exportFunction(CXCursor c)
{
    std::string name = cx(api.clang_getCursorSpelling(c));
    if (name.empty() || !functionNames.insert(name).second)
        return;
    if (api.clang_Cursor_getStorageClass(c) == CX_SC_Static)
        return; // static (inline) functions have no symbol to link

    CXType ft = api.clang_getCursorType(c);
    if (ft.kind != CXType_FunctionProto)
    {
        skipped.push_back({name, "function without a prototype"});
        return;
    }

    FFunc f;
    f.name = name;
    f.cType = cx(api.clang_getTypeSpelling(ft));
    f.variadic = api.clang_isFunctionTypeVariadic(ft) != 0;
    bool needsShim = false;
    std::string why;

    // return type
    CXType ret = api.clang_getResultType(ft);
    CXType retPeeled = peel(ret, nullptr);
    std::string retNative;
    peel(ret, &retNative);
    if (retPeeled.kind == CXType_Record && retNative.empty())
    {
        f.returns = typeString(retPeeled, why);
        f.retOut = true;
        needsShim = true;
    }
    else if (retPeeled.kind == CXType_Pointer && retNative.empty() &&
             isPlainChar(peel(api.clang_getPointeeType(retPeeled), nullptr)) &&
             api.clang_isConstQualifiedType(api.clang_getPointeeType(retPeeled)))
    {
        f.returns = "string";
        f.retCString = true;
    }
    else
    {
        f.returns = typeString(ret, why);
    }
    if (f.returns.empty())
    {
        skipped.push_back({name, "return type: " + why});
        return;
    }

    // parameters
    int n = (int)api.clang_getNumArgTypes(ft);
    std::vector<bool> byValue;
    for (int i = 0; i < n; i += 1)
    {
        FParam p;
        CXCursor arg = api.clang_Cursor_getArgument(c, (unsigned)i);
        p.name = api.clang_Cursor_isNull(arg) ? "" : cx(api.clang_getCursorSpelling(arg));
        bool byValueRecord = false;
        if (!mapParam(api.clang_getArgType(ft, (unsigned)i), p, byValueRecord, why))
        {
            skipped.push_back({name, "parameter " + std::to_string(i + 1) + ": " + why});
            return;
        }
        if (byValueRecord)
            needsShim = true;
        byValue.push_back(byValueRecord);
        f.params.push_back(std::move(p));
    }
    if (needsShim && f.variadic)
    {
        skipped.push_back({name, "variadic function that takes or returns a struct by value"});
        return;
    }

    if (needsShim)
    {
        // The C compiler knows the ABI for structs by value: a generated C function takes pointers instead.
        f.symbol = "__cs_shim_" + name;
        auto spell = [&](CXType t) { return cx(api.clang_getTypeSpelling(t)); };
        std::string params;
        std::string call;
        for (int i = 0; i < n; i += 1)
        {
            CXType at = api.clang_getArgType(ft, (unsigned)i);
            std::string ts = spell(at);
            std::string pn = "a" + std::to_string(i);
            if (i)
            {
                params += ", ";
                call += ", ";
            }
            if (byValue[i])
            {
                params += ts + " *" + pn;
                call += "*" + pn;
            }
            else if (ts.find('(') != std::string::npos)
            {
                params += "void *" + pn; // function pointers: passed as void* and cast back
                call += "(" + ts + ")" + pn;
            }
            else
            {
                params += ts + " " + pn;
                call += pn;
            }
        }
        std::string retSpelling = spell(ret);
        if (f.retOut)
        {
            params += std::string(params.empty() ? "" : ", ") + retSpelling + " *__ret";
            shimText += "void " + f.symbol + "(" + params + ") { *__ret = " + name + "(" + call + "); }\n";
        }
        else if (retSpelling == "void")
        {
            shimText += "void " + f.symbol + "(" + (params.empty() ? "void" : params) + ") { " + name + "(" + call + "); }\n";
        }
        else if (retSpelling.find('(') != std::string::npos)
        {
            shimText += "void *" + f.symbol + "(" + (params.empty() ? "void" : params) + ") { return (void *)" + name + "(" + call + "); }\n";
        }
        else
        {
            shimText += retSpelling + " " + f.symbol + "(" + (params.empty() ? "void" : params) + ") { return " + name + "(" + call + "); }\n";
        }
    }
    functions.push_back(std::move(f));
}

// ---- macros ---------------------------------------------------------------

static std::string decodeCString(const std::string& literal, bool& ok)
{
    // literal is one or more adjacent "..." tokens joined by the caller; here a single token
    ok = literal.size() >= 2 && literal.front() == '"' && literal.back() == '"';
    std::string out;
    if (!ok)
        return out;
    for (size_t i = 1; i + 1 < literal.size(); i += 1)
    {
        char c = literal[i];
        if (c != '\\' || i + 2 >= literal.size())
        {
            out += c;
            continue;
        }
        char n = literal[++i];
        switch (n)
        {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case 'a': out += '\a'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'v': out += '\v'; break;
        case '\\': out += '\\'; break;
        case '\'': out += '\''; break;
        case '"': out += '"'; break;
        case 'x':
        {
            int v = 0;
            while (i + 1 + 1 < literal.size() && std::isxdigit((unsigned char)literal[i + 1]))
            {
                char h = literal[++i];
                v = v * 16 + (std::isdigit((unsigned char)h) ? h - '0' : std::tolower(h) - 'a' + 10);
            }
            out += (char)v;
            break;
        }
        default:
            if (n >= '0' && n <= '7')
            {
                int v = n - '0';
                for (int k = 0; k < 2 && i + 1 + 1 < literal.size() && literal[i + 1] >= '0' && literal[i + 1] <= '7'; k += 1)
                    v = v * 8 + (literal[++i] - '0');
                out += (char)v;
            }
            else
                out += n;
        }
    }
    return out;
}

// token kinds: 0 punctuation, 1 keyword, 2 identifier, 3 literal
void Generator::collectMacros(std::vector<std::pair<std::string, std::vector<std::pair<int, std::string>>>>& macros)
{
    visit(api.clang_getTranslationUnitCursor(tu), [&](CXCursor c) {
        if (api.clang_getCursorKind(c) != CXCursor_MacroDefinition || !isApiCursor(c))
            return;
        if (api.clang_Cursor_isMacroFunctionLike(c) || api.clang_Cursor_isMacroBuiltin(c))
            return;
        std::string name = cx(api.clang_getCursorSpelling(c));
        if (name.empty() || name[0] == '_')
            return; // include guards and implementation details

        CXToken* tokens = nullptr;
        unsigned count = 0;
        api.clang_tokenize(tu, api.clang_getCursorExtent(c), &tokens, &count);
        std::vector<std::pair<int, std::string>> body;
        for (unsigned i = 1; i < count; i += 1) // tokens[0] is the macro name
        {
            int kind = api.clang_getTokenKind(tokens[i]);
            if (kind == CXToken_Comment)
                continue;
            body.push_back({kind == CXToken_Punctuation ? 0 : kind == CXToken_Keyword ? 1 : kind == CXToken_Identifier ? 2 : 3,
                            cx(api.clang_getTokenSpelling(tu, tokens[i]))});
        }
        if (tokens)
            api.clang_disposeTokens(tu, tokens, count);
        if (!body.empty())
            macros.push_back({name, std::move(body)});
    });
}

static bool isFloatLiteral(const std::string& s)
{
    if (s.size() > 1 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        return false;
    return s.find('.') != std::string::npos || s.find('e') != std::string::npos || s.find('E') != std::string::npos;
}

void Generator::exportMacros()
{
    std::vector<std::pair<std::string, std::vector<std::pair<int, std::string>>>> macros;
    collectMacros(macros);

    std::vector<std::pair<std::string, bool>> probes; // name, has unsigned suffix
    for (auto& m : macros)
    {
        const std::string& name = m.first;
        auto body = m.second;
        if (constantNames.count(name) || functionNames.count(name))
            continue;

        // strip redundant outer parentheses
        while (body.size() >= 2 && body.front().second == "(" && body.back().second == ")")
        {
            int depth = 0;
            bool wraps = true;
            for (size_t i = 0; i < body.size(); i += 1)
            {
                if (body[i].second == "(")
                    depth += 1;
                else if (body[i].second == ")")
                    depth -= 1;
                if (depth == 0 && i + 1 < body.size())
                {
                    wraps = false;
                    break;
                }
            }
            if (!wraps)
                break;
            body.erase(body.begin());
            body.pop_back();
        }
        if (body.empty())
            continue;

        // strings (adjacent literals are concatenated)
        bool allStrings = true;
        for (auto& t : body)
            allStrings = allStrings && t.first == 3 && !t.second.empty() && t.second[0] == '"';
        if (allStrings)
        {
            std::string text;
            bool ok = true;
            for (auto& t : body)
            {
                bool one = false;
                text += decodeCString(t.second, one);
                ok = ok && one;
            }
            if (ok)
            {
                FConst c;
                c.name = name;
                c.type = "string";
                c.kind = FConst::String;
                c.text = text;
                constants.push_back(std::move(c));
                constantNames.insert(name);
            }
            continue;
        }

        // floating point numbers
        bool negative = false;
        size_t first = 0;
        if (body.size() == 2 && body[0].second == "-")
        {
            negative = true;
            first = 1;
        }
        if (body.size() - first == 1 && body[first].first == 3 && isFloatLiteral(body[first].second) &&
            std::isdigit((unsigned char)body[first].second[0]))
        {
            std::string text = body[first].second;
            while (!text.empty() && (text.back() == 'f' || text.back() == 'F' || text.back() == 'l' || text.back() == 'L'))
                text.pop_back();
            FConst c;
            c.name = name;
            c.type = "float64";
            c.kind = FConst::Float;
            c.number = (negative ? -1 : 1) * std::strtod(text.c_str(), nullptr);
            constants.push_back(std::move(c));
            constantNames.insert(name);
            continue;
        }

        // integer constant expressions are evaluated by the compiler (second pass below)
        static const std::set<std::string> allowed = {"+", "-", "*", "/", "%", "<<", ">>", "&", "|", "^", "~", "!", "(", ")"};
        bool candidate = true;
        bool hasUnsigned = false;
        for (auto& t : body)
        {
            if (t.first == 0)
                candidate = candidate && allowed.count(t.second);
            else if (t.first == 3)
            {
                candidate = candidate && !t.second.empty() && (std::isdigit((unsigned char)t.second[0]) || t.second[0] == '\'') &&
                            !isFloatLiteral(t.second);
                if (t.second.size() > 1 && t.second[0] != '\'' && (t.second.back() == 'u' || t.second.back() == 'U' ||
                                                                    t.second[t.second.size() - 2] == 'u' || t.second[t.second.size() - 2] == 'U'))
                    hasUnsigned = true;
            }
            else if (t.first == 2)
                candidate = candidate && true; // other macros / enumerators
            else
                candidate = false;
        }
        if (candidate)
            probes.push_back({name, hasUnsigned});
    }
    if (probes.empty())
        return;

    // Second parse: one anonymous enum per macro; the compiler evaluates the expression and reports it invalid if it
    // is not an integer constant expression.
    std::string probeText = wrapperText;
    for (size_t i = 0; i < probes.size(); i += 1)
        probeText += "enum { __cs_m" + std::to_string(i) + " = (" + probes[i].first + ") };\n";

    CXUnsavedFile unsaved;
    unsaved.Filename = wrapperFile.c_str();
    unsaved.Contents = probeText.c_str();
    unsaved.Length = (unsigned long)probeText.size();
    std::vector<std::string> args = compilerArgs();
    std::vector<const char*> argv;
    for (const auto& a : args)
        argv.push_back(a.c_str());
    CXTranslationUnit probeTu = api.clang_parseTranslationUnit(index, wrapperFile.c_str(), argv.data(), (int)argv.size(),
                                                               &unsaved, 1, CXTranslationUnit_SkipFunctionBodies | CXTranslationUnit_KeepGoing);
    if (!probeTu)
        return;
    auto handle = [&](CXCursor c) {
            if (api.clang_getCursorKind(c) != CXCursor_EnumConstantDecl)
                return;
            std::string n = cx(api.clang_getCursorSpelling(c));
            if (n.rfind("__cs_m", 0) != 0 || api.clang_isInvalidDeclaration(c))
                return;
            size_t i = (size_t)std::strtoull(n.c_str() + 6, nullptr, 10);
            if (i >= probes.size())
                return;
            long long v = api.clang_getEnumConstantDeclValue(c);
            FConst k;
            k.name = probes[i].first;
            k.kind = FConst::Integer;
            k.integer.value = v;
            if (probes[i].second && v >= 0 && v <= 0xFFFFFFFFLL)
            {
                k.type = "uint32";
                k.integer.isUnsigned = true;
            }
            else if (v >= INT32_MIN && v <= INT32_MAX)
                k.type = "int32";
            else if (v >= 0 && v <= 0xFFFFFFFFLL)
            {
                k.type = "uint32";
                k.integer.isUnsigned = true;
            }
            else
                k.type = "int64";
            if (constantNames.insert(k.name).second)
                constants.push_back(std::move(k));
    };
    visit(api.clang_getTranslationUnitCursor(probeTu), [&](CXCursor top) {
        if (api.clang_getCursorKind(top) == CXCursor_EnumDecl)
            visit(top, handle);
    });
    api.clang_disposeTranslationUnit(probeTu);
}

// ---- output ---------------------------------------------------------------

static void writeInt(llvm::json::OStream& J, const FInt& v)
{
    if (v.isUnsigned && v.value < 0)
        J.value(std::to_string((unsigned long long)v.value)); // above INT64_MAX: decimal string
    else
        J.value((int64_t)v.value);
}

bool Generator::writeJson(const std::string& ffiPath, std::string& error)
{
    std::error_code ec;
    llvm::raw_fd_ostream os(ffiPath, ec, fs::OF_Text);
    if (ec)
    {
        error = "cannot write '" + ffiPath + "': " + ec.message();
        return false;
    }

    std::string shimName;
    if (!shimText.empty())
    {
        shimName = std::string(path::stem(path::filename(ffiPath))) + ".shim.c";
        std::string shimPath = std::string(path::parent_path(ffiPath)) + "/" + shimName;
        llvm::raw_fd_ostream shim(shimPath, ec, fs::OF_Text);
        if (ec)
        {
            error = "cannot write '" + shimPath + "': " + ec.message();
            return false;
        }
        shim << "/* Generated by cshiftc: wrappers for C functions that take or return structs by value. */\n"
             << "#include \"" << mainHeaderPath << "\"\n\n"
             << shimText;
    }

    llvm::json::OStream J(os, 2);
    J.object([&] {
        J.attribute("format", (int64_t)kFfiFormat);
        J.attribute("namespace", request.name);
        J.attribute("header", request.header);
        J.attribute("target", options.target);
        J.attributeArray("flags", [&] {
            for (const auto& f : ffiFlags(options))
                J.value(f);
        });
        J.attribute("generator", "cshiftc " + clangVersion);
        J.attributeArray("dependencies", [&] {
            for (const auto& d : dependencies)
            {
                bool ok = false;
                std::string hash = ffiHashFile(d, ok);
                J.object([&] {
                    J.attribute("path", d);
                    J.attribute("hash", hash);
                });
            }
        });
        if (!shimName.empty())
            J.attribute("shim", shimName);

        J.attributeArray("constants", [&] {
            for (const auto& c : constants)
                J.object([&] {
                    J.attribute("name", c.name);
                    J.attribute("type", c.type);
                    J.attributeBegin("value");
                    if (c.kind == FConst::Integer)
                        writeInt(J, c.integer);
                    else if (c.kind == FConst::Float)
                        J.value(c.number);
                    else
                        J.value(c.text);
                    J.attributeEnd();
                });
        });
        J.attributeArray("enums", [&] {
            for (const auto& e : enums)
                J.object([&] {
                    J.attribute("name", e.name);
                    J.attribute("base", e.base);
                    J.attributeArray("members", [&] {
                        for (const auto& m : e.members)
                            J.object([&] {
                                J.attribute("name", m.first);
                                J.attributeBegin("value");
                                writeInt(J, m.second);
                                J.attributeEnd();
                            });
                    });
                });
        });
        J.attributeArray("structs", [&] {
            for (const auto& s : structs)
                J.object([&] {
                    J.attribute("name", s.name);
                    J.attribute("kind", s.kind);
                    J.attribute("size", (int64_t)s.size);
                    J.attribute("align", (int64_t)s.align);
                    J.attribute("opaque", s.opaque);
                    J.attributeArray("fields", [&] {
                        for (const auto& f : s.fields)
                            J.object([&] {
                                J.attribute("name", f.name);
                                J.attribute("type", f.type);
                                J.attribute("offset", f.offset);
                            });
                    });
                });
        });
        J.attributeArray("functions", [&] {
            for (const auto& f : functions)
                J.object([&] {
                    J.attribute("name", f.name);
                    J.attribute("returns", f.returns);
                    J.attributeArray("params", [&] {
                        for (const auto& p : f.params)
                            J.object([&] {
                                J.attribute("name", p.name);
                                J.attribute("type", p.type);
                                if (p.ref != "none")
                                    J.attribute("ref", p.ref);
                                if (p.nullable)
                                    J.attribute("nullable", true);
                                if (p.cstring)
                                    J.attribute("cstring", true);
                            });
                    });
                    if (f.variadic)
                        J.attribute("variadic", true);
                    if (f.retCString)
                        J.attribute("retCString", true);
                    if (f.retOut)
                        J.attribute("retOut", true);
                    if (!f.symbol.empty())
                        J.attribute("symbol", f.symbol);
                    J.attribute("c", f.cType);
                });
        });
        J.attributeArray("skipped", [&] {
            for (const auto& s : skipped)
                J.object([&] {
                    J.attribute("name", s.name);
                    J.attribute("reason", s.reason);
                });
        });
    });
    os << "\n";
    return true;
}

bool Generator::run(const std::string& ffiPath, std::string& error)
{
    if (!parse())
    {
        error = "libclang could not parse \"" + request.header + "\"";
        return false;
    }
    clangVersion = cx(api.clang_getClangVersion());

    // Diagnostics: a header that cannot be found is fatal, everything else is only reported.
    unsigned diagnostics = api.clang_getNumDiagnostics(tu);
    std::string firstProblem, problems;
    unsigned errorCount = 0;
    for (unsigned i = 0; i < diagnostics; i += 1)
    {
        CXDiagnostic d = api.clang_getDiagnostic(tu, i);
        int severity = api.clang_getDiagnosticSeverity(d);
        if (severity >= CXDiagnostic_Error)
        {
            std::string text = cx(api.clang_formatDiagnostic(d, api.clang_defaultDiagnosticDisplayOptions()));
            if (firstProblem.empty())
                firstProblem = text;
            if (errorCount < 5)
                problems += "\n  " + text;
            errorCount += 1;
        }
        api.clang_disposeDiagnostic(d);
    }

    // Included files: the requested header (included directly by the wrapper) and everything that is part of the API.
    struct Inclusion
    {
        std::string name;
        unsigned depth;
        CXFile file;
    };
    std::vector<Inclusion> inclusions;
    api.clang_getInclusions(
        tu,
        [](CXFile file, CXSourceLocation*, unsigned depth, CXClientData d) {
            static_cast<std::vector<Inclusion>*>(d)->push_back({slash(cx(api.clang_getFileName(file))), depth, file});
        },
        &inclusions);
    std::string mainHeader;
    for (const auto& f : inclusions)
        if (f.depth == 1 && mainHeader.empty())
            mainHeader = f.name;
    if (mainHeader.empty())
    {
        error = "cannot find the header \"" + request.header + "\" (searched relative to '" + request.baseDir +
                "' and in the include paths)" + (firstProblem.empty() ? "" : ":\n  " + firstProblem);
        return false;
    }
    // Types that failed to resolve would silently become 'int', so errors in the header are fatal.
    if (errorCount > 0)
    {
        error = "libclang reports " + std::to_string(errorCount) + " error(s) in \"" + request.header + "\":" + problems +
                (errorCount > 5 ? "\n  ..." : "") +
                "\n  (set \"includePaths\" / \"defines\" in cshift.json or pass -I / -D if the header needs them)";
        return false;
    }
    mainHeaderPath = mainHeader;
    mainDir = slash(std::string(path::parent_path(mainHeader))) + "/";
    apiFiles.clear();

    // A header that lives in a system include directory (zlib.h in /usr/include) sits next to the whole C library, so
    // the directory says nothing about what belongs to it. Only the files it includes with "quotes" (zconf.h) do.
    mainIsSystem = false;
    systemApiFiles.clear();
    for (const auto& f : inclusions)
        if (f.depth == 1 && f.name == mainHeader)
            mainIsSystem = api.clang_Location_isInSystemHeader(api.clang_getLocation(tu, f.file, 1, 1)) != 0;
    if (mainIsSystem)
    {
        struct Directive
        {
            std::string includer, included;
            bool quoted;
        };
        std::vector<Directive> directives;
        visit(api.clang_getTranslationUnitCursor(tu), [&](CXCursor c) {
            if (api.clang_getCursorKind(c) != CXCursor_InclusionDirective)
                return;
            CXFile included = api.clang_getIncludedFile(c);
            CXFile includer = nullptr;
            unsigned line = 0, col = 0, offset = 0;
            api.clang_getFileLocation(api.clang_getCursorLocation(c), &includer, &line, &col, &offset);
            if (!included || !includer)
                return;
            bool quoted = false;
            CXToken* tokens = nullptr;
            unsigned count = 0;
            api.clang_tokenize(tu, api.clang_getCursorExtent(c), &tokens, &count);
            for (unsigned i = 0; i < count; i += 1)
                if (cx(api.clang_getTokenSpelling(tu, tokens[i])).compare(0, 1, "\"") == 0)
                    quoted = true;
            if (tokens)
                api.clang_disposeTokens(tu, tokens, count);
            directives.push_back({slash(cx(api.clang_getFileName(includer))), slash(cx(api.clang_getFileName(included))), quoted});
        });
        systemApiFiles.insert(mainHeader);
        for (bool changed = true; changed;)
        {
            changed = false;
            for (const auto& d : directives)
                if (d.quoted && systemApiFiles.count(d.includer) && systemApiFiles.insert(d.included).second)
                    changed = true;
        }
    }

    // Dependencies for the freshness check: every file that belongs to the API (not system headers, except the ones
    // next to the requested header, which may live in the system include path).
    {
        std::set<std::string> seen;
        for (const auto& f : inclusions)
            if (f.depth > 0 && isApiFile(f.file) && seen.insert(f.name).second)
                dependencies.push_back(f.name);
    }

    // typedef names of records and enums
    visit(api.clang_getTranslationUnitCursor(tu), [&](CXCursor c) {
        if (api.clang_getCursorKind(c) != CXCursor_TypedefDecl)
            return;
        CXType under = peel(api.clang_getTypedefDeclUnderlyingType(c), nullptr);
        if (under.kind != CXType_Record && under.kind != CXType_Enum)
            return;
        CXCursor decl = api.clang_getTypeDeclaration(under);
        unsigned key = api.clang_hashCursor(api.clang_getCanonicalCursor(decl));
        if (!typedefNames.count(key))
            typedefNames[key] = cx(api.clang_getCursorSpelling(c));
    });

    // the API: functions, records, enums
    visit(api.clang_getTranslationUnitCursor(tu), [&](CXCursor c) {
        if (!isApiCursor(c))
            return;
        switch (api.clang_getCursorKind(c))
        {
        case CXCursor_FunctionDecl: exportFunction(c); break;
        case CXCursor_StructDecl:
        case CXCursor_UnionDecl: needRecord(c); break;
        case CXCursor_EnumDecl: needEnum(c); break;
        case CXCursor_VarDecl:
        {
            std::string name = cx(api.clang_getCursorSpelling(c));
            if (!name.empty())
                skipped.push_back({name, "global variables are not supported"});
            break;
        }
        default: break;
        }
    });

    // exported types may pull in further types
    for (size_t i = 0; i < typeQueue.size(); i += 1)
    {
        auto [decl, isEnum] = typeQueue[i];
        if (isEnum)
            exportEnum(decl);
        else
            exportRecord(decl);
    }

    exportMacros();

    api.clang_disposeTranslationUnit(tu);
    api.clang_disposeIndex(index);
    return writeJson(ffiPath, error);
}
} // namespace

bool generateFfi(const FfiImportRequest& request, const FfiOptions& options, const std::string& ffiPath, std::string& error)
{
    if (!api.library.isValid() && !api.load(options.clang, error))
        return false;
    Generator generator(request, options);
    return generator.run(ffiPath, error);
}

#endif // CSHIFT_HAVE_LIBCLANG
