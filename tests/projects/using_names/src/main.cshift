// A name that two 'using' namespaces have is ambiguous (err_using_ambiguous), but a type of the file's own namespace
// (or of a parent namespace) hides them, and the full name always works.
namespace App.Model;

using System;
using Shapes;

void Main()
{
    JsonValue own = JsonValue { Text = "own" };                // App.Model.JsonValue
    System.JsonValue system = System.JsonValue.Number(2);
    Shapes.JsonValue shape = Shapes.JsonValue.Of(3);
    Shade shade = Shade.Dark;                                 // only Shapes has a Shade
    Console.WriteLine(own.Text + " " + system.ToString() + " " + shape.X.ToString() + " " + shade.ToString());
}
