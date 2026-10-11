// The standard library (stdlib/*.cshift) inside cshc: read when cshc is compiled; the path is relative to this file.
// New files in stdlib/ are picked up automatically.

namespace CShift.Driver;

const ReadOnlySlice<string> EmbeddedStdlibNames = embed_filenames("../../../stdlib/*.cshift");
const ReadOnlySlice<string> EmbeddedStdlibTexts = embed("../../../stdlib/*.cshift");

// The C library of the backends that bring their own (AmigaOS, WebAssembly): printf's formatting.
const ReadOnlySlice<string> EmbeddedLibcNames = embed_filenames("../../../stdlib/libc/*.cshift");
const ReadOnlySlice<string> EmbeddedLibcTexts = embed("../../../stdlib/libc/*.cshift");

// The C library of the wasm backend (stdlib/wasm/*.cshift: memory, files and the rest on WASI), only with
// --backend wasm.
const ReadOnlySlice<string> EmbeddedWasmNames = embed_filenames("../../../stdlib/wasm/*.cshift");
const ReadOnlySlice<string> EmbeddedWasmTexts = embed("../../../stdlib/wasm/*.cshift");

// The runtime of the 68000 backend (stdlib/m68k/*.cshift: software floating point, ...), only added with --backend m68k.
const ReadOnlySlice<string> EmbeddedM68kNames = embed_filenames("../../../stdlib/m68k/*.cshift");
const ReadOnlySlice<string> EmbeddedM68kTexts = embed("../../../stdlib/m68k/*.cshift");

// The operating system layer of the standard library (stdlib/os/<layer>/*.cshift: time, file times, seeking, ...): one
// of windows, wasi (WebAssembly), or posix with the struct layouts of the architecture (posix-64, posix-32, posix-m68k),
// see OsLayers.
// AmigaOS has its own in stdlib/amiga.
const ReadOnlySlice<string> EmbeddedOsWindowsNames = embed_filenames("../../../stdlib/os/windows/*.cshift");
const ReadOnlySlice<string> EmbeddedOsWindowsTexts = embed("../../../stdlib/os/windows/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosixNames = embed_filenames("../../../stdlib/os/posix/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosixTexts = embed("../../../stdlib/os/posix/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosix64Names = embed_filenames("../../../stdlib/os/posix-64/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosix64Texts = embed("../../../stdlib/os/posix-64/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosix32Names = embed_filenames("../../../stdlib/os/posix-32/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosix32Texts = embed("../../../stdlib/os/posix-32/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosixM68kNames = embed_filenames("../../../stdlib/os/posix-m68k/*.cshift");
const ReadOnlySlice<string> EmbeddedOsPosixM68kTexts = embed("../../../stdlib/os/posix-m68k/*.cshift");
const ReadOnlySlice<string> EmbeddedOsWasiNames = embed_filenames("../../../stdlib/os/wasi/*.cshift");
const ReadOnlySlice<string> EmbeddedOsWasiTexts = embed("../../../stdlib/os/wasi/*.cshift");

// The C library of AmigaOS programs (stdlib/amiga/*.cshift), only added for an amigaos target.
const ReadOnlySlice<string> EmbeddedAmigaNames = embed_filenames("../../../stdlib/amiga/*.cshift");
const ReadOnlySlice<string> EmbeddedAmigaTexts = embed("../../../stdlib/amiga/*.cshift");

// The declarations of the built-in types, only for their doc comments (LoadBuiltinDocs).
const ReadOnlySlice<string> EmbeddedBuiltinNames = embed_filenames("../../../stdlib/builtin/*.cshift");
const ReadOnlySlice<string> EmbeddedBuiltinTexts = embed("../../../stdlib/builtin/*.cshift");
