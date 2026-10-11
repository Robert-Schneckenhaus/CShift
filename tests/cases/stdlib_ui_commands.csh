// Standard library: System.Ui drawing with commands instead of pixels (Ui.BeginCommands, Ui.Commands: what the window
// of AmigaOS draws with graphics.library). The layout follows the given font (8 x 8, like Topaz), the frame starts
// with Clear, a button is a filled and an outlined rounded rectangle and its text, a scroll area clips and gives the
// clip back, the mouse works as with pixels, and no image of the frame's size is made.
// expect-stdout: first Clear
// expect-stdout: button FillRoundRect StrokeRoundRect Text 'OK' 8 x 8
// expect-stdout: clips 2 back true
// expect-stdout: clicked 1
// expect-stdout: image 0 x 0
// expect-exit: 0

using System;
using System.Image;
using System.Ui;

int Failures;

void Check(bool ok, string what)
{
    if (!ok)
    {
        Console.WriteLine("FAILED: " + what);
        Failures += 1;
    }
}

int Main()
{
    var ui = Ui.Create();
    var font = Font.Metrics(8, 8, 6);
    int clicks = 0;
    var button = Rect.Create(0, 0, 0, 0);
    for (var frame = 0; frame < 3; frame += 1)
    {
        var input = UiInput.Create();
        if (frame == 2)
        {
            input.MouseX = button.X + 2;
            input.MouseY = button.Y + 2;
            input.MousePressed = true;
            input.MouseReleased = true;
        }
        ui.BeginCommands(input, 320, 200, 1.0, font);
        if (ui.Button("OK"))
            clicks += 1;
        button = ui.LastRect();
        using (ui.Scroll("list", 40))
        {
            for (var i = 0; i < 10; i += 1)
                ui.Label($"line {i}");
        }
        ui.End();
    }

    var commands = ui.Commands();
    Console.WriteLine($"first {commands[0].Kind}");
    // the button: its commands follow the Clear
    var text = commands[3];
    Console.WriteLine($"button {commands[1].Kind} {commands[2].Kind} {text.Kind} '{text.Text}' {text.Rect.Width / 2} x {text.Rect.Height}");
    Check(button.Height == 8 + 2 * 5, $"the height of a button with an 8-pixel font: {button.Height}");
    Check(button.Width == 2 * 8 + 2 * 14, $"the width of a button: {button.Width}");
    int clips = 0;
    var last = Rect.Create(0, 0, 0, 0);
    foreach (var c in commands)
    {
        if (c.Kind == UiCommandKind.Clip)
        {
            clips += 1;
            last = c.Rect;
        }
    }
    Console.WriteLine($"clips {clips} back {last.Equals(Rect.Create(0, 0, 320, 200))}");
    Console.WriteLine($"clicked {clicks}");
    Console.WriteLine($"image {ui.Frame().Width} x {ui.Frame().Height}");

    // pixels again: the same Ui draws into an image after Begin
    ui.Begin(UiInput.Create(), 100, 50, 1.0);
    ui.Label("x");
    var image = ui.End();
    Check(image.Width == 100 && image.Height == 50 && image.GetPixel(0, 0).Equals(Theme.Light().Background), "back to pixels");
    return Failures;
}
