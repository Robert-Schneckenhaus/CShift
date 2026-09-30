// FastTrig: table based sin/cos/tan/cot/sec/csc/atan2 with 1024 angle steps and fixed point results.
// expect-stdout: sin 0 11585 16384 0 -16384 -16384
// expect-stdout: cos 16384 0 -16384 16384
// expect-stdout: tan 0 65536 2147483647 -65536 65536
// expect-stdout: cot 2147483647 65536 0
// expect-stdout: sec 65536 92682 2147483647 -65536
// expect-stdout: csc 2147483647 65536
// expect-stdout: atan2 0 128 256 384 512 640 768 896 0 0
// expect-stdout: deg 256 -256 85 1024 90 0 359 30
// expect-stdout: circle 100 0 0 100 -100 0 71 71
// expect-stdout: maxerr ok

using System;

int Main()
{
    Console.WriteLine("sin " + FastTrig.Sin(0).ToString() + " " + FastTrig.Sin(128).ToString() + " " + FastTrig.Sin(256).ToString() + " " +
        FastTrig.Sin(512).ToString() + " " + FastTrig.Sin(768).ToString() + " " + FastTrig.Sin(-256).ToString());
    Console.WriteLine("cos " + FastTrig.Cos(0).ToString() + " " + FastTrig.Cos(256).ToString() + " " + FastTrig.Cos(512).ToString() + " " +
        FastTrig.Cos(2147483647).ToString());
    Console.WriteLine("tan " + FastTrig.Tan(0).ToString() + " " + FastTrig.Tan(128).ToString() + " " + FastTrig.Tan(256).ToString() + " " +
        FastTrig.Tan(384).ToString() + " " + FastTrig.Tan(640).ToString());
    Console.WriteLine("cot " + FastTrig.Cot(0).ToString() + " " + FastTrig.Cot(128).ToString() + " " + FastTrig.Cot(256).ToString());
    Console.WriteLine("sec " + FastTrig.Sec(0).ToString() + " " + FastTrig.Sec(128).ToString() + " " + FastTrig.Sec(256).ToString() + " " +
        FastTrig.Sec(512).ToString());
    Console.WriteLine("csc " + FastTrig.Csc(0).ToString() + " " + FastTrig.Csc(256).ToString());
    Console.WriteLine("atan2 " + FastTrig.Atan2(0, 5).ToString() + " " + FastTrig.Atan2(7, 7).ToString() + " " + FastTrig.Atan2(3, 0).ToString() + " " +
        FastTrig.Atan2(9, -9).ToString() + " " + FastTrig.Atan2(0, -1).ToString() + " " + FastTrig.Atan2(-4, -4).ToString() + " " +
        FastTrig.Atan2(-2147483647 - 1, 0).ToString() + " " + FastTrig.Atan2(-100000, 100000).ToString() + " " + FastTrig.Atan2(0, 0).ToString() + " " +
        FastTrig.Atan2(-1, 2147483647).ToString());
    Console.WriteLine("deg " + FastTrig.FromDegrees(90).ToString() + " " + FastTrig.FromDegrees(-90).ToString() + " " + FastTrig.FromDegrees(30).ToString() + " " +
        FastTrig.FromDegrees(360).ToString() + " " + FastTrig.ToDegrees(256).ToString() + " " + FastTrig.ToDegrees(1024).ToString() + " " +
        FastTrig.ToDegrees(-3).ToString() + " " + FastTrig.ToDegrees(85).ToString());
    int r = 100;
    int a = FastTrig.FromDegrees(45);
    Console.WriteLine("circle " + ((r * FastTrig.Cos(0)) >> 14).ToString() + " " + ((r * FastTrig.Sin(0)) >> 14).ToString() + " " +
        ((r * FastTrig.Cos(256)) >> 14).ToString() + " " + ((r * FastTrig.Sin(256)) >> 14).ToString() + " " +
        ((r * FastTrig.Cos(512)) >> 14).ToString() + " " + ((r * FastTrig.Sin(512)) >> 14).ToString() + " " +
        ((r * FastTrig.Cos(a) + 8192) >> 14).ToString() + " " + ((r * FastTrig.Sin(a) + 8192) >> 14).ToString());

    // against the double functions: sin/cos within half a unit of 1.14, atan2 within one step
    bool ok = true;
    for (var i = 0; i < 1024; i += 1)
    {
        double rad = (double)i * Math.Tau / 1024.0;
        if (Math.Abs((double)FastTrig.Sin(i) - Math.Sin(rad) * 16384.0) > 0.5 || Math.Abs((double)FastTrig.Cos(i) - Math.Cos(rad) * 16384.0) > 0.5)
            ok = false;
        int x = (int)(Math.Cos(rad) * 10000.0);
        int y = (int)(Math.Sin(rad) * 10000.0);
        int d = (FastTrig.Atan2(y, x) - i) & FastTrig.Mask;
        if (d > 1 && d < 1023)
        {
            ok = false;
            Console.WriteLine("atan2 " + i.ToString() + " -> " + FastTrig.Atan2(y, x).ToString());
        }
    }
    Console.WriteLine(ok ? "maxerr ok" : "maxerr BAD");
    return 0;
}
