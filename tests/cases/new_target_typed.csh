// new { ... } and new() take the struct type they are used as: declarations (local and global), assignments, return
// values, arguments, fields of an initializer, Optional<T>
// expect-stdout: 100 200
// expect-stdout: 0 0
// expect-stdout: 3 4
// expect-stdout: 2
// expect-stdout: 7 8
// expect-stdout: 5 6
// expect-stdout: 9 0
// expect-stdout: 11
// expect-stdout: 1 2
using System;

struct Player
{
    int X;
    int Y;
}

struct Team
{
    Player Leader;
    string Name;
}

Player start = new { X = 3, Y = 4 };
List<int> numbers = new();

Player Make(int x, int y)
{
    return new { X = x, Y = y };
}

string Show(Player p)
{
    return $"{p.X} {p.Y}";
}

Optional<Player> Find(bool found)
{
    if (found)
        return new { X = 1, Y = 2 };
    return null;
}

int Main()
{
    Player player = new { X = 100, Y = 200 };
    Console.WriteLine(Show(player));
    Player empty = new();
    Console.WriteLine(Show(empty));
    Console.WriteLine(Show(start));
    numbers.Add(1);
    numbers.Add(2);
    Console.WriteLine(numbers.Count());
    player = new { X = 7, Y = 8 };
    Console.WriteLine(Show(player));
    Console.WriteLine(Show(Make(5, 6)));
    Console.WriteLine(Show(new { X = 9 }));
    var team = Team { Leader = new { X = 11 }, Name = "a" };
    Console.WriteLine(team.Leader.X);
    if (Find(true) is Player p)
        Console.WriteLine(Show(p));
    return 0;
}
