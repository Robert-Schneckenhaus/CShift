# The Amiga: the m68k backend

CShift programs run on the Amiga (68000 and up, AmigaOS 1.3 and later). For them the compiler has its own backend:
it turns the IR into 68000 code, assembles it and writes an AmigaOS executable itself. LLVM, clang and an Amiga
cross toolchain are not needed (libclang only for importing C headers of the NDK).

```
cshiftc --target m68k-amigaos hello.csh -o hello        # an AmigaOS executable (hunk format)
```

```json
{
	"name": "demo",
	"sources": ["src"],
	"target": "m68k-amigaos",
	"ndk": "../NDK3.2"
}
```

Three demos show what is possible: [demo-amiga-hw](../demo-amiga-hw/README.md) (copper raster bars on the custom chips,
50 frames per second on an A500), [demo-amiga-gfx](../demo-amiga-gfx/README.md) (bouncing balls with the blitter, double
buffering, a sprite and text) and [demo-amiga-ndk](../demo-amiga-ndk/README.md) (a rotating cube in an Intuition
window, written against the NDK 3.2).

## Choosing the backend

| Option | cshift.json | Meaning |
|---|---|---|
| `--backend llvm` | `"backend": "llvm"` | LLVM IR, compiled and linked by clang (the default for all targets but AmigaOS) |
| `--backend m68k` | `"backend": "m68k"` | CShift's own 68000 code generator (the default for `m68k-amigaos`) |
| `--ndk <dir>` | `"ndk": "<dir>"` | the AmigaOS NDK (also the environment variable `CSHIFT_NDK`); a path in cshift.json is relative to it |
| `--emit-asm` | – | write the assembly (`.s`, GNU syntax) instead of an executable; a comment before every function names it (`\| function: Name(params)`) |
| `-g` | `"debug": true` | write the names of the functions and globals into the executable (HUNK_SYMBOL), for debuggers and the profiler; the code stays the same |
| `-O0` … `-O3` | `"optimize": 0` … `3` | `-O2` (the default) and `-O3` inline larger functions in loops: faster, but bigger; `-O1` only inlines functions that are not larger than their call (smaller programs, e.g. for floppy disks); `-O0` inlines nothing |

The m68k backend accepts m68k targets only:

* `m68k-amigaos`: an AmigaOS executable (hunk format), with its own startup code and C library.
* `m68k-linux-gnu`: a program for m68k Linux, linked statically by a cross `gcc` (`m68k-linux-gnu-gcc`, or `--cc`),
  or an ELF object (`-c`). It runs under `qemu-m68k`. This is how the backend is tested: the test suite runs with it
  (`CSHIFT_TARGET=m68k-linux-gnu CSHIFT_BACKEND=m68k tests/run_tests.sh`, see *Testing Amiga programs*).

## What a program can use

The whole language and the standard library work, with these differences:

* **No threads.** `Thread`, `Mutex<T>` and `SharedPtr<T>` need pthreads, which AmigaOS does not have. A program that
  uses them does not link: the compiler names the missing functions.
* **Floating point in software.** `double` and `float` are computed by `stdlib/m68k/softfloat.csh` (IEEE 754, exact
  rounding); `Math` (`Sqrt`, `Sin`, `Exp`, `Pow`, ...) by `stdlib/m68k/math.csh` and `mathtrans.csh` (within 2 ULP of
  glibc). This works but is slow on a 68000: for graphics use integers, fixed point and
  [`FastTrig`](stdlib.md) (sine and cosine from tables).
* **The C library** (`stdlib/amiga/libc.csh`) is written on exec.library and dos.library: memory, `printf`, files,
  directories, `Process.GetEnv`, time, `Process.Run`. Functions that need a newer dos.library (environment
  variables, the current directory, the exit code of a command) check its version.
* **Only what is used.** An executable contains the functions of the program, the standard library and the C library
  that it calls, nothing else: the startup code and the runtime are taken in pieces as well. `printf`'s formatting
  (with the code for `double`) is only in a program that calls `printf` or formats floating point numbers;
  `Console.WriteLine` and the integer `ToString` do not need it.
* **The stack.** A program gets its own stack of 256 KB at startup (the stack of a CLI program is often only 4 KB).
* **`int` is 32 bits, pointers are 32 bits** (`nint`, `sizeof`, lengths). 64-bit integers work, in software.

## AmigaOS libraries from SFD files

The NDK describes every library in an SFD file: the offset of each function, the registers of its arguments, its C
prototype. CShift imports it like a C header:

```csharp
using Gfx from "graphics_lib.sfd";
using Intui from "intuition_lib.sfd";
using I from "intuition/intuition.h";   // structures, flags and tags come from the C headers

void* window = Intui.OpenWindowTags(null, I.WA_Width, 320, I.WA_Height, 200, I.TAG_DONE);
Gfx.SetAPen(rastPort, 1);
Gfx.Move(rastPort, 10, 10);
Gfx.Draw(rastPort, 100, 50);
```

* The SFD file is looked up next to the importing file, then in `<ndk>/SFD`.
* A call puts the arguments in the registers the SFD names and calls the library through its base in `a6`
  (`jsr -offset(a6)`). For the varargs versions (`OpenWindowTags`, ...) the arguments after the fixed ones stay on the
  stack as a tag list, and the last register gets its address.
* **The libraries that are used are opened when the program starts** (with version 0) and closed at its end; the
  program ends with a message if one cannot be opened. exec.library and dos.library are always there.
* Types: the integer typedefs of `exec/types.h` (`LONG`, `UWORD`, `BOOL`, ...) become their CShift types, pointers
  become `void*`, `CONST_STRPTR` becomes a string parameter (passed as a C string).
* C headers of the NDK: for amigaos targets `<ndk>/Include_H` is searched, and structs are laid out as on the Amiga
  (packed to 2 bytes).

## The custom chips: `Amiga.Hardware`

For demos and games that bypass the operating system (`stdlib/amiga/hardware.csh`, only for amigaos targets):

```csharp
using Amiga;

unsafe
{
    uint16* list = (uint16*)Hardware.AllocChip(1024);   // chip memory, cleared (null if there is none left)
    ...                                                  // write a copper list
    Hardware.TakeOver();                                 // the OS stops drawing; DMA and interrupts are ours
    Hardware.StartCopper(list);
    while (!Hardware.LeftMouseButton())
    {
        Hardware.WaitVBlank();                           // until the beam is below the picture (line 300)
        Hardware.Write(Custom.COLOR00, 0x0F00);
    }
    Hardware.Restore();                                  // the OS display, DMA and interrupts are back
    Hardware.FreeChip(list, 1024);
}
```

| Function | |
|---|---|
| `TakeOver()` / `Restore()` | take the machine from the OS (Forbid, the view, DMA, interrupts, the blitter) and give it back |
| `StartCopper(list)` | run a copper list (in chip memory) |
| `WaitVBlank()`, `RasterLine()` | wait for the vertical blank; the current line of the beam |
| `Write(reg, value)`, `Read(reg)`, `WriteLong(reg, address)`, `Register(reg)` | the custom chip registers (`Custom.COLOR00`, `DMACON`, `BPL1PTH`, ...), with volatile accesses |
| `LeftMouseButton()` | the left button (port 1) |
| `AllocChip(size)` / `FreeChip(memory, size)` | chip memory for copper lists, bitplanes, sprites and sounds |

## Graphics: `Amiga.Screen`, `Bitmap`, the blitter and sprites

On top of `Amiga.Hardware`, `stdlib/amiga/graphics.csh` has what a game or a demo draws with (low resolution PAL,
OCS/ECS, every Amiga from the A500 on). [demo-amiga-gfx](../demo-amiga-gfx/README.md) shows all of it.

```csharp
using Amiga;

Hardware.TakeOver();
if (Screen.Open(320, 256, 4, true) is Screen screen)   // 16 colors, double buffering
{
    screen.SetColor(1, 0xFFF);
    screen.Copper.Wait(100);                            // own copper instructions after the screen's setup
    screen.Copper.Color(0, 0x00F);                      // from line 100 on the background is blue
    screen.Show();
    while (!Hardware.LeftMouseButton())
    {
        Bitmap b = screen.Back;
        b.Clear();
        b.FillRect(10, 10, 100, 50, 2);
        b.DrawLine(0, 0, 319, 255, 3);
        b.DrawText(20, 100, "Hello, Amiga", 1);
        screen.Swap();                                  // Back is shown from the next frame on
    }
    Hardware.Restore();
    screen.Close();
}
```

| Type | |
|---|---|
| `Screen` | `Open(width, height, depth, doubleBuffer)` (width 128..320, a multiple of 16; height up to 256; 2..32 colors), `Front`/`Back` (the bitmaps), `SetColor(index, 0xRGB)`, `Show()`, `Swap()` (shows `Back`, waits for the vertical blank), `ShowSprite(n, sprite)`/`HideSprite(n)`, `Copper` (own instructions; `Copper.Reset()` removes them), `Close()` |
| `Bitmap` | `Create(width, height, depth)` (chip memory, `Free()`), `Width`, `Height`, `Depth`, `BytesPerRow`, `Plane(p)`; with the blitter: `Clear()`, `FillRect`, `DrawRect`, `Copy(source, sx, sy, x, y, w, h)`, `DrawMasked(source, mask, sx, sy, x, y, w, h)` (a "bob": only where the mask has a 1; `MakeMask()` makes it from the colors that are not 0); with the CPU: `SetPixel`, `GetPixel`, `DrawLine`, `DrawPattern(x, y, rows)` (pixels from strings), `DrawText(x, y, text, color)` |
| `Sprite` | a hardware sprite, 16 pixels wide, 3 colors: `Create(rows)` (`'1'`..`'3'`, others transparent), `MoveTo(x, y)`, `Free()` |
| `SystemFont` | the font of `DrawText` (Topaz 8 from the ROM, or the one of the preferences): `Height()`, `TextWidth(text)` |
| `CopperList` | a copper list of its own: `Create(n)`, `Move(register, value)`, `Color(index, rgb)`, `MovePointer`, `Wait(line)`, `Change(index, value)`, `Mark()`/`Reset()`, `Address()` for `Hardware.StartCopper` |
| `Blitter` | `Wait()`: until the blitter is done, before the CPU touches what it draws (the CPU functions of `Bitmap` wait themselves) |

* The blitter works in parallel with the CPU: a blitter function of `Bitmap` starts the blit and returns; the next one
  waits for it. It needs `Hardware.TakeOver()` (the program owns the blitter then).
* Drawing is clipped to the bitmap. `Copy` uses the blitter when `x % 16 >= sx % 16` (e.g. the same positions in a
  background bitmap, or sources at multiples of 16), otherwise the CPU; `DrawMasked` needs `sx % 16 == 0` and uses the
  CPU when the shape is not completely inside from left to right.
* Coordinates of sprites and copper waits count from the top left corner of the picture (the standard PAL display
  window: raster line 44, horizontal position 0x81). Sprites 0/1 use the colors 17-19, 2/3 21-23, 4/5 25-27, 6/7 29-31.
* Bitmaps are planar: one bitplane after the other (`Plane(p)`), 1 bit per pixel each.

## How the backend works

The sources are in [selfhost/src/M68k](../selfhost/src/M68k); the compiler writes its IR as always, and the backend
reads it back:

```
IR (text) ─▶ IrReader ─▶ Prepare (inlining, folding) ─▶ Regalloc ─▶ Gen (68000 assembly) ─▶ Peephole ─▶ Asm ─▶ Hunk / Elf
```

* **IrReader.csh** reads the LLVM IR the front end writes (types, constants, functions, instructions).
* **Prepare.csh, Inline.csh**: small functions are inlined: up to 6 instructions everywhere; with `-O2`/`-O3` in loops
  also those whose code that runs is small (what costs nothing once inlined is not counted: the panics of failed
  checks, variables, addresses), the deepest loops first, while the function grows by at most 240 instructions.
  Variables written once become their value (where the store dominates every load); the length of an array or string
  is read once per value (a check that an earlier one dominates uses its length; in a loop, the length of an array
  from outside of it is read before the loop); constants are folded; `&&` and `||` in a condition become branches (no
  `bool` is made) and a branch on `!c` branches on `c` with its targets swapped; dead code is removed; a pointer that is
  only used by one load or store becomes an addressing mode (`(d16,An)`, `(d8,An,Dn.l)`, with the register of a 32-bit
  index as it is).
* **Facts.csh**: what the IR knows at a place. A load of a variable that was stored or loaded before on every way to it
  (no store on the ways from there) is that value; the same computation of the same values twice is computed once; a
  block whose only predecessor branched on a comparison knows its outcome (so does every block it dominates), so the
  same comparison there is a constant: the bounds check of `data[i] ^= x` is made once. Checked additions and
  subtractions that cannot overflow become plain ones and lose their panics: `i + 1` where `i < n` or `i < length` is
  known, `length - 1`, and operations whose operands have small ranges (`(d << 4) + d + 87` with `d = x & 0xffff`).
  Branches on constants go to their target, unreachable blocks are removed, and a block that only one block branches
  to is joined to it.
* **Regalloc.csh**: a linear scan over live intervals; values, variables and parameters get `d4`-`d7` and `a2`-`a5` by
  their uses, weighted by loop depth; a value loaded from a variable shares its register (also when the variable is
  written after the value's last use, in a block where it ends); a value that only the next instruction uses, as its
  first operand, stays in `d0` and needs neither a register nor its slot.
* **Gen.csh** writes the code: 16-bit fast paths for multiplication and division (`muls.w`, `divs.w`), overflow checks
  fused with their branch (`bvs`; the code of the panics at the end of the function), absolute addresses for constant
  pointers (custom chip registers), division by constants (shifts for powers of two), `asl` for checked products by
  powers of two, the length of a string or array for its bounds check without a call, only the registers that are
  used are saved.
* **Peephole.csh** simplifies the assembly (for example a register copied back right after it was copied, or
  `moveq #0` before loading a byte or word instead of masking it afterwards); **Asm.csh** encodes it (68000 only, branches made short where they fit);
  **Hunk.csh** writes the AmigaOS executable, **Elf.csh** an ELF object.
* **AmigaRuntime.csh, Runtime.csh**: the startup code, the library stubs, `printf`, `memcpy` & co, and the helpers for
  32/64-bit multiplication and division. `memcpy`, `memmove` and `memset` go through *jump towers*: the move is
  unrolled 16 times and the loop jumps into the middle of it, so that the first pass does the remainder and every
  further pass 16 moves for one `subq`/`bcc` - longs where the addresses allow it (both even, or both odd after one
  byte), bytes otherwise. A copy of 64 KB takes about 6 cycles per byte instead of 44, a fill 3.4 instead of 38. **Chunks.csh** cuts them into pieces at their labels; only the pieces that
  the program reaches are written.

The calling convention is the one of GCC for m68k: arguments on the stack, results in `d0` (and `d1`), `a0` as well
for pointers; `d2`-`d7` and `a2`-`a6` are kept.

## Testing Amiga programs

* **vamos** ([amitools](https://github.com/cnvogelg/amitools)) runs AmigaOS command-line programs on the PC without an
  Amiga ROM: good for everything but the hardware. `vamos -v` also prints the number of CPU cycles, a measure of speed.
  (`pip install amitools "machine68k<0.4"`: amitools 0.8 does not run with machine68k 0.4.) When `vamos` is
  installed, `tests/run_tests.sh` runs [tests/amiga/memory.csh](../tests/amiga/memory.csh) with it.
* **FS-UAE** (or WinUAE) with an A500 configuration and a Kickstart ROM (or the free AROS ROM) for graphics and the
  custom chips.
* **The test suite with the backend:** `CSHIFT_TARGET=m68k-linux-gnu CSHIFT_BACKEND=m68k CSHIFT_SKIP_SELFHOST=1
  tests/run_tests.sh` compiles the programs of the tests with the 68000 backend for m68k Linux and runs them under
  `qemu-m68k` (Debian/Ubuntu: `qemu-user gcc-m68k-linux-gnu libc6-dev-m68k-cross`); the CI does that too. The cases
  with threads are left out (`// skip-target: m68k`): the backend has no atomic operations, AmigaOS has no threads.

### Where the time goes: tools/amiga/profile.py

[tools/amiga/profile.py](../tools/amiga/profile.py) runs a program under vamos with the instruction trace and counts
the executed instructions of every function. Build the program with `-g` (the names of the functions):

```
cshiftc build AmbermoonPack --target m68k-amigaos -g -o AmbermoonPack
python3 tools/amiga/profile.py AmbermoonPack UNPACK Floors.amb out
python3 tools/amiga/profile.py --annotate Lob.Decompress AmbermoonPack UNPACK Floors.amb out
```

```
4216290 instructions, 41572088 cycles (5.86 s on an A500)
instructions  share   entries  function
     1457505  34.6%        14  Ambermoon.Data.Legacy.Compression.Lob.Decompress(ref ...DataReader,uint32)
     1453547  34.5%        17  Ambermoon.Data.Legacy.Compression.JH.Crypt(uint8[],uint16,int32)
      731387  17.3%     17009  Ambermoon.Data.Legacy.Serialization.DataReader.ReadByte()
```

*entries* counts how often the function was entered (its calls). `--annotate NAME` lists the instructions of the
functions whose name contains NAME with how often each ran: the loops that matter, in the code the backend wrote. The
trace is slow (about 30,000 instructions per second); `vamos -v` alone gives the cycles quickly.
