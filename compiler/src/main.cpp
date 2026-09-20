// cshiftc - the CShift compiler driver.

#include <fstream>
#include <iostream>
#include <sstream>

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Support/CodeGen.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/TargetParser/Triple.h>

#include "CodeGen.h"
#include "Lexer.h"
#include "Parser.h"
#include "Project.h"
#include "StdlibData.h"

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
    std::vector<std::string> libs;
    int optLevel = 2;
    bool objectOnly = false;
    bool emitLlvm = false;
    bool run = false;
    bool verbose = false;
    bool arcStats = false;
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
                 "  --run            run the program after building\n"
                 "  --arc-stats      debug: print heap allocations/frees when the program exits\n"
                 "  -v               verbose output\n"
                 "  -h, --help       show this help\n";
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
        if (a == "-h" || a == "--help")
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
        else if (!a.empty() && a[0] == '-')
        {
            std::cerr << "error: unknown option '" << a << "'\n";
            return false;
        }
        else
            o.inputs.push_back(a);
    }
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
    Options opt;
    if (!parseArgs(argc, argv, opt))
    {
        printUsage();
        return 2;
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

    bool isWindows = triple.isOSWindows();
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
    if (opt.objectOnly)
    {
        if (fromProject)
            std::cout << "Built " << objPath << "\n";
        return 0;
    }

    // ---- Link ----
    std::string exePath = opt.output.empty() ? baseName + (isWindows ? ".exe" : "") : opt.output;
    if (fromProject && isWindows && !endsWith(exePath, ".exe"))
        exePath += ".exe";
    ensureParentDirectory(exePath);
    auto program = llvm::sys::findProgramByName(opt.cc);
    for (const char* fallback : {"cc", "gcc"})
    {
        if (program || opt.cc != "clang")
            break;
        program = llvm::sys::findProgramByName(fallback);
    }
    if (!program && isWindows && opt.cc == "clang")
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
    if (!program)
    {
        std::cerr << "error: cannot find the linker driver '" << opt.cc << "'\n"
                  << "       Put clang in PATH (e.g. C:\\msys64\\clang64\\bin) or pass --cc <path>.\n";
        return 1;
    }
    std::vector<std::string> linkArgs = {opt.cc, objPath, "-o", exePath};
    for (const auto& l : cg.linkLibraries())
        linkArgs.push_back("-l" + l);
    if (!isWindows)
        linkArgs.push_back("-lm"); // the math functions of the standard library
    for (const auto& l : opt.libs)
        linkArgs.push_back("-l" + l);
    std::vector<llvm::StringRef> refs(linkArgs.begin(), linkArgs.end());
    if (opt.verbose)
    {
        for (const auto& a : linkArgs)
            std::cerr << a << " ";
        std::cerr << "\n";
    }
    int rc = llvm::sys::ExecuteAndWait(*program, refs);
    llvm::sys::fs::remove(objPath);
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
