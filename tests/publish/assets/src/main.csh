// cshiftc publish: the files of "assets" are in the file system of the program, at their paths in the project.

using System;

int Main()
{
    Console.WriteLine("Hello from the page");
    foreach (var file in Directory.FindFiles("data", ""))
        Console.WriteLine(file + ": " + (File.ReadAllText(file) is string text ? text.Trim() : "cannot read"));
    Console.WriteLine(File.ReadAllText("notes.txt") is string notes ? notes.Trim() : "no notes");
    Console.WriteLine(File.Exists("src/main.csh") ? "the sources are there" : "only the assets are there");
    return 3;
}
