// Global variables in a namespace and in the global namespace, initialized in the order of the files.
namespace App.Config;

using System;

string Name = "app";
int Version = 3;
int Next = Version + 1;
List<string> Log = List<string>.Create();

void Add(string entry)
{
    Log.Add(Name + ": " + entry);
}
