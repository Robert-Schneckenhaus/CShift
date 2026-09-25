// cshiftc - the CShift compiler driver.

#include <cstring>
#include <fstream>
#include <map>
#include <iostream>
#include <sstream>

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Support/CodeGen.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/TargetParser/Triple.h>

#include "CodeGen.h"
#include "Dump.h"
#include "Ffi.h"
#include "Lexer.h"
#include "Parser.h"
#include "Project.h"
#include "StdlibData.h"

#ifndef CSHIFT_VERSION
#define CSHIFT_VERSION "dev"
#endif

namespace
{
enum class Command
{
    Compile, // cshiftc [options] files...
    Build,   // cshiftc build [project]
    Run,     // cshiftc run [project]
    New      // cshiftc new <path>
};

struct Options
{
    Command command = Command::Compile;
    bool optGiven = false;
    std::vector<std::string> inputs;
    std::string output;
    std::string target;
    std::string cc = "clang";
    std::vector<std::string> libs;         // -l<name>
    std::vector<std::string> libFiles;     // .a/.o/.lib files passed to the linker
    std::vector<std::string> libraryPaths; // -L<dir>
    std::vector<std::string> includePaths; // -I<dir> (for C headers imported with "using X from")
    std::vector<std::string> defines;      // -D<name>[=value]
    std::vector<std::string> apiPaths;     // --ffi-api=<text>
    int optLevel = 2;
    bool objectOnly = false;
    bool emitLlvm = false;
    bool run = false;
    bool verbose = false;
    bool arcStats = false;
    bool dumpTokens = false; // development: print the tokens / the syntax tree of the input files
    bool dumpAst = false;
    // Helper for cshc (the compiler written in CShift, which has no libclang): prepare the .ffi file of a C header.
    bool ffiPrepare = false;
    std::string ffiBaseDir;
    std::string ffiCacheDir;
};

void printUsage()
{
    std::cerr << "cshiftc - CShift compiler\n"
                 "\n"
                 "usage: cshiftc [options] file.csh [file2.csh ...]     compile single files\n"
                 "       cshiftc build [project] [options]              build a project (cshift.json)\n"
                 "       cshiftc run   [project] [options]              build and run a project\n"
                 "       cshiftc new   <directory>                      create a new project\n"
                 "\n"
                 "'project' is a directory containing cshift.json or the path of a project file;\n"
                 "without it cshift.json is searched in the current directory and its parents.\n"
                 "\n"
                 "options:\n"
                 "  -o <file>        output file\n"
                 "  -c               compile to an object file only (no linking)\n"
                 "  --emit-llvm      write LLVM IR (.ll) instead of an executable\n"
                 "  -O0 .. -O3       optimization level (default -O2)\n"
                 "  --target <triple> target triple (default: host)\n"
                 "  --cc <program>   C compiler used as linker driver (default: clang)\n"
                 "  -l<name>         link an additional library\n"
                 "  -L<dir>          library search path for the linker\n"
                 "  -I<dir>          include path for C headers (using X from \"header.h\")\n"
                 "  -D<name>[=value] define a macro when parsing C headers\n"
                 "  --ffi-api=<text> headers whose path contains <text> belong to the imported API (umbrella headers)\n"
                 "  file.a, file.o   libraries and object files are passed to the linker\n"
                 "  --run            run the program after building\n"
                 "  --arc-stats      debug: print heap allocations/frees when the program exits\n"
                 "  -v               verbose output\n"
                 "  --version        print the version\n"
                 "  -h, --help       show this help\n";
}

// Libraries and object files given on the command line go to the linker.
bool isLinkerInput(const std::string& a)
{
    for (const char* ext : {".a", ".o", ".obj", ".lib", ".so", ".dylib"})
    {
        size_t n = std::strlen(ext);
        if (a.size() > n && a.compare(a.size() - n, n, ext) == 0)
            return true;
    }
    return false;
}

bool parseArgs(int argc, char** argv, Options& o)
{
    int first = 1;
    if (argc > 1)
    {
        std::string cmd = argv[1];
        if (cmd == "build")
            o.command = Command::Build, first = 2;
        else if (cmd == "run")
            o.command = Command::Run, first = 2;
        else if (cmd == "new")
            o.command = Command::New, first = 2;
    }

    for (int i = first; i < argc; i += 1)
    {
        std::string a = argv[i];
        auto next = [&](const char* what) -> std::string {
            if (i + 1 >= argc)
            {
                std::cerr << "error: missing value for " << what << "\n";
                return "";
            }
            i += 1;
            return argv[i];
        };
        if (a == "--dump-tokens")
            o.dumpTokens = true;
        else if (a == "--dump-ast")
            o.dumpAst = true;
        else if (a == "--ffi-prepare")
            o.ffiPrepare = true;
        else if (a == "--ffi-base-dir")
            o.ffiBaseDir = next("--ffi-base-dir");
        else if (a == "--ffi-cache-dir")
            o.ffiCacheDir = next("--ffi-cache-dir");
        else if (a == "-h" || a == "--help")
            return false;
        else if (a == "-o")
            o.output = next("-o");
        else if (a == "-c")
            o.objectOnly = true;
        else if (a == "--emit-llvm")
            o.emitLlvm = true;
        else if (a == "--run")
            o.run = true;
        else if (a == "-v")
            o.verbose = true;
        else if (a == "--arc-stats")
            o.arcStats = true;
        else if (a == "--target")
            o.target = next("--target");
        else if (a == "--cc")
            o.cc = next("--cc");
        else if (a.size() == 3 && a.compare(0, 2, "-O") == 0 && a[2] >= '0' && a[2] <= '3')
            o.optLevel = a[2] - '0', o.optGiven = true;
        else if (a.size() > 2 && a.compare(0, 2, "-l") == 0)
            o.libs.push_back(a.substr(2));
        else if (a.size() > 2 && a.compare(0, 2, "-L") == 0)
            o.libraryPaths.push_back(a.substr(2));
        else if (a.size() > 2 && a.compare(0, 2, "-I") == 0)
            o.includePaths.push_back(a.substr(2));
        else if (a.compare(0, 10, "--ffi-api=") == 0)
            o.apiPaths.push_back(a.substr(10));
        else if (a.size() > 2 && a.compare(0, 2, "-D") == 0)
            o.defines.push_back(a.substr(2));
        else if (!a.empty() && a[0] == '-')
        {
            std::cerr << "error: unknown option '" << a << "'\n";
            return false;
        }
        else if (isLinkerInput(a))
            o.libFiles.push_back(a);
        else
            o.inputs.push_back(a);
    }
    if (o.ffiPrepare)
        return o.inputs.size() == 2;
    switch (o.command)
    {
    case Command::Compile: return !o.inputs.empty();
    case Command::New: return o.inputs.size() == 1;
    default: return o.inputs.size() <= 1;
    }
}

void ensureParentDirectory(const std::string& file)
{
    llvm::StringRef parent = llvm::sys::path::parent_path(file);
    if (!parent.empty())
        llvm::sys::fs::create_directories(parent);
}

bool endsWith(const std::string& s, const std::string& suffix)
{
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool readFile(const std::string& path, std::string& out)
{
    std::ifstream in(path, std::ios::binary);
    if (!in)
        return false;
    std::stringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    // Skip a UTF-8 byte order mark.
    if (out.size() >= 3 && (unsigned char)out[0] == 0xEF && (unsigned char)out[1] == 0xBB && (unsigned char)out[2] == 0xBF)
        out.erase(0, 3);
    return true;
}

std::unique_ptr<CompilationUnit> parseSource(const std::string& name, const std::string& text, bool isPrelude, Diagnostics& diag)
{
    int fileId = diag.addFile(name);
    Lexer lexer(text, fileId, diag);
    Parser parser(lexer.tokenize(), diag);
    return parser.parseUnit(isPrelude);
}

void optimize(llvm::Module& module, llvm::TargetMachine* tm, int level)
{
    llvm::LoopAnalysisManager lam;
    llvm::FunctionAnalysisManager fam;
    llvm::CGSCCAnalysisManager cgam;
    llvm::ModuleAnalysisManager mam;
    llvm::PassBuilder pb(tm);
    pb.registerModuleAnalyses(mam);
    pb.registerCGSCCAnalyses(cgam);
    pb.registerFunctionAnalyses(fam);
    pb.registerLoopAnalyses(lam);
    pb.crossRegisterProxies(lam, fam, cgam, mam);

    llvm::OptimizationLevel ol = level == 0   ? llvm::OptimizationLevel::O0
                                 : level == 1 ? llvm::OptimizationLevel::O1
                                 : level == 2 ? llvm::OptimizationLevel::O2
                                              : llvm::OptimizationLevel::O3;
    llvm::ModulePassManager mpm =
        level == 0 ? pb.buildO0DefaultPipeline(ol) : pb.buildPerModuleDefaultPipeline(ol);
    mpm.run(module, mam);
}

// ---------------------------------------------------------------------------
// The standalone build: a toolchain (clang, lld, libclang, C libraries) appended, gzip-compressed, after this
// executable's own image by packaging/make-standalone.sh, with a small footer identifying it. This works because
// both the PE and the ELF loader only read what their own headers declare and simply ignore trailing bytes, the
// same trick self-extracting installers (NSIS, 7z SFX) and AppImage use. It is extracted once, into a per-user,
// per-version cache directory, the first time it is actually needed; every run after that just finds it there.
// ---------------------------------------------------------------------------

namespace
{
constexpr char kToolchainFooterMagic[8] = {'C', 'S', 'F', 'T', 'T', 'C', '0', '1'};
constexpr size_t kToolchainFooterSize = 16; // 8 bytes magic + 8 bytes little-endian archive size

struct EmbeddedToolchain
{
    uint64_t offset; // where the gzip-compressed tar begins in this executable's own file
    uint64_t size;
};

// Reads the footer of 'selfPath' (this program's own executable file) and, if it carries one, returns the
// embedded archive's location within it. False for an ordinary (non-standalone) build.
bool findEmbeddedToolchain(const std::string& selfPath, EmbeddedToolchain& out)
{
    uint64_t fileSize = 0;
    if (llvm::sys::fs::file_size(selfPath, fileSize) || fileSize < kToolchainFooterSize)
        return false;
    // Only the footer is needed here, not the whole (multi-hundred-megabyte) file.
    auto footer = llvm::MemoryBuffer::getFileSlice(selfPath, kToolchainFooterSize, fileSize - kToolchainFooterSize);
    if (!footer)
        return false;
    llvm::StringRef bytes = (*footer)->getBuffer();
    if (bytes.substr(0, 8) != llvm::StringRef(kToolchainFooterMagic, 8))
        return false;
    uint64_t size = 0;
    memcpy(&size, bytes.data() + 8, 8); // written little-endian by make-standalone.sh; this compiler targets LE hosts
    if (size + kToolchainFooterSize > fileSize)
        return false; // corrupt or foreign trailer - ignore rather than misbehave
    out.size = size;
    out.offset = fileSize - kToolchainFooterSize - size;
    return true;
}

// A per-user, per-version cache directory to extract the embedded toolchain into (so an upgrade of cshiftc does
// not reuse a stale one). Not cleaned up automatically; that is a reasonable manual step (it is just a cache).
std::string toolchainCacheDir(bool isWindows)
{
    std::string base;
    if (isWindows)
    {
        if (const char* dir = std::getenv("LOCALAPPDATA"))
            base = dir;
    }
    else
    {
        if (const char* dir = std::getenv("XDG_CACHE_HOME"))
            base = dir;
        else if (const char* home = std::getenv("HOME"))
            base = std::string(home) + "/.cache";
    }
    if (base.empty())
        return "";
    llvm::SmallString<256> dir(base);
    llvm::sys::path::append(dir, "cshift", std::string("toolchain-") + CSHIFT_VERSION);
    return std::string(dir.str());
}

// Extracts the embedded archive directly into 'cacheDir' (the archive's own top-level entry is 'toolchain/', so
// this produces 'cacheDir/toolchain/...'), using the system 'tar' (part of Windows since 10 1803, and of every
// Linux/macOS install) - far simpler and more robust than hand-rolling a gzip/tar reader for a one-time,
// best-effort setup step. Two processes extracting into the same cache directory at the same first time (rather
// than one finding the other's already-complete extraction, the common case) can in principle race; 'tar x'
// overwrites rather than erroring on files that already exist, so a second attempt after a partial/interrupted
// one simply completes it, which is enough robustness for what is ultimately a cache.
bool extractEmbeddedToolchain(const std::string& selfPath, const EmbeddedToolchain& embedded, const std::string& cacheDir)
{
    auto tar = llvm::sys::findProgramByName("tar");
    if (!tar)
        return false;
    auto archive = llvm::MemoryBuffer::getFileSlice(selfPath, embedded.size, embedded.offset);
    if (!archive)
        return false;
    if (llvm::sys::fs::create_directories(cacheDir))
        return false;

    llvm::SmallString<256> tempFile;
    if (llvm::sys::fs::createTemporaryFile("cshift-toolchain", "tar.gz", tempFile))
        return false;
    {
        std::error_code ec;
        llvm::raw_fd_ostream os(tempFile, ec, llvm::sys::fs::OF_None);
        if (ec)
        {
            llvm::sys::fs::remove(tempFile);
            return false;
        }
        os << (*archive)->getBuffer();
    }

    std::vector<llvm::StringRef> args = {*tar, "xzf", tempFile, "-C", cacheDir};
    int rc = llvm::sys::ExecuteAndWait(*tar, args);
    llvm::sys::fs::remove(tempFile);
    return rc == 0;
}
} // namespace

// Finds the C compiler that is used as linker driver, to compile generated C code and to locate libclang.
// The release archives contain a toolchain (clang, lld, libclang, C libraries) in the folder 'toolchain' next to
// cshiftc; it is used before anything in PATH so that the versions match. A standalone build has no such folder
// but carries the same toolchain embedded in itself (see above) and extracts it into a cache directory on first
// use.
std::string bundledClang(const char* argv0, bool isWindows)
{
    std::string self = llvm::sys::fs::getMainExecutable(argv0, reinterpret_cast<void*>(&bundledClang));
    if (self.empty())
        return "";

    llvm::SmallString<256> candidate(llvm::sys::path::parent_path(self));
    llvm::sys::path::append(candidate, "toolchain", "bin", isWindows ? "clang.exe" : "clang");
    if (llvm::sys::fs::can_execute(candidate))
        return std::string(candidate.str());

    EmbeddedToolchain embedded;
    if (!findEmbeddedToolchain(self, embedded))
        return "";
    std::string cacheDir = toolchainCacheDir(isWindows);
    if (cacheDir.empty())
        return "";
    llvm::SmallString<256> cached(cacheDir);
    llvm::sys::path::append(cached, "toolchain", "bin", isWindows ? "clang.exe" : "clang");
    if (!llvm::sys::fs::can_execute(cached) && !extractEmbeddedToolchain(self, embedded, cacheDir))
        return "";
    return llvm::sys::fs::can_execute(cached) ? std::string(cached.str()) : std::string();
}

std::string locateClang(const std::string& cc, bool isWindows, const std::string& bundled)
{
    if (cc == "clang" && !bundled.empty())
        return bundled;
    auto program = llvm::sys::findProgramByName(cc);
    for (const char* fallback : {"cc", "gcc"})
    {
        if (program || cc != "clang")
            break;
        program = llvm::sys::findProgramByName(fallback);
    }
    if (!program && isWindows && cc == "clang")
    {
        // Not in PATH: try the usual MSYS2 installation folders (the toolchain this compiler is built with).
        std::vector<std::string> folders;
        if (const char* root = std::getenv("MSYS2_ROOT"))
            folders.push_back(std::string(root) + "\\clang64\\bin");
        folders.push_back("C:\\msys64\\clang64\\bin");
        for (const auto& folder : folders)
        {
            llvm::StringRef searchPath(folder);
            program = llvm::sys::findProgramByName("clang", searchPath);
            if (program)
                break;
        }
    }
    return program ? *program : std::string();
}

std::string joinPath(const std::string& dir, const std::string& name)
{
    llvm::SmallString<256> p(dir.empty() ? "." : dir);
    llvm::sys::path::append(p, name);
    return std::string(p.str());
}

std::string stem(const std::string& path)
{
    size_t slash = path.find_last_of("/\\");
    std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    size_t dot = name.find_last_of('.');
    return dot == std::string::npos ? name : name.substr(0, dot);
}
} // namespace

int main(int argc, char** argv)
{
    for (int i = 1; i < argc; i += 1)
    {
        if (std::string(argv[i]) == "--version")
        {
            std::cout << "cshiftc " << CSHIFT_VERSION << "\n";
            return 0;
        }
    }

    Options opt;
    if (!parseArgs(argc, argv, opt))
    {
        printUsage();
        return 2;
    }

    // Development aid (see Dump.h): print tokens or the syntax tree of the given files and stop.
    if (opt.dumpTokens || opt.dumpAst)
    {
        Diagnostics diag;
        for (const auto& path : opt.inputs)
        {
            std::string text;
            if (!readFile(path, text))
            {
                std::cerr << "error: cannot read '" << path << "'\n";
                return 1;
            }
            int fileId = diag.addFile(path);
            Lexer lexer(text, fileId, diag);
            std::vector<Token> tokens = lexer.tokenize();
            if (opt.dumpTokens)
            {
                dumpTokens(tokens, std::cout);
            }
            else
            {
                Parser parser(tokens, diag);
                std::unique_ptr<CompilationUnit> unit = parser.parseUnit(false);
                dumpUnit(*unit, std::cout);
            }
        }
        return diag.hasErrors() ? 1 : 0;
    }

    // ffi-prepare: "cshiftc --ffi-prepare <name> <header> --ffi-base-dir <dir> --ffi-cache-dir <dir> [-I..] [-D..]"
    // makes sure the .ffi file of a C header is up to date and prints "ffi <path>" and "shim <path>" lines.
    if (opt.ffiPrepare)
    {
        llvm::InitializeAllTargetInfos();
        std::string tripleStr = opt.target.empty() ? llvm::sys::getDefaultTargetTriple() : opt.target;
        bool isWin = llvm::Triple(tripleStr).isOSWindows();
        FfiOptions ffiOptions;
        ffiOptions.target = tripleStr;
        ffiOptions.includePaths = opt.includePaths;
        ffiOptions.defines = opt.defines;
        ffiOptions.apiPaths = opt.apiPaths;
        ffiOptions.verbose = opt.verbose;
        FfiImportRequest request;
        request.name = opt.inputs[0];
        request.header = opt.inputs[1];
        request.baseDir = opt.ffiBaseDir.empty() ? "." : opt.ffiBaseDir;
        request.cacheDir = opt.ffiCacheDir.empty() ? joinPath(request.baseDir, "obj/ffi") : opt.ffiCacheDir;
        bool isFfiFile = request.header.size() > 4 && request.header.compare(request.header.size() - 4, 4, ".ffi") == 0;
        ffiOptions.clang = isFfiFile ? "" : locateClang(opt.cc, isWin, bundledClang(argv[0], isWin));
        FfiResult result;
        std::string error;
        if (!prepareFfi(request, ffiOptions, result, error))
        {
            std::cerr << "error: cannot import \"" << request.header << "\": " << error << "\n";
            return 1;
        }
        std::cout << "ffi " << result.ffiPath << "\n";
        for (const auto& s : result.shimSources)
            std::cout << "shim " << s << "\n";
        return 0;
    }

    // ---- Project commands ----
    Project project;
    bool fromProject = false;
    if (opt.command == Command::New)
    {
        std::string error;
        if (!createProject(opt.inputs[0], error))
        {
            std::cerr << "error: " << error << "\n";
            return 1;
        }
        std::cout << "Created project '" << opt.inputs[0] << "'\n"
                  << "  cd " << opt.inputs[0] << "\n"
                  << "  cshiftc run\n";
        return 0;
    }
    if (opt.command == Command::Build || opt.command == Command::Run)
    {
        std::string error;
        if (!loadProject(opt.inputs.empty() ? "" : opt.inputs[0], project, error))
        {
            std::cerr << "error: " << error << "\n";
            return 1;
        }
        fromProject = true;
        opt.inputs = project.sources;
        if (opt.output.empty())
            opt.output = project.output;
        if (!opt.optGiven && project.hasOptimize)
            opt.optLevel = project.optimize;
        if (opt.target.empty())
            opt.target = project.target;
        opt.libs.insert(opt.libs.begin(), project.links.begin(), project.links.end());
        opt.libFiles.insert(opt.libFiles.begin(), project.linkFiles.begin(), project.linkFiles.end());
        opt.libraryPaths.insert(opt.libraryPaths.begin(), project.libraryPaths.begin(), project.libraryPaths.end());
        opt.includePaths.insert(opt.includePaths.begin(), project.includePaths.begin(), project.includePaths.end());
        opt.defines.insert(opt.defines.begin(), project.defines.begin(), project.defines.end());
        opt.apiPaths.insert(opt.apiPaths.begin(), project.apiPaths.begin(), project.apiPaths.end());
        if (project.type == "object")
            opt.objectOnly = true;
        if (opt.command == Command::Run)
            opt.run = true;
    }

    // ---- Parse ----
    Diagnostics diag;
    CodeGen* cgPtr = nullptr;
    std::vector<std::unique_ptr<CompilationUnit>> units;
    for (unsigned i = 0; i < kStdlibFileCount; i += 1)
    {
        const StdlibFile& lib = kStdlibFiles[i];
        std::string text(reinterpret_cast<const char*>(lib.data), lib.size);
        units.push_back(parseSource(std::string("<stdlib>/") + lib.name, text, true, diag));
    }
    for (const auto& path : opt.inputs)
    {
        std::string text;
        if (!readFile(path, text))
        {
            std::cerr << "error: cannot read '" << path << "'\n";
            return 1;
        }
        units.push_back(parseSource(path, text, false, diag));
    }
    if (diag.hasErrors())
        return 1;

    // ---- Target ----
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmPrinters();
    llvm::InitializeAllAsmParsers();

    std::string tripleStr = opt.target.empty() ? llvm::sys::getDefaultTargetTriple() : opt.target;
    llvm::Triple triple(tripleStr);
    std::string targetError;
    const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple, targetError);
    if (!target)
    {
        std::cerr << "error: " << targetError << "\n";
        return 1;
    }
    llvm::TargetOptions targetOptions;
    std::unique_ptr<llvm::TargetMachine> tm(
        target->createTargetMachine(triple, "generic", "", targetOptions, llvm::Reloc::PIC_));
    if (!tm)
    {
        std::cerr << "error: cannot create a target machine for " << tripleStr << "\n";
        return 1;
    }

    bool isWindows = triple.isOSWindows();
    std::string clangPath; // located when it is needed
    auto clang = [&]() -> const std::string& {
        if (clangPath.empty())
            clangPath = locateClang(opt.cc, isWindows, bundledClang(argv[0], isWindows));
        return clangPath;
    };

    // ---- FFI: C headers imported with "using Name from "header.h";" ----
    struct ShimJob
    {
        std::string source;
        std::string baseDir;
    };
    std::vector<ShimJob> shims;
    {
        struct Import
        {
            ImportDecl decl;
        };
        std::vector<ImportDecl> imports;
        for (const auto& u : units)
            for (const auto& i : u->imports)
                imports.push_back(i);

        FfiOptions ffiOptions;
        ffiOptions.target = tripleStr;
        ffiOptions.includePaths = opt.includePaths;
        ffiOptions.defines = opt.defines;
        ffiOptions.apiPaths = opt.apiPaths;
        ffiOptions.verbose = opt.verbose;

        std::map<std::string, std::string> importedHeaders; // namespace -> header
        for (const ImportDecl& imp : imports)
        {
            auto seen = importedHeaders.find(imp.name);
            if (seen != importedHeaders.end())
            {
                if (seen->second != imp.header)
                    diag.error(imp.loc, "namespace '" + imp.name + "' is already imported from \"" + seen->second + "\"");
                continue;
            }
            importedHeaders[imp.name] = imp.header;

            std::string sourcePath = imp.loc.file < (int)diag.files.size() ? diag.files[imp.loc.file] : "";
            llvm::StringRef parent = llvm::sys::path::parent_path(sourcePath);
            std::string baseDir = parent.empty() ? "." : std::string(parent);

            FfiImportRequest request;
            request.name = imp.name;
            request.header = imp.header;
            request.baseDir = baseDir;
            request.cacheDir = joinPath(fromProject && !project.dir.empty() ? project.dir : baseDir, "obj/ffi");
            request.loc = imp.loc;
            ffiOptions.clang = imp.header.size() > 4 && imp.header.compare(imp.header.size() - 4, 4, ".ffi") == 0 ? "" : clang();

            FfiResult result;
            std::string error;
            if (!prepareFfi(request, ffiOptions, result, error))
            {
                diag.error(imp.loc, "cannot import \"" + imp.header + "\": " + error);
                continue;
            }
            auto unit = loadFfiUnit(result.ffiPath, imp.name, diag, error);
            if (!unit)
            {
                diag.error(imp.loc, error);
                continue;
            }
            units.push_back(std::move(unit));
            for (const auto& s : result.shimSources)
                shims.push_back({s, baseDir});
        }
        if (diag.hasErrors())
            return 1;
    }

    // ---- Compile ----
    CodeGen cg(diag, fromProject ? project.name : stem(opt.inputs[0]));
    cgPtr = &cg;
    cg.setTargetTriple(tripleStr);
    cg.setArcStats(opt.arcStats);
    cg.setDataLayout(tm->createDataLayout());
    for (auto& u : units)
        cg.addUnit(std::move(u));
    if (!cg.compile())
    {
        std::cerr << diag.errors << " error(s)\n";
        return 1;
    }

    if (opt.optLevel > 0 || opt.emitLlvm)
        optimize(cg.module(), tm.get(), opt.optLevel);

    // ---- Output ----
    std::string baseName = opt.output.empty() ? stem(opt.inputs[0]) : opt.output;

    if (opt.emitLlvm)
    {
        std::string path = opt.output.empty() ? baseName + ".ll" : (fromProject ? opt.output + ".ll" : opt.output);
        ensureParentDirectory(path);
        std::error_code ec;
        llvm::raw_fd_ostream out(path, ec, llvm::sys::fs::OF_Text);
        if (ec)
        {
            std::cerr << "error: cannot write '" << path << "': " << ec.message() << "\n";
            return 1;
        }
        cg.module().print(out, nullptr);
        return 0;
    }

    std::string objPath = opt.objectOnly && !opt.output.empty() ? opt.output : baseName + (isWindows ? ".obj" : ".o");
    if (opt.output.empty() && !opt.objectOnly)
        objPath = baseName + (isWindows ? ".obj" : ".o");
    if (fromProject && opt.objectOnly)
        objPath = baseName + (isWindows ? ".obj" : ".o"); // a project's output has no extension yet
    ensureParentDirectory(objPath);
    {
        std::error_code ec;
        llvm::raw_fd_ostream dest(objPath, ec, llvm::sys::fs::OF_None);
        if (ec)
        {
            std::cerr << "error: cannot write '" << objPath << "': " << ec.message() << "\n";
            return 1;
        }
        llvm::legacy::PassManager pm;
        if (tm->addPassesToEmitFile(pm, dest, nullptr, llvm::CodeGenFileType::ObjectFile))
        {
            std::cerr << "error: the target machine cannot emit object files\n";
            return 1;
        }
        pm.run(cg.module());
        dest.flush();
    }
    // Shims (generated C code for functions that take or return structs by value) are compiled with clang, which
    // knows the platform ABI.
    std::vector<std::string> shimObjects;
    for (const ShimJob& job : shims)
    {
        if (clang().empty())
        {
            std::cerr << "error: cannot find clang to compile the FFI shim '" << job.source << "'\n"
                      << "       Put clang in PATH (e.g. C:\\msys64\\clang64\\bin) or pass --cc <path>.\n";
            return 1;
        }
        std::string object = std::string(llvm::sys::path::parent_path(job.source)) + "/" +
                             std::string(llvm::sys::path::stem(job.source)) + (isWindows ? ".obj" : ".o");
        std::vector<std::string> args = {opt.cc, "-c", "-target", tripleStr, "-O1", "-I" + job.baseDir};
        for (const auto& p : opt.includePaths)
            args.push_back("-I" + p);
        for (const auto& d : opt.defines)
            args.push_back("-D" + d);
        args.push_back(job.source);
        args.push_back("-o");
        args.push_back(object);
        std::vector<llvm::StringRef> argRefs(args.begin(), args.end());
        if (opt.verbose)
        {
            for (const auto& a : args)
                std::cerr << a << " ";
            std::cerr << "\n";
        }
        if (llvm::sys::ExecuteAndWait(clang(), argRefs) != 0)
        {
            std::cerr << "error: compiling the FFI shim '" << job.source << "' failed\n";
            return 1;
        }
        shimObjects.push_back(object);
    }

    if (opt.objectOnly)
    {
        if (fromProject)
            std::cout << "Built " << objPath << "\n";
        for (const auto& o : shimObjects)
            std::cout << "Also link " << o << " (FFI wrappers)\n";
        return 0;
    }

    // ---- Link ----
    std::string exePath = opt.output.empty() ? baseName + (isWindows ? ".exe" : "") : opt.output;
    if (fromProject && isWindows && !endsWith(exePath, ".exe"))
        exePath += ".exe";
    ensureParentDirectory(exePath);
    if (clang().empty())
    {
        std::cerr << "error: cannot find the linker driver '" << opt.cc << "'\n"
                  << "       Put clang in PATH (e.g. C:\\msys64\\clang64\\bin) or pass --cc <path>.\n";
        return 1;
    }
    std::vector<std::string> linkArgs = {opt.cc, objPath};
    for (const auto& o : shimObjects)
        linkArgs.push_back(o);
    linkArgs.push_back("-o");
    linkArgs.push_back(exePath);
    for (const auto& f : opt.libFiles)
        linkArgs.push_back(f);
    for (const auto& p : opt.libraryPaths)
        linkArgs.push_back("-L" + p);
    for (const auto& l : cg.linkLibraries())
        linkArgs.push_back("-l" + l);
    if (!isWindows)
        linkArgs.push_back("-lm"); // the math functions of the standard library
    // 'thread' functions and Thread/Thread<T> (stdlib/thread.csh). On Windows, a plain '-lpthread' picks the
    // *import* library (libpthread.dll.a/libwinpthread.dll.a) over the static one when both exist next to each
    // other, which makes every compiled program depend on libwinpthread-1.dll at run time - a DLL that is not
    // part of the bundled toolchain (it is only ever a build-time dependency of clang itself, never shipped for
    // programs clang compiles), so a program built this way fails to start anywhere outside an MSYS2 shell.
    // '-Wl,-Bstatic ... -Wl,-Bdynamic' forces the static archive instead, so the compiled program needs nothing
    // beyond what Windows itself and the bundled toolchain already provide.
    if (isWindows)
    {
        linkArgs.push_back("-Wl,-Bstatic");
        linkArgs.push_back("-lpthread");
        linkArgs.push_back("-Wl,-Bdynamic");
    }
    else
    {
        linkArgs.push_back("-lpthread");
    }
    for (const auto& l : opt.libs)
        linkArgs.push_back("-l" + l);
    std::vector<llvm::StringRef> refs(linkArgs.begin(), linkArgs.end());
    if (opt.verbose)
    {
        for (const auto& a : linkArgs)
            std::cerr << a << " ";
        std::cerr << "\n";
    }
    int rc = llvm::sys::ExecuteAndWait(clang(), refs);
    llvm::sys::fs::remove(objPath);
    for (const auto& o : shimObjects)
        llvm::sys::fs::remove(o);
    if (rc != 0)
    {
        std::cerr << "error: linking failed\n";
        return 1;
    }

    if (fromProject && !opt.run)
        std::cout << "Built " << exePath << "\n";

    if (opt.run)
    {
        std::string runPath = exePath;
        if (runPath.find('/') == std::string::npos && runPath.find('\\') == std::string::npos)
            runPath = "./" + runPath;
        std::vector<llvm::StringRef> runArgs = {runPath};
        return llvm::sys::ExecuteAndWait(runPath, runArgs);
    }
    (void)cgPtr;
    return 0;
}
