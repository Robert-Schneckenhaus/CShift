// The window part of the operating system layer on POSIX systems (Linux, and macOS with XQuartz) for System.Ui
// (stdlib/ui_window.csh), with X11; see stdlib/os/windows/ui.csh for the same struct with Win32. libX11 is loaded with
// dlopen when the first window opens, so programs without a window neither link nor need it. Its functions are called
// through function values (_UiX), and its structs are read at the offsets of the C layout: P is the size of a pointer
// (and of a long), so the offsets hold for 32 and 64 bits. A frame is shown with XPutImage: the ARGB pixels of an Image
// are the layout of a 24-bit TrueColor ZPixmap (32 bits per pixel). The scale comes from Xft.dpi (96 dpi = 1).
// The clipboard is kept inside the program for now (X11 selections need a protocol of events).

namespace System.Ui;

using System;
using System.Image;

extern "C" void* dlopen(char* file, int mode);
extern "C" void* dlsym(void* handle, char* name);
extern "C" int poll(void* fds, nuint count, int timeout);

// The functions of libX11 that the window needs.
struct _UiXApi
{
    Func<char*, void*> OpenDisplay;
    Func<void*, int> CloseDisplay;
    Func<void*, int> DefaultScreen;
    Func<void*, int, nuint> RootWindow;
    Func<void*, int, void*> DefaultVisual;
    Func<void*, int, int> DefaultDepth;
    Func<void*, int, void*> DefaultGC;
    Func<void*, int> ConnectionNumber;
    Func<void*, char*> ResourceManagerString;
    Func<void*, nuint, int, int, uint32, uint32, uint32, nuint, nuint, nuint> CreateSimpleWindow;
    Func<void*, nuint, int> DestroyWindow;
    Func<void*, nuint, int> MapWindow;
    Func<void*, nuint, nint, int> SelectInput;
    Func<void*, char*, int, nuint> InternAtom;
    Func<void*, nuint, void*, int, int> SetWMProtocols;
    Func<void*, nuint, nuint, nuint, int, int, void*, int, int> ChangeProperty;
    Func<void*, nuint, char*, int> StoreName;
    Func<void*, int> Pending;
    Func<void*, void*, int> NextEvent;
    Func<void*, char*, int, void*, void*, int> LookupString;
    Func<void*, void*, uint32, int, int, char*, uint32, uint32, int, int, void*> CreateImage;
    Func<void*, nuint, void*, void*, int, int, int, int, uint32, uint32, int> PutImage;
    Func<void*, int> Free;
    Func<void*, int> Flush;
    Func<void*, uint32, nuint> CreateFontCursor;
    Func<void*, nuint, nuint, int> DefineCursor;
}

// The state of the window (zero until the first Open).
struct _UiXWindow
{
    bool Loaded;
    bool Open;
    bool Closed;
    void* Display;
    nuint Window;
    int Screen;
    void* Gc;
    void* Visual;
    int Depth;
    nuint DeleteAtom;
    int Width;
    int Height;
    double Scale;
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
    Image Last;
    nuint CursorArrow;
    nuint CursorText;
    nuint CursorHand;
    Cursor Cursor;
}

_UiXApi _UiX;
_UiXWindow _UiXw;
string _UiClipboardText;

// Loads libX11 and looks up its functions; false if it is missing.
bool _UiXLoad()
{
    if (_UiXw.Loaded)
        return true;
    unsafe
    {
        void* lib = dlopen("libX11.so.6".CStr(), 2); // RTLD_NOW
        if (lib == null)
            lib = dlopen("libX11.so".CStr(), 2);
        if (lib == null)
            lib = dlopen("/opt/X11/lib/libX11.6.dylib".CStr(), 2); // XQuartz
        if (lib == null)
            return false;
        bool ok = true;
        _UiX.OpenDisplay = (Func<char*, void*>)_UiXSym(lib, "XOpenDisplay", ref ok);
        _UiX.CloseDisplay = (Func<void*, int>)_UiXSym(lib, "XCloseDisplay", ref ok);
        _UiX.DefaultScreen = (Func<void*, int>)_UiXSym(lib, "XDefaultScreen", ref ok);
        _UiX.RootWindow = (Func<void*, int, nuint>)_UiXSym(lib, "XRootWindow", ref ok);
        _UiX.DefaultVisual = (Func<void*, int, void*>)_UiXSym(lib, "XDefaultVisual", ref ok);
        _UiX.DefaultDepth = (Func<void*, int, int>)_UiXSym(lib, "XDefaultDepth", ref ok);
        _UiX.DefaultGC = (Func<void*, int, void*>)_UiXSym(lib, "XDefaultGC", ref ok);
        _UiX.ConnectionNumber = (Func<void*, int>)_UiXSym(lib, "XConnectionNumber", ref ok);
        _UiX.ResourceManagerString = (Func<void*, char*>)_UiXSym(lib, "XResourceManagerString", ref ok);
        _UiX.CreateSimpleWindow = (Func<void*, nuint, int, int, uint32, uint32, uint32, nuint, nuint, nuint>)_UiXSym(lib, "XCreateSimpleWindow", ref ok);
        _UiX.DestroyWindow = (Func<void*, nuint, int>)_UiXSym(lib, "XDestroyWindow", ref ok);
        _UiX.MapWindow = (Func<void*, nuint, int>)_UiXSym(lib, "XMapWindow", ref ok);
        _UiX.SelectInput = (Func<void*, nuint, nint, int>)_UiXSym(lib, "XSelectInput", ref ok);
        _UiX.InternAtom = (Func<void*, char*, int, nuint>)_UiXSym(lib, "XInternAtom", ref ok);
        _UiX.SetWMProtocols = (Func<void*, nuint, void*, int, int>)_UiXSym(lib, "XSetWMProtocols", ref ok);
        _UiX.ChangeProperty = (Func<void*, nuint, nuint, nuint, int, int, void*, int, int>)_UiXSym(lib, "XChangeProperty", ref ok);
        _UiX.StoreName = (Func<void*, nuint, char*, int>)_UiXSym(lib, "XStoreName", ref ok);
        _UiX.Pending = (Func<void*, int>)_UiXSym(lib, "XPending", ref ok);
        _UiX.NextEvent = (Func<void*, void*, int>)_UiXSym(lib, "XNextEvent", ref ok);
        _UiX.LookupString = (Func<void*, char*, int, void*, void*, int>)_UiXSym(lib, "XLookupString", ref ok);
        _UiX.CreateImage = (Func<void*, void*, uint32, int, int, char*, uint32, uint32, int, int, void*>)_UiXSym(lib, "XCreateImage", ref ok);
        _UiX.PutImage = (Func<void*, nuint, void*, void*, int, int, int, int, uint32, uint32, int>)_UiXSym(lib, "XPutImage", ref ok);
        _UiX.Free = (Func<void*, int>)_UiXSym(lib, "XFree", ref ok);
        _UiX.Flush = (Func<void*, int>)_UiXSym(lib, "XFlush", ref ok);
        _UiX.CreateFontCursor = (Func<void*, uint32, nuint>)_UiXSym(lib, "XCreateFontCursor", ref ok);
        _UiX.DefineCursor = (Func<void*, nuint, nuint, int>)_UiXSym(lib, "XDefineCursor", ref ok);
        _UiXw.Loaded = ok;
        return ok;
    }
}

void* _UiXSym(void* lib, string name, ref bool ok)
{
    unsafe
    {
        void* p = dlsym(lib, name.CStr());
        if (p == null)
            ok = false;
        return p;
    }
}

// Xft.dpi from the X resources (set by the desktop for its scale), as a scale: 96 dpi = 1.
double _UiXScale(void* display)
{
    unsafe
    {
        char* resources = _UiX.ResourceManagerString(display);
        if (resources == null)
            return 1.0;
        string text = string.FromCStr(resources);
        int at = text.IndexOf("Xft.dpi:");
        if (at < 0)
            return 1.0;
        int i = at + 8;
        while (i < text.Length && (text[i] == ' ' || text[i] == '\t'))
            i += 1;
        int dpi = 0;
        while (i < text.Length && text[i] >= '0' && text[i] <= '9')
        {
            dpi = dpi * 10 + (int)(text[i] - '0');
            i += 1;
        }
        return dpi >= 48 ? (double)dpi / 96.0 : 1.0;
    }
}

// The Key of an X keysym.
Key _UiXKeyOf(nuint keysym)
{
    int k = (int)keysym;
    if (k >= 0x61 && k <= 0x7A)
        return (Key)((int)Key.A + k - 0x61);
    if (k >= 0x41 && k <= 0x5A)
        return (Key)((int)Key.A + k - 0x41);
    if (k >= 0x30 && k <= 0x39)
        return (Key)((int)Key.D0 + k - 0x30);
    if (k >= 0xFFBE && k <= 0xFFC9)
        return (Key)((int)Key.F1 + k - 0xFFBE);
    switch (k)
    {
    case 0xFF0D: return Key.Enter;
    case 0xFF8D: return Key.Enter;
    case 0xFF1B: return Key.Escape;
    case 0xFF08: return Key.Backspace;
    case 0xFFFF: return Key.Delete;
    case 0xFF09: return Key.Tab;
    case 0xFE20: return Key.Tab; // Shift+Tab
    case 0x20: return Key.Space;
    case 0xFF63: return Key.Insert;
    case 0xFF51: return Key.Left;
    case 0xFF52: return Key.Up;
    case 0xFF53: return Key.Right;
    case 0xFF54: return Key.Down;
    case 0xFF50: return Key.Home;
    case 0xFF57: return Key.End;
    case 0xFF55: return Key.PageUp;
    case 0xFF56: return Key.PageDown;
    default: return Key.None;
    }
}

// The character of a keysym (Latin-1 keysyms are their code points, 0x01000000 + U the others), or 0.
int _UiXCharOf(nuint keysym)
{
    int k = (int)keysym;
    if ((k >= 0x20 && k <= 0x7E) || (k >= 0xA0 && k <= 0xFF))
        return k;
    if (k >= 0x01000100 && k <= 0x0110FFFF)
        return k - 0x01000000;
    return 0;
}

void _UiXAppend(StringBuilder sb, int code)
{
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

// Handles one event (an XEvent of 24 longs).
void _UiXEvent(int64[] buffer)
{
    unsafe
    {
        uint8* e = (uint8*)&buffer[0];
        int p = (int)sizeof(nint);
        int type = *(int*)e;
        switch (type)
        {
        case 2: // KeyPress
        case 3: // KeyRelease
        {
            uint32 state = *(uint32*)(e + 8 * p + 16);
            _UiXw.Shift = (state & 1u) != 0u;
            _UiXw.Ctrl = (state & 4u) != 0u;
            _UiXw.Alt = (state & 8u) != 0u;
            var chars = new uint8[32];
            nuint keysym = 0;
            _UiX.LookupString(e, (char*)&chars[0], 32, &keysym, null);
            int k = (int)keysym;
            bool down = type == 2;
            // the modifier keys themselves (the state is the one before the event)
            if (k == 0xFFE1 || k == 0xFFE2)
                _UiXw.Shift = down;
            else if (k == 0xFFE3 || k == 0xFFE4)
                _UiXw.Ctrl = down;
            else if (k == 0xFFE9 || k == 0xFFEA)
                _UiXw.Alt = down;
            if (!down)
                break;
            var key = _UiXKeyOf(keysym);
            if (key != Key.None)
                _UiXw.Keys.Add(key);
            int code = _UiXCharOf(keysym);
            if (code != 0 && !_UiXw.Ctrl)
                _UiXAppend(_UiXw.Text, code);
            break;
        }
        case 4: // ButtonPress
        case 5: // ButtonRelease
        {
            _UiXw.MouseX = *(int*)(e + 8 * p);
            _UiXw.MouseY = *(int*)(e + 8 * p + 4);
            uint32 button = *(uint32*)(e + 8 * p + 20);
            if (button == 1u)
            {
                _UiXw.MouseDown = type == 4;
                if (type == 4)
                    _UiXw.Pressed = true;
                else
                    _UiXw.Released = true;
                _UiXw.ButtonEvent = true;
            }
            else if (type == 4 && button == 4u)
                _UiXw.Wheel += 1;
            else if (type == 4 && button == 5u)
                _UiXw.Wheel -= 1;
            break;
        }
        case 6: // MotionNotify
            _UiXw.MouseX = *(int*)(e + 8 * p);
            _UiXw.MouseY = *(int*)(e + 8 * p + 4);
            break;
        case 12: // Expose
            _UiOs.Present(_UiXw.Last);
            break;
        case 22: // ConfigureNotify
            _UiXw.Width = *(int*)(e + 6 * p + 8);
            _UiXw.Height = *(int*)(e + 6 * p + 12);
            break;
        case 33: // ClientMessage
        {
            nuint atom = *(nuint*)(e + 7 * p);
            if (atom == _UiXw.DeleteAtom)
                _UiXw.Closed = true;
            break;
        }
        default:
            break;
        }
    }
}

struct _UiOs
{
    static bool Supported() { return true; }

    // 0: open, 2: no display (or no libX11), 3: failed, 4: a window is already open
    static int Open(string title, int width, int height)
    {
        if (_UiXw.Open)
            return 4;
        if (!_UiXLoad())
            return 2;
        unsafe
        {
            void* display = _UiX.OpenDisplay(null);
            if (display == null)
                return 2;
            int screen = _UiX.DefaultScreen(display);
            double scale = _UiXScale(display);
            int w = (int)Math.Round((double)width * scale);
            int h = (int)Math.Round((double)height * scale);
            nuint window = _UiX.CreateSimpleWindow(display, _UiX.RootWindow(display, screen), 0, 0, (uint32)w, (uint32)h, 0u, 0, 0);
            if (window == 0)
            {
                _UiX.CloseDisplay(display);
                return 3;
            }
            _UiXw = _UiXWindow { Loaded = true, Open = true, Display = display, Window = window, Screen = screen, Width = w, Height = h,
                                 Scale = scale, MouseX = -1, MouseY = -1, Keys = List<Key>.Create(), Text = StringBuilder.Create(),
                                 Last = Image.Create(0, 0) };
            _UiXw.Gc = _UiX.DefaultGC(display, screen);
            _UiXw.Visual = _UiX.DefaultVisual(display, screen);
            _UiXw.Depth = _UiX.DefaultDepth(display, screen);
            // keys, buttons, motion, exposure, structure (resizing)
            _UiX.SelectInput(display, window, (nint)(1 | 2 | 4 | 8 | 64 | 32768 | 131072));
            nuint delete = _UiX.InternAtom(display, "WM_DELETE_WINDOW".CStr(), 0);
            _UiXw.DeleteAtom = delete;
            _UiX.SetWMProtocols(display, window, &delete, 1);
            _UiXw.CursorArrow = _UiX.CreateFontCursor(display, 68u); // XC_left_ptr
            _UiXw.CursorText = _UiX.CreateFontCursor(display, 152u); // XC_xterm
            _UiXw.CursorHand = _UiX.CreateFontCursor(display, 60u); // XC_hand2
            _UiX.DefineCursor(display, window, _UiXw.CursorArrow);
            SetTitle(title);
            _UiX.MapWindow(display, window);
            _UiX.Flush(display);
            return 0;
        }
    }

    static bool Pump(int waitMs)
    {
        if (!_UiXw.Open)
            return false;
        unsafe
        {
            void* display = _UiXw.Display;
            if (waitMs != 0 && !_UiXw.Closed && _UiX.Pending(display) == 0)
            {
                var fds = new int32[2]; // struct pollfd: fd, events (POLLIN), revents
                fds[0] = _UiX.ConnectionNumber(display);
                fds[1] = 1;
                poll(&fds[0], 1, waitMs < 0 ? -1 : waitMs);
            }
            var ev = new int64[24]; // XEvent
            _UiXw.ButtonEvent = false;
            while (!_UiXw.ButtonEvent && _UiX.Pending(display) > 0)
            {
                _UiX.NextEvent(display, &ev[0]);
                _UiXEvent(ev);
            }
        }
        return !_UiXw.Closed;
    }

    static UiInput TakeInput()
    {
        var input = UiInput.Create();
        if (!_UiXw.Open)
            return input;
        input.MouseX = _UiXw.MouseX;
        input.MouseY = _UiXw.MouseY;
        input.MouseDown = _UiXw.MouseDown;
        input.MousePressed = _UiXw.Pressed;
        input.MouseReleased = _UiXw.Released;
        input.Wheel = _UiXw.Wheel;
        foreach (var key in _UiXw.Keys)
            input.Keys.Add(key);
        input.Text = _UiXw.Text.ToString();
        input.Ctrl = _UiXw.Ctrl;
        input.Shift = _UiXw.Shift;
        input.Alt = _UiXw.Alt;
        _UiXw.Pressed = false;
        _UiXw.Released = false;
        _UiXw.Wheel = 0;
        _UiXw.Keys.Clear();
        _UiXw.Text.Clear();
        return input;
    }

    static int Width() { return _UiXw.Width; }
    static int Height() { return _UiXw.Height; }
    static double Scale() { return _UiXw.Scale > 0 ? _UiXw.Scale : 1.0; }

    static void Present(Image image)
    {
        if (!_UiXw.Open)
            return;
        _UiXw.Last = image;
        if (image.Width <= 0 || image.Height <= 0)
            return;
        unsafe
        {
            void* display = _UiXw.Display;
            // an XImage around the pixels of the image (ZPixmap, 32 bits per pixel); its data is not freed with it
            void* ximage = _UiX.CreateImage(display, _UiXw.Visual, (uint32)_UiXw.Depth, 2, 0, (char*)&image.Pixels[0], (uint32)image.Width,
                                            (uint32)image.Height, 32, image.Width * 4);
            if (ximage == null)
                return;
            _UiX.PutImage(display, _UiXw.Window, _UiXw.Gc, ximage, 0, 0, 0, 0, (uint32)image.Width, (uint32)image.Height);
            *(void**)((uint8*)ximage + 16) = null; // XImage.data
            _UiX.Free(ximage);
            _UiX.Flush(display);
        }
    }

    static void SetPointer(Cursor cursor)
    {
        if (!_UiXw.Open || cursor == _UiXw.Cursor)
            return;
        _UiXw.Cursor = cursor;
        nuint shape = cursor == Cursor.Text ? _UiXw.CursorText : cursor == Cursor.Hand ? _UiXw.CursorHand : _UiXw.CursorArrow;
        unsafe
        {
            _UiX.DefineCursor(_UiXw.Display, _UiXw.Window, shape);
            _UiX.Flush(_UiXw.Display);
        }
    }

    static void SetTitle(string title)
    {
        if (!_UiXw.Open)
            return;
        unsafe
        {
            void* display = _UiXw.Display;
            nuint name = _UiX.InternAtom(display, "_NET_WM_NAME".CStr(), 0);
            nuint utf8 = _UiX.InternAtom(display, "UTF8_STRING".CStr(), 0);
            _UiX.ChangeProperty(display, _UiXw.Window, name, utf8, 8, 0, title.CStr(), title.Length); // PropModeReplace
            _UiX.StoreName(display, _UiXw.Window, title.CStr());
        }
    }

    static void Close()
    {
        if (!_UiXw.Open)
            return;
        unsafe
        {
            _UiX.DestroyWindow(_UiXw.Display, _UiXw.Window);
            _UiX.CloseDisplay(_UiXw.Display);
        }
        _UiXw = _UiXWindow { Loaded = true };
    }

    static string GetClipboard() { return _UiClipboardText; }
    static void SetClipboard(string text) { _UiClipboardText = text; }
}
