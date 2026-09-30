// The standard library (stdlib/*.csh) inside cshc: read when cshc is compiled; the path is relative to this file.
// New files in stdlib/ are picked up automatically.

namespace CShift.Driver;

const ReadOnlySlice<string> EmbeddedStdlibNames = embed_filenames("../../../stdlib/*.csh");
const ReadOnlySlice<string> EmbeddedStdlibTexts = embed("../../../stdlib/*.csh");

// The runtime of the 68000 backend (stdlib/m68k/*.csh: software floating point, ...), only added with --backend m68k.
const ReadOnlySlice<string> EmbeddedM68kNames = embed_filenames("../../../stdlib/m68k/*.csh");
const ReadOnlySlice<string> EmbeddedM68kTexts = embed("../../../stdlib/m68k/*.csh");

// The C library of AmigaOS programs (stdlib/amiga/*.csh), only added for an amigaos target.
const ReadOnlySlice<string> EmbeddedAmigaNames = embed_filenames("../../../stdlib/amiga/*.csh");
const ReadOnlySlice<string> EmbeddedAmigaTexts = embed("../../../stdlib/amiga/*.csh");
