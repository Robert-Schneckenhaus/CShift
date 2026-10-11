// demo-amiga-hw: raster bars on the Amiga's custom chips, without the operating system (runs on every Amiga, from the
// A500 with a 68000 on).
//
// The copper changes the background color (COLOR00) on every line of the picture; the program takes the machine over
// (Amiga.Hardware), builds the copper list in chip memory and moves six bars along sine curves (FastTrig: tables, no
// floating point) once per frame, in the vertical blank. The left mouse button ends it (or the number of frames given
// as the argument: "demo-amiga-hw 500").

using System;
using Amiga;

const int Lines = 256;               // the visible lines of a PAL picture
const int FirstLine = 0x2C;          // the first of them (the standard display window)
const int BarCount = 6;
const int BarHeight = 15;
const int ListBytes = 4 + Lines * 8 + 8; // BPLCON0, a WAIT and a MOVE per line, the WAIT for line 256, the end

// the dark blue background of a line
uint16 Background(int line)
{
    return (uint16)(1 + line / 48);
}

// the color of a bar at brightness b (1..15)
uint16 BarColor(int bar, int b)
{
    switch (bar)
    {
    case 0:
        return (uint16)(b << 8);                 // red
    case 1:
        return (uint16)((b << 8) | ((b / 2) << 4)); // orange
    case 2:
        return (uint16)((b << 8) | (b << 4));    // yellow
    case 3:
        return (uint16)(b << 4);                 // green
    case 4:
        return (uint16)((b << 4) | b);           // cyan
    default:
        return (uint16)((b << 8) | b);           // magenta
    }
}

int Main(string[] args)
{
    int frames = -1;
    if (args.Length > 0 && args[0].ParseInt() is int n)
        frames = n;
    Console.WriteLine("CShift raster bars - press the left mouse button to quit");

    unsafe
    {
        uint16* list = (uint16*)Hardware.AllocChip(ListBytes);
        if (list == null)
        {
            Console.WriteLine("not enough chip memory");
            return 20;
        }

        // the copper list: no bitplanes, then for every line: WAIT for it, MOVE its color to COLOR00
        var colorAt = new int[Lines];
        int w = 0;
        list[w] = 0x0100;       // MOVE BPLCON0: no bitplanes (only the background color is shown)
        list[w + 1] = 0x0200;
        w += 2;
        for (var i = 0; i < Lines; i += 1)
        {
            int y = FirstLine + i;
            if (y == 256)
            {
                list[w] = 0xFFDF; // WAIT for the end of line 255: the lines below count from 0 again
                list[w + 1] = 0xFFFE;
                w += 2;
            }
            list[w] = (uint16)(((y & 0xFF) << 8) | 0x07); // WAIT line y
            list[w + 1] = 0xFFFE;
            list[w + 2] = 0x0180;                          // MOVE COLOR00
            list[w + 3] = Background(i);
            colorAt[i] = w + 3;
            w += 4;
        }
        list[w] = 0xFFFF; // the end: wait for a position that never comes
        list[w + 1] = 0xFFFE;

        if (!Hardware.TakeOver())
        {
            Console.WriteLine("cannot open graphics.library");
            Hardware.FreeChip(list, ListBytes);
            return 20;
        }
        Hardware.StartCopper(list);

        var top = new int[BarCount];
        for (var k = 0; k < BarCount; k += 1)
            top[k] = 0;
        int phase = 0;
        while (!Hardware.LeftMouseButton() && frames != 0)
        {
            Hardware.WaitVBlank();
            // the bars of the last frame go, the new ones are drawn (the last one on top)
            for (var k = 0; k < BarCount; k += 1)
            {
                for (var j = 0; j < BarHeight; j += 1)
                    list[colorAt[top[k] + j]] = Background(top[k] + j);
            }
            for (var k = 0; k < BarCount; k += 1)
            {
                int center = 120 + ((100 * FastTrig.Sin(phase + k * 40)) >> 14) + ((12 * FastTrig.Cos(phase * 3 + k * 170)) >> 14);
                top[k] = center - BarHeight / 2;
                for (var j = 0; j < BarHeight; j += 1)
                {
                    int b = 15 - (j > 7 ? j - 7 : 7 - j) * 2; // bright in the middle
                    list[colorAt[top[k] + j]] = BarColor(k, b);
                }
            }
            phase += 5;
            if (frames > 0)
                frames -= 1;
        }

        Hardware.Restore();
        Hardware.FreeChip(list, ListBytes);
    }
    Console.WriteLine("bye");
    return 0;
}
