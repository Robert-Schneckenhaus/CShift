// The window part of the operating system layer on AmigaOS for System.Ui (stdlib/ui_window.csh; see
// stdlib/os/windows/ui.csh for the same struct with Win32): an Intuition window on the Workbench screen. A 68000 cannot
// paint every pixel of a frame in 32 bits, so the Ui records its frames as commands (Ui.BeginCommands) and this layer
// draws them with graphics.library: rectangles with RectFill (rounded corners and circles as runs of rows), lines with
// Move/Draw, text with the system font (its sizes are the Ui's font: Font.Metrics), colors as pens of the screen
// (ObtainBestPenA). It draws into a bitmap of its own and copies that into the window in one blit, so nothing
// flickers. The bitmap has no layer, so everything is clipped here. Images are not drawn. Needs AmigaOS 3.0
// (graphics.library and intuition.library 39). The clipboard is kept inside the program.

namespace System.Ui;

using System;
using System.Image;

extern "C" void* __exec_OpenLibrary(char* name, int version);
extern "C" void __exec_CloseLibrary(void* library);
extern "C" void* __exec_WaitPort(void* port);
extern "C" void* __exec_GetMsg(void* port);
extern "C" void __exec_ReplyMsg(void* message);
extern "C" void __cs_amiga_set(int index, int value);
extern "C" void __gfx_Text(void* rastPort, char* text, int count);
extern "C" void __gfx_SetFont(void* rastPort, void* font);
extern "C" void __gfx_InitRastPort(void* rastPort);
extern "C" void __gfx_Move(void* rastPort, int x, int y);
extern "C" void __gfx_Draw(void* rastPort, int x, int y);
extern "C" void __gfx_RectFill(void* rastPort, int left, int top, int right, int bottom);
extern "C" void __gfx_SetAPen(void* rastPort, int pen);
extern "C" void __gfx_SetDrMd(void* rastPort, int mode);
extern "C" void __gfx_BltBitMapRastPort(void* source, int sourceX, int sourceY, void* rastPort, int x, int y, int width, int height, int minterm);
extern "C" int __gfx_ObtainBestPenA(void* colorMap, int red, int green, int blue, void* tags);
extern "C" void* __gfx_AllocBitMap(int width, int height, int depth, int flags, void* friendBitMap);
extern "C" void __gfx_FreeBitMap(void* bitMap);
extern "C" void __gfx_ReleasePen(void* colorMap, int pen);
extern "C" void __gfx_WaitBlit();
extern "C" void* __intuition_OpenWindowTagList(void* newWindow, void* tags);
extern "C" void __intuition_CloseWindow(void* window);
extern "C" void __intuition_SetWindowTitles(void* window, char* title, char* screenTitle);

// the slots of the library bases (__cs_amiga_set, see stdlib/amiga/libc.csh and amiga-startup.s)
const int _VarGfxBase = 10;
const int _VarIntuitionBase = 11;

// IDCMP classes and the codes of the mouse button
const int _IdcmpNewSize = 0x2;
const int _IdcmpMouseButtons = 0x8;
const int _IdcmpMouseMove = 0x10;
const int _IdcmpCloseWindow = 0x200;
const int _IdcmpRawKey = 0x400;
const int _IdcmpVanillaKey = 0x200000;
const int _SelectDown = 0x68;
const int _SelectUp = 0xE8;

// The state of the window (zero until the first Open).
struct _UiAmiga
{
    bool Open;
    bool Closed;
    void* Gfx;
    void* Intuition;
    void* Window;
    void* Port;
    void* ColorMap;
    void* Font;
    int FontWidth;
    int FontHeight;
    int FontBaseline;
    int Width;
    int Height;
    uint8[] RastPort;      // the RastPort of the bitmap (100 bytes)
    void* BitMap;
    int BitMapWidth;
    int BitMapHeight;
    Dictionary<uint32, int> Pens;
    int Pen;               // the pen set in RastPort (-1: none yet)
    Rect Clip;
    uint8[] Title;         // the window keeps a pointer to it
    int MouseX;
    int MouseY;
    bool MouseDown;
    bool Pressed;
    bool Released;
    bool ButtonEvent;
    int Wheel;
    bool Ctrl;
    bool Shift;
    bool Alt;
    List<Key> Keys;
    StringBuilder Text;
}

_UiAmiga _UiA;
string _UiClipboardText;

// UTF-8 as Latin-1 (the characters of AmigaOS), NUL-terminated; other characters become '?'.
uint8[] _UiLatin1(StringSlice text)
{
    var bytes = List<uint8>.Create();
    int i = 0;
    while (i < text.Length)
    {
        int length = 1;
        int code = _DecodeChar(text, i, ref length);
        i += length;
        bytes.Add(code < 256 ? (uint8)code : (uint8)'?');
    }
    bytes.Add(0);
    return bytes.ToArray();
}

// The pen nearest to a color (obtained once, released when the window closes).
int _UiPen(Color color)
{
    uint32 key = color.ToArgb() & 0xFFFFFFu;
    var found = _UiA.Pens.TryGet(key);
    if (found is int known)
        return known;
    int pen = 1;
    unsafe
    {
        // the components as 32-bit fractions: 0xFF -> 0xFFFFFFFF
        int r = unchecked((int)((uint32)color.R * 0x01010101u));
        int g = unchecked((int)((uint32)color.G * 0x01010101u));
        int b = unchecked((int)((uint32)color.B * 0x01010101u));
        pen = __gfx_ObtainBestPenA(_UiA.ColorMap, r, g, b, null);
    }
    if (pen < 0)
        pen = 1;
    _UiA.Pens.Set(key, pen);
    return pen;
}

void _UiSetPen(Color color)
{
    int pen = _UiPen(color);
    if (pen == _UiA.Pen)
        return;
    _UiA.Pen = pen;
    unsafe
    {
        __gfx_SetAPen(&_UiA.RastPort[0], pen);
    }
}

// Fills the rows top..bottom from left to right (inclusive), within the clip rectangle.
void _UiSpan(int left, int top, int right, int bottom)
{
    var c = _UiA.Clip;
    int x0 = Math.Max(left, c.X);
    int y0 = Math.Max(top, c.Y);
    int x1 = Math.Min(right, c.X + c.Width - 1);
    int y1 = Math.Min(bottom, c.Y + c.Height - 1);
    if (x0 > x1 || y0 > y1)
        return;
    unsafe
    {
        __gfx_RectFill(&_UiA.RastPort[0], x0, y0, x1, y1);
    }
}

// How far row `dy` (from the top or the bottom) of a rounded rectangle is indented: 0 below the corners.
int _UiInset(int radius, int dy)
{
    if (dy >= radius)
        return 0;
    double d = (double)radius - (double)dy - 0.5;
    return radius - (int)Math.Round(Math.Sqrt(Math.Max(0.0, (double)(radius * radius) - d * d)));
}

void _UiRoundRect(Rect r, int radius, int width)
{
    if (r.Width <= 0 || r.Height <= 0)
        return;
    int rad = Math.Clamp(radius, 0, Math.Min(r.Width, r.Height) / 2);
    int right = r.X + r.Width - 1;
    int bottom = r.Y + r.Height - 1;
    if (width <= 0)
    {
        // filled: the corner rows (runs of equal indents), then the middle
        int dy = 0;
        while (dy < rad)
        {
            int inset = _UiInset(rad, dy);
            int end = dy;
            while (end + 1 < rad && _UiInset(rad, end + 1) == inset)
                end += 1;
            _UiSpan(r.X + inset, r.Y + dy, right - inset, r.Y + end);
            _UiSpan(r.X + inset, bottom - end, right - inset, bottom - dy);
            dy = end + 1;
        }
        _UiSpan(r.X, r.Y + rad, right, bottom - rad);
        return;
    }
    // an outline: the bands at the top and the bottom, the sides between them
    int w = Math.Min(width, Math.Min(r.Width, r.Height) / 2);
    for (var dy = 0; dy < Math.Max(rad, w); dy += 1)
    {
        int inset = _UiInset(rad, dy);
        if (dy < w)
        {
            _UiSpan(r.X + inset, r.Y + dy, right - inset, r.Y + dy);
            _UiSpan(r.X + inset, bottom - dy, right - inset, bottom - dy);
        }
        else
        {
            _UiSpan(r.X + inset, r.Y + dy, r.X + inset + w - 1, r.Y + dy);
            _UiSpan(right - inset - w + 1, r.Y + dy, right - inset, r.Y + dy);
            _UiSpan(r.X + inset, bottom - dy, r.X + inset + w - 1, bottom - dy);
            _UiSpan(right - inset - w + 1, bottom - dy, right - inset, bottom - dy);
        }
    }
    int top = r.Y + Math.Max(rad, w);
    int low = bottom - Math.Max(rad, w);
    _UiSpan(r.X, top, r.X + w - 1, low);
    _UiSpan(right - w + 1, top, right, low);
}

void _UiCircle(double cx, double cy, double radius)
{
    int top = (int)Math.Floor(cy - radius);
    int bottom = (int)Math.Ceiling(cy + radius);
    int runStart = top;
    int runLeft = 0;
    int runRight = -1;
    for (var y = top; y <= bottom + 1; y += 1)
    {
        int left = 0;
        int right = -1;
        double dy = (double)y + 0.5 - cy;
        if (y <= bottom && Math.Abs(dy) < radius)
        {
            double half = Math.Sqrt(radius * radius - dy * dy);
            left = (int)Math.Round(cx - half);
            right = (int)Math.Round(cx + half) - 1;
        }
        if (left != runLeft || right != runRight)
        {
            if (runRight >= runLeft)
                _UiSpan(runLeft, runStart, runRight, y - 1);
            runStart = y;
            runLeft = left;
            runRight = right;
        }
    }
}

void _UiLine(UiCommand c)
{
    int x0 = (int)Math.Round(c.X0);
    int y0 = (int)Math.Round(c.Y0);
    int x1 = (int)Math.Round(c.X1);
    int y1 = (int)Math.Round(c.Y1);
    var clip = _UiA.Clip;
    // the RastPort has no layer: a line that leaves the clip rectangle is not drawn
    if (!clip.Contains(x0, y0) || !clip.Contains(x1, y1) || !clip.Contains(x0 + 1, y0) || !clip.Contains(x1 + 1, y1))
        return;
    unsafe
    {
        void* rp = &_UiA.RastPort[0];
        __gfx_Move(rp, x0, y0);
        __gfx_Draw(rp, x1, y1);
        if (c.Size >= 1.5)
        {
            // thicker: once more, one pixel to the right
            __gfx_Move(rp, x0 + 1, y0);
            __gfx_Draw(rp, x1 + 1, y1);
        }
    }
}

void _UiText(UiCommand c)
{
    var clip = _UiA.Clip;
    int cw = _UiA.FontWidth;
    int y = c.Rect.Y;
    if (y < clip.Y || y + _UiA.FontHeight > clip.Y + clip.Height || cw <= 0)
        return; // a line that is cut off at the top or the bottom (in a scroll area) is left out
    var bytes = _UiLatin1(c.Text);
    int count = bytes.Length - 1;
    // the characters that are completely inside, from left to right
    int first = 0;
    while (first < count && c.Rect.X + first * cw < clip.X)
        first += 1;
    int last = count;
    while (last > first && c.Rect.X + last * cw > clip.X + clip.Width)
        last -= 1;
    if (last <= first)
        return;
    unsafe
    {
        void* rp = &_UiA.RastPort[0];
        __gfx_Move(rp, c.Rect.X + first * cw, y + _UiA.FontBaseline);
        __gfx_Text(rp, (char*)&bytes[first], last - first);
    }
}

// A bitmap of the size of the inside of the window, like the screen's (friend), and the RastPort for it.
bool _UiBitMap()
{
    if (_UiA.BitMap != null && _UiA.BitMapWidth == _UiA.Width && _UiA.BitMapHeight == _UiA.Height)
        return true;
    unsafe
    {
        if (_UiA.BitMap != null)
        {
            __gfx_WaitBlit();
            __gfx_FreeBitMap(_UiA.BitMap);
            _UiA.BitMap = null;
        }
        if (_UiA.Width <= 0 || _UiA.Height <= 0)
            return false;
        void* windowRp = *(void**)((uint8*)_UiA.Window + 50);    // Window.RPort
        void* friendBm = *(void**)((uint8*)windowRp + 4);          // RastPort.BitMap
        int depth = (int)*((uint8*)friendBm + 5);                  // BitMap.Depth
        _UiA.BitMap = __gfx_AllocBitMap(_UiA.Width, _UiA.Height, depth, 0, friendBm);
        if (_UiA.BitMap == null)
            return false;
        _UiA.BitMapWidth = _UiA.Width;
        _UiA.BitMapHeight = _UiA.Height;
        void* rp = &_UiA.RastPort[0];
        __gfx_InitRastPort(rp);
        *(void**)((uint8*)rp + 4) = _UiA.BitMap;
        __gfx_SetFont(rp, _UiA.Font);
        __gfx_SetDrMd(rp, 0); // JAM1: text without a background
        _UiA.Pen = -1;
        return true;
    }
}

// The size of the inside of the window (without its borders).
void _UiInnerSize()
{
    unsafe
    {
        uint8* w = (uint8*)_UiA.Window;
        _UiA.Width = (int)*(int16*)(w + 8) - (int)w[54] - (int)w[56];
        _UiA.Height = (int)*(int16*)(w + 10) - (int)w[55] - (int)w[57];
    }
}

// One IntuiMessage: class at 20, code at 24, qualifier at 26, the mouse at 32 and 34 (relative to the window).
void _UiMessage(uint8* m)
{
    unsafe
    {
        int cls = *(int*)(m + 20);
        int code = (int)*(uint16*)(m + 24);
        int qualifier = (int)*(uint16*)(m + 26);
        uint8* w = (uint8*)_UiA.Window;
        int mx = (int)*(int16*)(m + 32) - (int)w[54];
        int my = (int)*(int16*)(m + 34) - (int)w[55];
        _UiA.Shift = (qualifier & 3) != 0;
        _UiA.Ctrl = (qualifier & 8) != 0;
        _UiA.Alt = (qualifier & 0x30) != 0;
        switch (cls)
        {
        case _IdcmpCloseWindow:
            _UiA.Closed = true;
            break;
        case _IdcmpNewSize:
            _UiInnerSize();
            break;
        case _IdcmpMouseMove:
            _UiA.MouseX = mx;
            _UiA.MouseY = my;
            break;
        case _IdcmpMouseButtons:
            _UiA.MouseX = mx;
            _UiA.MouseY = my;
            if (code == _SelectDown)
            {
                _UiA.MouseDown = true;
                _UiA.Pressed = true;
                _UiA.ButtonEvent = true;
            }
            else if (code == _SelectUp)
            {
                _UiA.MouseDown = false;
                _UiA.Released = true;
                _UiA.ButtonEvent = true;
            }
            break;
        case _IdcmpVanillaKey:
            _UiVanilla(code);
            break;
        case _IdcmpRawKey:
            _UiRawKey(code);
            break;
        default:
            break;
        }
    }
}

// A key with a character (VANILLAKEY: Latin-1, control characters for Ctrl+letter).
void _UiVanilla(int c)
{
    switch (c)
    {
    case 8: _UiA.Keys.Add(Key.Backspace); return;
    case 9: _UiA.Keys.Add(Key.Tab); return;
    case 13: _UiA.Keys.Add(Key.Enter); return;
    case 27: _UiA.Keys.Add(Key.Escape); return;
    case 127: _UiA.Keys.Add(Key.Delete); return;
    default: break;
    }
    if (c >= 1 && c <= 26)
    {
        _UiA.Keys.Add((Key)((int)Key.A + c - 1)); // Ctrl+A ... Ctrl+Z
        return;
    }
    if (c == 32)
        _UiA.Keys.Add(Key.Space);
    if (c >= 32 && c != 127 && !(c >= 128 && c < 160))
        _UiAppendUtf8(_UiA.Text, c);
}

// A key without a character (RAWKEY): the cursor keys, the function keys, the wheel of NewMouse.
void _UiRawKey(int code)
{
    switch (code)
    {
    case 0x4C: _UiA.Keys.Add(Key.Up); break;
    case 0x4D: _UiA.Keys.Add(Key.Down); break;
    case 0x4E: _UiA.Keys.Add(Key.Right); break;
    case 0x4F: _UiA.Keys.Add(Key.Left); break;
    case 0x7A: _UiA.Wheel += 1; break;
    case 0x7B: _UiA.Wheel -= 1; break;
    default:
        if (code >= 0x50 && code <= 0x59)
            _UiA.Keys.Add((Key)((int)Key.F1 + code - 0x50));
        break;
    }
}

struct _UiOs
{
    static bool Supported() { return true; }

    // the window draws the frames of a Ui itself, from its commands
    static bool DrawsCommands() { return true; }
    static Font UiFont() { return Font.Metrics(Math.Max(1, _UiA.FontWidth), Math.Max(1, _UiA.FontHeight), _UiA.FontBaseline); }
    // the program is only woken by input: the text cursor does not blink
    static bool Blinks() { return false; }

    // 0: open, 3: failed, 4: a window is already open, 5: AmigaOS is older than 3.0
    static int Open(string title, int width, int height)
    {
        if (_UiA.Open)
            return 4;
        unsafe
        {
            void* gfx = __exec_OpenLibrary("graphics.library".CStr(), 39);
            void* intuition = __exec_OpenLibrary("intuition.library".CStr(), 39);
            if (gfx == null || intuition == null)
            {
                if (gfx != null)
                    __exec_CloseLibrary(gfx);
                if (intuition != null)
                    __exec_CloseLibrary(intuition);
                return 5;
            }
            __cs_amiga_set(_VarGfxBase, (int)(nint)gfx);
            __cs_amiga_set(_VarIntuitionBase, (int)(nint)intuition);
            _UiA = _UiAmiga { Gfx = gfx, Intuition = intuition, Pens = Dictionary<uint32, int>.Create(), Keys = List<Key>.Create(),
                              Text = StringBuilder.Create(), RastPort = new uint8[100], Pen = -1, MouseX = -1, MouseY = -1 };
            _UiA.Title = _UiLatin1(title);
            int idcmp = _IdcmpNewSize | _IdcmpMouseButtons | _IdcmpMouseMove | _IdcmpCloseWindow | _IdcmpRawKey | _IdcmpVanillaKey;
            int[] tags = [
                unchecked((int)0x80000076u), width,                         // WA_InnerWidth
                unchecked((int)0x80000077u), height,                        // WA_InnerHeight
                unchecked((int)0x8000006Eu), (int)(nint)&_UiA.Title[0],     // WA_Title
                unchecked((int)0x8000006Au), idcmp,                         // WA_IDCMP
                unchecked((int)0x80000082u), 1,                             // WA_DragBar
                unchecked((int)0x80000083u), 1,                             // WA_DepthGadget
                unchecked((int)0x80000084u), 1,                             // WA_CloseGadget
                unchecked((int)0x80000081u), 1,                             // WA_SizeGadget
                unchecked((int)0x80000072u), 120,                           // WA_MinWidth
                unchecked((int)0x80000073u), 60,                            // WA_MinHeight
                unchecked((int)0x80000074u), -1,                            // WA_MaxWidth: the screen's
                unchecked((int)0x80000075u), -1,                            // WA_MaxHeight
                unchecked((int)0x80000086u), 1,                             // WA_ReportMouse
                unchecked((int)0x8000008Au), 1,                             // WA_RMBTrap: no menus
                unchecked((int)0x8000008Du), 1,                             // WA_SmartRefresh
                unchecked((int)0x80000087u), 1,                             // WA_NoCareRefresh
                unchecked((int)0x80000089u), 1,                             // WA_Activate
                0];                                                         // TAG_DONE
            void* window = __intuition_OpenWindowTagList(null, &tags[0]);
            if (window == null)
            {
                __exec_CloseLibrary(intuition);
                __exec_CloseLibrary(gfx);
                _UiA = _UiAmiga { };
                return 3;
            }
            _UiA.Window = window;
            _UiA.Open = true;
            _UiA.Port = *(void**)((uint8*)window + 86);                  // Window.UserPort
            void* screen = *(void**)((uint8*)window + 46);                // Window.WScreen
            _UiA.ColorMap = *(void**)((uint8*)screen + 44 + 4);           // Screen.ViewPort.ColorMap
            // the system font (fixed width): GfxBase->DefaultFont
            void* font = *(void**)((uint8*)gfx + 154);
            _UiA.Font = font;
            _UiA.FontHeight = (int)*(uint16*)((uint8*)font + 20);        // tf_YSize
            _UiA.FontWidth = (int)*(uint16*)((uint8*)font + 24);         // tf_XSize
            _UiA.FontBaseline = (int)*(uint16*)((uint8*)font + 26);      // tf_Baseline
            _UiInnerSize();
            return 0;
        }
    }

    static bool Pump(int waitMs)
    {
        if (!_UiA.Open)
            return false;
        unsafe
        {
            // no timer: any wait is a wait for input (WaitPort returns at once if a message is there)
            if (waitMs != 0 && !_UiA.Closed)
                __exec_WaitPort(_UiA.Port);
            _UiA.ButtonEvent = false;
            while (!_UiA.ButtonEvent)
            {
                uint8* m = (uint8*)__exec_GetMsg(_UiA.Port);
                if (m == null)
                    break;
                _UiMessage(m);
                __exec_ReplyMsg(m);
            }
        }
        return !_UiA.Closed;
    }

    static UiInput TakeInput()
    {
        var input = UiInput.Create();
        if (!_UiA.Open)
            return input;
        input.MouseX = _UiA.MouseX;
        input.MouseY = _UiA.MouseY;
        input.MouseDown = _UiA.MouseDown;
        input.MousePressed = _UiA.Pressed;
        input.MouseReleased = _UiA.Released;
        input.Wheel = _UiA.Wheel;
        foreach (var key in _UiA.Keys)
            input.Keys.Add(key);
        input.Text = _UiA.Text.ToString();
        input.Ctrl = _UiA.Ctrl;
        input.Shift = _UiA.Shift;
        input.Alt = _UiA.Alt;
        _UiA.Pressed = false;
        _UiA.Released = false;
        _UiA.Wheel = 0;
        _UiA.Keys.Clear();
        _UiA.Text.Clear();
        return input;
    }

    static int Width() { return _UiA.Width; }
    static int Height() { return _UiA.Height; }
    static double Scale() { return 1.0; }

    static void Present(Image image) { } // images are not shown

    static void PresentCommands(List<UiCommand> commands)
    {
        if (!_UiA.Open || !_UiBitMap())
            return;
        var bounds = Rect.Create(0, 0, _UiA.BitMapWidth, _UiA.BitMapHeight);
        _UiA.Clip = bounds;
        foreach (var c in commands)
        {
            switch (c.Kind)
            {
            case UiCommandKind.Clear:
                _UiSetPen(c.Color);
                _UiSpan(0, 0, bounds.Width - 1, bounds.Height - 1);
                break;
            case UiCommandKind.Clip:
                _UiA.Clip = c.Rect.Intersect(bounds);
                break;
            case UiCommandKind.FillRect:
                _UiSetPen(c.Color);
                _UiSpan(c.Rect.X, c.Rect.Y, c.Rect.X + c.Rect.Width - 1, c.Rect.Y + c.Rect.Height - 1);
                break;
            case UiCommandKind.FillRoundRect:
                _UiSetPen(c.Color);
                _UiRoundRect(c.Rect, c.Radius, 0);
                break;
            case UiCommandKind.StrokeRoundRect:
                _UiSetPen(c.Color);
                _UiRoundRect(c.Rect, c.Radius, Math.Max(1, c.Width));
                break;
            case UiCommandKind.FillCircle:
                _UiSetPen(c.Color);
                _UiCircle(c.X0, c.Y0, c.Size);
                break;
            case UiCommandKind.Line:
                _UiSetPen(c.Color);
                _UiLine(c);
                break;
            case UiCommandKind.Text:
                _UiSetPen(c.Color);
                _UiText(c);
                break;
            case UiCommandKind.Image:
                break;
            }
        }
        unsafe
        {
            uint8* w = (uint8*)_UiA.Window;
            void* windowRp = *(void**)(w + 50);
            __gfx_BltBitMapRastPort(_UiA.BitMap, 0, 0, windowRp, (int)w[54], (int)w[55], _UiA.BitMapWidth, _UiA.BitMapHeight, 0xC0);
        }
    }

    static void SetPointer(Cursor cursor) { }

    static void SetTitle(string title)
    {
        if (!_UiA.Open)
            return;
        _UiA.Title = _UiLatin1(title);
        unsafe
        {
            __intuition_SetWindowTitles(_UiA.Window, (char*)&_UiA.Title[0], (char*)(nint)(-1));
        }
    }

    static void Close()
    {
        if (!_UiA.Open)
            return;
        unsafe
        {
            __intuition_CloseWindow(_UiA.Window);
            __gfx_WaitBlit();
            if (_UiA.BitMap != null)
                __gfx_FreeBitMap(_UiA.BitMap);
            foreach (var pen in _UiA.Pens.Values())
                __gfx_ReleasePen(_UiA.ColorMap, pen);
            __exec_CloseLibrary(_UiA.Intuition);
            __exec_CloseLibrary(_UiA.Gfx);
            __cs_amiga_set(_VarIntuitionBase, 0);
            __cs_amiga_set(_VarGfxBase, 0);
        }
        _UiA = _UiAmiga { };
    }

    static string GetClipboard() { return _UiClipboardText; }
    static void SetClipboard(string text) { _UiClipboardText = text; }
}
