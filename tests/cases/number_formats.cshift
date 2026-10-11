// Number formats: ToString("F2") and $"{x:F2}", alignment $"{x,8}". Floating point values are formatted from their
// exact value, rounded half away from zero; the text does not depend on the platform.
// expect-exit: 0
// expect-stdout: D |00042|-0042|7|
// expect-stdout: X |FF|00ff|FFFFFFFF|FF|FFFFFFFFFFFFFFFF|
// expect-stdout: B |00000101|11111111|
// expect-stdout: F |3.14|3.142|3|0.13|3|-2|0.00|1234.50|12.00|
// expect-stdout: N |1,234,567|1,234,567.89|-999.00|0.50|
// expect-stdout: E |1.23E+003|1.234500e+003|0.00E+000|-4.9E-324|1E+308|
// expect-stdout: P |25.6 %|50.00 %|
// expect-stdout: G |0.1|0.1|42|
// expect-stdout: exact |0.1000000000000000055511151231257827021181583404541015625|0.10000000149011611938|
// expect-stdout: big |179,769,313,486,231,570,814,527,423,731,704,356,798,070,567,525,844,996,598,917,476,803,157,260,780,028,538,760,589,558,632,766,878,171,540,458,953,514,382,464,234,321,326,889,464,182,768,467,546,703,537,516,986,049,910,576,551,282,076,245,490,090,389,328,944,075,868,508,455,133,942,304,583,236,903,222,948,165,808,559,332,123,348,274,797,826,204,144,723,168,738,177,180,919,299,881,250,404,026,184,124,858,368|
// expect-stdout: minmax |-9223372036854775808|18446744073709551615|8000000000000000|
// expect-stdout: interp |  3.14|3.14  |    42|x   |0042|a:b|3|
// expect-stdout: special |inf|-inf|nan|

using System;

int Main()
{
    int n = 42;
    Console.WriteLine("D |" + n.ToString("D5") + "|" + (-n).ToString("D4") + "|" + 7.ToString("D") + "|");
    uint8 b = 255;
    int64 minusOne = -1;
    Console.WriteLine("X |" + 255.ToString("X") + "|" + 255.ToString("x4") + "|" + (-1).ToString("X") + "|" + b.ToString("X") + "|" +
                      minusOne.ToString("X") + "|");
    int8 m = -1;
    Console.WriteLine("B |" + 5.ToString("B8") + "|" + m.ToString("B") + "|");
    Console.WriteLine("F |" + 3.14159.ToString("F2") + "|" + 3.14159.ToString("F3") + "|" + 3.14159.ToString("F0") + "|" +
                      0.125.ToString("F2") + "|" + 2.5.ToString("F0") + "|" + (-1.5).ToString("F0") + "|" + (-0.001).ToString("F2") + "|" +
                      1234.5.ToString("F") + "|" + 12.ToString("F") + "|");
    Console.WriteLine("N |" + 1234567.ToString("N0") + "|" + 1234567.891.ToString("N2") + "|" + (-999).ToString("N") + "|" + 0.5.ToString("N") + "|");
    Console.WriteLine("E |" + 1234.5.ToString("E2") + "|" + 1234.5.ToString("e") + "|" + 0.0.ToString("E2") + "|" + (-5e-324).ToString("E1") + "|" +
                      1e308.ToString("E0") + "|");
    Console.WriteLine("P |" + 0.256.ToString("P1") + "|" + 0.5.ToString("P") + "|");
    float f = 0.1f;
    Console.WriteLine("G |" + 0.1.ToString("G") + "|" + f.ToString("G") + "|" + 42.ToString("G") + "|");
    Console.WriteLine("exact |" + 0.1.ToString("F55") + "|" + f.ToString("F20") + "|");
    Console.WriteLine("big |" + double.MaxValue.ToString("N0") + "|");
    int64 lo = int64.MinValue;
    uint64 hi = uint64.MaxValue;
    Console.WriteLine("minmax |" + lo.ToString("D") + "|" + hi.ToString("D") + "|" + lo.ToString("X") + "|");
    double pi = 3.14159;
    string key = "x";
    bool yes = true;
    Console.WriteLine($"interp |{pi,6:F2}|{pi,-6:F2}|{n,6}|{key,-4}|{n:D4}|{(yes ? "a" : "b")}:{"b"}|{yes ? 3 : 4}|");
    double zero = 0.0;
    Console.WriteLine("special |" + (1.0 / zero).ToString("F2") + "|" + (-1.0 / zero).ToString("N") + "|" + (zero / zero).ToString("E") + "|");
    return 0;
}
