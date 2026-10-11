// System.Ui in the browser (--backend wasm): run by tests/ui-web-check.mjs with web/cshift.js and a canvas that only
// pretends. The program tells where its widgets are; the test clicks the button, types into the text box and pastes,
// and the program ends when it got all of it. Between those inputs it waits (the program is suspended until input).

using System;
using System.Ui;

int Main()
{
    var opened = Window.Open("web", 200, 120);
    if (opened is not Window window)
    {
        Console.WriteLine("error: " + opened.Message);
        return 1;
    }
    var ui = Ui.Create();
    string text = "";
    int clicks = 0;
    int frames = 0;
    while (window.Update())
    {
        frames += 1;
        ui.Begin(window);
        if (ui.Button("Click"))
        {
            clicks += 1;
            Console.WriteLine("clicked");
        }
        var button = ui.LastRect();
        if (ui.TextBox("text", ref text))
            Console.WriteLine("text " + text);
        var box = ui.LastRect();
        if (frames == 1)
            Console.WriteLine($"layout {button.X + button.Width / 2} {button.Y + button.Height / 2} {box.X + 10} {box.Y + box.Height / 2} scale {window.Scale()}");
        window.Show(ui);
        if (clicks == 1 && text == "hi there")
            break;
        if (frames > 200)
        {
            Console.WriteLine("error: too many frames (the program does not wait for input)");
            return 1;
        }
    }
    window.Dispose();
    Console.WriteLine($"done after {frames} frames");
    return 0;
}
