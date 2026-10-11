// Memory.VolatileRead/VolatileWrite (unsafe): loads and stores that are never merged, moved or left out (hardware
// registers, memory changed by an interrupt).
// expect-stdout: volatile 7 65535 true 2.5 -3
using System;

enum Mode : uint8 { Off, On }

int Main()
{
    unsafe
    {
        int cell = 0;
        int* p = &cell;
        for (var i = 0; i < 8; i += 1)
            Memory.VolatileWrite(p, i);
        uint16 reg = 0;
        Memory.VolatileWrite(&reg, 65535);
        bool flag = false;
        Memory.VolatileWrite(&flag, true);
        double d = 0;
        Memory.VolatileWrite(&d, 2.5);
        Mode m = Mode.Off;
        Memory.VolatileWrite(&m, Mode.On);
        int8 small = 0;
        Memory.VolatileWrite(&small, -3);
        Console.WriteLine("volatile " + Memory.VolatileRead(p).ToString() + " " + Memory.VolatileRead(&reg).ToString() + " " +
                          Memory.VolatileRead(&flag).ToString().ToLower() + " " + Memory.VolatileRead(&d).ToString() + " " +
                          Memory.VolatileRead(&small).ToString());
        if (Memory.VolatileRead(&m) != Mode.On)
            return 1;
    }
    return 0;
}
