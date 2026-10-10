namespace System.Ui;

using System;
using System.Image;

//! A window on the screen for System.Ui: it collects the input of the mouse and the keyboard for a frame and shows
//! the image of a frame. Windows has it with Win32 (stdlib/os/windows/ui.csh), Linux with X11 (stdlib/os/posix/ui.csh,
//! libX11 is loaded when the first window opens, so programs without windows do not need it); other targets report
//! UiError.NotSupported.

/// The errors of opening a window.
error UiError
{
    /// The target has no windows (WebAssembly, AmigaOS, macOS for now).
    NotSupported = 1,
    /// There is no screen to show a window on (Linux: no X server, or libX11 is missing).
    NoDisplay = 2,
    /// The system refused to create the window.
    CannotCreate = 3
}

/// A window that shows the frames of a [Ui] (or images of your own, for games). One window at a time.
///
/// ```
/// var window = try Window.Open("Demo", 400, 300);
/// var ui = Ui.Create();
/// while (window.Update())        // waits for input; false once the window was closed
/// {
///     ui.Begin(window);
///     ui.Label("Hello");
///     window.Show(ui);
/// }
/// ```
struct Window : IDisposable
{
    int _Wait; // what Update waits for: -1 input, 0 nothing, n milliseconds at most

    /// Opens a window whose inside is `width` x `height` pixels at scale 1 (on a screen with a higher scale it is
    /// larger by that factor).
    static UiError<Window> Open(string title, int width, int height)
    {
        if (!_UiOs.Supported())
            return error("this target has no windows", UiError.NotSupported);
        int code = _UiOs.Open(title, Math.Max(1, width), Math.Max(1, height));
        switch (code)
        {
        case 0:
            return Window { _Wait = 0 };
        case 2:
            return error("cannot open a window: no display (is an X server running, and libX11 installed?)", UiError.NoDisplay);
        case 4:
            return error("only one window can be open at a time", UiError.CannotCreate);
        default:
            return error("the system refused to create the window", UiError.CannotCreate);
        }
    }

    /// Handles the events of the window and waits for input first, as long as the last frame asked for (see
    /// [Ui.WaitMilliseconds]; after [Window.Show] of an image it does not wait). False once the user closed the window.
    bool Update()
    {
        bool open = _UiOs.Pump(_Wait);
        _Wait = -1;
        return open;
    }

    /// The input since the last frame.
    UiInput Input()
    {
        var input = _UiOs.TakeInput();
        input.Time = (double)_Os.MonotonicTicks() / 10000000.0;
        return input;
    }

    /// The width of the inside of the window in pixels.
    int Width() { return _UiOs.Width(); }

    /// The height of the inside of the window in pixels.
    int Height() { return _UiOs.Height(); }

    /// The scale of the screen the window is on: 1 at 96 dpi, 1.5 at 144 dpi, ...
    double Scale() { return _UiOs.Scale(); }

    /// Ends the frame of a Ui and shows it.
    void Show(Ui ui)
    {
        var frame = ui.End();
        _UiOs.Present(frame);
        _UiOs.SetPointer(ui.Cursor());
        _Wait = ui.WaitMilliseconds();
    }

    /// Shows an image (drawn from the top left corner); the next [Window.Update] does not wait, so a loop of Update and
    /// Show draws as many frames as the program can (an animation, a game).
    void Show(Image image)
    {
        _UiOs.Present(image);
        _Wait = 0;
    }

    /// Changes the text in the title bar.
    void SetTitle(string title) { _UiOs.SetTitle(title); }

    /// Closes the window.
    void Dispose() { _UiOs.Close(); }
}

/// The text of the system's clipboard ([Ui.TextBox] uses it for Ctrl+C, Ctrl+X and Ctrl+V). Where there are no
/// windows, it is kept inside the program.
struct Clipboard
{
    /// The text on the clipboard ("" if there is none).
    static string GetText() { return _UiOs.GetClipboard(); }

    /// Puts a text on the clipboard.
    static void SetText(string text) { _UiOs.SetClipboard(text); }
}
