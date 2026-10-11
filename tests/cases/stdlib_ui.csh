// Standard library: System.Ui without a window - frames drawn into an image, with input made by the test: clicks on
// buttons, check boxes and radio buttons (a press and a release in one frame), typing and editing in a text box,
// Tab and Space, dragging a slider and the arrow keys, the mouse wheel in a scroll area, ids with ## and Ui.Id,
// a panel's size settling in a second frame, the colors of the theme in the pixels. Main returns the number of failed
// checks.
// expect-stdout: clicks 1 0 1
// expect-stdout: text 'q' submitted true
// expect-stdout: tab toggles true
// expect-stdout: slider 0 1
// expect-stdout: radio 2
// expect-stdout: scroll moved true
// expect-stdout: settle 0 -1
// expect-exit: 0

using System;
using System.Image;
using System.Ui;

struct App
{
    int Clicks;
    int Delete1;
    int Delete2;
    bool Check;
    string Name;
    bool NameSubmitted;
    int Level;
    int Choice;
    int Picked;
}

// the rectangles of the widgets, from the last frame
struct Rects
{
    Rect Plus;
    Rect Delete1;
    Rect Delete2;
    Rect Check;
    Rect Name;
    Rect Level;
    Rect Choice2;
    Rect Scroll;
    Rect Item0;
    Rect Item1Of2;
}

int Failures;

void Check(bool ok, string what)
{
    if (!ok)
    {
        Console.WriteLine("FAILED: " + what);
        Failures += 1;
    }
}

void Draw(Ui ui, ref App app, ref Rects rects)
{
    using (ui.Row())
    {
        if (ui.Button("+"))
            app.Clicks += 1;
        rects.Plus = ui.LastRect();
        if (ui.Button("Delete##1"))
            app.Delete1 += 1;
        rects.Delete1 = ui.LastRect();
        if (ui.Button("Delete##2"))
            app.Delete2 += 1;
        rects.Delete2 = ui.LastRect();
    }
    ui.TextBox("name", ref app.Name);
    rects.Name = ui.LastRect();
    if (ui.Submitted("name"))
        app.NameSubmitted = true;
    ui.Checkbox("Check", ref app.Check);
    rects.Check = ui.LastRect();
    ui.Slider("level", ref app.Level, 0, 10);
    rects.Level = ui.LastRect();
    using (ui.Row())
    {
        ui.Radio("A", ref app.Choice, 1);
        ui.Radio("B", ref app.Choice, 2);
        rects.Choice2 = ui.LastRect();
    }
    using (ui.Scroll("list", 100))
    {
        for (var i = 0; i < 30; i += 1)
        {
            using (ui.Id(i))
            {
                if (ui.ListItem("Item", app.Picked == i))
                    app.Picked = i;
                if (i == 0)
                    rects.Item0 = ui.LastRect();
            }
        }
    }
    rects.Scroll = ui.LastRect();
    using (ui.Panel("Panel"))
    {
        ui.Label("inside");
    }
}

UiInput Click(Rect r)
{
    var input = UiInput.Create();
    input.MouseX = r.X + r.Width / 2;
    input.MouseY = r.Y + r.Height / 2;
    input.MousePressed = true;
    input.MouseReleased = true;
    return input;
}

UiInput Keys(ReadOnlySlice<Key> keys, string text)
{
    var input = UiInput.Create();
    foreach (var k in keys)
        input.Keys.Add(k);
    input.Text = text;
    return input;
}

Image Frame(Ui ui, ref App app, ref Rects rects, UiInput input)
{
    ui.Begin(input, 300, 600, 1.0);
    Draw(ui, ref app, ref rects);
    return ui.End();
}

int Main()
{
    var ui = Ui.Create();
    var app = App { Name = "", Picked = -1 };
    var rects = Rects { };
    var none = UiInput.Create();

    // the first frame: the panel does not know its height yet, so the Ui asks for another frame at once
    Frame(ui, ref app, ref rects, none);
    int first = ui.WaitMilliseconds();
    Frame(ui, ref app, ref rects, none);
    int second = ui.WaitMilliseconds();

    // clicks: "+" and the second of two buttons with the same label
    Frame(ui, ref app, ref rects, Click(rects.Plus));
    Frame(ui, ref app, ref rects, Click(rects.Delete2));
    Console.WriteLine($"clicks {app.Clicks} {app.Delete1} {app.Delete2}");

    // the text box: click, type, edit, select all, replace, Enter
    Frame(ui, ref app, ref rects, Click(rects.Name));
    Check(ui.HasFocus("name"), "the text box has the focus after a click");
    Frame(ui, ref app, ref rects, Keys([], "abc"));
    Check(app.Name == "abc", "typed abc: " + app.Name);
    Frame(ui, ref app, ref rects, Keys([Key.Backspace, Key.Home], "Z"));
    Check(app.Name == "Zab", "Backspace, Home, Z: " + app.Name);
    Frame(ui, ref app, ref rects, Keys([Key.End, Key.Left, Key.Delete], ""));
    Check(app.Name == "Za", "End, Left, Delete: " + app.Name);
    Frame(ui, ref app, ref rects, Keys([], "ü€"));
    Check(app.Name == "Zaü€", "UTF-8 text: " + app.Name);
    Frame(ui, ref app, ref rects, Keys([Key.Backspace], ""));
    Check(app.Name == "Zaü", "Backspace removes a whole character: " + app.Name);
    var selectAll = Keys([Key.A], "");
    selectAll.Ctrl = true;
    Frame(ui, ref app, ref rects, selectAll);
    Frame(ui, ref app, ref rects, Keys([], "q"));
    Frame(ui, ref app, ref rects, Keys([Key.Enter], ""));
    Console.WriteLine($"text '{app.Name}' submitted {app.NameSubmitted.ToString().ToLower()}");

    // Tab moves the focus from the text box to the check box; Space toggles it
    Frame(ui, ref app, ref rects, Keys([Key.Tab], ""));
    Frame(ui, ref app, ref rects, Keys([Key.Space], ""));
    Console.WriteLine($"tab toggles {app.Check.ToString().ToLower()}");
    Check(ui.HasFocus("Check"), "the check box has the focus after Tab");

    // the slider: pressed at its left end, then one step to the right with the keyboard
    var press = UiInput.Create();
    press.MouseX = rects.Level.X;
    press.MouseY = rects.Level.Y + rects.Level.Height / 2;
    press.MousePressed = true;
    press.MouseDown = true;
    Frame(ui, ref app, ref rects, press);
    int atLeft = app.Level;
    var release = press;
    release.MousePressed = false;
    release.MouseDown = false;
    release.MouseReleased = true;
    Frame(ui, ref app, ref rects, release);
    Frame(ui, ref app, ref rects, Keys([Key.Right], ""));
    Console.WriteLine($"slider {atLeft} {app.Level}");

    // a radio button
    Frame(ui, ref app, ref rects, Click(rects.Choice2));
    Console.WriteLine($"radio {app.Choice}");

    // the mouse wheel moves the content of the scroll area up
    int before = rects.Item0.Y;
    var wheel = UiInput.Create();
    wheel.MouseX = rects.Scroll.X + 10;
    wheel.MouseY = rects.Scroll.Y + 10;
    wheel.Wheel = -1;
    Frame(ui, ref app, ref rects, wheel);
    Frame(ui, ref app, ref rects, none);
    Console.WriteLine($"scroll moved {(rects.Item0.Y < before).ToString().ToLower()}");

    // a click on an item of the list selects it (each one has its own id through Ui.Id)
    var second2 = rects.Item0;
    second2.Y += second2.Height + 6;
    Frame(ui, ref app, ref rects, Click(second2));
    Check(app.Picked == 1, "the second item is picked: " + app.Picked.ToString());

    // the pixels: the background of the theme, and the accent color in the checked box
    var image = Frame(ui, ref app, ref rects, none);
    var theme = Theme.Light();
    Check(image.GetPixel(1, 1).Equals(theme.Background), "the background color");
    Check(image.GetPixel(rects.Check.X + 1, rects.Check.Y + rects.Check.Height / 2).Equals(theme.Accent), "the checked box: " + image.GetPixel(rects.Check.X + 1, rects.Check.Y + rects.Check.Height / 2).ToString());
    Console.WriteLine($"settle {first} {second}");
    return Failures;
}
