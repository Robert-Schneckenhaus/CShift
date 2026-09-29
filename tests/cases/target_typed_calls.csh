// Target-typed integer arithmetic in arguments and in the branches of ?: (see target_typed.csh). An argument is
// computed in the parameter type when all candidates with that many parameters agree on it; with overloads that differ
// there the usual rules decide (int32).
// expect-stdout: cond 120 101
// expect-stdout: args 120 2000 61 101 105
// expect-stdout: overload i32 120
using System;

struct Acc
{
    uint8 Total;
    void Add(uint8 v) { Total += v; }
    static uint8 Half(uint8 v) { return v / 2; }
}

uint8 Pick(uint8 v) { return v; }
int16 Wide(int16 v) { return v; }
string Over(uint8 v) { return "u8 " + v.ToString(); }
string Over(int32 v) { return "i32 " + v.ToString(); }

int Main()
{
    uint8 a = 100;
    uint8 b = 20;
    bool c = a > b;
    uint8 r = c ? a + b : b - 1;
    uint8 s = (c ? a : b) + 1;
    Console.WriteLine("cond " + r.ToString() + " " + s.ToString());

    var acc = Acc { Total = 0 };
    acc.Add(a + 1);
    var list = List<uint8>.Create();
    list.Add(a + 5);
    Console.WriteLine("args " + Pick(a + b).ToString() + " " + Wide(a * b).ToString() + " " + Acc.Half(b + b + b + 62).ToString() +
                      " " + acc.Total.ToString() + " " + list.Get(0).ToString());
    Console.WriteLine("overload " + Over(a + b));
    return 0;
}
