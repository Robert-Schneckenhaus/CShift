// Reading .ffi files: freshness check and creation of the declarations.

#include "Ffi.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/JSON.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/xxhash.h>

#include "Lexer.h"
#include "Parser.h"

namespace fs = llvm::sys::fs;
namespace path = llvm::sys::path;

namespace
{
std::string join(const std::string& dir, const std::string& name)
{
    llvm::SmallString<256> p(dir);
    path::append(p, name);
    return std::string(p.str());
}

bool endsWith(const std::string& s, const std::string& suffix)
{
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool readText(const std::string& file, std::string& out)
{
    std::ifstream in(file, std::ios::binary);
    if (!in)
        return false;
    std::stringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    return true;
}

std::string sanitize(const std::string& name)
{
    std::string s = name;
    for (char& c : s)
        if (!(std::isalnum((unsigned char)c) || c == '_' || c == '-'))
            c = '_';
    return s;
}

bool loadJson(const std::string& file, llvm::json::Value& out, std::string& error)
{
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
    out = std::move(*parsed);
    return true;
}

std::string str(const llvm::json::Object& o, const char* key, const std::string& fallback = "")
{
    if (auto s = o.getString(key))
        return std::string(*s);
    return fallback;
}

bool boolean(const llvm::json::Object& o, const char* key)
{
    auto b = o.getBoolean(key);
    return b && *b;
}

// Integer values are JSON numbers; values above INT64_MAX are stored as decimal strings.
bool readInteger(const llvm::json::Object& o, const char* key, bool& negative, uint64_t& magnitude)
{
    const llvm::json::Value* v = o.get(key);
    if (!v)
        return false;
    if (auto i = v->getAsInteger())
    {
        negative = *i < 0;
        magnitude = negative ? (uint64_t)(-(*i + 1)) + 1 : (uint64_t)*i;
        return true;
    }
    if (auto s = v->getAsString())
    {
        std::string text(*s);
        negative = !text.empty() && text[0] == '-';
        magnitude = std::strtoull(text.c_str() + (negative ? 1 : 0), nullptr, 10);
        return true;
    }
    return false;
}
} // namespace

std::string ffiHashFile(const std::string& file, bool& ok)
{
    std::string text;
    ok = readText(file, text);
    if (!ok)
        return "";
    uint64_t h = llvm::xxh3_64bits(llvm::ArrayRef<uint8_t>((const uint8_t*)text.data(), text.size()));
    char buf[17];
    std::snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)h);
    return buf;
}

std::vector<std::string> ffiFlags(const FfiOptions& options)
{
    std::vector<std::string> flags;
    for (const auto& p : options.includePaths)
        flags.push_back("-I" + p);
    for (const auto& d : options.defines)
        flags.push_back("-D" + d);
    for (const auto& p : options.apiPaths)
        flags.push_back("-cshift-api=" + p); // not a clang flag: recorded so that the cache notices changes
    return flags;
}

// ---------------------------------------------------------------------------
// Freshness of a cached .ffi file
// ---------------------------------------------------------------------------

static bool isFresh(const std::string& ffiPath, const FfiImportRequest& request, const FfiOptions& options, std::string& why)
{
    llvm::json::Value root = nullptr;
    std::string error;
    if (!loadJson(ffiPath, root, error))
    {
        why = "unreadable";
        return false;
    }
    const llvm::json::Object* o = root.getAsObject();
    if (!o)
    {
        why = "not a JSON object";
        return false;
    }
    auto format = o->getInteger("format");
    if (!format || *format != kFfiFormat)
    {
        why = "format changed";
        return false;
    }
    if (str(*o, "header") != request.header)
    {
        why = "different header";
        return false;
    }
    if (str(*o, "target") != options.target)
    {
        why = "different target";
        return false;
    }
    std::vector<std::string> flags = ffiFlags(options);
    const llvm::json::Array* recorded = o->getArray("flags");
    if (!recorded || recorded->size() != flags.size())
    {
        why = "different compiler flags";
        return false;
    }
    for (size_t i = 0; i < flags.size(); i += 1)
    {
        auto s = (*recorded)[i].getAsString();
        if (!s || *s != flags[i])
        {
            why = "different compiler flags";
            return false;
        }
    }
    const llvm::json::Array* deps = o->getArray("dependencies");
    if (!deps || deps->empty())
    {
        why = "no dependency information";
        return false;
    }
    for (const llvm::json::Value& d : *deps)
    {
        const llvm::json::Object* dep = d.getAsObject();
        if (!dep)
        {
            why = "invalid dependency list";
            return false;
        }
        bool ok = false;
        std::string hash = ffiHashFile(str(*dep, "path"), ok);
        if (!ok)
        {
            why = "'" + str(*dep, "path") + "' is missing";
            return false;
        }
        if (hash != str(*dep, "hash"))
        {
            why = "'" + str(*dep, "path") + "' changed";
            return false;
        }
    }
    return true;
}

static std::vector<std::string> shimsOf(const std::string& ffiPath)
{
    std::vector<std::string> out;
    llvm::json::Value root = nullptr;
    std::string error;
    if (!loadJson(ffiPath, root, error) || !root.getAsObject())
        return out;
    std::string shim = str(*root.getAsObject(), "shim");
    if (!shim.empty())
        out.push_back(join(std::string(path::parent_path(ffiPath)), shim));
    return out;
}

bool prepareFfi(const FfiImportRequest& request, const FfiOptions& options, FfiResult& result, std::string& error)
{
    result = FfiResult{};

    // A ready-made .ffi file is used as it is.
    if (endsWith(request.header, ".ffi"))
    {
        std::string file = path::is_absolute(request.header) ? request.header : join(request.baseDir, request.header);
        if (!fs::exists(file))
        {
            error = "cannot find the FFI file '" + request.header + "' (looked for '" + file + "')";
            return false;
        }
        result.ffiPath = file;
        result.shimSources = shimsOf(file);
        return true;
    }

    std::string ffiPath = join(request.cacheDir, sanitize(request.name) + ".ffi");
    std::string why = "not generated yet";
    if (fs::exists(ffiPath) && isFresh(ffiPath, request, options, why))
    {
        if (options.verbose)
            std::cerr << "ffi: '" << request.name << "' is up to date (" << ffiPath << ")\n";
        result.ffiPath = ffiPath;
        result.shimSources = shimsOf(ffiPath);
        return true;
    }

    if (options.verbose)
        std::cerr << "ffi: generating '" << ffiPath << "' from \"" << request.header << "\" (" << why << ")\n";
    if (auto ec = fs::create_directories(request.cacheDir))
    {
        error = "cannot create '" + request.cacheDir + "': " + ec.message();
        return false;
    }
    if (!generateFfi(request, options, ffiPath, error))
        return false;
    result.ffiPath = ffiPath;
    result.shimSources = shimsOf(ffiPath);
    result.regenerated = true;
    return true;
}

// ---------------------------------------------------------------------------
// Creating declarations from a .ffi file
// ---------------------------------------------------------------------------

namespace
{
struct Builder
{
    Builder(Diagnostics& diag, CompilationUnit& unit, const std::string& ffiPath) : diag(diag), unit(unit), ffiPath(ffiPath)
    {
        loc.file = unit.file.fileId;
    }

    TypeRefPtr type(const std::string& text, const std::string& where)
    {
        if (text.empty())
        {
            problem(where + ": missing type");
            return nullptr;
        }
        Diagnostics local;
        local.addFile(ffiPath);
        Lexer lexer(text, 0, local);
        Parser parser(lexer.tokenize(), local);
        try
        {
            TypeRefPtr t = parser.parseStandaloneType();
            if (!local.hasErrors())
                return t;
        }
        catch (const CompileError&)
        {
        }
        problem(where + ": invalid type '" + text + "'");
        return nullptr;
    }

    ExprPtr integer(bool negative, uint64_t magnitude)
    {
        auto lit = std::make_unique<IntLitExpr>(loc);
        lit->value = magnitude;
        if (!negative)
            return lit;
        auto neg = std::make_unique<UnaryExpr>(loc);
        neg->op = UnOp::Neg;
        neg->operand = std::move(lit);
        return neg;
    }

    void problem(const std::string& message)
    {
        diag.error(SourceLoc{}, ffiPath + ": " + message);
        failed = true;
    }

    Diagnostics& diag;
    CompilationUnit& unit;
    std::string ffiPath;
    SourceLoc loc;
    bool failed = false;
};
} // namespace

std::unique_ptr<CompilationUnit> loadFfiUnit(const std::string& ffiPath, const std::string& name, Diagnostics& diag,
                                             std::string& error)
{
    llvm::json::Value root = nullptr;
    if (!loadJson(ffiPath, root, error))
        return nullptr;
    const llvm::json::Object* o = root.getAsObject();
    if (!o)
    {
        error = ffiPath + ": the FFI file must contain a JSON object";
        return nullptr;
    }
    auto format = o->getInteger("format");
    if (!format || *format != kFfiFormat)
    {
        error = ffiPath + ": unsupported FFI format (expected " + std::to_string(kFfiFormat) + ")";
        return nullptr;
    }

    auto unit = std::make_unique<CompilationUnit>();
    unit->file.fileId = diag.addFile(ffiPath);
    unit->file.ns = name;
    unit->file.isPrelude = true; // library declarations are only compiled when they are used
    Builder b(diag, *unit, ffiPath);

    if (const llvm::json::Array* structs = o->getArray("structs"))
    {
        for (const llvm::json::Value& v : *structs)
        {
            const llvm::json::Object* so = v.getAsObject();
            if (!so)
                continue;
            auto s = std::make_unique<StructDecl>();
            s->file = &unit->file;
            s->loc = b.loc;
            s->name = str(*so, "name");
            s->explicitLayout = true;
            s->opaque = boolean(*so, "opaque");
            s->layoutSize = (uint64_t)so->getInteger("size").value_or(0);
            s->layoutAlign = (uint64_t)so->getInteger("align").value_or(1);
            if (const llvm::json::Array* fields = so->getArray("fields"))
            {
                for (const llvm::json::Value& fv : *fields)
                {
                    const llvm::json::Object* fo = fv.getAsObject();
                    if (!fo)
                        continue;
                    FieldDecl f;
                    f.loc = b.loc;
                    f.name = str(*fo, "name");
                    f.offset = fo->getInteger("offset").value_or(0);
                    f.type = b.type(str(*fo, "type"), "struct " + s->name + "." + f.name);
                    if (f.type)
                        s->fields.push_back(std::move(f));
                }
            }
            unit->structs.push_back(std::move(s));
        }
    }

    if (const llvm::json::Array* enums = o->getArray("enums"))
    {
        for (const llvm::json::Value& v : *enums)
        {
            const llvm::json::Object* eo = v.getAsObject();
            if (!eo)
                continue;
            auto e = std::make_unique<EnumDecl>();
            e->file = &unit->file;
            e->loc = b.loc;
            e->name = str(*eo, "name");
            e->base = b.type(str(*eo, "base"), "enum " + e->name);
            if (const llvm::json::Array* members = eo->getArray("members"))
            {
                for (const llvm::json::Value& mv : *members)
                {
                    const llvm::json::Object* mo = mv.getAsObject();
                    if (!mo)
                        continue;
                    EnumMember m;
                    m.loc = b.loc;
                    m.name = str(*mo, "name");
                    bool negative = false;
                    uint64_t magnitude = 0;
                    if (readInteger(*mo, "value", negative, magnitude))
                        m.value = b.integer(negative, magnitude);
                    e->members.push_back(std::move(m));
                }
            }
            if (e->base)
                unit->enums.push_back(std::move(e));
        }
    }

    if (const llvm::json::Array* consts = o->getArray("constants"))
    {
        for (const llvm::json::Value& v : *consts)
        {
            const llvm::json::Object* co = v.getAsObject();
            if (!co)
                continue;
            auto c = std::make_unique<ConstDecl>();
            c->file = &unit->file;
            c->loc = b.loc;
            c->name = str(*co, "name");
            c->type = b.type(str(*co, "type"), "constant " + c->name);
            const llvm::json::Value* value = co->get("value");
            std::string typeName = str(*co, "type");
            bool negative = false;
            uint64_t magnitude = 0;
            if (typeName == "string")
            {
                auto lit = std::make_unique<StringLitExpr>(b.loc);
                lit->value = str(*co, "value");
                c->init = std::move(lit);
            }
            else if (typeName == "float64" || typeName == "float32")
            {
                auto lit = std::make_unique<FloatLitExpr>(b.loc);
                lit->value = value ? value->getAsNumber().value_or(0.0) : 0.0;
                c->init = std::move(lit);
            }
            else if (readInteger(*co, "value", negative, magnitude))
            {
                c->init = b.integer(negative, magnitude);
            }
            if (c->type && c->init)
                unit->consts.push_back(std::move(c));
        }
    }

    if (const llvm::json::Array* functions = o->getArray("functions"))
    {
        for (const llvm::json::Value& v : *functions)
        {
            const llvm::json::Object* fo = v.getAsObject();
            if (!fo)
                continue;
            auto f = std::make_unique<FuncDecl>();
            f->file = &unit->file;
            f->loc = b.loc;
            f->name = str(*fo, "name");
            f->isExtern = true;
            f->isVariadic = boolean(*fo, "variadic");
            f->symbol = str(*fo, "symbol");
            f->retCString = boolean(*fo, "retCString");
            f->retOut = boolean(*fo, "retOut");
            f->ret = b.type(str(*fo, "returns", "void"), "function " + f->name);
            bool ok = f->ret != nullptr;
            if (const llvm::json::Array* params = fo->getArray("params"))
            {
                for (const llvm::json::Value& pv : *params)
                {
                    const llvm::json::Object* po = pv.getAsObject();
                    if (!po)
                        continue;
                    Param p;
                    p.loc = b.loc;
                    p.name = str(*po, "name");
                    std::string ref = str(*po, "ref", "none");
                    p.refKind = ref == "ref" ? RefKind::Ref : ref == "constref" ? RefKind::ConstRef : RefKind::None;
                    p.nullable = boolean(*po, "nullable");
                    p.cstring = boolean(*po, "cstring");
                    p.type = b.type(str(*po, "type"), "function " + f->name + ", parameter " + p.name);
                    if (!p.type)
                        ok = false;
                    f->params.push_back(std::move(p));
                }
            }
            if (ok)
                unit->funcs.push_back(std::move(f));
        }
    }

    if (b.failed)
    {
        error = ffiPath + ": the FFI file contains invalid entries (delete it to regenerate it)";
        return nullptr;
    }
    return unit;
}
