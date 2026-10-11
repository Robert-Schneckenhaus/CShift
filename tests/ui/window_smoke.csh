// System.Ui with a real window: opens it, draws frames of a Ui and shows them, and closes it again - without input, so
// it runs unattended (CI: on Linux under Xvfb, with libX11 loaded at run time). Prints "window ok" and the size.
//
//   cshiftc tests/ui/window_smoke.csh -o smoke && xvfb-run -a ./smoke

using System;
using System.Ui;

int Main()
{
    var opened = Window.Open("CShift window test", 240, 120);
    if (opened is not Window window)
    {
        Console.WriteLine("error: " + opened.Message);
        return 1;
    }
    var ui = Ui.Create();
    int clicks = 0;
    for (var frame = 0; frame < 30; frame += 1)
    {
        if (!window.Update())
        {
            Console.WriteLine("error: closed");
            return 1;
        }
        ui.Begin(window);
        ui.Label($"Frame {frame}");
        if (ui.Button("Click"))
            clicks += 1;
        window.Show(ui.End()); // shown as an image: the next Update does not wait for input
    }
    int width = window.Width();
    int height = window.Height();
    double scale = window.Scale();
    window.SetTitle("CShift window test (done)");
    window.Dispose();
    if (width <= 0 || height <= 0)
    {
        Console.WriteLine($"error: size {width} x {height}");
        return 1;
    }
    Console.WriteLine($"window ok {width} x {height}, scale {scale:F2}");
    return 0;
}
