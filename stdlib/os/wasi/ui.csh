// The window part of the operating system layer on WebAssembly (see stdlib/os/windows/ui.csh): WASI has no windows,
// so Window.Open reports UiError.NotSupported. The clipboard is kept inside the program.

namespace System.Ui;

using System;
using System.Image;

string _UiClipboardText;

struct _UiOs
{
    static bool Supported() { return false; }
    static int Open(string title, int width, int height) { return 1; }
    static bool Pump(int waitMs) { return false; }
    static UiInput TakeInput() { return UiInput.Create(); }
    static int Width() { return 0; }
    static int Height() { return 0; }
    static double Scale() { return 1.0; }
    static void Present(Image image) { }
    static void SetPointer(Cursor cursor) { }
    static void SetTitle(string title) { }
    static void Close() { }
    static string GetClipboard() { return _UiClipboardText; }
    static void SetClipboard(string text) { _UiClipboardText = text; }
}
