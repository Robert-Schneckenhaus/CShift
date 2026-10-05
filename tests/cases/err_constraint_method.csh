// In a generic body, a value of a type parameter offers the methods of its constraints (and ToString), checked once
// for the body, also if nothing instantiates it.
// expect-error: err_constraint_method.csh:20:24: error: 'first' has the type parameter 'T', which has no method 'Perimeter': a type parameter only offers the methods of its constraints ('T : IShape')
// expect-error: err_constraint_method.csh:25:14: error: 'a' has the type parameter 'T', which has no method 'Clone': a type parameter only offers the methods of its constraints, and 'T' has none (add 'where T : I...')

using System;

interface IShape
{
    double Area();
}

double Total<T>(T[] shapes) where T : IShape
{
    double sum = 0;
    foreach (var s in shapes)
        sum += s.Area();
    T first = shapes[0];
    Console.WriteLine(first.ToString());
    return sum + first.Perimeter();
}

T Pick<T>(T a)
{
    return a.Clone();
}

int Main()
{
    return 0;
}
