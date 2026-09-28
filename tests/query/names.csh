// cshiftc query: hover and definition of the names of a program (see tests/run_tests.sh, section 3b).
// query: 42 13 => "hover": "struct Person"
// query: 42 20 => "hover": "static Person Person.Make(string name)"
// query: 43 17 => "hover": "int32 Add(int32 a, int32 b)"
// query: 43 17 => "line": 35
// query: 43 23 => "hover": "int32 Person.Age"
// query: 43 28 => "hover": "const int32 Limit = 10"
// query: 43 39 => "hover": "int32 Person.Twice()"
// query: 44 16 => "hover": "struct System.List<Person>"
// query: 45 10 => "hover": "void System.List<Person>.Add(Person value)"
// query: 45 14 => "hover": "Person p"
// query: 46 21 => "hover": "Color.Green = 1"
// query: 48 18 => "hover": "Person item"
// query: 49 51 => "hover": "int32 counter (global)"
// query: 31 26 => "line": 29
// query: 37 16 => "hover": "(parameter) int32 b"

using System;

enum Color : uint8 { Red, Green }

const int Limit = 10;

int counter = 0;

struct Person
{
    string Name;
    int Age;

    int Twice() { return Age * 2; }
    static Person Make(string name) { return Person { Name = name, Age = 1 }; }
}

int Add(int a, int b)
{
    return a + b;
}

int Main()
{
    var p = Person.Make("Ann");
    int total = Add(p.Age, Limit) + p.Twice();
    var list = List<Person>.Create();
    list.Add(p);
    Color c = Color.Green;
    foreach (var item in list)
        total += item.Age;
    Console.WriteLine(p.Name + total.ToString() + counter.ToString() + c.ToString());
    return 0;
}
