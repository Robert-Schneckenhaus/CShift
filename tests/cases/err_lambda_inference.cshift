// The type arguments of a call cannot be inferred when the body of the lambda that gives them has an error; the
// message names that error.
// expect-error: cannot infer the type arguments: the lambda has an error (struct 'Person' has no field 'Nme')

using System;

struct Person
{
    string Name;
}

int Main()
{
    var people = List<Person>.Create();
    var names = people.Select(p => p.Nme);
    return 0;
}
