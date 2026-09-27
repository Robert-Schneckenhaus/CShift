// Fixed<T, N>: N elements stored inline (on the stack, or inside the struct that has the field). A Fixed is a value:
// assigning, passing and returning copy the elements. Indexing (also ^n) is checked, Length is a constant, foreach,
// ToArray() (a heap copy), collection expressions (the number of elements is checked), ref/const ref parameters,
// generics, struct fields, containers, Optional and Fixed of Fixed all work; strings inside are counted.
// expect-exit: 0
// expect-stdout: 16 7 9 0
// expect-stdout: 12 15 2
// expect-stdout: 5 a changed 32
// expect-stdout: 1 100 9 64
// expect-stdout: 58 x 4
// expect-stdout: list 4
// expect-stdout: nested 37 5 true az 8 33
using System;

const int Size = 4;

struct Vertex
{
    Fixed<float, 3> Pos;
    Fixed<string, 2> Tags;
}

float Sum(const ref Fixed<float, 3> v)
{
    float total = 0;
    foreach (var x in v)
        total += x;
    return total;
}

void Scale(ref Fixed<float, 3> v, float f)
{
    for (var i = 0; i < v.Length; i += 1)
        v[i] *= f;
}

Fixed<int, Size> Squares()
{
    Fixed<int, Size> r;
    for (var i = 0; i < r.Length; i += 1)
        r[i] = i * i;
    return r;
}

T First<T>(Fixed<T, 2> pair)
{
    return pair[0];
}

int Main()
{
    Fixed<int, 16> buffer;
    buffer[3] = 7;
    buffer[^1] = 9;
    Console.WriteLine(buffer.Length.ToString() + " " + buffer[3].ToString() + " " + buffer[15].ToString() + " " + buffer[0].ToString());

    Fixed<float, 3> p = [1, 2, 3];
    var q = p;                 // a copy
    q[0] = 10;
    Scale(ref p, 2);
    Console.WriteLine(Sum(p).ToString() + " " + Sum(q).ToString() + " " + p[0].ToString());

    var v = Vertex { };
    v.Pos = [1, 1, 1];
    v.Pos[2] = 5;
    v.Tags = ["a", "b"];
    var w = v;
    w.Tags[0] = "changed";
    Console.WriteLine(v.Pos[2].ToString() + " " + v.Tags[0] + " " + w.Tags[0] + " " + sizeof(Vertex).ToString());

    var sq = Squares();
    int[] heap = sq.ToArray();
    heap[1] = 100;
    Console.WriteLine(sq[1].ToString() + " " + heap[1].ToString() + " " + Squares()[3].ToString() + " " + sizeof(Fixed<int, 16>).ToString());

    int[] more = [5, 6];
    Fixed<int, 4> spread = [..more, 7, 8];
    Fixed<string, 2> names = ["x", "y"];
    Console.WriteLine(spread[0].ToString() + spread[3].ToString() + " " + First(names) + " " + First<int>([4, 5]).ToString());

    var list = List<Fixed<int, 2>>.Create();
    list.Add([1, 2]);
    list.Add([3, 4]);
    Console.WriteLine("list " + list.Get(1)[1].ToString());
    Nested();
    return 0;
}

struct Cell { string Name; int V; }
Optional<Fixed<int, 2>> Find(bool ok)
{
    if (ok)
    {
        Fixed<int, 2> r = [7, 8];
        return r;
    }
    return null;
}
void Nested()
{
    Fixed<Fixed<int, 2>, 2> m = [[1, 2], [3, 4]];
    m[1][0] = 30;
    var arr = new Fixed<int, 3>[2];
    arr[1][2] = 5;
    var d = default(Fixed<string, 2>);
    Fixed<Cell, 2> cells = [Cell { Name = "a", V = 1 }, Cell { Name = "b", V = 2 }];
    var cells2 = cells;
    cells2[0].Name = "z";
    int total = 0;
    foreach (var row in m)
    {
        foreach (var x in row)
            total += x;
    }
    string s = "";
    if (Find(true) is Fixed<int, 2> f)
        s = f[1].ToString();
    int[][] jagged = [[1], [2, 3]];
    Fixed<int, 2>[] pairs = [[1, 2], [3, 4]];
    Console.WriteLine("nested " + total.ToString() + " " + arr[1][2].ToString() + " " + (d[0] == null).ToString().ToLower() + " " + cells[0].Name + cells2[0].Name + " " + s + " " + jagged[1][1].ToString() + pairs[1][0].ToString());
}
