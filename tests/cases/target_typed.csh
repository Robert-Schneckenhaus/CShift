// Target-typed integer arithmetic: with a target of an integer type (a typed variable, an assignment, a return value,
// a field, an array element, a constant) the arithmetic is computed in that type when all operands fit it; without a
// target (var, a method call on the result) the usual rules apply (int32 for the small types).
// expect-stdout: r=250 w=10000 v=250 x=3 m=195 k=107
// expect-stdout: field=100 inc=201 try=201 arr=101
// expect-stdout: prod=4000000000 u=255 sh=5 call=250
// expect-stdout: const 6 250 -6 12
using System;

struct P { uint8 X; }

uint8 Inc(uint8 v) { return v + 1; }
Error<uint8> TryInc(uint8 v) { return v + 1; }

const uint8 A = 5;
const uint8 B = A + 1;
const uint8 C = ~A;
const int8 D = -(int8)3 * 2;

int Main()
{
    uint8 a = 200;
    uint8 b = 50;
    uint8 r = a + b;
    int32 w = a * b;                 // computed in int32: 10000
    var v = a + b;                   // no target: int32
    uint8 x = 1 + 2;                 // two literals are combined when compiling
    int8 n = -5;
    int16 m = a + n;                 // uint8 and int8 fit int16
    uint8 k = (a >> 2) + (b & 7) + ~a;
    Console.WriteLine("r=" + r.ToString() + " w=" + w.ToString() + " v=" + v.ToString() + " x=" + x.ToString() +
                      " m=" + m.ToString() + " k=" + k.ToString());

    var p = P { X = a / 2 };
    uint8[] arr = new uint8[] { a - b, b * 2 };
    arr[0] = arr[1] + 1;
    uint8 t = 0;
    if (TryInc(a) is uint8 tv)
        t = tv;
    Console.WriteLine("field=" + p.X.ToString() + " inc=" + Inc(a).ToString() + " try=" + t.ToString() + " arr=" + arr[0].ToString());

    int32 i1 = 2000000000;
    int64 prod = i1 * 2;             // computed in int64: no overflow
    uint8 u = 250;
    u += 5;
    int16 sh = 3;
    sh += i1 / 1000000000;           // int32 result, narrowed (checked) to int16
    Console.WriteLine("prod=" + prod.ToString() + " u=" + u.ToString() + " sh=" + sh.ToString() + " call=" + (a + b).ToString());

    const uint8 L = A * 2 + 2;
    Console.WriteLine("const " + B.ToString() + " " + C.ToString() + " " + D.ToString() + " " + L.ToString());
    return 0;
}
