// Standard library: System.Ui drawing - Canvas (clipping, alpha blending, rounded rectangles, circles, lines, text,
// images), Font (measuring UTF-8, the fallback for missing characters, zoom), Rect, and the widgets and groups that
// stdlib_ui.csh does not use: Column, Columns, Separator, Space, Image, Area, Text (wrapped), Note, ProgressBar, the
// slider for doubles, hovering, a theme of one's own. Main returns the number of failed checks.
// expect-stdout: fonts 7x13 10x20 14
// expect-stdout: measure 21 7 7
// expect-stdout: wrapped 4
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
    var white = Color.White();
    var red = Color.FromRgb(255, 0, 0);

    // fonts
    var small = Font.Fixed7x13();
    var large = Font.Fixed10x20();
    var zoomed = Font.ForScale(2.5);
    Console.WriteLine($"fonts {small.Width}x{small.Height} {large.Width}x{large.Height} {zoomed.CharWidth()}");
    Console.WriteLine($"measure {small.Measure("abc")} {small.Measure("ü")} {small.Measure("中")}");
    Check(Font.ForScale(1.5).Width == 10, "scale 1.5 uses 10x20");

    // clipping and filling
    var image = Image.Create(40, 30, white);
    var canvas = Canvas.Create(image);
    canvas.SetClip(Rect.Create(10, 10, 10, 10));
    canvas.FillRect(Rect.Create(0, 0, 40, 30), red);
    Check(image.GetPixel(10, 10).Equals(red) && image.GetPixel(19, 19).Equals(red), "inside the clip");
    Check(image.GetPixel(9, 10).Equals(white) && image.GetPixel(20, 19).Equals(white), "outside the clip");

    // half transparent black on white: gray
    canvas.SetClip(Rect.Create(0, 0, 40, 30));
    canvas.FillRect(Rect.Create(0, 20, 5, 5), Color.FromArgb(128, 0, 0, 0));
    var gray = image.GetPixel(2, 22);
    Check(gray.R > 120 && gray.R < 135 && gray.R == gray.G && gray.A == 255, "blended " + gray.ToString());

    // a rounded rectangle leaves its corners, a circle its outside
    canvas.Clear(white);
    canvas.FillRoundRect(Rect.Create(0, 0, 20, 20), 6, red);
    Check(image.GetPixel(0, 0).Equals(white) && image.GetPixel(10, 10).Equals(red) && image.GetPixel(10, 0).Equals(red), "rounded corners");
    canvas.StrokeRoundRect(Rect.Create(20, 0, 20, 20), 4, 1, red);
    Check(image.GetPixel(30, 10).Equals(white) && image.GetPixel(30, 0).Equals(red), "outline");
    canvas.Clear(white);
    canvas.FillCircle(15.0, 15.0, 5.0, red);
    Check(image.GetPixel(15, 15).Equals(red) && image.GetPixel(5, 5).Equals(white), "circle");
    canvas.Line(0.0, 25.5, 40.0, 25.5, 1.0, red);
    Check(image.GetPixel(20, 25).Equals(red) && image.GetPixel(20, 22).Equals(white), "line");

    // text: some pixels of the color inside the cell, none outside
    canvas.Clear(white);
    int width = canvas.Text(small, 2, 2, "H", red);
    int inside = 0;
    for (var y = 0; y < 30; y += 1)
    {
        for (var x = 0; x < 40; x += 1)
        {
            if (image.GetPixel(x, y).Equals(red))
            {
                inside += 1;
                Check(x >= 2 && x < 9 && y >= 2 && y < 15, $"text pixel at {x}, {y}");
            }
        }
    }
    Check(width == 7 && inside > 10, $"text width {width}, {inside} pixels");

    // images keep their transparent pixels out
    var sprite = Image.Create(2, 1, Color.Transparent());
    sprite.SetPixel(1, 0, red);
    canvas.Clear(white);
    canvas.DrawImage(sprite, 5, 5);
    Check(image.GetPixel(5, 5).Equals(white) && image.GetPixel(6, 5).Equals(red), "transparent pixels");

    // Rect
    var a = Rect.Create(0, 0, 10, 10);
    Check(a.Intersect(Rect.Create(5, 5, 10, 10)).Equals(Rect.Create(5, 5, 5, 5)), "intersect");
    Check(a.Intersect(Rect.Create(20, 20, 5, 5)).IsEmpty(), "no overlap");
    Check(a.Shrink(2).Equals(Rect.Create(2, 2, 6, 6)) && a.Contains(9, 9) && !a.Contains(10, 0), "shrink, contains");

    // the other widgets, with a theme of one's own
    var ui = Ui.Create();
    var theme = Theme.Dark();
    theme.Background = Color.FromRgb(1, 2, 3);
    ui.SetTheme(theme);
    double level = 0.5;
    var input = UiInput.Create();
    input.MouseX = 15;
    input.MouseY = 15;
    for (var frame = 0; frame < 2; frame += 1)
    {
        ui.Begin(input, 200, 400, 1.0);
        using (ui.Row())
        {
            using (ui.Column())
            {
                ui.Label("a");
                ui.Note("b");
            }
            ui.Space(20);
            ui.Image(sprite);
        }
        ui.Separator();
        ui.Text("one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen");
        if (frame == 1)
            Console.WriteLine($"wrapped {ui.LastRect().Height / (ui.Font().LineHeight() + 2)}");
        using (ui.Columns(2))
        {
            ui.Label("Level");
            ui.Slider("level", ref level, 0.0, 1.0);
        }
        ui.ProgressBar(level);
        var area = ui.Area(0, 30);
        var c = ui.Canvas();
        c.FillRect(area, red);
        if (frame == 1)
            Check(ui.IsHovered("level") == false && ui.Input().MouseX == 15 && ui.Scale() == 1.0, "hover, input, scale");
        ui.End();
    }
    var frameImage = ui.Frame();
    Check(frameImage.GetPixel(0, 0).Equals(theme.Background), "own theme");
    Check(ui.GetTheme().Background.Equals(theme.Background), "GetTheme");
    var last = ui.LastRect();
    Check(frameImage.GetPixel(last.X + 1, last.Y + 1).Equals(red), "drawn into an area");
    return Failures;
}
