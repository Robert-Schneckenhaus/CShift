# User interfaces: System.Ui

← [Documentation](README.md)

`System.Ui` makes windows with buttons, text boxes, sliders and lists, in a few lines and without anything to
install. It works in **immediate mode**: the program describes its whole window again for every frame, from its own
state, and each widget tells what the user did with it as its result. There are no widget objects, no callbacks and
no events to unsubscribe; the state of the program stays in its own structs.

```csharp
using System;
using System.Ui;

struct App
{
    int Count;
    string Name;
    bool Loud;
}

void Draw(Ui ui, ref App app)
{
    ui.Label($"Hello, {app.Name}! Count: {app.Count}");
    using (ui.Row())
    {
        if (ui.Button("-")) app.Count -= 1;
        if (ui.Button("+")) app.Count += 1;
    }
    ui.TextBox("name", ref app.Name);
    ui.Checkbox("Loud", ref app.Loud);
}

int Main()
{
    var window = try Window.Open("Counter", 320, 200);
    var ui = Ui.Create();
    var app = App { Name = "World" };
    while (window.Update())        // waits for input; false once the window is closed
    {
        ui.Begin(window);
        Draw(ui, ref app);
        window.Show(ui);
    }
    return 0;
}
```

`Draw` runs for every frame. `ui.Button("+")` draws the button and is `true` in the frame in which it was clicked;
`ui.TextBox("name", ref app.Name)` shows `app.Name` and changes it while the user types. Nothing has to be kept in
sync: the next frame shows the new state. A complete example with lists, scrolling, panels and a theme switch is
[demo-ui](../demo-ui/README.md).

| Platform | Window | Notes |
|---|---|---|
| Windows | Win32 and GDI | per-monitor DPI aware; the system clipboard |
| Linux | X11 | libX11 is loaded when the first window opens (`libx11-6`, present on every desktop); programs without a window do not need it. The clipboard stays inside the program for now |
| WebAssembly, AmigaOS | none yet | `Window.Open` fails with `UiError.NotSupported`; a `Ui` still draws into images |

The Ui draws with its own software renderer into an `Image` ([Canvas](#drawing-canvas-and-font)), so a program
needs no graphics library, and the same frames can be drawn without a window: for tests and screenshots
([without a window](#without-a-window)).

## Widgets

| Call | Shows | Result |
|---|---|---|
| `ui.Label(text)` | text in one line | |
| `ui.Note(text)` | text in the muted color | |
| `ui.Text(text)` | text wrapped at the width of the layout (also at `\n`) | |
| `ui.Button(label)` | a button | `true` when clicked (also Enter or Space when it has the focus) |
| `ui.Checkbox(label, ref bool value)` | a check box | `true` when the user changed `value` |
| `ui.Radio(label, ref int value, option)` | one of a group of options | `true` when it was chosen (`value` becomes `option`) |
| `ui.Slider(id, ref double value, min, max)` | a slider (also for `int`) | `true` while the user changes `value` |
| `ui.TextBox(id, ref string text)` | a line of editable text | `true` when the user changed `text` |
| `ui.Submitted(id)` | | `true` in the frame in which Enter was pressed in that text box |
| `ui.ProgressBar(fraction)` | a bar filled from 0.0 to 1.0 | |
| `ui.ListItem(label, selected)` | a line of a list, highlighted if selected | `true` when clicked |
| `ui.Image(image)` | an image in its own size | |
| `ui.Separator()`, `ui.Space(size)` | a line, empty space | |

The text box edits with the arrow keys, Home, End, Backspace and Delete (Shift selects), Ctrl+A, Ctrl+C, Ctrl+X and
Ctrl+V, and the mouse (click, drag to select); Escape ends the editing. Tab and Shift+Tab move the keyboard focus
through the widgets; a focused slider moves with the arrow keys, Home and End.

## Layout

Widgets go from top to bottom. Groups are `using` blocks, which end the group when the block is left:

```csharp
using (ui.Row())                  // side by side
{
    ui.TextBox("search", ref app.Search);   // takes the rest of the line
    if (ui.Button("Find")) Find(ref app);
}
using (ui.Columns(2))             // a grid of 2 columns of equal width
{
    ui.Label("Volume");  ui.Slider("volume", ref app.Volume, 0.0, 100.0);
    ui.Label("Balance"); ui.Slider("balance", ref app.Balance, -1.0, 1.0);
}
using (ui.Panel("Settings"))      // a framed group with a title
{
    ui.Checkbox("Dark theme", ref app.Dark);
}
using (ui.Scroll("files", 200))   // 200 pixels high, the content scrolls (wheel, scroll bar)
{
    foreach (var file in app.Files)
        ui.Label(file);
}
```

`ui.Column()` stacks widgets inside a row. Labels, buttons and check boxes are as wide as they need; text boxes,
sliders, progress bars and list items take the width that is there (in a row: what the other widgets leave). A row and
a panel learn their size while they are drawn, so when it changes (the first frame, a longer label) the Ui asks for a
second frame at once; `Window.Update` does that without waiting.

Sizes are pixels at a scale of 1 (96 dpi). The Ui scales them, and picks its font, for the scale of the screen
(`Window.Scale`: 1.5 at 144 dpi). `ui.Begin(window.Input(), window.Width(), window.Height(), window.Scale() * 1.25)`
makes everything a quarter larger.

## Ids

Every widget has an id, made from its label (or the `id` argument) and the groups around it. It is how the Ui knows
across frames which button the mouse was pressed on, or which text box has the focus. Two widgets with the same label
in the same group need different ids: either with `##`, whose part after it is not shown, or with `ui.Id`:

```csharp
if (ui.Button("Delete##" + i)) ...        // shows "Delete"

for (var i = 0; i < app.Tasks.Count(); i += 1)
{
    using (ui.Id(i))                      // the widgets inside get ids of their own
    {
        ui.Checkbox("##done", ref app.Done[i]);   // no label
        ui.Label(app.Tasks[i]);
    }
}
```

## The loop

`window.Update()` handles the events of the window and **waits for input** before it returns, so a window that nobody
touches takes no time: a frame is drawn when something happened (a click, a key, the mouse moved), when the text
cursor blinks, or when the layout has to settle. It returns `false` when the user closed the window.

`window.Show(ui)` ends the frame and shows it. For animations and games, draw into an image of your own and call
`window.Show(image)`: then the next `Update` does not wait, and the loop runs as fast as frames are drawn. Both can be
combined: `ui.End()` gives the image of the frame, which the program can draw on before it shows it.

`ui.Canvas()` and `ui.Area(width, height)` draw into the frame: `Area` takes a rectangle of the layout, and the canvas
draws into it (charts, previews, games inside a window):

```csharp
var r = ui.Area(0, 120);               // the whole width, 120 pixels high
var canvas = ui.Canvas();
canvas.FillRoundRect(r, 6, Color.FromRgb(30, 30, 40));
canvas.Line((double)r.X, (double)r.Bottom(), (double)r.Right(), (double)r.Y, 2.0, Color.White());
```

## Themes

`ui.SetTheme(Theme.Dark())` switches to dark colors; `Theme.Light()` is the default. A `Theme` is a struct of
colors, so a theme of your own is a copy with other values:

```csharp
var theme = Theme.Light();
theme.Accent = Color.FromRgb(200, 60, 120);
ui.SetTheme(theme);
```

## Without a window

`ui.Begin(input, width, height, scale)` starts a frame of any size with a `UiInput` that the program makes, and
`ui.End()` gives its image. That is how the Ui is tested ([tests/cases/stdlib_ui.csh](../tests/cases/stdlib_ui.csh)):
a click is `MousePressed` and `MouseReleased` in the same frame, typing is `Keys` and `Text`.

```csharp
var ui = Ui.Create();
var input = UiInput.Create();
input.MouseX = 40;
input.MouseY = 20;
input.MousePressed = true;
input.MouseReleased = true;
ui.Begin(input, 300, 200, 1.0);
bool clicked = ui.Button("OK");
try ui.End().Save("frame.png");
```

`ui.LastRect()` is the rectangle of the widget placed last (for tests, or to draw next to a widget).

## Drawing: Canvas and Font

`Canvas` draws into an `Image`: `FillRect`, `StrokeRect`, `FillRoundRect`, `StrokeRoundRect`, `FillCircle`,
`Line` (any width, round ends), `Text` and `DrawImage`. Everything is clipped to `canvas.Clip`
(`canvas.SetClip(rect)`), colors with an alpha below 255 are blended, and the edges of rounded rectangles, circles and
lines are smooth.

The text is drawn with bitmap fonts: `Font.Fixed7x13()` and `Font.Fixed10x20()` are the "fixed" fonts of X11, which
are in the public domain, so a program that embeds them owes nobody a notice. They have ASCII, Latin-1 and a few marks
(€, typographic quotes and dashes, arrows); other characters are drawn as `?`. `Font.ForScale(scale)` picks the one
for a scale (`font.Zoomed(2)` doubles the pixels). Every character has the same width, so `font.Measure(text)` is the
number of characters times `font.CharWidth()`. The font data in `stdlib/ui_fonts.csh` is made from the BDF files by
[tools/ui/bdf2csh.py](../tools/ui/bdf2csh.py).

## How it works

A `Ui` keeps what has to last from one frame to the next: which widget is under the mouse ("hot"), which one the
mouse button went down on ("active"), which one has the keyboard focus, the cursor and the selection of the text box
being edited, the scroll positions and the sizes of panels and rows from the last frame. Everything else is made
again for each frame. A copy of a `Ui` shares this state (it is held in a one-element array), so `Ui` can be passed to
functions by value, and `using (ui.Row())` can end the row it began.

The window layer is the operating system part of the standard library (`stdlib/os/<layer>/ui.csh`): Win32 on
Windows, X11 on Linux, and a stub on the other targets. One window can be open at a time.
