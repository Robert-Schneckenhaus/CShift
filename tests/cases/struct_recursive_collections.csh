// A struct can hold lists and dictionaries of itself (they store their elements behind an array); only a struct that
// contains itself by value is an error.
// expect-stdout: 2 3 2 x
using System;

struct Node
{
    double N;
    List<Node> Items;
    Dictionary<string, Node> Fields;
}

int Main()
{
    var a = Node { Items = List<Node>.Create(), Fields = Dictionary<string, Node>.Create() };
    a.Items.Add(Node { N = 1.5 });
    a.Fields.Set("x", Node { N = 2 });
    var inner = Node { Items = List<Node>.Create() };
    inner.Items.Add(Node { N = 3 });
    a.Items.Add(inner);
    Console.WriteLine(a.Items.Count().ToString() + " " + a.Items.Get(1).Items.Get(0).N.ToString() + " " +
                      a.Fields.Get("x").N.ToString() + " " + string.Join(",", a.Fields.Keys()));
    return 0;
}
