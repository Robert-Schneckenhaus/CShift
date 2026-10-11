// Binary numeric promotion like in C#: uint8, uint16 and char meet uint32 and uint64 as that type (they are not
// widened to int32 first); the small signed types still widen to int32, and with uint32 to int64.
// expect-stdout: unsigned promotion ok
using System;

int Slot(int parent, uint8 key, int shift)
{
    // no target type inside the cast: computed in uint32, the product wraps around (Fibonacci hashing)
    return (int)(unchecked(((uint32)parent * 256u + key) * 2654435769u) >> shift);
}

int Main()
{
    uint32 u = 4000000000u;
    uint8 b = 200;
    uint16 w = 60000;
    char c = 'A';

    // 'var' takes the promoted type: uint32, not int64
    var x = u + b;
    uint32 y = x;
    var p = u + w;
    uint32 q = p;
    var r = c + u;
    uint32 s = r;
    if (y != 4000000200u || q != 4000060000u || s != 4000000065u)
        return 1;

    // uint64 with a small unsigned type: uint64 (was an error)
    uint64 big = 18000000000000000000ul;
    var t = big + b;
    uint64 t2 = t;
    var t3 = w + big;
    if (t2 != 18000000000000000200ul || t3 != 18000000000000060000ul)
        return 2;

    // comparisons and the other operators
    if (!(u > b) || u == w || (u & b) != 0u || (u | b) != 4000000200u || (b ^ u) != 4000000200u)
        return 3;
    if (u / w != 66666u || u % b != 0u || u - b != 3999999800u)
        return 4;

    // a small signed type with uint32 still is int64 (C#: long)
    int8 n = -1;
    var m = u + n;
    int64 m2 = m;
    if (m2 != 3999999999)
        return 5;

    // the hash of a MatchTrie: the same slots as with 32-bit arithmetic
    if (Slot(0, 0, 20) != 0 || Slot(1, 0, 20) != 887 || Slot(300, 7, 20) != 1378)
        return 6;

    // shifts keep the type of the left operand
    var sh = (u >> 4) + b;
    uint32 sh2 = sh;
    if (sh2 != 250000200u)
        return 7;

    Console.WriteLine("unsigned promotion ok");
    return 0;
}
