// cshiftc - the CShift compiler driver.

#include <fstream>
#include <iostream>
#include <sstream>

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Support/CodeGen.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/TargetParser/Triple.h>

#include "CodeGen.h"
#include "Lexer.h"
#include "Parser.h"
#include "StdlibData.h"

namespace
{
struct Options
{
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
                 "usage: cshiftc [options] file.csh [file2.csh ...]\n"
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
    for (int i = 1; i < argc; i += 1)
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
            o.optLevel = a[2] - '0';
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
    return !o.inputs.empty();
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
    CodeGen cg(diag, stem(opt.inputs[0]));
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
        std::string path = opt.output.empty() ? baseName + ".ll" : opt.output;
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
        return 0;

    // ---- Link ----
    std::string exePath = opt.output.empty() ? baseName + (isWindows ? ".exe" : "") : opt.output;
    auto program = llvm::sys::findProgramByName(opt.cc);
    for (const char* fallback : {"cc", "gcc"})
    {
        if (program || opt.cc != "clang")
            break;
        program = llvm::sys::findProgramByName(fallback);
    }
    if (!program)
    {
        std::cerr << "error: cannot find the linker driver '" << opt.cc << "' (use --cc <path>)\n";
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
