// embed("*.txt") and embed_filenames("*.txt"): the contents and names of all matching files, sorted by name, as a
// constant ReadOnlySlice<string>. Wildcards: '*' (any characters) and '?' (one character), only in the file name;
// folders never match. Without a wildcard, embed_filenames gives the name as a string (and checks that the file exists).
// expect-exit: 0
// expect-stdout: names 1-alpha.txt,2-beta.txt,4.txt
// expect-stdout: texts 3 alpha\r|beta "b"|x
// expect-stdout: numbered 1-alpha.txt,2-beta.txt
// expect-stdout: markdown 3-gamma.md not a text
// expect-stdout: none 0
// expect-stdout: single 2-beta.txt
// expect-stdout: local 4.txt x

using System;

const ReadOnlySlice<string> Names = embed_filenames("embed/texts/*.txt");
const ReadOnlySlice<string> Texts = embed("embed/texts/*.txt");
const ReadOnlySlice<string> Numbered = embed_filenames("embed/texts/?-*.txt");
const ReadOnlySlice<string> Markdown = embed("embed/texts/*.md");
const ReadOnlySlice<string> MarkdownName = embed_filenames("embed/texts/*.md");
const ReadOnlySlice<string> None = embed("embed/texts/*.none");
const string Single = embed_filenames("embed/texts/2-beta.txt");
const ReadOnlySlice<string> Both = [..Names, ..MarkdownName];   // ordinary constant slices

string Join(ReadOnlySlice<string> items, string sep)
{
    string all = "";
    for (var i = 0; i < items.Length; i += 1)
        all += (i > 0 ? sep : "") + items[i];
    return all;
}

int Main()
{
    Console.WriteLine("names " + Join(Names, ","));
    Console.WriteLine("texts " + Texts.Length.ToString() + " " + Join(Texts, "|").Replace("\r", "\\r").Replace("\n", ""));
    Console.WriteLine("numbered " + Join(Numbered, ","));
    Console.WriteLine("markdown " + MarkdownName[0] + " " + Markdown[0]);
    Console.WriteLine("none " + None.Length.ToString());
    Console.WriteLine("single " + Single);
    const ReadOnlySlice<string> Last = embed_filenames("embed/texts/4.*");
    const ReadOnlySlice<string> LastText = embed("embed/texts/4.*");
    Console.WriteLine("local " + Last[0] + " " + LastText[0]);
    if (Both.Length != 4)
        return 1;
    return 0;
}
