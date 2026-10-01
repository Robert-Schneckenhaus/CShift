# demo-amiga-gfx

Bouncing balls on the Amiga's custom chips, written in CShift with `Amiga.Screen` and the blitter
([stdlib/amiga/graphics.csh](../stdlib/amiga/graphics.csh)): eight balls fall and bounce over a tiled floor, a ship (a
hardware sprite) flies along a sine curve, the sky is colored line by line by the copper.

* a **screen** of 320 x 256 pixels with 16 colors and **double buffering**: the program draws into one bitmap while
  the other is shown, `Screen.Swap` exchanges them in the vertical blank,
* the **background** (rectangles, lines and text in the system font) is drawn once into a bitmap of its own,
* per frame the **blitter** copies the background back where the balls were two frames ago (`Bitmap.Copy`) and draws
  the balls at their new places, only where their mask is set (`Bitmap.DrawMasked`: a "bob"),
* a **sprite** (`Sprite.Create` from text, `Screen.ShowSprite`, `Sprite.MoveTo`),
* the **copper** changes color 0 every 8 lines (`Screen.Copper.Wait`, `Screen.Copper.Color`).

It runs on every Amiga from the A500 (68000, 7 MHz, Kickstart 1.3) on, at 50 frames per second. The **left mouse
button** ends it and gives the machine back to the operating system.

```
demo-amiga-gfx/
├── cshift.json        project file ("target": "m68k-amigaos")
├── src/
│   └── main.csh       the background, the balls and the sprite
└── bin/               the Amiga executable (generated, not in git)
```

## Building

```
cshiftc build demo-amiga-gfx        ->  demo-amiga-gfx/bin/demo-amiga-gfx
```

No clang, no Amiga toolchain and no NDK are needed (see [../docs/amiga.md](../docs/amiga.md)).

## Running

Copy `bin/demo-amiga-gfx` to the Amiga (a hard disk folder in an emulator such as FS-UAE or WinUAE works) and start it
from the Shell:

```
demo-amiga-gfx          runs until the left mouse button is pressed
demo-amiga-gfx 500      runs for 500 frames (10 seconds)
```

The graphics functions are described in [../docs/amiga.md](../docs/amiga.md#graphics-amigascreen-bitmap-the-blitter-and-sprites).
