// embed("file"): first relative to the source file, then relative to the project folder.
using System;

const string Version = embed("data/version.txt");   // not next to this file: found in the project folder
const string Note = embed("note.txt");              // next to this file
const ReadOnlySlice<string> DataNames = embed_filenames("data/*.txt"); // no data/ next to this file: the project's

int Main()
{
    Console.Write("version " + Version);
    Console.Write("note " + Note);
    string names = "";
    foreach (var name in DataNames)
        names += " " + name;
    Console.WriteLine("data" + names);
    return 0;
}
