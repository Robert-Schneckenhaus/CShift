// embed("file"): first relative to the source file, then relative to the project folder.
using System;

const string Version = embed("data/version.txt");   // not next to this file: found in the project folder
const string Note = embed("note.txt");              // next to this file

int Main()
{
    Console.Write("version " + Version);
    Console.Write("note " + Note);
    return 0;
}
