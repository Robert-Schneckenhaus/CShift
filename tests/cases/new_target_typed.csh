// new { ... } and new() take their type from the declaration (local and global variables)
// expect-stdout: 100 200
// expect-stdout: 0 0
// expect-stdout: 3 4
// expect-stdout: 2
using System;

struct Player
{
    int X;
    int Y;
}

Player start = new { X = 3, Y = 4 };
List<int> numbers = new();

int Main()
{
    Player player = new { X = 100, Y = 200 };
    Console.WriteLine($"{player.X} {player.Y}");
    Player empty = new();
    Console.WriteLine($"{empty.X} {empty.Y}");
    Console.WriteLine($"{start.X} {start.Y}");
    numbers.Add(1);
    numbers.Add(2);
    Console.WriteLine(numbers.Count());
    return 0;
}
