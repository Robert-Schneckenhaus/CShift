# demo-amiga-hw

Raster bars on the Amiga's custom chips, written in CShift: six colored bars move along sine curves over a dark blue
background. The program takes the machine over from the operating system, like a classic demo:

* the **copper** changes the background color (`COLOR00`) on every one of the 256 lines of the picture; its list lives
  in chip memory,
* once per frame, in the vertical blank, the program writes the new colors of the bars into that list,
* the positions come from [`FastTrig`](../docs/stdlib.md) (sine tables and fixed point: no floating point on a 68000).

It runs on every Amiga from the A500 (68000, 7 MHz, Kickstart 1.3) on, at 50 frames per second: a frame takes about
122,000 of the 141,800 cycles an A500 has per frame. The **left mouse button** ends it and gives the machine back to
the operating system.

```
demo-amiga-hw/
├── cshift.json        project file ("target": "m68k-amigaos")
├── src/
│   └── main.csh       the copper list and the bars
└── bin/               the Amiga executable (generated, not in git)
```

## Building

```
cshiftc build demo-amiga-hw        ->  demo-amiga-hw/bin/demo-amiga-hw
```

The target `m68k-amigaos` selects CShift's own 68000 backend: no clang, no Amiga toolchain and no NDK are needed
(see [../docs/amiga.md](../docs/amiga.md)).

## Running

Copy `bin/demo-amiga-hw` to the Amiga (a hard disk folder in an emulator such as FS-UAE or WinUAE works) and start it
from the Shell:

```
demo-amiga-hw          runs until the left mouse button is pressed
demo-amiga-hw 500      runs for 500 frames (10 seconds)
```

## How it works

* `Hardware.AllocChip` gets chip memory for the copper list; the list is a WAIT and a MOVE per line (plus a WAIT for
  line 256, where the vertical position wraps around in 8 bits).
* `Hardware.TakeOver` stops the operating system (Forbid, its view, DMA and interrupts), `Hardware.StartCopper`
  starts the list; `Hardware.Restore` gives everything back.
* Per frame: `Hardware.WaitVBlank`, then the lines of the old bars get their background color back, and the new bars
  are drawn: 15 lines each, brightest in the middle.

`Amiga.Hardware` is described in [../docs/amiga.md](../docs/amiga.md#the-custom-chips-amigahardware).
