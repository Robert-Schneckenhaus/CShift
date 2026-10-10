// The window part of the operating system layer on Windows (Win32 and GDI) for System.Ui (stdlib/ui_window.csh); see
// stdlib/os/posix/ui.csh for the same struct with X11. One window: its state is in the global _UiWin, which the
// window procedure (called by Windows during DispatchMessage) fills in. The window is per-monitor DPI aware, so the
// frames are drawn in the screen's own pixels (Window.Scale) instead of being stretched by Windows. A frame is copied
// to the window with SetDIBitsToDevice: the ARGB pixels of an Image are the layout of a 32-bit DIB.

namespace System.Ui;

using System;
using System.Image;

link "user32";
link "gdi32";

extern "C" void* GetModuleHandleW(void* name);
extern "C" uint16 RegisterClassExW(void* windowClass);
extern "C" void* CreateWindowExW(uint32 exStyle, void* className, void* title, uint32 style, int x, int y, int width, int height,
                                 void* parent, void* menu, void* instance, void* param);
extern "C" nint DefWindowProcW(void* window, uint32 message, nuint wParam, nint lParam);
extern "C" int PeekMessageW(void* message, void* window, uint32 first, uint32 last, uint32 remove);
extern "C" int TranslateMessage(void* message);
extern "C" nint DispatchMessageW(void* message);
extern "C" uint32 MsgWaitForMultipleObjectsEx(uint32 count, void* handles, uint32 milliseconds, uint32 wakeMask, uint32 flags);
extern "C" int ShowWindow(void* window, int command);
extern "C" int DestroyWindow(void* window);
extern "C" void* GetDC(void* window);
extern "C" int ReleaseDC(void* window, void* dc);
extern "C" void* BeginPaint(void* window, void* paint);
extern "C" int EndPaint(void* window, void* paint);
extern "C" int SetDIBitsToDevice(void* dc, int x, int y, uint32 width, uint32 height, int srcX, int srcY, uint32 startLine, uint32 lines,
                                 void* bits, void* info, uint32 usage);
extern "C" void* LoadCursorW(void* instance, nint name);
extern "C" void* SetCursor(void* cursor);
extern "C" void* SetCapture(void* window);
extern "C" int ReleaseCapture();
extern "C" int SetWindowTextW(void* window, void* text);
extern "C" int SetWindowPos(void* window, void* after, int x, int y, int width, int height, uint32 flags);
extern "C" int AdjustWindowRectExForDpi(int* rect, uint32 style, int menu, uint32 exStyle, uint32 dpi);
extern "C" int SetProcessDpiAwarenessContext(nint context);
extern "C" uint32 GetDpiForWindow(void* window);
extern "C" int16 GetKeyState(int key);
extern "C" int OpenClipboard(void* window);
extern "C" int CloseClipboard();
extern "C" int EmptyClipboard();
extern "C" void* GetClipboardData(uint32 format);
extern "C" void* SetClipboardData(uint32 format, void* memory);
extern "C" void* GlobalAlloc(uint32 flags, nuint bytes);
extern "C" void* GlobalFree(void* memory);
extern "C" void* GlobalLock(void* memory);
extern "C" int GlobalUnlock(void* memory);
extern "C" int MultiByteToWideChar(uint32 codePage, uint32 flags, char* text, int length, uint16* wide, int wideLength);
extern "C" int WideCharToMultiByte(uint32 codePage, uint32 flags, uint16* wide, int wideLength, char* text, int length, void* defaultChar,
                                   void* usedDefault);

// The state of the window (zero until the first Open).
struct _UiWin32
{
    void* Hwnd;
    bool Open;
    bool Closed;          // the user asked to close it
    int Width;
    int Height;
    uint32 Dpi;
    int MouseX;
    int MouseY;
    bool MouseDown;
    bool Pressed;
    bool Released;
    bool ButtonEvent;     // a button changed in this round of messages: stop, so that it gets a frame of its own
    int WheelDelta;       // 1/120 notches
    List<Key> Keys;
    StringBuilder Text;
    int HighSurrogate;
    Image Last;           // the last frame, for WM_PAINT
    void* CursorArrow;
    void* CursorText;
    void* CursorHand;
    void* Cursor;
}

_UiWin32 _UiWin;

const uint32 _WmSize = 0x0005u;
const uint32 _WmPaint = 0x000Fu;
const uint32 _WmClose = 0x0010u;
const uint32 _WmEraseBackground = 0x0014u;
const uint32 _WmSetCursor = 0x0020u;
const uint32 _WmKeyDown = 0x0100u;
const uint32 _WmChar = 0x0102u;
const uint32 _WmSysKeyDown = 0x0104u;
const uint32 _WmMouseMove = 0x0200u;
const uint32 _WmLButtonDown = 0x0201u;
const uint32 _WmLButtonUp = 0x0202u;
const uint32 _WmMouseWheel = 0x020Au;
const uint32 _WmDpiChanged = 0x02E0u;
const uint32 _WsOverlappedWindow = 0x00CF0000u;

// The window procedure: Windows calls it for the messages of the window.
nint _UiWndProc(void* hwnd, uint32 message, nuint wParam, nint lParam)
{
    unsafe
    {
        switch (message)
        {
        case _WmClose:
            _UiWin.Closed = true;
            return 0;
        case _WmSize:
            _UiWin.Width = (int)(lParam & 0xFFFF);
            _UiWin.Height = (int)((lParam >> 16) & 0xFFFF);
            return 0;
        case _WmEraseBackground:
            return 1;
        case _WmPaint:
        {
            var paint = new uint8[80]; // PAINTSTRUCT
            void* dc = BeginPaint(hwnd, &paint[0]);
            _UiBlit(dc, _UiWin.Last);
            EndPaint(hwnd, &paint[0]);
            return 0;
        }
        case _WmSetCursor:
            if ((lParam & 0xFFFF) == 1 && _UiWin.Cursor != null) // HTCLIENT
            {
                SetCursor(_UiWin.Cursor);
                return 1;
            }
            break;
        case _WmMouseMove:
            _UiWin.MouseX = (int)(int16)(lParam & 0xFFFF);
            _UiWin.MouseY = (int)(int16)((lParam >> 16) & 0xFFFF);
            return 0;
        case _WmLButtonDown:
            _UiWin.MouseX = (int)(int16)(lParam & 0xFFFF);
            _UiWin.MouseY = (int)(int16)((lParam >> 16) & 0xFFFF);
            _UiWin.MouseDown = true;
            _UiWin.Pressed = true;
            _UiWin.ButtonEvent = true;
            SetCapture(hwnd);
            return 0;
        case _WmLButtonUp:
            _UiWin.MouseX = (int)(int16)(lParam & 0xFFFF);
            _UiWin.MouseY = (int)(int16)((lParam >> 16) & 0xFFFF);
            _UiWin.MouseDown = false;
            _UiWin.Released = true;
            _UiWin.ButtonEvent = true;
            ReleaseCapture();
            return 0;
        case _WmMouseWheel:
            _UiWin.WheelDelta += (int)(int16)((wParam >> 16) & 0xFFFFu);
            return 0;
        case _WmKeyDown:
        case _WmSysKeyDown:
        {
            var key = _UiKeyOf((int)(wParam & 0xFFu));
            if (key != Key.None)
                _UiWin.Keys.Add(key);
            if (message == _WmKeyDown)
                return 0;
            break; // Alt+F4 and the like
        }
        case _WmChar:
            _UiChar((int)(wParam & 0xFFFFu));
            return 0;
        case _WmDpiChanged:
        {
            _UiWin.Dpi = (uint32)(wParam & 0xFFFFu);
            int* r = (int*)lParam; // the suggested rectangle
            SetWindowPos(hwnd, null, r[0], r[1], r[2] - r[0], r[3] - r[1], 0x0014u); // SWP_NOZORDER | SWP_NOACTIVATE
            return 0;
        }
        default:
            break;
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
}

// A typed character (UTF-16 code unit, surrogate pairs are combined) as UTF-8 into the text of the frame.
void _UiChar(int unit)
{
    if (unit >= 0xD800 && unit < 0xDC00)
    {
        _UiWin.HighSurrogate = unit;
        return;
    }
    int code = unit;
    if (unit >= 0xDC00 && unit < 0xE000)
    {
        if (_UiWin.HighSurrogate == 0)
            return;
        code = 0x10000 + ((_UiWin.HighSurrogate - 0xD800) << 10) + (unit - 0xDC00);
        _UiWin.HighSurrogate = 0;
    }
    if (code < 32 || code == 127)
        return; // control characters come as keys
    var sb = _UiWin.Text;
    if (code < 0x80)
        sb.Append((char)code);
    else if (code < 0x800)
    {
        sb.Append((char)(0xC0 | (code >> 6)));
        sb.Append((char)(0x80 | (code & 0x3F)));
    }
    else if (code < 0x10000)
    {
        sb.Append((char)(0xE0 | (code >> 12)));
        sb.Append((char)(0x80 | ((code >> 6) & 0x3F)));
        sb.Append((char)(0x80 | (code & 0x3F)));
    }
    else
    {
        sb.Append((char)(0xF0 | (code >> 18)));
        sb.Append((char)(0x80 | ((code >> 12) & 0x3F)));
        sb.Append((char)(0x80 | ((code >> 6) & 0x3F)));
        sb.Append((char)(0x80 | (code & 0x3F)));
    }
}

// The Key of a virtual key code.
Key _UiKeyOf(int vk)
{
    if (vk >= 0x41 && vk <= 0x5A)
        return (Key)((int)Key.A + vk - 0x41);
    if (vk >= 0x30 && vk <= 0x39)
        return (Key)((int)Key.D0 + vk - 0x30);
    if (vk >= 0x70 && vk <= 0x7B)
        return (Key)((int)Key.F1 + vk - 0x70);
    switch (vk)
    {
    case 0x0D: return Key.Enter;
    case 0x1B: return Key.Escape;
    case 0x08: return Key.Backspace;
    case 0x2E: return Key.Delete;
    case 0x09: return Key.Tab;
    case 0x20: return Key.Space;
    case 0x2D: return Key.Insert;
    case 0x25: return Key.Left;
    case 0x26: return Key.Up;
    case 0x27: return Key.Right;
    case 0x28: return Key.Down;
    case 0x24: return Key.Home;
    case 0x23: return Key.End;
    case 0x21: return Key.PageUp;
    case 0x22: return Key.PageDown;
    default: return Key.None;
    }
}

// Copies an image to a device context (top-down, 32 bits per pixel).
void _UiBlit(void* dc, Image image)
{
    if (image.Width <= 0 || image.Height <= 0 || dc == null)
        return;
    unsafe
    {
        var info = new int32[10]; // BITMAPINFOHEADER
        info[0] = 40;
        info[1] = image.Width;
        info[2] = -image.Height; // negative: the first row is the top one
        info[3] = 1 | (32 << 16); // planes, bits per pixel
        SetDIBitsToDevice(dc, 0, 0, (uint32)image.Width, (uint32)image.Height, 0, 0, 0u, (uint32)image.Height, &image.Pixels[0], &info[0], 0u);
    }
}

// A string as a NUL-terminated UTF-16 string.
uint16[] _UiWide(string text)
{
    unsafe
    {
        int length = MultiByteToWideChar(65001u, 0u, text.CStr(), -1, null, 0);
        var wide = new uint16[Math.Max(1, length)];
        if (length > 0)
            MultiByteToWideChar(65001u, 0u, text.CStr(), -1, &wide[0], length);
        return wide;
    }
}

struct _UiOs
{
    static bool Supported() { return true; }

    // 0: open, 1: failed, 4: a window is already open
    static int Open(string title, int width, int height)
    {
        if (_UiWin.Open)
            return 4;
        unsafe
        {
            SetProcessDpiAwarenessContext(-4); // per monitor v2 (fails harmlessly if it was set before)
            void* instance = GetModuleHandleW(null);
            var className = _UiWide("CShiftWindow");
            Func<void*, uint32, nuint, nint, nint> proc = _UiWndProc;
            var wc = new int64[10]; // WNDCLASSEXW
            wc[0] = 80 | (3L << 32); // cbSize, CS_HREDRAW | CS_VREDRAW
            wc[1] = (int64)(nint)(void*)proc;
            wc[3] = (int64)(nint)instance;
            wc[8] = (int64)(nint)(void*)&className[0];
            RegisterClassExW(&wc[0]); // fails the second time: the class exists already
            var wideTitle = _UiWide(title);
            void* hwnd = CreateWindowExW(0u, &className[0], &wideTitle[0], _WsOverlappedWindow, (int)0x80000000u, (int)0x80000000u, width, height,
                                         null, null, instance, null);
            if (hwnd == null)
                return 1;
            _UiWin = _UiWin32 { Hwnd = hwnd, Open = true, Keys = List<Key>.Create(), Text = StringBuilder.Create(), Last = Image.Create(0, 0),
                                MouseX = -1, MouseY = -1 };
            _UiWin.CursorArrow = LoadCursorW(null, 32512);
            _UiWin.CursorText = LoadCursorW(null, 32513);
            _UiWin.CursorHand = LoadCursorW(null, 32649);
            _UiWin.Cursor = _UiWin.CursorArrow;
            // the size for the screen's scale
            _UiWin.Dpi = GetDpiForWindow(hwnd);
            if (_UiWin.Dpi == 0u)
                _UiWin.Dpi = 96u;
            var rect = new int[4];
            rect[2] = (int)Math.Round((double)width * (double)_UiWin.Dpi / 96.0);
            rect[3] = (int)Math.Round((double)height * (double)_UiWin.Dpi / 96.0);
            AdjustWindowRectExForDpi(&rect[0], _WsOverlappedWindow, 0, 0u, _UiWin.Dpi);
            SetWindowPos(hwnd, null, 0, 0, rect[2] - rect[0], rect[3] - rect[1], 0x0016u); // SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
            ShowWindow(hwnd, 1);
            return 0;
        }
    }

    static bool Pump(int waitMs)
    {
        if (!_UiWin.Open)
            return false;
        unsafe
        {
            if (waitMs != 0 && !_UiWin.Closed)
            {
                uint32 ms = waitMs < 0 ? 0xFFFFFFFFu : (uint32)waitMs;
                MsgWaitForMultipleObjectsEx(0u, null, ms, 0x04FFu, 0x0004u); // QS_ALLINPUT, MWMO_INPUTAVAILABLE
            }
            var msg = new int64[6]; // MSG
            _UiWin.ButtonEvent = false;
            while (!_UiWin.ButtonEvent && PeekMessageW(&msg[0], null, 0u, 0u, 1u) != 0) // PM_REMOVE
            {
                TranslateMessage(&msg[0]);
                DispatchMessageW(&msg[0]);
            }
        }
        return !_UiWin.Closed;
    }

    static UiInput TakeInput()
    {
        var input = UiInput.Create();
        if (!_UiWin.Open)
            return input;
        input.MouseX = _UiWin.MouseX;
        input.MouseY = _UiWin.MouseY;
        input.MouseDown = _UiWin.MouseDown;
        input.MousePressed = _UiWin.Pressed;
        input.MouseReleased = _UiWin.Released;
        input.Wheel = _UiWin.WheelDelta / 120;
        _UiWin.WheelDelta -= input.Wheel * 120;
        foreach (var key in _UiWin.Keys)
            input.Keys.Add(key);
        input.Text = _UiWin.Text.ToString();
        input.Ctrl = GetKeyState(0x11) < 0;
        input.Shift = GetKeyState(0x10) < 0;
        input.Alt = GetKeyState(0x12) < 0;
        _UiWin.Pressed = false;
        _UiWin.Released = false;
        _UiWin.Keys.Clear();
        _UiWin.Text.Clear();
        return input;
    }

    static int Width() { return _UiWin.Width; }
    static int Height() { return _UiWin.Height; }
    static double Scale() { return _UiWin.Dpi > 0u ? (double)_UiWin.Dpi / 96.0 : 1.0; }

    static void Present(Image image)
    {
        if (!_UiWin.Open)
            return;
        _UiWin.Last = image;
        unsafe
        {
            void* dc = GetDC(_UiWin.Hwnd);
            _UiBlit(dc, image);
            ReleaseDC(_UiWin.Hwnd, dc);
        }
    }

    static void SetPointer(Cursor cursor)
    {
        void* wanted = cursor == Cursor.Text ? _UiWin.CursorText : cursor == Cursor.Hand ? _UiWin.CursorHand : _UiWin.CursorArrow;
        if (wanted != _UiWin.Cursor)
        {
            _UiWin.Cursor = wanted;
            unsafe
            {
                SetCursor(wanted);
            }
        }
    }

    static void SetTitle(string title)
    {
        if (!_UiWin.Open)
            return;
        var wide = _UiWide(title);
        unsafe
        {
            SetWindowTextW(_UiWin.Hwnd, &wide[0]);
        }
    }

    static void Close()
    {
        if (!_UiWin.Open)
            return;
        unsafe
        {
            DestroyWindow(_UiWin.Hwnd);
        }
        _UiWin = _UiWin32 { };
    }

    static string GetClipboard()
    {
        unsafe
        {
            if (OpenClipboard(_UiWin.Hwnd) == 0)
                return "";
            string text = "";
            void* data = GetClipboardData(13u); // CF_UNICODETEXT
            if (data != null)
            {
                uint16* wide = (uint16*)GlobalLock(data);
                if (wide != null)
                {
                    int length = WideCharToMultiByte(65001u, 0u, wide, -1, null, 0, null, null);
                    if (length > 0)
                    {
                        char* buffer = (char*)Memory.Allocate(length);
                        WideCharToMultiByte(65001u, 0u, wide, -1, buffer, length, null, null);
                        text = string.FromCStr(buffer);
                        Memory.Free(buffer);
                    }
                    GlobalUnlock(data);
                }
            }
            CloseClipboard();
            return text;
        }
    }

    static void SetClipboard(string text)
    {
        var wide = _UiWide(text);
        unsafe
        {
            if (OpenClipboard(_UiWin.Hwnd) == 0)
                return;
            EmptyClipboard();
            void* memory = GlobalAlloc(0x0002u, (nuint)(wide.Length * 2)); // GMEM_MOVEABLE
            if (memory != null)
            {
                uint16* target = (uint16*)GlobalLock(memory);
                for (var i = 0; i < wide.Length; i += 1)
                    target[i] = wide[i];
                GlobalUnlock(memory);
                if (SetClipboardData(13u, memory) == null)
                    GlobalFree(memory);
            }
            CloseClipboard();
        }
    }
}
