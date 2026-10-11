using System;

interface IShape { double Area(); }

struct Circle : IShape
{
    double R;
    double Area() { return Math.PI * R * R; }
}

struct Square : IShape
{
    double Side;
    double Area() { return Side * Side; }
}

union Shape : IShape { Circle, Square }    // either one, stored inline: no allocation

Error<int> Parse(string text)
{
    if (text.ParseInt() is int value)
        return value;
    return error($"'{text}' is not a number");
}

int Main()
{
    var shapes = List<Shape>.Create();
    shapes.Add(Circle { R = 1.0 });
    shapes.Add(Square { Side = 2.0 });
    shapes.ForEach(s => Console.WriteLine($"area {s.Area()}"));

    int n = try Parse("42");        // an error ends Main with the message
    Console.WriteLine(n);
    return 0;
}
