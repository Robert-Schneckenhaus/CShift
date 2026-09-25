// Generating a .ffi file from a C header with libclang (port of compiler/src/FfiGenerator.cpp).
//
// libclang is loaded at run time (selfhost/native/host.c, next to clang or from CSHIFT_LIBCLANG). The header is
// parsed once; its functions, structs, unions, enums and simple macros become the JSON description that
// LoadFfiUnit reads (see FFI.md). Functions that take or return structs by value get a C wrapper (the shim).

namespace CShift.Driver;

using System;
using Host from "../../native/host.ffi";

// CXTypeKind
enum CxType : int32
{
    Invalid = 0, Unexposed = 1, Void = 2, Bool = 3, CharU = 4, UChar = 5, Char16 = 6, Char32 = 7, UShort = 8, UInt = 9,
    ULong = 10, ULongLong = 11, UInt128 = 12, CharS = 13, SChar = 14, WChar = 15, Short = 16, Int = 17, Long = 18,
    LongLong = 19, Int128 = 20, Float = 21, Double = 22, LongDouble = 23, Complex = 100, Pointer = 101, Record = 105,
    Enum = 106, Typedef = 107, FunctionNoProto = 110, FunctionProto = 111, ConstantArray = 112, Vector = 113,
    IncompleteArray = 114, VariableArray = 115, Elaborated = 119, Attributed = 163
}

// CXCursorKind
enum CxCursor : int32
{
    StructDecl = 2, UnionDecl = 3, EnumDecl = 5, FieldDecl = 6, EnumConstantDecl = 7, FunctionDecl = 8, VarDecl = 9,
    TypedefDecl = 20, MacroDefinition = 501, InclusionDirective = 503
}

struct FfiOptions
{
    string Target;                 // target triple the header is parsed for
    List<string> IncludePaths;     // -I
    List<string> Defines;          // -D
    List<string> ApiPaths;         // headers whose path contains one of these texts belong to the API
    string Clang;                  // the clang executable (libclang is looked up next to it)
    bool Verbose;
}

// The format version of .ffi files. Files with another version are regenerated.
int FfiFormat()
{
    return 2; // 2: function pointers are Action/Func types
}

List<string> FfiFlags(FfiOptions options)
{
    var flags = List<string>.Create();
    foreach (var p in options.IncludePaths)
        flags.Add("-I" + p);
    foreach (var d in options.Defines)
        flags.Add("-D" + d);
    foreach (var p in options.ApiPaths)
        flags.Add("-cshift-api=" + p); // not a clang flag: recorded so that the cache notices changes
    return flags;
}

// The hash of a file's content for the freshness check (FNV-1a, 64 bit), "" if it cannot be read.
string FfiHashFile(string path)
{
    var read = File.ReadAllBytes(path);
    if (read is uint8[] bytes)
    {
        uint64 hash = 14695981039346656037;
        foreach (var b in bytes)
            hash = unchecked((hash ^ (uint64)b) * 1099511628211);
        return "fnv1a:" + HexDigits(hash);
    }
    return "";
}

string HexDigits(uint64 value)
{
    string digits = "0123456789abcdef";
    string text = "";
    for (var i = 0; i < 16; i += 1)
    {
        text = digits[(int)(value % 16)].ToString() + text;
        value = value / 16;
    }
    return text;
}

string Slashes(string p)
{
    return p.Replace("\\", "/");
}

// ---------------------------------------------------------------------------
// Loading libclang
// ---------------------------------------------------------------------------

bool[] ClangLoaded = new bool[1];

Error<void> LoadLibclang(string clangExe)
{
    if (ClangLoaded[0])
        return;
    var candidates = List<string>.Create();
    var env = Process.GetEnv("CSHIFT_LIBCLANG");
    if (env is string fromEnv)
    {
        if (fromEnv.Length > 0)
            candidates.Add(fromEnv);
    }
    string binDir = clangExe.Length == 0 ? "" : Path.GetDirectory(clangExe);
    if (binDir.Length > 0)
    {
        candidates.Add(Path.Combine(binDir, "libclang.dll"));
        string libDir = Path.Combine(Path.GetDirectory(binDir), "lib");
        candidates.Add(Path.Combine(libDir, "libclang.so"));
        candidates.Add(Path.Combine(libDir, "libclang.dylib"));
        if (Directory.Exists(libDir))
        {
            foreach (var name in Directory.GetEntries(libDir))
            {
                if (name.StartsWith("libclang") && !name.Contains("cpp") && (name.Contains(".so") || name.Contains(".dylib")))
                    candidates.Add(Path.Combine(libDir, name));
            }
        }
    }
    candidates.Add("libclang.dll");
    candidates.Add("libclang.so");
    candidates.Add("libclang.dylib");
    // Linux distributions keep libclang in the LLVM folder of clang (clang itself is often a link into it).
    if (clangExe.Length > 0 && !Process.IsWindows())
    {
        var resolved = Process.RunCapture("readlink -f \"" + clangExe + "\" 2>/dev/null");
        if (resolved is string real)
        {
            string realDir = Path.GetDirectory(real.Trim());
            if (realDir.Length > 0 && realDir != binDir)
                candidates.Add(Path.Combine(Path.Combine(Path.GetDirectory(realDir), "lib"), "libclang.so"));
        }
    }

    string lastError = "";
    foreach (var file in candidates)
    {
        bool isPath = file.Contains('/') || file.Contains('\\');
        if (isPath && !File.Exists(file))
            continue;
        if (Host.ClangOpen(file) != 0)
        {
            ClangLoaded[0] = true;
            return;
        }
        lastError = Host.ClangError();
        if (lastError.StartsWith("this libclang"))
            return error(lastError);
    }
    return error("libclang was not found (looked next to '" + clangExe + "'; set CSHIFT_LIBCLANG to its path)" +
                 (lastError.Length == 0 ? "" : ": " + lastError));
}

// ---------------------------------------------------------------------------
// The exported model
// ---------------------------------------------------------------------------

struct FField
{
    string Name;
    string Type;
    int64 Offset;
}

struct FStruct
{
    string Name;
    string Kind; // "struct" or "union"
    int64 Size;
    int64 Align;
    bool Opaque;
    List<FField> Fields;
}

struct FInt
{
    int64 Value;
    bool IsUnsigned; // Value holds the bit pattern of an unsigned number
}

struct FMember
{
    string Name;
    FInt Value;
}

struct FEnum
{
    string Name;
    string Base;
    List<FMember> Members;
}

enum FConstKind : int32 { Integer, Float, Text }

struct FConst
{
    string Name;
    string Type;
    FConstKind Kind;
    FInt Integer;
    double Number;
    string Text;
}

struct FParam
{
    string Name;
    string Type;
    string Ref;  // none | ref | constref
    bool Nullable;
    bool CString;
}

struct FFunc
{
    string Name;
    string Returns;
    List<FParam> Params;
    bool Variadic;
    string Symbol;
    bool RetCString;
    bool RetOut;
    string CType;
}

struct FSkip
{
    string Name;
    string Reason;
}

struct TypeWork
{
    Host.CXCursor Decl;
    bool IsEnum;
}

struct MacroToken
{
    int Kind; // 0 punctuation, 1 keyword, 2 identifier, 3 literal
    string Text;
}

struct Macro
{
    string Name;
    List<MacroToken> Body;
}

struct IncludeDirective
{
    string Includer;
    string Included;
    bool Quoted;
}

struct MacroProbe
{
    string Name;
    bool HasUnsigned;
}

string NativeIntegerName(string typedefName)
{
    if (typedefName == "size_t" || typedefName == "uintptr_t" || typedefName == "SIZE_T" || typedefName == "UINT_PTR" ||
        typedefName == "ULONG_PTR" || typedefName == "DWORD_PTR" || typedefName == "__size_t" || typedefName == "rsize_t")
        return "nuint";
    if (typedefName == "ssize_t" || typedefName == "ptrdiff_t" || typedefName == "intptr_t" || typedefName == "SSIZE_T" ||
        typedefName == "INT_PTR" || typedefName == "LONG_PTR" || typedefName == "__ssize_t")
        return "nint";
    return "";
}

bool LooksAnonymous(string name)
{
    return name.Length == 0 || name.Contains('(') || name.Contains("unnamed") || name.Contains("anonymous");
}

// ---------------------------------------------------------------------------
// The generator
// ---------------------------------------------------------------------------

struct FfiGenerator
{
    string Name;         // namespace name
    string Header;       // as written
    string BaseDir;      // directory of the importing file
    FfiOptions Options;

    void* Index;
    void* Tu;
    string WrapperFile;
    string WrapperText;
    string MainDir;          // directory of the requested header
    bool MainIsSystem;       // the requested header lives in a system include directory
    HashSet<string> SystemApiFiles;
    string MainHeaderPath;
    List<string> Dependencies;
    Dictionary<string, bool> ApiFiles;
    List<string> SystemIncludeCache;
    bool SystemIncludesKnown;

    Dictionary<int, string> TypedefNames; // record/enum declaration -> typedef name
    Dictionary<int, string> RecordNames;
    Dictionary<int, string> EnumNames;
    HashSet<int> ExportedTypes;
    List<TypeWork> TypeQueue;

    List<FStruct> Structs;
    List<FEnum> Enums;
    List<FConst> Constants;
    List<FFunc> Functions;
    List<FSkip> Skipped;
    HashSet<string> ConstantNames;
    HashSet<string> FunctionNames;
    StringBuilder ShimText;
    string ClangVersion;

    static FfiGenerator Create(string name, string header, string baseDir, FfiOptions options)
    {
        var g = FfiGenerator { Name = name, Header = header, BaseDir = baseDir, Options = options };
        g.WrapperFile = "";
        g.WrapperText = "";
        g.MainDir = "";
        g.MainHeaderPath = "";
        g.ClangVersion = "";
        g.SystemApiFiles = HashSet<string>.Create();
        g.Dependencies = List<string>.Create();
        g.ApiFiles = Dictionary<string, bool>.Create();
        g.SystemIncludeCache = List<string>.Create();
        g.TypedefNames = Dictionary<int, string>.Create();
        g.RecordNames = Dictionary<int, string>.Create();
        g.EnumNames = Dictionary<int, string>.Create();
        g.ExportedTypes = HashSet<int>.Create();
        g.TypeQueue = List<TypeWork>.Create();
        g.Structs = List<FStruct>.Create();
        g.Enums = List<FEnum>.Create();
        g.Constants = List<FConst>.Create();
        g.Functions = List<FFunc>.Create();
        g.Skipped = List<FSkip>.Create();
        g.ConstantNames = HashSet<string>.Create();
        g.FunctionNames = HashSet<string>.Create();
        g.ShimText = StringBuilder.Create();
        return g;
    }

    // ---- libclang helpers ----

    static List<Host.CXCursor> Children(Host.CXCursor c)
    {
        var list = List<Host.CXCursor>.Create();
        int n = Host.ClangChildren(c);
        for (var i = 0; i < n; i += 1)
            list.Add(Host.ClangChild(i));
        return list;
    }

    static int Kind(Host.CXCursor c)
    {
        return Host.ClangCursorKind(c);
    }

    static int HashOf(Host.CXCursor decl)
    {
        return unchecked((int)Host.ClangHashCursor(Host.ClangCanonicalCursor(decl)));
    }

    // libclang does not know where the C library headers (stddef.h, ...) of the installation are, so ask the clang
    // driver, which does: "clang -E -x c -v -" lists its include search path on stderr.
    List<string> SystemIncludes()
    {
        if (SystemIncludesKnown)
            return SystemIncludeCache;
        SystemIncludesKnown = true;
        if (Options.Clang.Length == 0)
            return SystemIncludeCache;
        bool windows = Process.IsWindows();
        string command = "\"" + (windows ? Options.Clang.Replace("/", "\\") : Options.Clang) + "\" -E -x c -v";
        if (Options.Target.Length > 0)
            command += " -target " + Options.Target;
        command += windows ? " - < nul 2>&1" : " - < /dev/null 2>&1";
        var output = Process.RunCapture(windows ? "\"" + command + "\"" : command);
        if (output is string text)
        {
            bool inList = false;
            foreach (var raw in text.Split('\n'))
            {
                string line = raw.Replace("\r", "");
                if (line.StartsWith("#include <...> search starts here"))
                    inList = true;
                else if (line.StartsWith("End of search list"))
                    break;
                else if (inList && line.StartsWith(" "))
                {
                    string dir = line.Trim();
                    // "(framework directory)" entries only exist on macOS and cannot be used with -isystem.
                    if (!dir.Contains(" ("))
                        SystemIncludeCache.Add(dir);
                }
            }
        }
        return SystemIncludeCache;
    }

    string CompilerArgs()
    {
        var args = List<string>.Create();
        args.Add("-x");
        args.Add("c");
        args.Add("-I" + Slashes(BaseDir.Length == 0 ? "." : BaseDir));
        if (Options.Target.Length > 0)
        {
            args.Add("-target");
            args.Add(Options.Target);
        }
        foreach (var dir in SystemIncludes())
            args.Add("-isystem" + Slashes(dir));
        foreach (var f in FfiFlags(Options))
        {
            if (!f.StartsWith("-cshift-api="))
                args.Add(f);
        }
        return string.Join("\n", args.ToArray());
    }

    bool Parse()
    {
        Index = Host.ClangCreateIndex();
        string baseDir = Path.GetFullPath(BaseDir.Length == 0 ? "." : BaseDir);
        WrapperFile = Slashes(Path.Combine(baseDir, "__cshift_ffi_wrapper.c"));
        WrapperText = "#include \"" + Header + "\"\n";
        int flags = 0x01 | 0x40 | 0x200; // DetailedPreprocessingRecord | SkipFunctionBodies | KeepGoing
        Tu = Host.ClangParse(Index, WrapperFile, CompilerArgs(), WrapperText, flags);
        return Tu != null;
    }

    bool IsApiFile(void* file)
    {
        if (file == null)
            return false;
        string name = Slashes(Host.ClangFileName(file));
        var known = ApiFiles.TryGet(name);
        if (known is bool cached)
            return cached;
        bool system = Host.ClangFileIsSystem(Tu, file) != 0;
        bool underMain = MainDir.Length > 0 && name.StartsWith(MainDir);
        bool explicitApi = false; // "apiPaths" in cshift.json / --ffi-api: umbrella headers for libraries in system paths
        foreach (var p in Options.ApiPaths)
        {
            if (name.Contains(p))
                explicitApi = true;
        }
        bool result = name != WrapperFile && (explicitApi || !system || (MainIsSystem ? SystemApiFiles.Contains(name) : underMain));
        ApiFiles.Set(name, result);
        return result;
    }

    bool IsApiCursor(Host.CXCursor c)
    {
        return IsApiFile(Host.ClangCursorFile(c));
    }

    // ---- types ----

    // Removes typedefs and other sugar. A typedef of a pointer-sized integer (size_t, ...) stops the peeling and
    // reports its native type name (only with 'wantNative').
    Host.CXType Peel(Host.CXType type, bool wantNative, ref string nativeName)
    {
        var t = type;
        for (var depth = 0; depth < 32; depth += 1)
        {
            int kind = t.Kind;
            if (kind == (int)CxType.Typedef)
            {
                var decl = Host.ClangTypeDeclaration(t);
                if (wantNative)
                {
                    string n = NativeIntegerName(Host.ClangCursorSpelling(decl));
                    if (n.Length > 0)
                    {
                        nativeName = n;
                        return t;
                    }
                }
                t = Host.ClangTypedefUnderlying(decl);
            }
            else if (kind == (int)CxType.Elaborated)
                t = Host.ClangNamedType(t);
            else if (kind == (int)CxType.Attributed)
                t = Host.ClangModifiedType(t);
            else if (kind == (int)CxType.Unexposed)
            {
                var canonical = Host.ClangCanonicalType(t);
                if (canonical.Kind == (int)CxType.Unexposed)
                    return canonical;
                t = canonical;
            }
            else
                return t;
        }
        return Host.ClangCanonicalType(t);
    }

    Host.CXType PeelPlain(Host.CXType t)
    {
        string unused = "";
        return Peel(t, false, ref unused);
    }

    string NativeNameOf(Host.CXType t)
    {
        string native = "";
        Peel(t, true, ref native);
        return native;
    }

    static bool IsPlainChar(Host.CXType t)
    {
        return t.Kind == (int)CxType.CharS || t.Kind == (int)CxType.CharU;
    }

    bool IsComplete(Host.CXCursor decl)
    {
        var def = Host.ClangCursorDefinition(decl);
        return Host.ClangCursorIsNull(def) == 0 && Host.ClangSizeOf(Host.ClangCursorType(def)) >= 0;
    }

    // The CShift name of a struct/union: the typedef name if there is one (the public name: z_stream, not
    // z_stream_s; FILE, not _iobuf), else the tag.
    string RecordName(Host.CXCursor decl)
    {
        int key = HashOf(decl);
        var known = RecordNames.TryGet(key);
        if (known is string found)
            return found;
        string name = PublicName(decl, key);
        RecordNames.Set(key, name);
        return name;
    }

    string EnumName(Host.CXCursor decl)
    {
        int key = HashOf(decl);
        var known = EnumNames.TryGet(key);
        if (known is string found)
            return found;
        string name = PublicName(decl, key);
        EnumNames.Set(key, name);
        return name;
    }

    string PublicName(Host.CXCursor decl, int key)
    {
        string tag = Host.ClangCursorSpelling(decl);
        if (LooksAnonymous(tag))
            tag = "";
        string td = "";
        var typedefName = TypedefNames.TryGet(key);
        if (typedefName is string t)
            td = t;
        return td.Length == 0 ? tag : td;
    }

    void NeedRecord(Host.CXCursor decl)
    {
        if (ExportedTypes.Add(HashOf(decl)))
            TypeQueue.Add(TypeWork { Decl = decl, IsEnum = false });
    }

    void NeedEnum(Host.CXCursor decl)
    {
        if (ExportedTypes.Add(HashOf(decl)))
            TypeQueue.Add(TypeWork { Decl = decl, IsEnum = true });
    }

    // The CShift type of a C type, or "" (with a reason) if it cannot be represented. Pointers become raw pointers.
    string TypeString(Host.CXType t, ref string why)
    {
        string native = "";
        var p = Peel(t, true, ref native);
        if (native.Length > 0)
            return native;

        int kind = p.Kind;
        if (kind == (int)CxType.Void)
            return "void";
        if (kind == (int)CxType.Bool)
            return "bool";
        if (kind == (int)CxType.CharU || kind == (int)CxType.CharS)
            return "char";
        if (kind == (int)CxType.SChar)
            return "int8";
        if (kind == (int)CxType.UChar)
            return "uint8";
        if (kind == (int)CxType.Short)
            return "int16";
        if (kind == (int)CxType.UShort)
            return "uint16";
        if (kind == (int)CxType.Int)
            return "int32";
        if (kind == (int)CxType.UInt)
            return "uint32";
        if (kind == (int)CxType.Long)
            return Host.ClangSizeOf(p) == 8 ? "int64" : "int32";
        if (kind == (int)CxType.ULong)
            return Host.ClangSizeOf(p) == 8 ? "uint64" : "uint32";
        if (kind == (int)CxType.LongLong)
            return "int64";
        if (kind == (int)CxType.ULongLong)
            return "uint64";
        if (kind == (int)CxType.WChar)
            return Host.ClangSizeOf(p) == 2 ? "uint16" : "uint32";
        if (kind == (int)CxType.Char16)
            return "uint16";
        if (kind == (int)CxType.Char32)
            return "uint32";
        if (kind == (int)CxType.Float)
            return "float32";
        if (kind == (int)CxType.Double)
            return "float64";
        if (kind == (int)CxType.Pointer)
            return RawPointerString(p, ref why);
        if (kind == (int)CxType.Record)
        {
            var decl = Host.ClangTypeDeclaration(p);
            NeedRecord(decl);
            string name = RecordName(decl);
            if (name.Length == 0)
            {
                why = "anonymous struct or union";
                return "";
            }
            return name;
        }
        if (kind == (int)CxType.Enum)
        {
            var decl = Host.ClangTypeDeclaration(p);
            string name = EnumName(decl);
            if (name.Length == 0)
                return TypeString(Host.ClangEnumIntegerType(decl), ref why); // anonymous enum: plain integer
            NeedEnum(decl);
            return name;
        }
        if (kind == (int)CxType.ConstantArray || kind == (int)CxType.IncompleteArray || kind == (int)CxType.VariableArray)
            why = "array type";
        else if (kind == (int)CxType.FunctionProto || kind == (int)CxType.FunctionNoProto)
            why = "function type";
        else if (kind == (int)CxType.LongDouble)
            why = "long double";
        else if (kind == (int)CxType.Int128 || kind == (int)CxType.UInt128)
            why = "128-bit integer";
        else if (kind == (int)CxType.Complex)
            why = "complex number";
        else if (kind == (int)CxType.Vector)
            why = "vector type";
        else
            why = "unsupported type '" + Host.ClangTypeSpelling(t) + "'";
        return "";
    }

    string RawPointerString(Host.CXType pointer, ref string why)
    {
        var pointee = PeelPlain(Host.ClangPointeeType(pointer));
        if (pointee.Kind == (int)CxType.Void || pointee.Kind == (int)CxType.FunctionNoProto)
            return "void*";
        if (pointee.Kind == (int)CxType.FunctionProto)
            return FunctionTypeString(pointee);
        string inner = TypeString(pointee, ref why);
        if (inner.Length == 0 || inner == "void")
        {
            why = "";
            return "void*"; // pointer to something that cannot be represented
        }
        return inner + "*";
    }

    // A callback parameter or result: scalars, enums and pointers only ("" otherwise).
    string CallbackType(Host.CXType t)
    {
        string native = "";
        var p = Peel(t, true, ref native);
        if (native.Length == 0 && p.Kind == (int)CxType.Record)
            return ""; // struct by value
        if (native.Length == 0 && (p.Kind == (int)CxType.ConstantArray || p.Kind == (int)CxType.IncompleteArray))
            return ""; // decays to a pointer in C, rare in callbacks
        string why = "";
        return TypeString(t, ref why);
    }

    // A C function pointer type becomes Action<...> / Func<..., R>; anything that cannot be represented (structs by
    // value, variadic functions, long double) stays a plain void*.
    string FunctionTypeString(Host.CXType function)
    {
        if (Host.ClangIsVariadic(function) != 0)
            return "void*";
        int count = Host.ClangNumArgTypes(function);
        if (count < 0 || count > 8)
            return "void*";
        var parts = List<string>.Create();
        for (var i = 0; i < count; i += 1)
        {
            string s = CallbackType(Host.ClangArgType(function, i));
            if (s.Length == 0 || s == "void")
                return "void*";
            parts.Add(s);
        }
        string result = CallbackType(Host.ClangResultType(function));
        if (result.Length == 0)
            return "void*";
        string name = result == "void" ? "Action" : "Func";
        if (result != "void")
            parts.Add(result);
        return parts.Count() == 0 ? name : name + "<" + string.Join(", ", parts.ToArray()) + ">";
    }

    // Maps a function parameter. Pointers to values become ref/const ref (that accept null), const char* becomes a
    // string, everything else stays a raw pointer.
    bool MapParam(Host.CXType t, ref FParam output, ref bool byValueRecord, ref string why)
    {
        byValueRecord = false;
        var p = PeelPlain(t);
        string nativeName = NativeNameOf(t);

        if (p.Kind == (int)CxType.Record && nativeName.Length == 0)
        {
            output.Type = TypeString(p, ref why);
            if (output.Type.Length == 0)
                return false;
            output.Ref = "constref"; // structs by value are passed through a generated shim
            byValueRecord = true;
            return true;
        }
        // An array parameter (char* argv[]) is a pointer to its first element in C.
        if (p.Kind == (int)CxType.ConstantArray || p.Kind == (int)CxType.IncompleteArray || p.Kind == (int)CxType.VariableArray)
        {
            string element = TypeString(Host.ClangArrayElementType(p), ref why);
            if (element.Length == 0 || element == "void")
                return false;
            output.Type = element + "*";
            return true;
        }
        if (p.Kind != (int)CxType.Pointer || nativeName.Length > 0)
        {
            output.Type = TypeString(t, ref why);
            return output.Type.Length > 0;
        }

        var pointeeSugar = Host.ClangPointeeType(p);
        bool isConst = Host.ClangIsConst(pointeeSugar) != 0;
        var pointee = PeelPlain(pointeeSugar);

        if (IsPlainChar(pointee))
        {
            if (isConst)
            {
                output.Type = "string";
                output.CString = true;
                return true;
            }
            output.Type = "char*";
            return true;
        }
        int kind = pointee.Kind;
        if (kind == (int)CxType.Void || kind == (int)CxType.FunctionNoProto)
        {
            output.Type = "void*";
            return true;
        }
        if (kind == (int)CxType.FunctionProto)
        {
            output.Type = FunctionTypeString(pointee);
            return true;
        }
        if (kind == (int)CxType.Pointer)
        {
            output.Type = RawPointerString(pointee, ref why);
            output.Ref = "ref";
            output.Nullable = true;
            return true;
        }
        if (kind == (int)CxType.Record)
        {
            var decl = Host.ClangTypeDeclaration(pointee);
            string name = RecordName(decl);
            NeedRecord(decl);
            if (name.Length == 0 || !IsComplete(decl))
            {
                output.Type = name.Length == 0 ? "void*" : name + "*"; // opaque handle
                return true;
            }
            output.Type = name;
            output.Ref = isConst ? "constref" : "ref";
            output.Nullable = true;
            return true;
        }

        string inner = TypeString(pointee, ref why);
        if (inner.Length == 0 || inner == "void")
        {
            why = "";
            output.Type = "void*";
            return true;
        }
        output.Type = inner;
        output.Ref = isConst ? "constref" : "ref";
        output.Nullable = true;
        return true;
    }

    // ---- export ----

    void ExportRecord(Host.CXCursor decl)
    {
        string name = RecordName(decl);
        if (name.Length == 0)
            return;
        var def = Host.ClangCursorDefinition(decl);
        var s = FStruct { Name = name, Kind = Kind(decl) == (int)CxCursor.UnionDecl ? "union" : "struct", Align = 1 };
        s.Fields = List<FField>.Create();
        if (Host.ClangCursorIsNull(def) != 0)
        {
            s.Opaque = true;
            Structs.Add(s);
            return;
        }
        var type = Host.ClangCursorType(def);
        int64 size = Host.ClangSizeOf(type);
        int64 align = Host.ClangAlignOf(type);
        if (size < 0)
        {
            s.Opaque = true;
            Structs.Add(s);
            return;
        }
        s.Size = size;
        s.Align = align > 0 ? align : 1;

        // Unions overlap their members: they are imported as a blob of the right size and alignment.
        if (s.Kind == "struct")
        {
            foreach (var field in Children(def))
            {
                if (Kind(field) != (int)CxCursor.FieldDecl)
                    continue;
                string fieldName = Host.ClangCursorSpelling(field);
                if (fieldName.Length == 0 || Host.ClangIsBitField(field) != 0)
                    continue; // anonymous members and bit fields are padding
                int64 bits = Host.ClangOffsetOfField(field);
                if (bits < 0 || bits % 8 != 0)
                    continue;
                string why = "";
                string ft = TypeString(Host.ClangCursorType(field), ref why);
                if (ft.Length == 0 || ft == "void")
                    continue; // arrays, long double, ... are padding
                s.Fields.Add(FField { Name = fieldName, Type = ft, Offset = bits / 8 });
            }
        }
        Structs.Add(s);
    }

    void ExportEnum(Host.CXCursor decl)
    {
        var def = Host.ClangCursorDefinition(decl);
        if (Host.ClangCursorIsNull(def) != 0)
            return;
        string why = "";
        string baseType = TypeString(Host.ClangEnumIntegerType(def), ref why);
        if (baseType.Length == 0)
            baseType = "int32";
        bool isUnsigned = baseType.StartsWith("uint");
        string name = EnumName(decl);

        var e = FEnum { Name = name, Base = baseType };
        e.Members = List<FMember>.Create();
        foreach (var member in Children(def))
        {
            if (Kind(member) != (int)CxCursor.EnumConstantDecl)
                continue;
            string memberName = Host.ClangCursorSpelling(member);
            var value = FInt { IsUnsigned = isUnsigned };
            value.Value = isUnsigned ? unchecked((int64)Host.ClangEnumUnsignedValue(member)) : Host.ClangEnumValue(member);
            e.Members.Add(FMember { Name = memberName, Value = value });

            // C code uses the enumerators as plain constants.
            if (ConstantNames.Add(memberName))
                Constants.Add(FConst { Name = memberName, Type = name.Length == 0 ? baseType : name, Kind = FConstKind.Integer, Integer = value, Text = "" });
        }
        if (name.Length > 0)
            Enums.Add(e);
    }

    void ExportFunction(Host.CXCursor c)
    {
        string name = Host.ClangCursorSpelling(c);
        if (name.Length == 0 || !FunctionNames.Add(name))
            return;
        if (Host.ClangStorageClass(c) == 3) // CX_SC_Static: static (inline) functions have no symbol to link
            return;

        var ft = Host.ClangCursorType(c);
        if (ft.Kind != (int)CxType.FunctionProto)
        {
            Skipped.Add(FSkip { Name = name, Reason = "function without a prototype" });
            return;
        }

        var f = FFunc { Name = name, Returns = "void", Symbol = "", CType = Host.ClangTypeSpelling(ft) };
        f.Params = List<FParam>.Create();
        f.Variadic = Host.ClangIsVariadic(ft) != 0;
        bool needsShim = false;
        string why = "";

        // return type
        var ret = Host.ClangResultType(ft);
        var retPeeled = PeelPlain(ret);
        string retNative = NativeNameOf(ret);
        if (retPeeled.Kind == (int)CxType.Record && retNative.Length == 0)
        {
            f.Returns = TypeString(retPeeled, ref why);
            f.RetOut = true;
            needsShim = true;
        }
        else if (retPeeled.Kind == (int)CxType.Pointer && retNative.Length == 0 &&
                 IsPlainChar(PeelPlain(Host.ClangPointeeType(retPeeled))) && Host.ClangIsConst(Host.ClangPointeeType(retPeeled)) != 0)
        {
            f.Returns = "string";
            f.RetCString = true;
        }
        else
        {
            f.Returns = TypeString(ret, ref why);
        }
        if (f.Returns.Length == 0)
        {
            Skipped.Add(FSkip { Name = name, Reason = "return type: " + why });
            return;
        }

        // parameters
        int n = Host.ClangNumArgTypes(ft);
        var byValue = List<bool>.Create();
        for (var i = 0; i < n; i += 1)
        {
            var p = FParam { Name = "", Type = "", Ref = "none" };
            var arg = Host.ClangArgument(c, i);
            p.Name = Host.ClangCursorIsNull(arg) != 0 ? "" : Host.ClangCursorSpelling(arg);
            bool byValueRecord = false;
            if (!MapParam(Host.ClangArgType(ft, i), ref p, ref byValueRecord, ref why))
            {
                Skipped.Add(FSkip { Name = name, Reason = "parameter " + (i + 1).ToString() + ": " + why });
                return;
            }
            if (byValueRecord)
                needsShim = true;
            byValue.Add(byValueRecord);
            f.Params.Add(p);
        }
        if (needsShim && f.Variadic)
        {
            Skipped.Add(FSkip { Name = name, Reason = "variadic function that takes or returns a struct by value" });
            return;
        }

        if (needsShim)
        {
            // The C compiler knows the ABI for structs by value: a generated C function takes pointers instead.
            f.Symbol = "__cs_shim_" + name;
            string parameters = "";
            string call = "";
            for (var i = 0; i < n; i += 1)
            {
                string ts = Host.ClangTypeSpelling(Host.ClangArgType(ft, i));
                string pn = "a" + i.ToString();
                if (i > 0)
                {
                    parameters += ", ";
                    call += ", ";
                }
                if (byValue.Get(i))
                {
                    parameters += ts + " *" + pn;
                    call += "*" + pn;
                }
                else if (ts.Contains('('))
                {
                    parameters += "void *" + pn; // function pointers: passed as void* and cast back
                    call += "(" + ts + ")" + pn;
                }
                else
                {
                    parameters += ts + " " + pn;
                    call += pn;
                }
            }
            string retSpelling = Host.ClangTypeSpelling(ret);
            string plain = parameters.Length == 0 ? "void" : parameters;
            if (f.RetOut)
            {
                parameters += (parameters.Length == 0 ? "" : ", ") + retSpelling + " *__ret";
                ShimText.Append("void " + f.Symbol + "(" + parameters + ") { *__ret = " + name + "(" + call + "); }\n");
            }
            else if (retSpelling == "void")
                ShimText.Append("void " + f.Symbol + "(" + plain + ") { " + name + "(" + call + "); }\n");
            else if (retSpelling.Contains('('))
                ShimText.Append("void *" + f.Symbol + "(" + plain + ") { return (void *)" + name + "(" + call + "); }\n");
            else
                ShimText.Append(retSpelling + " " + f.Symbol + "(" + plain + ") { return " + name + "(" + call + "); }\n");
        }
        Functions.Add(f);
    }

    // ---- macros ----

    List<Macro> CollectMacros()
    {
        var macros = List<Macro>.Create();
        Host.CXCursor root = Host.ClangTuCursor(Tu);
        foreach (var c in Children(root))
        {
            if (Kind(c) != (int)CxCursor.MacroDefinition || !IsApiCursor(c))
                continue;
            if (Host.ClangMacroFunctionLike(c) != 0 || Host.ClangMacroBuiltin(c) != 0)
                continue;
            string name = Host.ClangCursorSpelling(c);
            if (name.Length == 0 || name[0] == '_')
                continue; // include guards and implementation details
            int count = Host.ClangTokenize(Tu, c);
            var body = List<MacroToken>.Create();
            for (var i = 1; i < count; i += 1) // token 0 is the macro name
            {
                int kind = Host.ClangTokenKind(i);
                if (kind == 4) // comment
                    continue;
                body.Add(MacroToken { Kind = kind, Text = Host.ClangTokenSpelling(i) });
            }
            if (body.Count() > 0)
                macros.Add(Macro { Name = name, Body = body });
        }
        return macros;
    }

    void ExportMacros()
    {
        var probes = List<MacroProbe>.Create();
        foreach (var m in CollectMacros())
        {
            string name = m.Name;
            var body = m.Body;
            if (ConstantNames.Contains(name) || FunctionNames.Contains(name))
                continue;

            // strip redundant outer parentheses
            while (body.Count() >= 2 && body.Get(0).Text == "(" && body.Get(body.Count() - 1).Text == ")")
            {
                int depth = 0;
                bool wraps = true;
                for (var i = 0; i < body.Count(); i += 1)
                {
                    if (body.Get(i).Text == "(")
                        depth += 1;
                    else if (body.Get(i).Text == ")")
                        depth -= 1;
                    if (depth == 0 && i + 1 < body.Count())
                    {
                        wraps = false;
                        break;
                    }
                }
                if (!wraps)
                    break;
                var inner = List<MacroToken>.Create();
                for (var i = 1; i < body.Count() - 1; i += 1)
                    inner.Add(body.Get(i));
                body = inner;
            }
            if (body.Count() == 0)
                continue;

            // strings (adjacent literals are concatenated)
            bool allStrings = true;
            foreach (var t in body)
                allStrings = allStrings && t.Kind == 3 && t.Text.Length > 0 && t.Text[0] == '"';
            if (allStrings)
            {
                string text = "";
                bool ok = true;
                foreach (var t in body)
                {
                    bool one = false;
                    text += DecodeCString(t.Text, ref one);
                    ok = ok && one;
                }
                if (ok)
                {
                    Constants.Add(FConst { Name = name, Type = "string", Kind = FConstKind.Text, Text = text });
                    ConstantNames.Add(name);
                }
                continue;
            }

            // floating point numbers
            bool negative = false;
            int first = 0;
            if (body.Count() == 2 && body.Get(0).Text == "-")
            {
                negative = true;
                first = 1;
            }
            if (body.Count() - first == 1 && body.Get(first).Kind == 3 && IsFloatLiteral(body.Get(first).Text) && Char.IsDigit(body.Get(first).Text[0]))
            {
                string text = body.Get(first).Text;
                while (text.Length > 0 && (text[text.Length - 1] == 'f' || text[text.Length - 1] == 'F' || text[text.Length - 1] == 'l' || text[text.Length - 1] == 'L'))
                    text = text.Substring(0, text.Length - 1);
                var parsed = text.ParseDouble();
                if (parsed is double number)
                {
                    Constants.Add(FConst { Name = name, Type = "float64", Kind = FConstKind.Float, Number = negative ? -number : number, Text = "" });
                    ConstantNames.Add(name);
                }
                continue;
            }

            // integer constant expressions are evaluated by the compiler (second parse below)
            bool candidate = true;
            bool hasUnsigned = false;
            foreach (var t in body)
            {
                if (t.Kind == 0)
                    candidate = candidate && IsIntegerOperator(t.Text);
                else if (t.Kind == 3)
                {
                    string s = t.Text;
                    candidate = candidate && s.Length > 0 && (Char.IsDigit(s[0]) || s[0] == '\'') && !IsFloatLiteral(s);
                    if (s.Length > 1 && s[0] != '\'' && (s[s.Length - 1] == 'u' || s[s.Length - 1] == 'U' || s[s.Length - 2] == 'u' || s[s.Length - 2] == 'U'))
                        hasUnsigned = true;
                }
                else if (t.Kind != 2)
                    candidate = false; // identifiers are other macros or enumerators
            }
            if (candidate)
                probes.Add(MacroProbe { Name = name, HasUnsigned = hasUnsigned });
        }
        if (probes.Count() == 0)
            return;

        // Second parse: one anonymous enum per macro; the compiler evaluates the expression and reports it invalid if
        // it is not an integer constant expression.
        var probeText = StringBuilder.Create();
        probeText.Append(WrapperText);
        for (var i = 0; i < probes.Count(); i += 1)
            probeText.Append("enum { __cs_m" + i.ToString() + " = (" + probes.Get(i).Name + ") };\n");
        void* probeTu = Host.ClangParse(Index, WrapperFile, CompilerArgs(), probeText.ToString(), 0x40 | 0x200);
        if (probeTu == null)
            return;
        foreach (var top in Children(Host.ClangTuCursor(probeTu)))
        {
            if (Kind(top) != (int)CxCursor.EnumDecl)
                continue;
            foreach (var c in Children(top))
            {
                if (Kind(c) != (int)CxCursor.EnumConstantDecl)
                    continue;
                string n = Host.ClangCursorSpelling(c);
                if (!n.StartsWith("__cs_m") || Host.ClangIsInvalid(c) != 0)
                    continue;
                var index = n.Substring(6).ParseInt();
                if (index is int i)
                {
                    if (i < 0 || i >= probes.Count())
                        continue;
                    int64 v = Host.ClangEnumValue(c);
                    var k = FConst { Name = probes.Get(i).Name, Kind = FConstKind.Integer, Text = "" };
                    k.Integer.Value = v;
                    if (probes.Get(i).HasUnsigned && v >= 0 && v <= 4294967295)
                    {
                        k.Type = "uint32";
                        k.Integer.IsUnsigned = true;
                    }
                    else if (v >= -2147483648 && v <= 2147483647)
                        k.Type = "int32";
                    else if (v >= 0 && v <= 4294967295)
                    {
                        k.Type = "uint32";
                        k.Integer.IsUnsigned = true;
                    }
                    else
                        k.Type = "int64";
                    if (ConstantNames.Add(k.Name))
                        Constants.Add(k);
                }
            }
        }
        Host.ClangDisposeTu(probeTu);
    }

    static bool IsIntegerOperator(string s)
    {
        return s == "+" || s == "-" || s == "*" || s == "/" || s == "%" || s == "<<" || s == ">>" || s == "&" || s == "|" ||
               s == "^" || s == "~" || s == "!" || s == "(" || s == ")";
    }

    static bool IsFloatLiteral(string s)
    {
        if (s.Length > 1 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
            return false;
        return s.Contains('.') || s.Contains('e') || s.Contains('E');
    }

    // A single C string literal token ("..."), decoded.
    static string DecodeCString(string literal, ref bool ok)
    {
        ok = literal.Length >= 2 && literal[0] == '"' && literal[literal.Length - 1] == '"';
        if (!ok)
            return "";
        var bytes = List<uint8>.Create();
        int i = 1;
        while (i + 1 < literal.Length)
        {
            char c = literal[i];
            if (c != '\\' || i + 2 >= literal.Length)
            {
                bytes.Add((uint8)c);
                i += 1;
                continue;
            }
            i += 1;
            char n = literal[i];
            if (n == 'n')
                bytes.Add(10);
            else if (n == 't')
                bytes.Add(9);
            else if (n == 'r')
                bytes.Add(13);
            else if (n == 'a')
                bytes.Add(7);
            else if (n == 'b')
                bytes.Add(8);
            else if (n == 'f')
                bytes.Add(12);
            else if (n == 'v')
                bytes.Add(11);
            else if (n == 'x')
            {
                int v = 0;
                while (i + 2 < literal.Length && Char.IsHexDigit(literal[i + 1]))
                {
                    i += 1;
                    v = v * 16 + Char.HexValue(literal[i]);
                }
                bytes.Add((uint8)(v & 255));
            }
            else if (n >= '0' && n <= '7')
            {
                int v = (int)n - 48;
                for (var k = 0; k < 2 && i + 2 < literal.Length && literal[i + 1] >= '0' && literal[i + 1] <= '7'; k += 1)
                {
                    i += 1;
                    v = v * 8 + ((int)literal[i] - 48);
                }
                bytes.Add((uint8)(v & 255));
            }
            else
                bytes.Add((uint8)n);
            i += 1;
        }
        return string.FromBytes(bytes.ToArray());
    }

    // ---- output ----

    Error<void> WriteJson(string ffiPath)
    {
        string shimName = "";
        if (ShimText.Length() > 0)
        {
            shimName = Path.GetStem(ffiPath) + ".shim.c";
            string shimPath = Path.Combine(Path.GetDirectory(ffiPath), shimName);
            string shim = "/* Generated by cshc: wrappers for C functions that take or return structs by value. */\n" +
                          "#include \"" + MainHeaderPath + "\"\n\n" + ShimText.ToString();
            var written = File.WriteAllText(shimPath, shim);
            if (!written)
                return error("cannot write '" + shimPath + "': " + written.Message);
        }

        var w = JsonWriter.Create();
        w.BeginObject();
        w.Key("format");
        w.Raw(FfiFormat().ToString());
        w.Key("namespace");
        w.Text(Name);
        w.Key("header");
        w.Text(Header);
        w.Key("target");
        w.Text(Options.Target);
        w.Key("flags");
        w.BeginArray();
        foreach (var f in FfiFlags(Options))
            w.Text(f);
        w.EndArray();
        w.Key("generator");
        w.Text("cshc " + ClangVersion);
        w.Key("dependencies");
        w.BeginArray();
        foreach (var d in Dependencies)
        {
            w.BeginObject();
            w.Key("path");
            w.Text(d);
            w.Key("hash");
            w.Text(FfiHashFile(d));
            w.EndObject();
        }
        w.EndArray();
        if (shimName.Length > 0)
        {
            w.Key("shim");
            w.Text(shimName);
        }

        w.Key("constants");
        w.BeginArray();
        foreach (var c in Constants)
        {
            w.BeginObject();
            w.Key("name");
            w.Text(c.Name);
            w.Key("type");
            w.Text(c.Type);
            w.Key("value");
            if (c.Kind == FConstKind.Integer)
                w.Raw(IntText(c.Integer));
            else if (c.Kind == FConstKind.Float)
                w.Raw(c.Number.ToString());
            else
                w.Text(c.Text);
            w.EndObject();
        }
        w.EndArray();

        w.Key("enums");
        w.BeginArray();
        foreach (var e in Enums)
        {
            w.BeginObject();
            w.Key("name");
            w.Text(e.Name);
            w.Key("base");
            w.Text(e.Base);
            w.Key("members");
            w.BeginArray();
            foreach (var m in e.Members)
            {
                w.BeginObject();
                w.Key("name");
                w.Text(m.Name);
                w.Key("value");
                w.Raw(IntText(m.Value));
                w.EndObject();
            }
            w.EndArray();
            w.EndObject();
        }
        w.EndArray();

        w.Key("structs");
        w.BeginArray();
        foreach (var s in Structs)
        {
            w.BeginObject();
            w.Key("name");
            w.Text(s.Name);
            w.Key("kind");
            w.Text(s.Kind);
            w.Key("size");
            w.Raw(s.Size.ToString());
            w.Key("align");
            w.Raw(s.Align.ToString());
            w.Key("opaque");
            w.Raw(s.Opaque ? "true" : "false");
            w.Key("fields");
            w.BeginArray();
            foreach (var f in s.Fields)
            {
                w.BeginObject();
                w.Key("name");
                w.Text(f.Name);
                w.Key("type");
                w.Text(f.Type);
                w.Key("offset");
                w.Raw(f.Offset.ToString());
                w.EndObject();
            }
            w.EndArray();
            w.EndObject();
        }
        w.EndArray();

        w.Key("functions");
        w.BeginArray();
        foreach (var f in Functions)
        {
            w.BeginObject();
            w.Key("name");
            w.Text(f.Name);
            w.Key("returns");
            w.Text(f.Returns);
            w.Key("params");
            w.BeginArray();
            foreach (var p in f.Params)
            {
                w.BeginObject();
                w.Key("name");
                w.Text(p.Name);
                w.Key("type");
                w.Text(p.Type);
                if (p.Ref != "none")
                {
                    w.Key("ref");
                    w.Text(p.Ref);
                }
                if (p.Nullable)
                {
                    w.Key("nullable");
                    w.Raw("true");
                }
                if (p.CString)
                {
                    w.Key("cstring");
                    w.Raw("true");
                }
                w.EndObject();
            }
            w.EndArray();
            if (f.Variadic)
            {
                w.Key("variadic");
                w.Raw("true");
            }
            if (f.RetCString)
            {
                w.Key("retCString");
                w.Raw("true");
            }
            if (f.RetOut)
            {
                w.Key("retOut");
                w.Raw("true");
            }
            if (f.Symbol.Length > 0)
            {
                w.Key("symbol");
                w.Text(f.Symbol);
            }
            w.Key("c");
            w.Text(f.CType);
            w.EndObject();
        }
        w.EndArray();

        w.Key("skipped");
        w.BeginArray();
        foreach (var s in Skipped)
        {
            w.BeginObject();
            w.Key("name");
            w.Text(s.Name);
            w.Key("reason");
            w.Text(s.Reason);
            w.EndObject();
        }
        w.EndArray();
        w.EndObject();

        var result = File.WriteAllText(ffiPath, w.ToString() + "\n");
        if (!result)
            return error("cannot write '" + ffiPath + "': " + result.Message);
        return;
    }

    static string IntText(FInt v)
    {
        if (v.IsUnsigned && v.Value < 0)
            return "\"" + unchecked((uint64)v.Value).ToString() + "\""; // above int64.MaxValue: decimal string
        return v.Value.ToString();
    }

    // ---- the whole run ----

    Error<void> Run(string ffiPath)
    {
        if (!Parse())
            return error("libclang could not parse \"" + Header + "\"");
        ClangVersion = Host.ClangVersion();

        // Diagnostics: a header that cannot be found is fatal, everything else is only reported.
        int diagnostics = Host.ClangNumDiagnostics(Tu);
        string firstProblem = "";
        string problems = "";
        int errorCount = 0;
        for (var i = 0; i < diagnostics; i += 1)
        {
            if (Host.ClangDiagnosticSeverity(Tu, i) >= 3) // CXDiagnostic_Error
            {
                string text = Host.ClangDiagnosticText(Tu, i);
                if (firstProblem.Length == 0)
                    firstProblem = text;
                if (errorCount < 5)
                    problems += "\n  " + text;
                errorCount += 1;
            }
        }

        // Included files: the requested header (included directly by the wrapper) and everything that is part of the API.
        var inclusionNames = List<string>.Create();
        var inclusionDepths = List<int>.Create();
        var inclusionFiles = List<void*>.Create();
        int inclusions = Host.ClangInclusions(Tu);
        for (var i = 0; i < inclusions; i += 1)
        {
            void* file = Host.ClangInclusionFile(i);
            inclusionFiles.Add(file);
            inclusionDepths.Add(Host.ClangInclusionDepth(i));
            inclusionNames.Add(Slashes(Host.ClangFileName(file)));
        }
        string mainHeader = "";
        for (var i = 0; i < inclusions; i += 1)
        {
            if (inclusionDepths.Get(i) == 1 && mainHeader.Length == 0)
                mainHeader = inclusionNames.Get(i);
        }
        if (mainHeader.Length == 0)
            return error("cannot find the header \"" + Header + "\" (searched relative to '" + BaseDir + "' and in the include paths)" +
                         (firstProblem.Length == 0 ? "" : ":\n  " + firstProblem));
        // Types that failed to resolve would silently become 'int', so errors in the header are fatal.
        if (errorCount > 0)
            return error("libclang reports " + errorCount.ToString() + " error(s) in \"" + Header + "\":" + problems +
                         (errorCount > 5 ? "\n  ..." : "") +
                         "\n  (set \"includePaths\" / \"defines\" in cshift.json or pass -I / -D if the header needs them)");
        MainHeaderPath = mainHeader;
        MainDir = Slashes(Path.GetDirectory(mainHeader)) + "/";
        ApiFiles = Dictionary<string, bool>.Create();

        // A header that lives in a system include directory (zlib.h in /usr/include) sits next to the whole C library,
        // so the directory says nothing about what belongs to it. Only the files it includes with "quotes" (zconf.h) do.
        MainIsSystem = false;
        SystemApiFiles = HashSet<string>.Create();
        for (var i = 0; i < inclusions; i += 1)
        {
            if (inclusionDepths.Get(i) == 1 && inclusionNames.Get(i) == mainHeader)
                MainIsSystem = Host.ClangFileIsSystem(Tu, inclusionFiles.Get(i)) != 0;
        }
        var root = Host.ClangTuCursor(Tu);
        var top = Children(root);
        if (MainIsSystem)
        {
            var directives = List<IncludeDirective>.Create();
            foreach (var c in top)
            {
                if (Kind(c) != (int)CxCursor.InclusionDirective)
                    continue;
                void* included = Host.ClangIncludedFile(c);
                void* includer = Host.ClangCursorFile(c);
                if (included == null || includer == null)
                    continue;
                bool quoted = false;
                int count = Host.ClangTokenize(Tu, c);
                for (var i = 0; i < count; i += 1)
                {
                    if (Host.ClangTokenSpelling(i).StartsWith("\""))
                        quoted = true;
                }
                directives.Add(IncludeDirective { Includer = Slashes(Host.ClangFileName(includer)), Included = Slashes(Host.ClangFileName(included)), Quoted = quoted });
            }
            SystemApiFiles.Add(mainHeader);
            bool changed = true;
            while (changed)
            {
                changed = false;
                foreach (var d in directives)
                {
                    if (d.Quoted && SystemApiFiles.Contains(d.Includer) && SystemApiFiles.Add(d.Included))
                        changed = true;
                }
            }
        }

        // Dependencies for the freshness check: every file that belongs to the API.
        var seen = HashSet<string>.Create();
        for (var i = 0; i < inclusions; i += 1)
        {
            if (inclusionDepths.Get(i) > 0 && IsApiFile(inclusionFiles.Get(i)) && seen.Add(inclusionNames.Get(i)))
                Dependencies.Add(inclusionNames.Get(i));
        }

        // typedef names of records and enums
        foreach (var c in top)
        {
            if (Kind(c) != (int)CxCursor.TypedefDecl)
                continue;
            var under = PeelPlain(Host.ClangTypedefUnderlying(c));
            if (under.Kind != (int)CxType.Record && under.Kind != (int)CxType.Enum)
                continue;
            int key = HashOf(Host.ClangTypeDeclaration(under));
            if (!TypedefNames.ContainsKey(key))
                TypedefNames.Set(key, Host.ClangCursorSpelling(c));
        }

        // the API: functions, records, enums
        foreach (var c in top)
        {
            if (!IsApiCursor(c))
                continue;
            int kind = Kind(c);
            if (kind == (int)CxCursor.FunctionDecl)
                ExportFunction(c);
            else if (kind == (int)CxCursor.StructDecl || kind == (int)CxCursor.UnionDecl)
                NeedRecord(c);
            else if (kind == (int)CxCursor.EnumDecl)
                NeedEnum(c);
            else if (kind == (int)CxCursor.VarDecl)
            {
                string name = Host.ClangCursorSpelling(c);
                if (name.Length > 0)
                    Skipped.Add(FSkip { Name = name, Reason = "global variables are not supported" });
            }
        }

        // exported types may pull in further types
        for (var i = 0; i < TypeQueue.Count(); i += 1)
        {
            var work = TypeQueue.Get(i);
            if (work.IsEnum)
                ExportEnum(work.Decl);
            else
                ExportRecord(work.Decl);
        }

        ExportMacros();

        Host.ClangDisposeTu(Tu);
        Host.ClangDisposeIndex(Index);
        return WriteJson(ffiPath);
    }
}

Error<void> GenerateFfi(string name, string header, string baseDir, FfiOptions options, string ffiPath)
{
    try LoadLibclang(options.Clang);
    var generator = FfiGenerator.Create(name, header, baseDir, options);
    return generator.Run(ffiPath);
}

// ---------------------------------------------------------------------------
// A small JSON writer (the layout of llvm::json::OStream with an indentation of 2)
// ---------------------------------------------------------------------------

struct JsonWriter
{
    StringBuilder Out;
    List<int> Counts;     // values written in each open object/array
    bool[] AfterKey;

    static JsonWriter Create()
    {
        return JsonWriter { Out = StringBuilder.Create(), Counts = List<int>.Create(), AfterKey = new bool[1] };
    }

    void Indent()
    {
        Out.Append('\n');
        for (var i = 0; i < Counts.Count(); i += 1)
            Out.Append("  ");
    }

    // Before a value or a key: the separator and the line break.
    void Start()
    {
        if (AfterKey[0])
        {
            AfterKey[0] = false;
            return;
        }
        int depth = Counts.Count();
        if (depth == 0)
            return;
        if (Counts.Get(depth - 1) > 0)
            Out.Append(',');
        Counts.Set(depth - 1, Counts.Get(depth - 1) + 1);
        Indent();
    }

    void BeginObject()
    {
        Start();
        Out.Append('{');
        Counts.Add(0);
    }

    void EndObject()
    {
        End('}');
    }

    void BeginArray()
    {
        Start();
        Out.Append('[');
        Counts.Add(0);
    }

    void EndArray()
    {
        End(']');
    }

    void End(char close)
    {
        int count = Counts.Get(Counts.Count() - 1);
        Counts.RemoveAt(Counts.Count() - 1);
        if (count > 0)
            Indent();
        Out.Append(close);
    }

    void Key(string key)
    {
        Start();
        Out.Append(Quote(key) + ": ");
        AfterKey[0] = true;
    }

    void Text(string value)
    {
        Start();
        Out.Append(Quote(value));
    }

    void Raw(string value)
    {
        Start();
        Out.Append(value);
    }

    static string Quote(string s)
    {
        var sb = StringBuilder.Create();
        sb.Append('"');
        for (var i = 0; i < s.Length; i += 1)
        {
            char c = s[i];
            if (c == '"')
                sb.Append("\\\"");
            else if (c == '\\')
                sb.Append("\\\\");
            else if (c == '\n')
                sb.Append("\\n");
            else if (c == '\r')
                sb.Append("\\r");
            else if (c == '\t')
                sb.Append("\\t");
            else if ((int)c < 32)
                sb.Append("\\u00" + "0123456789abcdef"[(int)c / 16].ToString() + "0123456789abcdef"[(int)c % 16].ToString());
            else
                sb.Append(c);
        }
        sb.Append('"');
        return sb.ToString();
    }

    string ToString()
    {
        return Out.ToString();
    }
}
