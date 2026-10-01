// Graphics on the Amiga's custom chips (only for amigaos targets, after Hardware.TakeOver): bitmaps in chip memory, a
// screen with its copper list and double buffering, the blitter, hardware sprites and the system font.
//
//     using Amiga;
//
//     Hardware.TakeOver();
//     if (Screen.Open(320, 256, 4, true) is Screen screen)
//     {
//         screen.SetColor(1, 0xFFF);
//         screen.Show();
//         while (!Hardware.LeftMouseButton())
//         {
//             screen.Back.Clear();                            // the blitter
//             screen.Back.FillRect(10, 10, 100, 50, 2);
//             screen.Back.DrawText(20, 100, "Hello", 1);     // Topaz, from the ROM
//             screen.Swap();                                  // shows Back, waits for the vertical blank
//         }
//         Hardware.Restore();
//         screen.Close();
//     }
//
// Coordinates are pixels, (0, 0) is the top left corner; drawing is clipped to the bitmap. Colors are numbers of the
// palette (0 .. 2^depth - 1); the palette has 12-bit colors (0xRGB).

namespace Amiga;

using System;

// A picture in chip memory: Depth bitplanes of Width x Height pixels, one after the other (plane p starts at
// Plane(p)). Width is a multiple of 16.
struct Bitmap
{
    uint8* _planes;
    int Width;
    int Height;
    int Depth;
    int BytesPerRow;
    int PlaneSize;

    // A cleared bitmap; null if there is not enough chip memory. width: a multiple of 16 up to 1024, height up to
    // 1024, depth 1..6.
    static unsafe Optional<Bitmap> Create(int width, int height, int depth)
    {
        if (width <= 0 || width > 1024 || width % 16 != 0 || height <= 0 || height > 1024 || depth < 1 || depth > 6)
            Environment.Panic("Bitmap.Create: " + width.ToString() + " x " + height.ToString() + " x " +
                              depth.ToString() + " (the width must be a multiple of 16 up to 1024, the height " +
                              "up to 1024, the depth 1..6)");
        int bytesPerRow = width / 8;
        int planeSize = bytesPerRow * height;
        void* memory = Hardware.AllocChip(planeSize * depth);
        if (memory == null)
            return null;
        return Bitmap { _planes = (uint8*)memory, Width = width, Height = height, Depth = depth,
                        BytesPerRow = bytesPerRow, PlaneSize = planeSize };
    }

    // gives the chip memory back
    unsafe void Free()
    {
        Blitter.Wait();
        Hardware.FreeChip(_planes, PlaneSize * Depth);
        _planes = null;
    }

    unsafe uint8* Plane(int p)
    {
        return _planes + p * PlaneSize;
    }

    // all pixels color 0 (the blitter)
    unsafe void Clear()
    {
        unchecked
        {
            _BlitBegin();
            int size = _BlitSize(Height, BytesPerRow / 2);
            uint8* plane = _planes;
            for (var p = 0; p < Depth; p += 1)
            {
                Blitter.Wait();
                _BlitWord(0x040, 0x0100);   // BLTCON0: only D, minterm 0
                _BlitWord(0x042, 0);        // BLTCON1
                _BlitWord(0x066, 0);        // BLTDMOD
                _BlitPointer(0x054, plane); // BLTDPT
                _BlitWord(0x058, size);     // BLTSIZE: starts the blit
                plane += PlaneSize;
            }
        }
    }

    // a filled rectangle (the blitter)
    unsafe void FillRect(int x, int y, int w, int h, int color)
    {
        unchecked
        {
            if (x < 0) { w += x; x = 0; }
            if (y < 0) { h += y; y = 0; }
            if (x + w > Width) w = Width - x;
            if (y + h > Height) h = Height - y;
            if (w <= 0 || h <= 0)
                return;
            int first = x >> 4;
            int words = ((x + w - 1) >> 4) - first + 1;
            int modulo = BytesPerRow - words * 2;
            int offset = y * BytesPerRow + first * 2;
            int size = _BlitSize(h, words);
            _BlitBegin();
            _BlitWord(0x044, 0xFFFF >> (x & 15));                   // BLTAFWM
            _BlitWord(0x046, 0xFFFF << (15 - ((x + w - 1) & 15)));  // BLTALWM
            _BlitWord(0x074, 0xFFFF);  // BLTADAT: A is the constant 0xFFFF, cut to the rectangle by the masks
            _BlitWord(0x042, 0);       // BLTCON1
            _BlitWord(0x060, modulo);  // BLTCMOD
            _BlitWord(0x066, modulo);  // BLTDMOD
            uint8* at = _planes + offset;
            for (var p = 0; p < Depth; p += 1)
            {
                Blitter.Wait();
                // BLTCON0: C and D; A | C sets the bits of the rectangle, !A & C clears them
                _BlitWord(0x040, ((color >> p) & 1) != 0 ? 0x03FA : 0x030A);
                _BlitPointer(0x048, at);  // BLTCPT
                _BlitPointer(0x054, at);  // BLTDPT
                _BlitWord(0x058, size);
                at += PlaneSize;
            }
        }
    }

    // the outline of a rectangle
    void DrawRect(int x, int y, int w, int h, int color)
    {
        if (w <= 0 || h <= 0)
            return;
        FillRect(x, y, w, 1, color);
        FillRect(x, y + h - 1, w, 1, color);
        FillRect(x, y + 1, 1, h - 2, color);
        FillRect(x + w - 1, y + 1, 1, h - 2, color);
    }

    void SetPixel(int x, int y, int color)
    {
        Blitter.Wait();
        _Plot(x, y, color);
    }

    // the color of a pixel (0 outside the bitmap)
    unsafe int GetPixel(int x, int y)
    {
        unchecked
        {
            if (x < 0 || y < 0 || x >= Width || y >= Height)
                return 0;
            Blitter.Wait();
            uint8* at = _planes + y * BytesPerRow + (x >> 3);
            int bit = 0x80 >> (x & 7);
            int color = 0;
            for (var p = 0; p < Depth; p += 1)
            {
                if ((at[0] & bit) != 0)
                    color |= 1 << p;
                at += PlaneSize;
            }
            return color;
        }
    }

    unsafe void _Plot(int x, int y, int color)
    {
        unchecked
        {
            if (x < 0 || y < 0 || x >= Width || y >= Height)
                return;
            uint8* at = _planes + y * BytesPerRow + (x >> 3);
            uint8 bit = (uint8)(0x80 >> (x & 7));
            for (var p = 0; p < Depth; p += 1)
            {
                if (((color >> p) & 1) != 0)
                    at[0] |= bit;
                else
                    at[0] &= (uint8)~bit;
                at += PlaneSize;
            }
        }
    }

    // a line from (x0, y0) to (x1, y1), both ends included
    void DrawLine(int x0, int y0, int x1, int y1, int color)
    {
        Blitter.Wait();
        int dx = x1 > x0 ? x1 - x0 : x0 - x1;
        int dy = y1 > y0 ? y0 - y1 : y1 - y0;
        int sx = x0 < x1 ? 1 : -1;
        int sy = y0 < y1 ? 1 : -1;
        int err = dx + dy;
        while (true)
        {
            _Plot(x0, y0, color);
            if (x0 == x1 && y0 == y1)
                break;
            int e2 = 2 * err;
            if (e2 >= dy)
            {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx)
            {
                err += dx;
                y0 += sy;
            }
        }
    }

    // Pixels from text, one string per row: '0'..'9' and 'A'..'V' are the colors 0..31, every other character ('.',
    // ' ') leaves the pixel as it is.
    void DrawPattern(int x, int y, ReadOnlySlice<string> rows)
    {
        Blitter.Wait();
        for (var r = 0; r < rows.Length; r += 1)
        {
            string row = rows[r];
            for (var i = 0; i < row.Length; i += 1)
            {
                int color = _PatternColor(row[i]);
                if (color >= 0)
                    _Plot(x + i, y + r, color);
            }
        }
    }

    static int _PatternColor(char c)
    {
        if (c >= '0' && c <= '9')
            return (int)c - '0';
        if (c >= 'A' && c <= 'V')
            return (int)c - 'A' + 10;
        if (c >= 'a' && c <= 'v')
            return (int)c - 'a' + 10;
        return -1;
    }

    // Copies w x h pixels from (sx, sy) of source to (x, y) (the planes both have; source and destination must not
    // overlap). The blitter does it when x % 16 >= sx % 16 (e.g. sources at multiples of 16), the CPU otherwise; it is
    // fastest for whole words (x, sx and w multiples of 16).
    unsafe void Copy(const ref Bitmap source, int sx, int sy, int x, int y, int w, int h)
    {
        unchecked
        {
            // clipped to both bitmaps
            if (sx < 0) { w += sx; x -= sx; sx = 0; }
            if (sy < 0) { h += sy; y -= sy; sy = 0; }
            if (x < 0) { w += x; sx -= x; x = 0; }
            if (y < 0) { h += y; sy -= y; y = 0; }
            if (sx + w > source.Width) w = source.Width - sx;
            if (sy + h > source.Height) h = source.Height - sy;
            if (x + w > Width) w = Width - x;
            if (y + h > Height) h = Height - y;
            if (w <= 0 || h <= 0)
                return;
            int planes = Depth < source.Depth ? Depth : source.Depth;
            int shift = (x & 15) - (sx & 15);
            if (shift < 0)
            {
                Blitter.Wait();
                for (var j = 0; j < h; j += 1)
                {
                    for (var i = 0; i < w; i += 1)
                        _Plot(x + i, y + j, source.GetPixel(sx + i, sy + j));
                }
                return;
            }
            int words = ((x + w - 1) >> 4) - (x >> 4) + 1;
            _BlitBegin();
            if (shift == 0 && (x & 15) == 0 && (w & 15) == 0)
            {
                // whole words: B to D, without masks (fewer cycles of the blitter)
                _BlitWord(0x040, 0x05CC);
                _BlitWord(0x042, 0);
            }
            else
            {
                // A: the constant 0xFFFF cut by the masks to the columns of the rectangle; B: the source,
                // shifted; C, D: here; D = A ? B : C
                _BlitWord(0x044, 0xFFFF >> (x & 15));
                _BlitWord(0x046, 0xFFFF << (15 - ((x + w - 1) & 15)));
                _BlitWord(0x074, 0xFFFF);
                _BlitWord(0x040, 0x07CA);
                _BlitWord(0x042, shift << 12);
            }
            _BlitWord(0x062, source.BytesPerRow - words * 2);  // BLTBMOD
            _BlitWord(0x060, BytesPerRow - words * 2);
            _BlitWord(0x066, BytesPerRow - words * 2);
            int size = _BlitSize(h, words);
            uint8* b = source._planes + (sy * source.BytesPerRow + ((sx >> 4) << 1));
            uint8* d = _planes + (y * BytesPerRow + ((x >> 4) << 1));
            int sourcePlane = source.PlaneSize;
            int plane = PlaneSize;
            for (var p = 0; p < planes; p += 1)
            {
                Blitter.Wait();
                _BlitPointer(0x04C, b);  // BLTBPT
                _BlitPointer(0x048, d);
                _BlitPointer(0x054, d);
                _BlitWord(0x058, size);
                b += sourcePlane;
                d += plane;
            }
        }
    }

    // Draws a shape (a "bob"): w x h pixels from (sx, sy) of source to (x, y), only where mask (a bitmap with one
    // plane, the same size as source, e.g. source.MakeMask()) has a 1. sx must be a multiple of 16; the pixels
    // right of the shape up to the next multiple of 16 are drawn too where the mask has a 1. The blitter does it
    // when the shape is inside the bitmap from left to right, the CPU otherwise.
    unsafe void DrawMasked(const ref Bitmap source, const ref Bitmap mask, int sx, int sy, int x, int y, int w, int h)
    {
        unchecked
        {
            if ((sx & 15) != 0)
                Environment.Panic("Bitmap.DrawMasked: sx must be a multiple of 16 (is " + sx.ToString() + ")");
            if (mask.BytesPerRow != source.BytesPerRow || mask.Height != source.Height)
                Environment.Panic("Bitmap.DrawMasked: the mask must have the size of the source");
            // clipped to both bitmaps (from top to bottom; from left to right by the CPU)
            if (sy < 0) { h += sy; y -= sy; sy = 0; }
            if (y < 0) { h += y; sy -= y; y = 0; }
            if (sy + h > source.Height) h = source.Height - sy;
            if (y + h > Height) h = Height - y;
            if (sx + w > source.Width) w = source.Width - sx;
            if (w <= 0 || h <= 0)
                return;
            if (x < 0 || x + w > Width)
            {
                Blitter.Wait();
                for (var j = 0; j < h; j += 1)
                {
                    for (var i = 0; i < w; i += 1)
                    {
                        if (mask.GetPixel(sx + i, sy + j) != 0)
                            _Plot(x + i, y + j, source.GetPixel(sx + i, sy + j));
                    }
                }
                return;
            }
            int shift = x & 15;
            int words = ((x + w - 1) >> 4) - (x >> 4) + 1;
            int lastMask = 0;  // one word more than the shape: the mask is 0 there
            if (words == (w + 15) >> 4)
                lastMask = (w & 15) == 0 ? 0xFFFF : 0xFFFF << (16 - (w & 15));
            _BlitBegin();
            // A: the mask, B: the shape (both shifted), C, D: here; D = A ? B : C
            _BlitWord(0x044, 0xFFFF);
            _BlitWord(0x046, lastMask);
            _BlitWord(0x042, shift << 12);
            _BlitWord(0x064, mask.BytesPerRow - words * 2);    // BLTAMOD
            _BlitWord(0x062, source.BytesPerRow - words * 2);
            _BlitWord(0x060, BytesPerRow - words * 2);
            _BlitWord(0x066, BytesPerRow - words * 2);
            int size = _BlitSize(h, words);
            int from = sy * source.BytesPerRow + ((sx >> 4) << 1);
            uint8* a = mask._planes + from;
            uint8* b = source._planes + from;
            uint8* d = _planes + (y * BytesPerRow + ((x >> 4) << 1));
            int con = (shift << 12) | 0x0FCA;
            int sourcePlanes = source.Depth;
            int sourcePlane = source.PlaneSize;
            int plane = PlaneSize;
            for (var p = 0; p < Depth; p += 1)
            {
                Blitter.Wait();
                if (p < sourcePlanes)
                {
                    _BlitWord(0x040, con);
                    _BlitPointer(0x04C, b);
                    b += sourcePlane;
                }
                else
                {
                    _BlitWord(0x040, con & 0xFBFF); // a plane the source does not have: no B, B = 0
                    _BlitWord(0x072, 0);             // BLTBDAT
                }
                _BlitPointer(0x050, a);  // BLTAPT
                _BlitPointer(0x048, d);
                _BlitPointer(0x054, d);
                _BlitWord(0x058, size);
                d += plane;
            }
        }
    }

    // A mask for DrawMasked: a bitmap with one plane that is 1 where this bitmap's color is not 0; null if there is
    // not enough chip memory.
    unsafe Optional<Bitmap> MakeMask()
    {
        if (Bitmap.Create(Width, Height, 1) is Bitmap mask)
        {
            Blitter.Wait();
            for (var i = 0; i < PlaneSize; i += 1)
            {
                uint8 bits = 0;
                for (var p = 0; p < Depth; p += 1)
                    bits |= _planes[p * PlaneSize + i];
                mask._planes[i] = bits;
            }
            return mask;
        }
        return null;
    }

    // Text in the system font (Topaz 8 or the font set in the preferences), at (x, y) = the top left corner of the
    // first character; the pixels around the letters stay. UTF-8 characters up to U+00FF are shown, others as '?'.
    // The x after the text is returned.
    unsafe int DrawText(int x, int y, StringSlice text, int color)
    {
        uint8* font = _FontGet();
        if (font == null)
            return x;
        int height = (int)*(uint16*)(font + 20);
        uint8* data = *(uint8**)(font + 34);
        int modulo = (int)*(uint16*)(font + 38);
        Blitter.Wait();
        for (var i = 0; i < text.Length; i += 1)
        {
            int c = _FontNextChar(text, ref i);
            int glyph = _FontGlyph(font, c);
            int start = _FontStart(font, glyph);
            int width = _FontWidth(font, glyph);
            if (width > 16)
                width = 16;
            int left = x + _FontKern(font, glyph);
            for (var row = 0; row < height; row += 1)
            {
                uint8* bits = data + row * modulo + (start >> 3);
                uint32 v = ((uint32)bits[0] << 24) | ((uint32)bits[1] << 16) | ((uint32)bits[2] << 8) | (uint32)bits[3];
                v = (v << (start & 7)) & ~(0xFFFFFFFFu >> width);
                if (v != 0u)
                    _PutRow(left, y + row, v, color);
            }
            x += _FontAdvance(font, glyph);
        }
        return x;
    }

    // ORs (or clears, by color) the bits of v (from bit 31 on) into row y at x
    unsafe void _PutRow(int x, int y, uint32 v, int color)
    {
        unchecked
        {
            if (y < 0 || y >= Height || x >= Width || x <= -32)
                return;
            if (x < 0)
            {
                v = v << (-x);
                x = 0;
            }
            int word = x >> 4;
            uint32 bits = v >> (x & 15);
            int words = BytesPerRow / 2;
            uint16 high = (uint16)(bits >> 16);
            uint16 low = (uint16)(bits & 0xFFFFu);
            uint16 extra = (uint16)((x & 15) == 0 ? 0u : (v << (16 - (x & 15))) & 0xFFFFu); // the third word
            for (var p = 0; p < Depth; p += 1)
            {
                uint16* at = (uint16*)(Plane(p) + y * BytesPerRow) + word;
                bool set = ((color >> p) & 1) != 0;
                for (var k = 0; k < 3; k += 1)
                {
                    uint16 part = k == 0 ? high : k == 1 ? low : extra;
                    if (part != 0 && word + k < words)
                    {
                        if (set)
                            at[k] |= part;
                        else
                            at[k] &= (uint16)~part;
                    }
                }
            }
        }
    }
}

// The font of the system (GfxBase->DefaultFont, in ROM): Topaz 8, or the one set in the preferences.
struct SystemFont
{
    // the height of a line of text in pixels (0 if there is no font)
    static int Height()
    {
        unsafe
        {
            uint8* font = _FontGet();
            return font == null ? 0 : (int)*(uint16*)(font + 20);
        }
    }

    // the width of the text in pixels
    static int TextWidth(StringSlice text)
    {
        unsafe
        {
            uint8* font = _FontGet();
            if (font == null)
                return 0;
            int width = 0;
            for (var i = 0; i < text.Length; i += 1)
                width += _FontAdvance(font, _FontGlyph(font, _FontNextChar(text, ref i)));
            return width;
        }
    }
}

void* _systemFont;

unsafe uint8* _FontGet()
{
    if (_systemFont == null)
    {
        void* gfx = __exec_OpenLibrary("graphics.library".CStr(), 0);
        if (gfx == null)
            return null;
        _systemFont = *(void**)((uint8*)gfx + 154); // gb_DefaultFont
        __exec_CloseLibrary(gfx);
    }
    return (uint8*)_systemFont;
}

// the character at i (a UTF-8 sequence of two bytes is decoded and i moved to its last byte)
int _FontNextChar(StringSlice text, ref int i)
{
    int c = (int)text[i];
    if (c < 0x80)
        return c;
    if (c >= 0xC0 && c < 0xE0 && i + 1 < text.Length)
    {
        int code = ((c & 0x1F) << 6) | ((int)text[i + 1] & 0x3F);
        i += 1;
        return code < 256 ? code : '?';
    }
    while (i + 1 < text.Length && ((int)text[i + 1] & 0xC0) == 0x80)
        i += 1;
    return '?';
}

// the glyph of character c: tf_LoChar..tf_HiChar, then one for all others
unsafe int _FontGlyph(uint8* font, int c)
{
    int lo = (int)font[32];
    int hi = (int)font[33];
    if (c < lo || c > hi)
        return hi - lo + 1;
    return c - lo;
}

unsafe int _FontStart(uint8* font, int glyph)
{
    uint16* loc = *(uint16**)(font + 40);
    return (int)loc[glyph * 2];
}

unsafe int _FontWidth(uint8* font, int glyph)
{
    uint16* loc = *(uint16**)(font + 40);
    return (int)loc[glyph * 2 + 1];
}

unsafe int _FontKern(uint8* font, int glyph)
{
    int16* kern = *(int16**)(font + 48);
    return kern == null ? 0 : (int)kern[glyph];
}

unsafe int _FontAdvance(uint8* font, int glyph)
{
    int16* space = *(int16**)(font + 44);
    return space == null ? (int)*(uint16*)(font + 24) : (int)space[glyph];
}

// The blitter: draws into chip memory while the CPU goes on. Bitmap's drawing functions start it; Wait() before the
// CPU touches what it draws (the CPU drawing functions of Bitmap do that themselves).
struct Blitter
{
    static void Wait()
    {
        unsafe
        {
            var dmaconr = (uint16*)(nint)0xDFF002;
            Memory.VolatileRead(dmaconr); // the first read is wrong on early Agnus chips
            while ((Memory.VolatileRead(dmaconr) & 0x4000) != 0)
            {
            }
        }
    }
}

// a blitter register (its offset from 0xDFF000)
unsafe void _BlitWord(int offset, int value)
{
    Memory.VolatileWrite((uint16*)(nint)(0xDFF000 | offset), (uint16)(value & 0xFFFF));
}

// a pointer register pair of the blitter (BLTAPTH/BLTAPTL, ...)
unsafe void _BlitPointer(int offset, void* address)
{
    Memory.VolatileWrite((uint32*)(nint)(0xDFF000 | offset), (uint32)(nint)address);
}

// the blitter's DMA on, the last blit finished
void _BlitBegin()
{
    if (!Hardware.IsTakenOver())
        Environment.Panic("Amiga: the blitter can only be used after Hardware.TakeOver()");
    Hardware.Write(Custom.DMACON, DmaSet | DmaMaster | DmaBlitter);
    Blitter.Wait();
}

// BLTSIZE: rows (1..1024) and words (1..64) of a blit
int _BlitSize(int rows, int words)
{
    return ((rows & 1023) << 6) | (words & 63);
}

// A copper list in chip memory: MOVEs to the custom chip registers and WAITs for raster lines. It always ends with
// the copper's end instruction, so it can run while it grows.
struct CopperList
{
    uint16* _words;
    int _capacity;
    int _count;
    int _mark;
    bool _wrapped;
    bool _markWrapped;

    // room for 'instructions' MOVEs and WAITs; null if there is not enough chip memory
    static unsafe Optional<CopperList> Create(int instructions)
    {
        void* memory = Hardware.AllocChip((instructions + 1) * 4);
        if (memory == null)
            return null;
        var list = CopperList { _words = (uint16*)memory, _capacity = instructions };
        list._End();
        return list;
    }

    unsafe void* Address()
    {
        return _words;
    }

    // the number of instructions
    int Count()
    {
        return _count;
    }

    // MOVE value to a register; the result is the instruction's index for Change
    int Move(Custom register, int value)
    {
        return _Add((int)register & 0x1FE, value);
    }

    // MOVE to the color register 0..31 (0xRGB)
    int Color(int index, int rgb)
    {
        return _Add(0x180 + 2 * (index & 31), rgb);
    }

    // MOVE to a bitplane or sprite pointer (BPL1PTH, SPR0PTH, ... + 4 * number): two instructions, high and low word
    int MovePointer(Custom register, int number, void* address)
    {
        unsafe
        {
            int value = (int)(nint)address;
            int index = _Add(((int)register + 4 * number) & 0x1FE, (value >> 16) & 0xFFFF);
            _Add(((int)register + 4 * number + 2) & 0x1FE, value & 0xFFFF);
            return index;
        }
    }

    // WAIT until the beam reaches line y of the picture (y = 0: the first line of the standard PAL display window,
    // raster line 44; up to 268). Lines must come in order.
    void Wait(int y)
    {
        int beam = 0x2C + y;
        if (beam > 255 && !_wrapped)
        {
            _Instruction(0xFFDF, 0xFFFE); // the end of line 255: the vertical position has only 8 bits
            _wrapped = true;
        }
        _Instruction(((beam & 0xFF) << 8) | 0x07, 0xFFFE);
    }

    // a new value for the MOVE at index
    void Change(int index, int value)
    {
        unsafe
        {
            if (index < 0 || index >= _count)
                Environment.Panic("CopperList.Change: index " + index.ToString() + " (the list has " +
                                  _count.ToString() + ")");
            _words[index * 2 + 1] = (uint16)(value & 0xFFFF);
        }
    }

    // a new address for the pointer MOVEs at index (from MovePointer)
    void ChangePointer(int index, void* address)
    {
        unsafe
        {
            int value = (int)(nint)address;
            Change(index, (value >> 16) & 0xFFFF);
            Change(index + 1, value & 0xFFFF);
        }
    }

    // Reset goes back to here
    void Mark()
    {
        _mark = _count;
        _markWrapped = _wrapped;
    }

    // removes the instructions after the mark (all without one)
    void Reset()
    {
        _count = _mark;
        _wrapped = _markWrapped;
        _End();
    }

    unsafe void Free()
    {
        Hardware.FreeChip(_words, (_capacity + 1) * 4);
        _words = null;
    }

    int _Add(int register, int value)
    {
        int index = _count;
        _Instruction(register, value & 0xFFFF);
        return index;
    }

    void _Instruction(int first, int second)
    {
        unsafe
        {
            if (_count >= _capacity)
                Environment.Panic("CopperList: full (" + _capacity.ToString() + " instructions)");
            _words[_count * 2 + 2] = 0xFFFF;  // the new end first, then the instruction over the old end
            _words[_count * 2 + 3] = 0xFFFE;
            _words[_count * 2 + 1] = (uint16)second;
            _words[_count * 2] = (uint16)first;
            _count += 1;
        }
    }

    void _End()
    {
        unsafe
        {
            _words[_count * 2] = 0xFFFF;
            _words[_count * 2 + 1] = 0xFFFE;
        }
    }
}

// A hardware sprite: 16 pixels wide, as high as needed, three colors (sprites 0 and 1 use the colors 17-19, 2 and 3
// 21-23, 4 and 5 25-27, 6 and 7 29-31). Screen.ShowSprite shows it.
struct Sprite
{
    uint16* _data;
    int Height;

    // One string per row (up to 16 characters): '1'..'3' are the sprite's colors, every other character ('.', ' ')
    // is transparent. Null if there is not enough chip memory.
    static Optional<Sprite> Create(ReadOnlySlice<string> rows)
    {
        unsafe
        {
            int height = rows.Length;
            var data = (uint16*)Hardware.AllocChip((height + 2) * 4);
            if (data == null)
                return null;
            for (var r = 0; r < height; r += 1)
            {
                string row = rows[r];
                int plane0 = 0;
                int plane1 = 0;
                for (var i = 0; i < row.Length && i < 16; i += 1)
                {
                    int c = (int)row[i] - '0';
                    if (c >= 1 && c <= 3)
                    {
                        if ((c & 1) != 0)
                            plane0 |= 0x8000 >> i;
                        if ((c & 2) != 0)
                            plane1 |= 0x8000 >> i;
                    }
                }
                data[2 + r * 2] = (uint16)plane0;
                data[3 + r * 2] = (uint16)plane1;
            }
            var sprite = Sprite { _data = data, Height = height };
            sprite.MoveTo(0, 0);
            return sprite;
        }
    }

    // the top left corner at (x, y) of the picture
    void MoveTo(int x, int y)
    {
        unsafe
        {
            int hstart = x + 0x80;
            int vstart = y + 0x2C;
            int vstop = vstart + Height;
            _data[0] = (uint16)(((vstart & 0xFF) << 8) | ((hstart >> 1) & 0xFF));
            _data[1] = (uint16)(((vstop & 0xFF) << 8) | ((vstart >> 6) & 4) | ((vstop >> 7) & 2) | (hstart & 1));
        }
    }

    unsafe void* Address()
    {
        return _data;
    }

    unsafe void Free()
    {
        Hardware.FreeChip(_data, (Height + 2) * 4);
        _data = null;
    }
}

// A low resolution PAL screen: a bitmap (two with double buffering) shown by a copper list that also sets the
// palette and the sprites. After the setup, Copper takes your own instructions (Copper.Wait(y), Copper.Color(0,
// 0xF00), ...; Copper.Reset() removes them again).
struct Screen
{
    Bitmap Front;          // what is shown
    Bitmap Back;           // where to draw (the same as Front without double buffering)
    CopperList Copper;
    int Width;
    int Height;
    int Depth;
    int _planesAt;
    int _spritesAt;
    int _colorsAt;
    void* _noSprite;

    // width: a multiple of 16, 128..320; height 1..256; depth 1..5 (2..32 colors). Null if there is not enough chip
    // memory.
    static Optional<Screen> Open(int width, int height, int depth, bool doubleBuffer)
    {
        if (width < 128 || width > 320 || width % 16 != 0 || height < 1 || height > 256 || depth < 1 || depth > 5)
            Environment.Panic("Screen.Open: " + width.ToString() + " x " + height.ToString() + " x " +
                              depth.ToString() + " (the width must be a multiple of 16 from 128 to 320, the height " +
                              "up to 256, the depth 1..5)");
        unsafe
        {
            void* noSprite = Hardware.AllocChip(8);
            if (noSprite == null)
                return null;
            if (Bitmap.Create(width, height, depth) is Bitmap front)
            {
                var back = front;
                bool ok = true;
                if (doubleBuffer)
                {
                    if (Bitmap.Create(width, height, depth) is Bitmap second)
                        back = second;
                    else
                        ok = false;
                }
                if (ok)
                {
                    if (CopperList.Create(9 + depth * 2 + 16 + 32 + 1000) is CopperList copper)
                    {
                        var screen = Screen { Front = front, Back = back, Copper = copper, Width = width,
                                              Height = height, Depth = depth, _noSprite = noSprite };
                        screen._Build();
                        return screen;
                    }
                    if (doubleBuffer)
                        back.Free();
                }
                front.Free();
            }
            Hardware.FreeChip(noSprite, 8);
            return null;
        }
    }

    void _Build()
    {
        Copper.Move(Custom.BPLCON0, (Depth << 12) | 0x0200);
        Copper.Move(Custom.BPLCON1, 0);
        Copper.Move(Custom.BPLCON2, 0x0024);                      // sprites in front of the picture
        Copper.Move(Custom.DIWSTRT, 0x2C81);
        Copper.Move(Custom.DIWSTOP, (((0x2C + Height) & 0xFF) << 8) | ((0x81 + Width) & 0xFF));
        Copper.Move(Custom.DDFSTRT, 0x0038);
        Copper.Move(Custom.DDFSTOP, 0x0038 + (Width / 16 - 1) * 8);
        Copper.Move(Custom.BPL1MOD, 0);
        Copper.Move(Custom.BPL2MOD, 0);
        _planesAt = Copper.Count();
        for (var p = 0; p < Depth; p += 1)
            Copper.MovePointer(Custom.BPL1PTH, p, Front.Plane(p));
        _spritesAt = Copper.Count();
        for (var s = 0; s < 8; s += 1)
            Copper.MovePointer(Custom.SPR0PTH, s, _noSprite);
        _colorsAt = Copper.Count();
        for (var c = 0; c < 32; c += 1)
            Copper.Color(c, _DefaultColors[c]);
        Copper.Mark();
    }

    // color 0..31 as 0xRGB (from the next frame on)
    void SetColor(int index, int rgb)
    {
        if (index < 0 || index > 31)
            Environment.Panic("Screen.SetColor: color " + index.ToString() + " (0..31)");
        Copper.Change(_colorsAt + index, rgb);
    }

    // Shows the screen: starts its copper list and the DMA for bitplanes, copper, blitter and sprites (after
    // Hardware.TakeOver).
    void Show()
    {
        if (!Hardware.IsTakenOver())
            Environment.Panic("Screen.Show: call Hardware.TakeOver() first");
        Hardware.StartCopper(Copper.Address());
        Hardware.Write(Custom.DMACON, DmaSet | DmaMaster | DmaBitplanes | DmaCopper | DmaBlitter | DmaSprites);
    }

    // Shows Back from the next frame on (Front and Back swap) and waits for the vertical blank: then the new Back is
    // no longer on the screen. Without double buffering it only waits.
    void Swap()
    {
        Blitter.Wait();
        var shown = Back;
        Back = Front;
        Front = shown;
        for (var p = 0; p < Depth; p += 1)
            Copper.ChangePointer(_planesAt + p * 2, Front.Plane(p));
        Hardware.WaitVBlank();
    }

    // sprite 'number' (0..7) shows sprite (from the next frame on)
    void ShowSprite(int number, Sprite sprite)
    {
        if (number < 0 || number > 7)
            Environment.Panic("Screen.ShowSprite: sprite " + number.ToString() + " (0..7)");
        Copper.ChangePointer(_spritesAt + number * 2, sprite.Address());
    }

    void HideSprite(int number)
    {
        if (number < 0 || number > 7)
            Environment.Panic("Screen.HideSprite: sprite " + number.ToString() + " (0..7)");
        Copper.ChangePointer(_spritesAt + number * 2, _noSprite);
    }

    // frees the bitmaps and the copper list (after Hardware.Restore, when the screen is no longer shown)
    void Close()
    {
        Blitter.Wait();
        if (Back.Plane(0) != Front.Plane(0))
            Back.Free();
        Front.Free();
        Copper.Free();
        Hardware.FreeChip(_noSprite, 8);
        _noSprite = null;
    }
}

// black, white, then a few colors; 16-31 (also the sprites' colors) the same again
const ReadOnlySlice<int> _DefaultColors = [
    0x000, 0xFFF, 0xF00, 0x0F0, 0x00F, 0xFF0, 0x0FF, 0xF0F, 0x888, 0x444, 0xF80, 0x8F0, 0x08F, 0xF08, 0xCCC, 0x666,
    0x000, 0xFFF, 0xF00, 0x0F0, 0x00F, 0xFF0, 0x0FF, 0xF0F, 0x888, 0x444, 0xF80, 0x8F0, 0x08F, 0xF08, 0xCCC, 0x666
];
