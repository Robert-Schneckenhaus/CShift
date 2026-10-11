//! Programming the Amiga's custom chips directly (only for amigaos targets): taking the machine over from the
//! operating system and giving it back, waiting for the vertical blank, chip memory, the copper and the mouse button
//! ([Hardware]); bitmaps, the blitter, copper lists, sprites and a screen to draw on ([Screen], [Bitmap], [Blitter],
//! [CopperList], [Sprite]).
//!
//! ```
//! using Amiga;
//!
//! Hardware.TakeOver();                       // the OS stops drawing; DMA and interrupts are ours
//! Hardware.StartCopper(list);                // a copper list in chip memory (Hardware.AllocChip)
//! while (!Hardware.LeftMouseButton())
//! {
//!     Hardware.WaitVBlank();
//!     ...                                    // Hardware.Write(Custom.COLOR00, 0x0F00), ...
//! }
//! Hardware.Restore();                        // the OS display, DMA and interrupts are back
//! ```
//!
//! The registers are written with volatile accesses (`Memory.VolatileWrite`), so every write reaches the chips.

namespace Amiga;

using System;

extern "C" void __exec_Forbid();
extern "C" void __exec_Permit();
extern "C" int __exec_AllocMem(int size, int requirements);
extern "C" void __exec_FreeMem(void* memory, int size);
extern "C" void* __exec_OpenLibrary(char* name, int version);
extern "C" void __exec_CloseLibrary(void* library);
extern "C" void __gfx_LoadView(void* view);
extern "C" void __gfx_WaitTOF();
extern "C" void __gfx_OwnBlitter();
extern "C" void __gfx_DisownBlitter();
extern "C" void __gfx_WaitBlit();
extern "C" void __cs_amiga_set(int index, int value);

/// The custom chip registers: their offsets from `0xDFF000`, for [Hardware.Write], [Hardware.Read] and copper
/// lists ([CopperList.Move]).
enum Custom : int32
{
    /// DMA control (read): which DMA channels are on.
    DMACONR = 0x002,
    /// The vertical position of the beam, high bit (read; with [Hardware.RasterLine]).
    VPOSR = 0x004,
    /// The vertical and horizontal position of the beam (read).
    VHPOSR = 0x006,
    /// The counters of the mouse or joystick in port 0 (read).
    JOY0DAT = 0x00A,
    /// The counters of the mouse or joystick in port 1 (read).
    JOY1DAT = 0x00C,
    /// The enabled interrupts (read).
    INTENAR = 0x01C,
    /// The requested interrupts (read).
    INTREQR = 0x01E,
    /// Blitter control 0: the channels it uses, the minterm and the shift of A.
    BLTCON0 = 0x040,
    /// Blitter control 1: the shift of B, line mode, fill and descending mode.
    BLTCON1 = 0x042,
    /// The mask of the first word of channel A.
    BLTAFWM = 0x044,
    /// The mask of the last word of channel A.
    BLTALWM = 0x046,
    /// The address of the source C (a 32-bit pair, [Hardware.WriteLong]).
    BLTCPTH = 0x048,
    /// The address of the source B (a 32-bit pair).
    BLTBPTH = 0x04C,
    /// The address of the source A (a 32-bit pair).
    BLTAPTH = 0x050,
    /// The address of the destination D (a 32-bit pair).
    BLTDPTH = 0x054,
    /// The size of a blit (height * 64 + width in words); writing it starts the blitter.
    BLTSIZE = 0x058,
    /// The modulo of the source C: bytes skipped at the end of each row.
    BLTCMOD = 0x060,
    /// The modulo of the source B.
    BLTBMOD = 0x062,
    /// The modulo of the source A.
    BLTAMOD = 0x064,
    /// The modulo of the destination D.
    BLTDMOD = 0x066,
    /// The data of the source C (when its DMA is off).
    BLTCDAT = 0x070,
    /// The data of the source B (when its DMA is off).
    BLTBDAT = 0x072,
    /// The data of the source A (when its DMA is off).
    BLTADAT = 0x074,
    /// The address of the first copper list (a 32-bit pair, [Hardware.WriteLong]).
    COP1LCH = 0x080,
    /// The address of the second copper list (a 32-bit pair).
    COP2LCH = 0x084,
    /// Writing it restarts the copper at the first list.
    COPJMP1 = 0x088,
    /// Writing it restarts the copper at the second list.
    COPJMP2 = 0x08A,
    /// The upper left corner of the display window.
    DIWSTRT = 0x08E,
    /// The lower right corner of the display window.
    DIWSTOP = 0x090,
    /// The horizontal start of the bitplane data fetch.
    DDFSTRT = 0x092,
    /// The horizontal end of the bitplane data fetch.
    DDFSTOP = 0x094,
    /// DMA control (write): bit 15 ([DmaSet]) set switches the given channels on, clear switches them off.
    DMACON = 0x096,
    /// Enables (bit 15 set) or disables interrupts (write).
    INTENA = 0x09A,
    /// Requests (bit 15 set) or acknowledges interrupts (write).
    INTREQ = 0x09C,
    /// The address of bitplane 1, high word; the other planes follow every 4 bytes (`BPL1PTH + 4 * n`).
    BPL1PTH = 0x0E0,
    /// The address of bitplane 1, low word.
    BPL1PTL = 0x0E2,
    /// Bitplane control 0: the number of planes, hires, HAM, dual playfield, color.
    BPLCON0 = 0x100,
    /// Bitplane control 1: the horizontal scroll of the playfields.
    BPLCON1 = 0x102,
    /// Bitplane control 2: the priority of playfields and sprites.
    BPLCON2 = 0x104,
    /// The modulo of the odd bitplanes: bytes skipped at the end of each line.
    BPL1MOD = 0x108,
    /// The modulo of the even bitplanes.
    BPL2MOD = 0x10A,
    /// The address of the data of sprite 0, high word; the other sprites follow every 4 bytes.
    SPR0PTH = 0x120,
    /// The address of the data of sprite 0, low word.
    SPR0PTL = 0x122,
    /// Color register 0 (the background) as `0x0RGB`; the other 31 follow every 2 bytes.
    COLOR00 = 0x180,
    /// Color register 1 as `0x0RGB`.
    COLOR01 = 0x182,
}

/// The bit of [Custom.DMACON] that switches the given channels on (otherwise off).
const int DmaSet = 0x8000;
/// DMACON: all DMA (the master switch).
const int DmaMaster = 0x0200;
/// DMACON: the bitplanes.
const int DmaBitplanes = 0x0100;
/// DMACON: the copper.
const int DmaCopper = 0x0080;
/// DMACON: the blitter.
const int DmaBlitter = 0x0040;
/// DMACON: the sprites.
const int DmaSprites = 0x0020;

/// [Hardware.AllocChip]: chip memory (`MEMF_CHIP`), which the custom chips can reach.
const int MemChip = 2;
/// Memory that is cleared (`MEMF_CLEAR`).
const int MemClear = 65536;

int _savedDma;
int _savedInterrupts;
void* _gfx;
void* _savedView;
bool _active;

/// Direct access to the custom chips: registers, taking the machine over, the vertical blank, chip memory and the
/// mouse button. All functions are static.
struct Hardware
{
    /// The address of a custom chip register.
    static uint16* Register(Custom reg)
    {
        unsafe
        {
            return (uint16*)(nint)(0xDFF000 + (int)reg);
        }
    }

    /// Writes `value` (16 bits) to the register `reg`.
    static void Write(Custom reg, int value)
    {
        unsafe
        {
            Memory.VolatileWrite(Register(reg), (uint16)(value & 0xFFFF));
        }
    }

    /// Reads the register `reg` (16 bits).
    static int Read(Custom reg)
    {
        unsafe
        {
            return (int)Memory.VolatileRead(Register(reg));
        }
    }

    /// A 32-bit register pair (COP1LCH/COP1LCL, BPL1PTH/BPL1PTL, ...): the high word, then the low word.
    static void WriteLong(Custom reg, void* address)
    {
        unsafe
        {
            int value = (int)(nint)address;
            Memory.VolatileWrite(Register(reg), (uint16)((value >> 16) & 0xFFFF));
            Memory.VolatileWrite((uint16*)((uint8*)Register(reg) + 2), (uint16)(value & 0xFFFF));
        }
    }

    /// Takes the machine over: multitasking and the OS display stop, DMA and interrupts are switched off (then
    /// StartCopper and the program's own DMA). False if graphics.library cannot be opened.
    static bool TakeOver()
    {
        unsafe
        {
            if (_active)
                return true;
            _gfx = __exec_OpenLibrary("graphics.library".CStr(), 0);
            if (_gfx == null)
                return false;
            __cs_amiga_set(10, (int)(nint)_gfx);
            _savedView = *(void**)((uint8*)_gfx + 34); // gb_ActiView
            __gfx_OwnBlitter();
            __gfx_WaitBlit();
            __exec_Forbid();
            __gfx_LoadView(null);
            __gfx_WaitTOF();
            __gfx_WaitTOF();
            _savedDma = Read(Custom.DMACONR) | DmaSet;
            _savedInterrupts = Read(Custom.INTENAR) | 0xC000;
            Write(Custom.INTENA, 0x7FFF);
            Write(Custom.INTREQ, 0x7FFF);
            Write(Custom.DMACON, 0x7FFF);
            _active = true;
            return true;
        }
    }

    /// Gives the machine back: the system's copper list, DMA, interrupts, display and multitasking.
    static void Restore()
    {
        unsafe
        {
            if (!_active)
                return;
            WaitVBlank();
            Write(Custom.DMACON, 0x7FFF);
            Write(Custom.INTENA, 0x7FFF);
            WriteLong(Custom.COP1LCH, *(void**)((uint8*)_gfx + 38)); // gb_copinit
            Write(Custom.COPJMP1, 0);
            Write(Custom.DMACON, _savedDma);
            Write(Custom.INTENA, _savedInterrupts);
            __gfx_LoadView(_savedView);
            __gfx_WaitTOF();
            __gfx_WaitTOF();
            __gfx_WaitBlit();
            __gfx_DisownBlitter();
            __exec_Permit();
            __exec_CloseLibrary(_gfx);
            _gfx = null;
            _active = false;
        }
    }

    /// Starts the copper on a list in chip memory (and switches on copper DMA).
    static void StartCopper(void* list)
    {
        WriteLong(Custom.COP1LCH, list);
        Write(Custom.COPJMP1, 0);
        Write(Custom.DMACON, DmaSet | DmaMaster | DmaCopper);
    }

    /// Whether the machine is taken over: between [Hardware.TakeOver] and [Hardware.Restore].
    static bool IsTakenOver()
    {
        return _active;
    }

    /// The current raster line (0..312 on PAL).
    static int RasterLine()
    {
        unsafe
        {
            uint32 pos = Memory.VolatileRead((uint32*)(nint)0xDFF004); // VPOSR and VHPOSR
            return (int)((pos >> 8) & 0x1FFu);
        }
    }

    /// Waits for the vertical blank: until the beam is at line 300, below the visible picture.
    static void WaitVBlank()
    {
        while (RasterLine() == 300)
        {
        }
        while (RasterLine() != 300)
        {
        }
    }

    /// Whether the left mouse button is pressed (port 1: CIA-A, PRA bit 6, low while pressed).
    static bool LeftMouseButton()
    {
        unsafe
        {
            return (Memory.VolatileRead((uint8*)(nint)0xBFE001) & 64) == 0;
        }
    }

    /// Chip memory (for copper lists, bitplanes, sprites and sounds), cleared; FreeChip gives it back.
    static void* AllocChip(int size)
    {
        unsafe
        {
            return (void*)(nint)__exec_AllocMem(size, MemChip | MemClear);
        }
    }

    /// Gives back chip memory from [Hardware.AllocChip]; `size` must be the same.
    static void FreeChip(void* memory, int size)
    {
        if (memory != null)
            __exec_FreeMem(memory, size);
    }
}
