// The standard library (stdlib/*.csh) inside cshc. The files are read when cshc is compiled (EmbedNames/EmbedTexts, see
// CodeGen/Embed.csh); the path is relative to this file. New files in stdlib/ are picked up automatically.

namespace CShift.Driver;

string[] EmbeddedStdlibNames()
{
    return EmbedNames("../../../stdlib", ".csh");
}

string[] EmbeddedStdlibTexts()
{
    return EmbedTexts("../../../stdlib", ".csh");
}
