// The standard library (stdlib/*.csh) inside cshc: read when cshc is compiled; the path is relative to this file.
// New files in stdlib/ are picked up automatically.

namespace CShift.Driver;

const ReadOnlySlice<string> EmbeddedStdlibNames = embed_filenames("../../../stdlib/*.csh");
const ReadOnlySlice<string> EmbeddedStdlibTexts = embed("../../../stdlib/*.csh");
