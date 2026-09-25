/* Native helpers of cshc (imported through host.ffi, compiled and linked like an FFI shim).
 *
 * - libclang, loaded at run time (like the C++ compiler does): the header import (using X from "header.h") parses C
 *   headers with it. libclang passes its cursors, types and strings by value; these wrappers take and return them
 *   through pointers, so CShift only sees plain functions. Strings are copied (the copy lives until the next call).
 *   Children, inclusions and tokens are collected into buffers that CShift reads by index.
 * - the path of the running executable and copying a part of a file (the toolchain next to or inside cshc).
 *
 * The libclang types are declared here instead of including clang-c/Index.h: their layout is part of libclang's
 * stable C ABI, and cshc must build without the libclang headers. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#include <unistd.h>
#endif
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

typedef struct { int kind; int xdata; const void *data[3]; } CXCursor;
typedef struct { int kind; int pad; void *data[2]; } CXType;
typedef struct { const void *data; unsigned private_flags; } CXString;
typedef struct { const void *ptr_data[2]; unsigned int_data; } CXSourceLocation;
typedef struct { const void *ptr_data[2]; unsigned begin_int_data; unsigned end_int_data; } CXSourceRange;
typedef struct { unsigned int_data[4]; void *ptr_data; } CXToken;
struct CXUnsavedFile { const char *Filename; const char *Contents; unsigned long Length; };
typedef void *CXFile;
typedef int (*CXCursorVisitor)(CXCursor, CXCursor, void *);
typedef void (*CXInclusionVisitor)(CXFile, CXSourceLocation *, unsigned, void *);

#define CLANG_FUNCTIONS(X)                                                                                             \
    X(void *, clang_createIndex, (int, int))                                                                           \
    X(void, clang_disposeIndex, (void *))                                                                              \
    X(void *, clang_parseTranslationUnit, (void *, const char *, const char *const *, int, struct CXUnsavedFile *, unsigned, unsigned)) \
    X(void, clang_disposeTranslationUnit, (void *))                                                                    \
    X(CXCursor, clang_getTranslationUnitCursor, (void *))                                                              \
    X(unsigned, clang_visitChildren, (CXCursor, CXCursorVisitor, void *))                                              \
    X(int, clang_getCursorKind, (CXCursor))                                                                            \
    X(CXString, clang_getCursorSpelling, (CXCursor))                                                                   \
    X(const char *, clang_getCString, (CXString))                                                                      \
    X(void, clang_disposeString, (CXString))                                                                           \
    X(CXType, clang_getCursorType, (CXCursor))                                                                         \
    X(CXType, clang_getCanonicalType, (CXType))                                                                        \
    X(CXType, clang_getPointeeType, (CXType))                                                                          \
    X(CXType, clang_getResultType, (CXType))                                                                           \
    X(int, clang_getNumArgTypes, (CXType))                                                                             \
    X(CXType, clang_getArgType, (CXType, unsigned))                                                                    \
    X(unsigned, clang_isFunctionTypeVariadic, (CXType))                                                                \
    X(CXCursor, clang_getTypeDeclaration, (CXType))                                                                    \
    X(CXType, clang_getTypedefDeclUnderlyingType, (CXCursor))                                                          \
    X(CXType, clang_Type_getNamedType, (CXType))                                                                       \
    X(CXType, clang_Type_getModifiedType, (CXType))                                                                    \
    X(long long, clang_Type_getSizeOf, (CXType))                                                                       \
    X(long long, clang_Type_getAlignOf, (CXType))                                                                      \
    X(long long, clang_Cursor_getOffsetOfField, (CXCursor))                                                            \
    X(unsigned, clang_Cursor_isBitField, (CXCursor))                                                                   \
    X(unsigned, clang_isConstQualifiedType, (CXType))                                                                  \
    X(long long, clang_getEnumConstantDeclValue, (CXCursor))                                                           \
    X(unsigned long long, clang_getEnumConstantDeclUnsignedValue, (CXCursor))                                          \
    X(CXType, clang_getEnumDeclIntegerType, (CXCursor))                                                                \
    X(CXSourceLocation, clang_getCursorLocation, (CXCursor))                                                           \
    X(void, clang_getFileLocation, (CXSourceLocation, CXFile *, unsigned *, unsigned *, unsigned *))                   \
    X(CXString, clang_getFileName, (CXFile))                                                                           \
    X(int, clang_Location_isInSystemHeader, (CXSourceLocation))                                                        \
    X(CXSourceLocation, clang_getLocation, (void *, CXFile, unsigned, unsigned))                                       \
    X(void, clang_getInclusions, (void *, CXInclusionVisitor, void *))                                                 \
    X(CXCursor, clang_getCursorDefinition, (CXCursor))                                                                 \
    X(CXCursor, clang_getCanonicalCursor, (CXCursor))                                                                  \
    X(unsigned, clang_hashCursor, (CXCursor))                                                                          \
    X(int, clang_Cursor_isNull, (CXCursor))                                                                            \
    X(CXCursor, clang_Cursor_getArgument, (CXCursor, unsigned))                                                        \
    X(int, clang_Cursor_getStorageClass, (CXCursor))                                                                   \
    X(CXString, clang_getTypeSpelling, (CXType))                                                                       \
    X(unsigned, clang_Cursor_isMacroFunctionLike, (CXCursor))                                                          \
    X(unsigned, clang_Cursor_isMacroBuiltin, (CXCursor))                                                               \
    X(CXSourceRange, clang_getCursorExtent, (CXCursor))                                                                \
    X(void, clang_tokenize, (void *, CXSourceRange, CXToken **, unsigned *))                                           \
    X(int, clang_getTokenKind, (CXToken))                                                                              \
    X(CXString, clang_getTokenSpelling, (void *, CXToken))                                                             \
    X(void, clang_disposeTokens, (void *, CXToken *, unsigned))                                                        \
    X(unsigned, clang_isInvalidDeclaration, (CXCursor))                                                                \
    X(unsigned, clang_getNumDiagnostics, (void *))                                                                     \
    X(void *, clang_getDiagnostic, (void *, unsigned))                                                                 \
    X(int, clang_getDiagnosticSeverity, (void *))                                                                      \
    X(CXString, clang_formatDiagnostic, (void *, unsigned))                                                            \
    X(unsigned, clang_defaultDiagnosticDisplayOptions, (void))                                                         \
    X(void, clang_disposeDiagnostic, (void *))                                                                         \
    X(CXString, clang_getClangVersion, (void))                                                                         \
    X(CXFile, clang_getIncludedFile, (CXCursor))                                                                       \
    X(CXType, clang_getArrayElementType, (CXType))

#define DECLARE(ret, name, params) static ret(*p_##name) params;
CLANG_FUNCTIONS(DECLARE)
#undef DECLARE

static char *last_error;
static char *strings[8]; /* a few recent string results stay valid at the same time */
static int next_string;

static const char *keep(char *s)
{
    free(strings[next_string]);
    strings[next_string] = s;
    next_string = (next_string + 1) % 8;
    return s;
}

static char *copy(const char *s)
{
    size_t n = strlen(s);
    char *r = (char *)malloc(n + 1);
    if (r)
        memcpy(r, s, n + 1);
    return r;
}

static const char *cx(CXString s)
{
    const char *c = p_clang_getCString(s);
    char *r = copy(c ? c : "");
    p_clang_disposeString(s);
    return keep(r);
}

/* ---- loading ---- */

/* Loads libclang from the path; 1 on success. On failure host_clang_error() tells why. */
int host_clang_open(const char *path)
{
    void *lib;
    char missing[4096];
    missing[0] = 0;
#ifdef _WIN32
    {
        /* the DLL's own dependencies (libc++.dll, ...) live next to it */
        char dir[4096];
        const char *slash = strrchr(path, '\\');
        const char *slash2 = strrchr(path, '/');
        if (slash2 > slash)
            slash = slash2;
        if (slash && (size_t)(slash - path) < sizeof(dir))
        {
            memcpy(dir, path, (size_t)(slash - path));
            dir[slash - path] = 0;
            SetDllDirectoryA(dir);
        }
    }
    lib = (void *)LoadLibraryA(path);
#define SYMBOL(name) (void *)GetProcAddress((HMODULE)lib, name)
#else
    lib = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
#define SYMBOL(name) dlsym(lib, name)
#endif
    if (!lib)
    {
        free(last_error);
#ifdef _WIN32
        last_error = copy("cannot load the library");
#else
        last_error = copy(dlerror());
#endif
        return 0;
    }
#define LOAD(ret, name, params)                                                                                        \
    *(void **)&p_##name = SYMBOL(#name);                                                                               \
    if (!p_##name && strlen(missing) + strlen(#name) + 3 < sizeof(missing))                                            \
    {                                                                                                                  \
        if (missing[0])                                                                                                \
            strcat(missing, ", ");                                                                                     \
        strcat(missing, #name);                                                                                        \
    }
    CLANG_FUNCTIONS(LOAD)
#undef LOAD
#undef SYMBOL
    if (missing[0])
    {
        free(last_error);
        last_error = (char *)malloc(strlen(missing) + 64);
        if (last_error)
            sprintf(last_error, "this libclang is too old or incompatible, missing: %s", missing);
        return 0;
    }
    return 1;
}

const char *host_clang_error(void)
{
    return last_error ? last_error : "";
}

const char *host_clang_version(void)
{
    return cx(p_clang_getClangVersion());
}

/* ---- translation units ---- */

void *host_clang_create_index(void)
{
    return p_clang_createIndex(0, 0);
}

void host_clang_dispose_index(void *index)
{
    p_clang_disposeIndex(index);
}

/* 'args' are the compiler arguments separated by '\n'; the unsaved file replaces the file 'file'. */
void *host_clang_parse(void *index, const char *file, const char *args, const char *unsaved_text, int32_t flags)
{
    char *text = copy(args);
    const char *argv[256];
    int argc = 0;
    char *p = text;
    struct CXUnsavedFile unsaved;
    void *tu;
    while (p && *p && argc < 256)
    {
        char *end = strchr(p, '\n');
        argv[argc++] = p;
        if (!end)
            break;
        *end = 0;
        p = end + 1;
    }
    unsaved.Filename = file;
    unsaved.Contents = unsaved_text;
    unsaved.Length = (unsigned long)strlen(unsaved_text);
    tu = p_clang_parseTranslationUnit(index, file, argv, argc, &unsaved, 1, (unsigned)flags);
    free(text);
    return tu;
}

void host_clang_dispose_tu(void *tu)
{
    p_clang_disposeTranslationUnit(tu);
}

int32_t host_clang_num_diagnostics(void *tu)
{
    return (int32_t)p_clang_getNumDiagnostics(tu);
}

int32_t host_clang_diagnostic_severity(void *tu, int32_t i)
{
    void *d = p_clang_getDiagnostic(tu, (unsigned)i);
    int s = p_clang_getDiagnosticSeverity(d);
    p_clang_disposeDiagnostic(d);
    return s;
}

const char *host_clang_diagnostic_text(void *tu, int32_t i)
{
    void *d = p_clang_getDiagnostic(tu, (unsigned)i);
    const char *s = cx(p_clang_formatDiagnostic(d, p_clang_defaultDiagnosticDisplayOptions()));
    p_clang_disposeDiagnostic(d);
    return s;
}

/* ---- inclusions ---- */

typedef struct { CXFile file; unsigned depth; } Inclusion;
static Inclusion *inclusions;
static int inclusion_count, inclusion_capacity;

static void on_inclusion(CXFile file, CXSourceLocation *stack, unsigned depth, void *data)
{
    (void)stack;
    (void)data;
    if (inclusion_count == inclusion_capacity)
    {
        inclusion_capacity = inclusion_capacity ? inclusion_capacity * 2 : 64;
        inclusions = (Inclusion *)realloc(inclusions, sizeof(Inclusion) * (size_t)inclusion_capacity);
    }
    inclusions[inclusion_count].file = file;
    inclusions[inclusion_count].depth = depth;
    inclusion_count += 1;
}

int32_t host_clang_inclusions(void *tu)
{
    inclusion_count = 0;
    p_clang_getInclusions(tu, on_inclusion, NULL);
    return inclusion_count;
}

void *host_clang_inclusion_file(int32_t i)
{
    return inclusions[i].file;
}

int32_t host_clang_inclusion_depth(int32_t i)
{
    return (int32_t)inclusions[i].depth;
}

const char *host_clang_file_name(void *file)
{
    return cx(p_clang_getFileName(file));
}

int32_t host_clang_file_is_system(void *tu, void *file)
{
    return p_clang_Location_isInSystemHeader(p_clang_getLocation(tu, file, 1, 1)) != 0;
}

/* ---- cursors ---- */

void host_clang_tu_cursor(void *tu, CXCursor *ret)
{
    *ret = p_clang_getTranslationUnitCursor(tu);
}

static CXCursor *children;
static int child_count, child_capacity;

static int on_child(CXCursor cursor, CXCursor parent, void *data)
{
    (void)parent;
    (void)data;
    if (child_count == child_capacity)
    {
        child_capacity = child_capacity ? child_capacity * 2 : 256;
        children = (CXCursor *)realloc(children, sizeof(CXCursor) * (size_t)child_capacity);
    }
    children[child_count++] = cursor;
    return 1; /* CXChildVisit_Continue */
}

/* Collects the direct children of the cursor; read them with host_clang_child. */
int32_t host_clang_children(const CXCursor *c)
{
    child_count = 0;
    p_clang_visitChildren(*c, on_child, NULL);
    return child_count;
}

void host_clang_child(int32_t i, CXCursor *ret)
{
    *ret = children[i];
}

int32_t host_clang_cursor_kind(const CXCursor *c) { return p_clang_getCursorKind(*c); }
const char *host_clang_cursor_spelling(const CXCursor *c) { return cx(p_clang_getCursorSpelling(*c)); }
void host_clang_cursor_type(const CXCursor *c, CXType *ret) { *ret = p_clang_getCursorType(*c); }
void host_clang_cursor_definition(const CXCursor *c, CXCursor *ret) { *ret = p_clang_getCursorDefinition(*c); }
void host_clang_canonical_cursor(const CXCursor *c, CXCursor *ret) { *ret = p_clang_getCanonicalCursor(*c); }
uint32_t host_clang_hash_cursor(const CXCursor *c) { return p_clang_hashCursor(*c); }
int32_t host_clang_cursor_is_null(const CXCursor *c) { return p_clang_Cursor_isNull(*c) != 0; }
void host_clang_argument(const CXCursor *c, int32_t i, CXCursor *ret) { *ret = p_clang_Cursor_getArgument(*c, (unsigned)i); }
int32_t host_clang_storage_class(const CXCursor *c) { return p_clang_Cursor_getStorageClass(*c); }
int64_t host_clang_offset_of_field(const CXCursor *c) { return p_clang_Cursor_getOffsetOfField(*c); }
int32_t host_clang_is_bit_field(const CXCursor *c) { return p_clang_Cursor_isBitField(*c) != 0; }
int64_t host_clang_enum_value(const CXCursor *c) { return p_clang_getEnumConstantDeclValue(*c); }
uint64_t host_clang_enum_unsigned_value(const CXCursor *c) { return p_clang_getEnumConstantDeclUnsignedValue(*c); }
void host_clang_enum_integer_type(const CXCursor *c, CXType *ret) { *ret = p_clang_getEnumDeclIntegerType(*c); }
void host_clang_typedef_underlying(const CXCursor *c, CXType *ret) { *ret = p_clang_getTypedefDeclUnderlyingType(*c); }
int32_t host_clang_macro_function_like(const CXCursor *c) { return p_clang_Cursor_isMacroFunctionLike(*c) != 0; }
int32_t host_clang_macro_builtin(const CXCursor *c) { return p_clang_Cursor_isMacroBuiltin(*c) != 0; }
int32_t host_clang_is_invalid(const CXCursor *c) { return p_clang_isInvalidDeclaration(*c) != 0; }
void *host_clang_included_file(const CXCursor *c) { return p_clang_getIncludedFile(*c); }

/* The file the cursor is in (NULL for none). */
void *host_clang_cursor_file(const CXCursor *c)
{
    CXFile file = NULL;
    unsigned line = 0, column = 0, offset = 0;
    p_clang_getFileLocation(p_clang_getCursorLocation(*c), &file, &line, &column, &offset);
    return file;
}

/* ---- tokens ---- */

static CXToken *tokens;
static unsigned token_count;
static void *token_tu;

/* Tokenizes the extent of the cursor; read the tokens with host_clang_token_kind/spelling. */
int32_t host_clang_tokenize(void *tu, const CXCursor *c)
{
    if (tokens)
        p_clang_disposeTokens(token_tu, tokens, token_count);
    tokens = NULL;
    token_count = 0;
    token_tu = tu;
    p_clang_tokenize(tu, p_clang_getCursorExtent(*c), &tokens, &token_count);
    return (int32_t)token_count;
}

int32_t host_clang_token_kind(int32_t i) { return p_clang_getTokenKind(tokens[i]); }
const char *host_clang_token_spelling(int32_t i) { return cx(p_clang_getTokenSpelling(token_tu, tokens[i])); }

/* ---- types ---- */

void host_clang_canonical_type(const CXType *t, CXType *ret) { *ret = p_clang_getCanonicalType(*t); }
void host_clang_pointee_type(const CXType *t, CXType *ret) { *ret = p_clang_getPointeeType(*t); }
void host_clang_result_type(const CXType *t, CXType *ret) { *ret = p_clang_getResultType(*t); }
int32_t host_clang_num_arg_types(const CXType *t) { return p_clang_getNumArgTypes(*t); }
void host_clang_arg_type(const CXType *t, int32_t i, CXType *ret) { *ret = p_clang_getArgType(*t, (unsigned)i); }
int32_t host_clang_is_variadic(const CXType *t) { return p_clang_isFunctionTypeVariadic(*t) != 0; }
void host_clang_type_declaration(const CXType *t, CXCursor *ret) { *ret = p_clang_getTypeDeclaration(*t); }
void host_clang_named_type(const CXType *t, CXType *ret) { *ret = p_clang_Type_getNamedType(*t); }
void host_clang_modified_type(const CXType *t, CXType *ret) { *ret = p_clang_Type_getModifiedType(*t); }
int64_t host_clang_size_of(const CXType *t) { return p_clang_Type_getSizeOf(*t); }
int64_t host_clang_align_of(const CXType *t) { return p_clang_Type_getAlignOf(*t); }
int32_t host_clang_is_const(const CXType *t) { return p_clang_isConstQualifiedType(*t) != 0; }
const char *host_clang_type_spelling(const CXType *t) { return cx(p_clang_getTypeSpelling(*t)); }
void host_clang_array_element_type(const CXType *t, CXType *ret) { *ret = p_clang_getArrayElementType(*t); }

/* ---- the running program ---- */

/* The absolute path of the running executable, or "" if it cannot be found. */
const char *host_executable_path(void)
{
    char buffer[4096];
    buffer[0] = 0;
#if defined(_WIN32)
    {
        DWORD n = GetModuleFileNameA(NULL, buffer, sizeof(buffer));
        buffer[n < sizeof(buffer) ? n : 0] = 0;
    }
#elif defined(__APPLE__)
    {
        uint32_t size = sizeof(buffer);
        char resolved[4096];
        if (_NSGetExecutablePath(buffer, &size) != 0)
            buffer[0] = 0;
        else if (realpath(buffer, resolved))
            strcpy(buffer, resolved);
    }
#else
    {
        ssize_t n = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
        buffer[n > 0 ? n : 0] = 0;
    }
#endif
    return keep(copy(buffer));
}

/* The size of a file, or -1. */
int64_t host_file_size(const char *path)
{
    FILE *f = fopen(path, "rb");
    int64_t size;
    if (!f)
        return -1;
#ifdef _WIN32
    _fseeki64(f, 0, SEEK_END);
    size = _ftelli64(f);
#else
    fseeko(f, 0, SEEK_END);
    size = (int64_t)ftello(f);
#endif
    fclose(f);
    return size;
}

/* Copies 'size' bytes at 'offset' of 'source' into the new file 'target' (the toolchain archive inside a standalone
 * cshc). 1 on success. */
int32_t host_copy_file_part(const char *source, int64_t offset, int64_t size, const char *target)
{
    FILE *in = fopen(source, "rb");
    FILE *out;
    char buffer[65536];
    int ok = 1;
    if (!in)
        return 0;
    out = fopen(target, "wb");
    if (!out)
    {
        fclose(in);
        return 0;
    }
#ifdef _WIN32
    _fseeki64(in, offset, SEEK_SET);
#else
    fseeko(in, (off_t)offset, SEEK_SET);
#endif
    while (size > 0 && ok)
    {
        size_t chunk = size < (int64_t)sizeof(buffer) ? (size_t)size : sizeof(buffer);
        size_t n = fread(buffer, 1, chunk, in);
        if (n != chunk || fwrite(buffer, 1, n, out) != n)
            ok = 0;
        size -= (int64_t)n;
    }
    fclose(in);
    if (fclose(out) != 0)
        ok = 0;
    return ok;
}

/* The toolchain appended to a standalone build (packaging/make-standalone.sh): a gzip-compressed tar followed by a
 * 16-byte footer, "CSFTTC01" and the little-endian size of the archive. 1 if the file carries one; then 'offset' and
 * 'size' say where the archive is. */
int32_t host_embedded_toolchain(const char *path, int64_t *offset, int64_t *size)
{
    unsigned char footer[16];
    int64_t file_size = host_file_size(path);
    uint64_t archive = 0;
    FILE *f;
    int i;
    if (file_size < 16)
        return 0;
    f = fopen(path, "rb");
    if (!f)
        return 0;
#ifdef _WIN32
    _fseeki64(f, file_size - 16, SEEK_SET);
#else
    fseeko(f, (off_t)(file_size - 16), SEEK_SET);
#endif
    if (fread(footer, 1, 16, f) != 16)
    {
        fclose(f);
        return 0;
    }
    fclose(f);
    if (memcmp(footer, "CSFTTC01", 8) != 0)
        return 0;
    for (i = 7; i >= 0; i -= 1)
        archive = archive * 256 + footer[8 + i];
    if (archive + 16 > (uint64_t)file_size)
        return 0; /* corrupt or foreign trailer */
    *size = (int64_t)archive;
    *offset = file_size - 16 - (int64_t)archive;
    return 1;
}

/* The current working directory ('/' separators on every system), or "". */
const char *host_current_directory(void)
{
    char buffer[4096];
    char *p;
#ifdef _WIN32
    DWORD n = GetCurrentDirectoryA(sizeof(buffer), buffer);
    if (n == 0 || n >= sizeof(buffer))
        buffer[0] = 0;
#else
    if (!getcwd(buffer, sizeof(buffer)))
        buffer[0] = 0;
#endif
    for (p = buffer; *p; p += 1)
        if (*p == '\\')
            *p = '/';
    return keep(copy(buffer));
}
