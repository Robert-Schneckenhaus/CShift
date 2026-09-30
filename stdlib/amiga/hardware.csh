// Programming the Amiga's custom chips directly (only for amigaos targets): taking the machine over from the
// operating system and giving it back, waiting for the vertical blank, chip memory, the copper and the mouse button.
//
//     using Amiga;
//
//     Hardware.TakeOver();                       // the OS stops drawing; DMA and interrupts are ours
//     Hardware.StartCopper(list);                // a copper list in chip memory (Hardware.AllocChip)
//     while (!Hardware.LeftMouseButton())
//     {
//         Hardware.WaitVBlank();
//         ...                                    // Hardware.Write(Custom.COLOR00, 0x0F00), ...
//     }
//     Hardware.Restore();                        // the OS display, DMA and interrupts are back
//
// The registers are written with volatile accesses (Memory.VolatileWrite), so every write reaches the chips.

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

// Offsets of the custom chip registers (from 0xDFF000)
enum Custom : int32
{
    DMACONR = 0x002,
    VPOSR = 0x004,
    VHPOSR = 0x006,
    JOY0DAT = 0x00A,
    JOY1DAT = 0x00C,
    INTENAR = 0x01C,
    INTREQR = 0x01E,
    COP1LCH = 0x080,
    COP2LCH = 0x084,
    COPJMP1 = 0x088,
    COPJMP2 = 0x08A,
    DIWSTRT = 0x08E,
    DIWSTOP = 0x090,
    DDFSTRT = 0x092,
    DDFSTOP = 0x094,
    DMACON = 0x096,
    INTENA = 0x09A,
    INTREQ = 0x09C,
    BPL1PTH = 0x0E0,
    BPLCON0 = 0x100,
    BPLCON1 = 0x102,
    BPLCON2 = 0x104,
    BPL1MOD = 0x108,
    BPL2MOD = 0x10A,
    COLOR00 = 0x180,
    COLOR01 = 0x182,
}

// DMACON bits
const int DmaSet = 0x8000;
const int DmaMaster = 0x0200;
const int DmaBitplanes = 0x0100;
const int DmaCopper = 0x0080;
const int DmaBlitter = 0x0040;
const int DmaSprites = 0x0020;

const int MemChip = 2;
const int MemClear = 65536;

int _savedDma;
int _savedInterrupts;
void* _gfx;
void* _savedView;
bool _active;

struct Hardware
{
    // The address of a custom chip register.
    static uint16* Register(Custom reg)
    {
        unsafe
        {
            return (uint16*)(nint)(0xDFF000 + (int)reg);
        }
    }

    static void Write(Custom reg, int value)
    {
        unsafe
        {
            Memory.VolatileWrite(Register(reg), (uint16)(value & 0xFFFF));
        }
    }

    static int Read(Custom reg)
    {
        unsafe
        {
            return (int)Memory.VolatileRead(Register(reg));
        }
    }

    // A 32-bit register pair (COP1LCH/COP1LCL, BPL1PTH/BPL1PTL, ...): the high word, then the low word.
    static void WriteLong(Custom reg, void* address)
    {
        unsafe
        {
            int value = (int)(nint)address;
            Memory.VolatileWrite(Register(reg), (uint16)((value >> 16) & 0xFFFF));
            Memory.VolatileWrite((uint16*)((uint8*)Register(reg) + 2), (uint16)(value & 0xFFFF));
        }
    }

    // Takes the machine over: multitasking and the OS display stop, DMA and interrupts are switched off (then
    // StartCopper and the program's own DMA). False if graphics.library cannot be opened.
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

    // Gives the machine back: the system's copper list, DMA, interrupts, display and multitasking.
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

    // Starts the copper on a list in chip memory (and switches on copper DMA).
    static void StartCopper(void* list)
    {
        WriteLong(Custom.COP1LCH, list);
        Write(Custom.COPJMP1, 0);
        Write(Custom.DMACON, DmaSet | DmaMaster | DmaCopper);
    }

    // The current raster line (0..312 on PAL).
    static int RasterLine()
    {
        unsafe
        {
            uint32 pos = Memory.VolatileRead((uint32*)(nint)0xDFF004); // VPOSR and VHPOSR
            return (int)((pos >> 8) & 0x1FFu);
        }
    }

    // Waits for the vertical blank: until the beam is at line 300, below the visible picture.
    static void WaitVBlank()
    {
        while (RasterLine() == 300)
        {
        }
        while (RasterLine() != 300)
        {
        }
    }

    // The left mouse button (port 1: CIA-A, PRA bit 6, low while pressed).
    static bool LeftMouseButton()
    {
        unsafe
        {
            return (Memory.VolatileRead((uint8*)(nint)0xBFE001) & 64) == 0;
        }
    }

    // Chip memory (for copper lists, bitplanes, sprites and sounds), cleared; FreeChip gives it back.
    static void* AllocChip(int size)
    {
        unsafe
        {
            return (void*)(nint)__exec_AllocMem(size, MemChip | MemClear);
        }
    }

    static void FreeChip(void* memory, int size)
    {
        if (memory != null)
            __exec_FreeMem(memory, size);
    }
}
