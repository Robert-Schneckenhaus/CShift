#include "Project.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/raw_ostream.h>

namespace fs = llvm::sys::fs;
namespace path = llvm::sys::path;

namespace
{
// Paths inside the current directory are shown relative to it, in error messages and output.
std::string displayPath(const std::string& absolute)
{
    llvm::SmallString<256> cwd;
    if (!fs::current_path(cwd))
    {
        std::string prefix = std::string(cwd.str()) + std::string(1, path::get_separator()[0]);
        if (absolute.compare(0, prefix.size(), prefix) == 0)
            return absolute.substr(prefix.size());
    }
    return absolute;
}

std::string join(const std::string& dir, const std::string& name)
{
    llvm::SmallString<256> p(dir);
    path::append(p, name);
    return std::string(p.str());
}

bool validName(const std::string& name)
{
    if (name.empty())
        return false;
    for (char c : name)
        if (!(std::isalnum((unsigned char)c) || c == '_' || c == '-' || c == '.'))
            return false;
    return true;
}

bool readText(const std::string& file, std::string& out)
{
    std::ifstream in(file, std::ios::binary);
    if (!in)
        return false;
    std::stringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    if (out.size() >= 3 && (unsigned char)out[0] == 0xEF && (unsigned char)out[1] == 0xBB && (unsigned char)out[2] == 0xBF)
        out.erase(0, 3);
    return true;
}

bool findProjectFile(const std::string& location, std::string& file, std::string& error)
{
    if (!location.empty())
    {
        file = fs::is_directory(location) ? join(location, "cshift.json") : location;
        if (!fs::exists(file))
        {
            error = "cannot find project file '" + file + "'";
            return false;
        }
        return true;
    }

    // Search the current directory and its parents.
    llvm::SmallString<256> dir;
    if (fs::current_path(dir))
    {
        error = "cannot determine the current directory";
        return false;
    }
    std::string start = std::string(dir.str());
    while (true)
    {
        std::string candidate = join(std::string(dir.str()), "cshift.json");
        if (fs::exists(candidate))
        {
            file = displayPath(candidate);
            return true;
        }
        // parent_path() returns a view into 'dir', so copy it before assigning it back.
        std::string parent = std::string(path::parent_path(dir));
        if (parent.empty() || parent == dir.str())
            break;
        dir = parent;
    }
    error = "no cshift.json found in '" + start + "' or any parent directory";
    return false;
}

// A source entry is a .csh file or a directory that is searched recursively for .csh files.
bool addSources(const std::string& projectDir, const std::string& entry, std::vector<std::string>& out, std::string& error)
{
    std::string full = projectDir.empty() ? entry : join(projectDir, entry);
    if (fs::is_regular_file(full))
    {
        out.push_back(full);
        return true;
    }
    if (!fs::is_directory(full))
    {
        error = "source '" + entry + "' does not exist (looked for '" + full + "')";
        return false;
    }

    std::error_code ec;
    for (fs::recursive_directory_iterator it(full, ec), end; !ec && it != end; it.increment(ec))
    {
        if (path::extension(it->path()) == ".csh" && fs::is_regular_file(it->path()))
            out.push_back(it->path());
    }
    if (ec)
    {
        error = "cannot read directory '" + full + "': " + ec.message();
        return false;
    }
    return true;
}
} // namespace

bool loadProject(const std::string& location, Project& project, std::string& error)
{
    std::string file;
    if (!findProjectFile(location, file, error))
        return false;

    std::string text;
    if (!readText(file, text))
    {
        error = "cannot read '" + file + "'";
        return false;
    }
    auto parsed = llvm::json::parse(text);
    if (!parsed)
    {
        error = file + ": invalid JSON: " + llvm::toString(parsed.takeError());
        return false;
    }
    const llvm::json::Object* obj = parsed->getAsObject();
    if (!obj)
    {
        error = file + ": the project file must contain a JSON object";
        return false;
    }

    project = Project{};
    project.file = file;
    llvm::StringRef dirRef = path::parent_path(file);
    project.dir = dirRef.empty() ? "" : std::string(dirRef);

    auto fail = [&](const std::string& message) {
        error = file + ": " + message;
        return false;
    };

    // Reads a string property. Returns false (with an error) if it exists but is not a string.
    auto readString = [&](const char* key, std::string& value, bool& ok) {
        const llvm::json::Value* v = obj->get(key);
        if (!v)
            return false;
        auto s = v->getAsString();
        if (!s)
        {
            ok = false;
            error = file + ": '" + key + "' must be a string";
            return false;
        }
        value = std::string(*s);
        return true;
    };
    auto readStringList = [&](const char* key, std::vector<std::string>& values, bool& present, bool& ok) {
        const llvm::json::Value* v = obj->get(key);
        if (!v)
            return;
        present = true;
        const llvm::json::Array* array = v->getAsArray();
        if (!array)
        {
            ok = false;
            error = file + ": '" + key + "' must be an array of strings";
            return;
        }
        for (const llvm::json::Value& item : *array)
        {
            auto s = item.getAsString();
            if (!s)
            {
                ok = false;
                error = file + ": '" + key + "' must be an array of strings";
                return;
            }
            values.push_back(std::string(*s));
        }
    };

    for (const auto& entry : *obj)
    {
        std::string key = llvm::StringRef(entry.first).str();
        static const char* known[] = {"$schema", "name", "version", "type", "sources", "output", "optimize", "links", "target",
                                         "includePaths", "libraryPaths", "defines"};
        if (std::find(std::begin(known), std::end(known), key) == std::end(known))
            std::cerr << file << ": warning: unknown key '" << key << "' is ignored\n";
    }

    bool ok = true;
    readString("name", project.name, ok);
    if (!ok)
        return false;
    if (!validName(project.name))
        return fail("'name' is required and may only contain letters, digits, '_', '-' and '.'");
    readString("version", project.version, ok);
    readString("type", project.type, ok);
    std::string outputKey;
    if (readString("output", outputKey, ok))
        project.output = outputKey;
    readString("target", project.target, ok);
    if (!ok)
        return false;

    if (project.type != "executable" && project.type != "object")
        return fail("'type' must be \"executable\" or \"object\", not \"" + project.type + "\"");

    if (const llvm::json::Value* v = obj->get("optimize"))
    {
        auto level = v->getAsInteger();
        if (!level || *level < 0 || *level > 3)
            return fail("'optimize' must be an integer from 0 to 3");
        project.optimize = (int)*level;
        project.hasOptimize = true;
    }

    bool linksPresent = false;
    std::vector<std::string> linkEntries;
    readStringList("links", linkEntries, linksPresent, ok);
    bool pathsPresent = false;
    std::vector<std::string> includeEntries, libraryEntries;
    readStringList("includePaths", includeEntries, pathsPresent, ok);
    readStringList("libraryPaths", libraryEntries, pathsPresent, ok);
    readStringList("defines", project.defines, pathsPresent, ok);
    std::vector<std::string> sourceEntries;
    bool sourcesPresent = false;
    readStringList("sources", sourceEntries, sourcesPresent, ok);
    if (!ok)
        return false;
    if (!sourcesPresent)
        sourceEntries.push_back("src");

    for (const auto& entry : sourceEntries)
    {
        std::string problem;
        if (!addSources(project.dir, entry, project.sources, problem))
            return fail(problem);
    }
    std::sort(project.sources.begin(), project.sources.end());
    project.sources.erase(std::unique(project.sources.begin(), project.sources.end()), project.sources.end());
    if (project.sources.empty())
        return fail("no .csh source files found");

    // Paths are relative to the project file. "links" entries that name a file (or contain a path) are passed to the
    // linker as files, everything else is a library name (-l<name>).
    auto inProject = [&](const std::string& p) {
        return path::is_absolute(p) || project.dir.empty() ? p : join(project.dir, p);
    };
    for (const auto& p : includeEntries)
        project.includePaths.push_back(inProject(p));
    for (const auto& p : libraryEntries)
        project.libraryPaths.push_back(inProject(p));
    for (const auto& l : linkEntries)
    {
        bool isFile = l.find('/') != std::string::npos || l.find('\\') != std::string::npos;
        for (const char* ext : {".a", ".o", ".obj", ".lib", ".so", ".dylib", ".dll"})
        {
            size_t n = std::strlen(ext);
            if (l.size() > n && l.compare(l.size() - n, n, ext) == 0)
                isFile = true;
        }
        if (isFile)
            project.linkFiles.push_back(inProject(l));
        else
            project.links.push_back(l);
    }

    if (project.output.empty())
        project.output = "bin/" + project.name;
    project.output = project.dir.empty() ? project.output : join(project.dir, project.output);
    return true;
}

bool createProject(const std::string& projectPath, std::string& error)
{
    if (fs::exists(projectPath))
    {
        error = "'" + projectPath + "' already exists";
        return false;
    }
    std::string name = std::string(path::filename(llvm::StringRef(projectPath).rtrim("/\\")));
    if (!validName(name))
    {
        error = "invalid project name '" + name + "' (letters, digits, '_', '-' and '.' are allowed)";
        return false;
    }

    std::string src = join(projectPath, "src");
    if (auto ec = fs::create_directories(src))
    {
        error = "cannot create '" + src + "': " + ec.message();
        return false;
    }

    auto write = [&](const std::string& file, const std::string& content) {
        std::error_code ec;
        llvm::raw_fd_ostream out(file, ec, fs::OF_Text);
        if (ec)
        {
            error = "cannot write '" + file + "': " + ec.message();
            return false;
        }
        out << content;
        return true;
    };

    bool ok = write(join(projectPath, "cshift.json"),
                    "{\n"
                    "\t\"name\": \"" + name + "\",\n"
                    "\t\"version\": \"0.1.0\",\n"
                    "\t\"type\": \"executable\",\n"
                    "\t\"sources\": [\"src\"],\n"
                    "\t\"output\": \"bin/" + name + "\",\n"
                    "\t\"optimize\": 2,\n"
                    "\t\"links\": []\n"
                    "}\n") &&
              write(join(src, "main.csh"),
                    "int Main()\n"
                    "{\n"
                    "    Console.WriteLine(\"Hello, World!\");\n"
                    "    return 0;\n"
                    "}\n") &&
              write(join(projectPath, ".gitignore"), "bin/\nobj/\n");
    return ok;
}
