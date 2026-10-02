// The standard library (stdlib/*.csh) inside cshc: read when cshc is compiled; the path is relative to this file.
// New files in stdlib/ are picked up automatically.

namespace CShift.Driver;

const ReadOnlySlice<string> EmbeddedStdlibNames = embed_filenames("../../../stdlib/*.csh");
const ReadOnlySlice<string> EmbeddedStdlibTexts = embed("../../../stdlib/*.csh");

// The runtime of the 68000 backend (stdlib/m68k/*.csh: software floating point, ...), only added with --backend m68k.
const ReadOnlySlice<string> EmbeddedM68kNames = embed_filenames("../../../stdlib/m68k/*.csh");
const ReadOnlySlice<string> EmbeddedM68kTexts = embed("../../../stdlib/m68k/*.csh");

// The operating system layer of the standard library (stdlib/os/<layer>/*.csh: time, file times, seeking, ...): one
// of windows, wasi (WebAssembly), or posix with the struct layouts of the architecture (posix-64, posix-32, posix-m68k),
// see OsLayers.
// AmigaOS has its own in stdlib/amiga.
const ReadOnlySlice<string> EmbeddedOsWindowsNames = embed_filenames("../../../stdlib/os/windows/*.csh");
const ReadOnlySlice<string> EmbeddedOsWindowsTexts = embed("../../../stdlib/os/windows/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosixNames = embed_filenames("../../../stdlib/os/posix/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosixTexts = embed("../../../stdlib/os/posix/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosix64Names = embed_filenames("../../../stdlib/os/posix-64/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosix64Texts = embed("../../../stdlib/os/posix-64/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosix32Names = embed_filenames("../../../stdlib/os/posix-32/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosix32Texts = embed("../../../stdlib/os/posix-32/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosixM68kNames = embed_filenames("../../../stdlib/os/posix-m68k/*.csh");
const ReadOnlySlice<string> EmbeddedOsPosixM68kTexts = embed("../../../stdlib/os/posix-m68k/*.csh");
const ReadOnlySlice<string> EmbeddedOsWasiNames = embed_filenames("../../../stdlib/os/wasi/*.csh");
const ReadOnlySlice<string> EmbeddedOsWasiTexts = embed("../../../stdlib/os/wasi/*.csh");

// The C library of AmigaOS programs (stdlib/amiga/*.csh), only added for an amigaos target.
const ReadOnlySlice<string> EmbeddedAmigaNames = embed_filenames("../../../stdlib/amiga/*.csh");
const ReadOnlySlice<string> EmbeddedAmigaTexts = embed("../../../stdlib/amiga/*.csh");

// The declarations of the built-in types, only for their doc comments (LoadBuiltinDocs).
const ReadOnlySlice<string> EmbeddedBuiltinNames = embed_filenames("../../../stdlib/builtin/*.csh");
const ReadOnlySlice<string> EmbeddedBuiltinTexts = embed("../../../stdlib/builtin/*.csh");
