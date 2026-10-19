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
| Windows | Win32 and GDI | per-monitor DPI aware; the system clipboard; all three mouse buttons and both wheels |
| Linux | X11 | libX11 is loaded when the first window opens (`libx11-6`, present on every desktop); programs without a window do not need it. All three buttons and both wheels (buttons 4 to 7). The clipboard stays inside the program for now |
| The browser | a `<canvas>` | `--backend wasm`, with [web/cshift.js](../web/cshift.js) (`cshiftc publish`, `cshiftc serve`): see [in the browser](#in-the-browser); the right button is the program's (no menu of the browser on the canvas) |
| AmigaOS 3.0 and later | an Intuition window | drawn with graphics.library from the commands of the frames: see [on the Amiga](#on-the-amiga) |
| WASI without a browser | none | `Window.Open` fails with `UiError.NotSupported`; a `Ui` still draws into images |

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
| `ui.ComboBox(id, ref int selected, items)` | the chosen item of a `List<string>`; a click opens the list over the rest | `true` when `selected` changed |
| `ui.IntBox(id, ref int value, min, max)` | a text box for a whole number (digits and `-`, Up and Down add 1) | `true` when `value` changed |
| `ui.Image(image)` | an image in its own size | |
| `ui.Separator()`, `ui.Space(size)` | a line, empty space | |
| `ui.MenuItem(label)`, `ui.MenuItem(label, shortcut)` | an item of a popup or a menu ([popups](#popups-menus-and-dialogs)) | `true` when chosen |

The text box edits with the arrow keys, Home, End, Backspace and Delete (Shift selects), Ctrl+A, Ctrl+C, Ctrl+X and
Ctrl+V, and the mouse (click, drag to select); Escape ends the editing. Tab and Shift+Tab move the keyboard focus
through the widgets; a focused slider moves with the arrow keys, Home and End. A focused combo box chooses the item
before or after with Up and Down; Enter or Space open its list, where Up, Down, Home, End and Enter choose and Escape
or a click outside closes it. Long lists scroll (the wheel, the scroll bar).

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

A side bar of a fixed width next to a view that takes the rest: `ui.Column(width)` inside a row is a column of that
width (pixels at scale 1), `ui.Column(0)` one that takes the rest of the row (several share it equally; it may come
before or after the fixed ones). A height of 0 means "down to the bottom of the window": `ui.Scroll(id, 0)`,
`ui.Area(0, 0)`.

```csharp
using (ui.Row())
{
    using (ui.Column(220))                     // the tools
    {
        ui.ComboBox("tileset", ref app.Tileset, app.Tilesets);
        ui.IntBox("event", ref app.Event, 0, 255);
    }
    using (ui.Column(0))                       // the map: the rest of the row
    {
        using (ui.ScrollArea("map", 0, 0))     // both scroll bars, down to the bottom of the window
        {
            var r = ui.Area(app.Width * 16 * app.Zoom, app.Height * 16 * app.Zoom);
            DrawMap(ui, r, ref app);
        }
    }
}
```

`ui.ScrollArea(id, width, height)` scrolls both ways: content wider than the area (an `Area` of a fixed size, a long
row) gets a horizontal scroll bar. The wheel scrolls down and up, Shift with the wheel and the horizontal wheel
(`UiInput.WheelX`) to the sides. `ui.ScrollX(id)` and `ui.ScrollY(id)` tell how far an area is scrolled,
`ui.SetScroll(id, x, y)` scrolls it from the next frame on (keeping the point under the mouse while zooming).

`ui.Column()` stacks widgets inside a row. Labels, buttons and check boxes are as wide as they need; text boxes,
sliders, progress bars and list items take the width that is there (in a row: what the other widgets leave). A row and
a panel learn their size while they are drawn, so when it changes (the first frame, a longer label) the Ui asks for a
second frame at once; `Window.Update` does that without waiting.

Sizes are pixels at a scale of 1 (96 dpi). The Ui scales them, and picks its font, for the scale of the screen
(`Window.Scale`: 1.5 at 144 dpi). `ui.Begin(window, 1.25)` makes everything a quarter larger.

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

## Popups, menus and dialogs

Popups, the lists of combo boxes, menus, modal dialogs and tooltips are drawn in a layer over the rest of the frame,
after it, and the mouse and the keys go to the topmost layer first: a click into an open list does not reach the
widget below it.

**A context menu** is opened by the program, for example with the right mouse button, and drawn wherever the program
likes (the id of a popup is the same in every group). It closes when an item is chosen, with Escape, or with a click
outside of it; a left click outside goes no further (it does not press the button under it), a right click does (it may
open the menu somewhere else). `ui.CloseCurrentPopup()` closes it from the inside, `ui.IsPopupOpen(id)` tells.

```csharp
var r = ui.Area(0, 0);
if (ui.RightClicked())
{
    app.MenuTile = TileAt(r, ui.Input());
    ui.OpenPopup("tile");
}
using (ui.Popup("tile"))                  // the widgets inside only do something while it is open
{
    if (ui.MenuItem("Clear event"))
        ClearEvent(ref app);
    if (ui.MenuItem("Edit tile...", "E"))
        app.EditingTile = true;
}
```

**A menu bar** is a row of menus, each a popup below its title; a press on the title opens it, and while one is open
the mouse moving along the bar opens the others. The shortcuts are only shown: the program handles the keys itself
(`ui.Input().Pressed(Key.S, KeyModifiers.Ctrl)`, see [The mouse and the keys](#the-mouse-and-the-keys)).

```csharp
using (ui.MenuBar())
{
    using (ui.Menu("File"))
    {
        if (ui.MenuItem("Open map...", "Ctrl+O")) app.Opening = true;
        if (ui.MenuItem("Save", "Ctrl+S")) Save(ref app);
    }
    using (ui.Menu("View"))
    {
        if (ui.MenuItem("Zoom in", "Ctrl++")) app.Zoom += 1;
    }
}
```

**A modal dialog** is shown in the middle of the window as long as the program draws it; the rest of the window is
dimmed and gets no input meanwhile (neither the mouse nor the keys). The program closes it by not drawing it any more:

```csharp
if (app.Asking)
{
    using (ui.Modal("unsaved", "Unsaved changes"))
    {
        ui.Text("The map has changes that are not saved.");
        using (ui.Row())
        {
            if (ui.Button("Save")) { Save(ref app); app.Asking = false; }
            if (ui.Button("Cancel") || ui.Input().Pressed(Key.Escape)) app.Asking = false;
        }
    }
}
```

`ui.FileDialog(id, title, ref path)` is a modal dialog for choosing a file, made of widgets: the folder (a text box
and "Up"), its folders and files, the name, OK and Cancel. It returns `UiDialogResult.None` while it is open, `Ok`
(`path` is the chosen file) or `Cancel`:

```csharp
if (app.Opening)
{
    var result = ui.FileDialog("open", "Open map", ref app.Path);
    if (result == UiDialogResult.Ok) Load(ref app);
    if (result != UiDialogResult.None) app.Opening = false;
}
```

`ui.FileDialog(id, title, ref path, mode)` chooses something else (`FileDialogMode`):

| Mode | The dialog | In the browser |
|---|---|---|
| `Open` (the call without a mode) | one file | the browser's file chooser |
| `OpenMany` | several files: a click adds a file or takes it away; `ui.FileDialogPaths(id)` has them all, `path` the first | the chooser with several files |
| `Save` | a file to write: the name gets the focus, and an existing file is replaced only after "Replace" | only a name: the file becomes a download |
| `Folder` | only folders; OK chooses the folder shown | the chooser of a folder, with all its files |

`ui.FileDialogPaths(id)` gives the files of the last OK of the dialog `id` (one in the other modes).

`ui.Tooltip(text)` after a widget shows the text next to the mouse when it rests on the widget for half a second.

Inside a popup or a dialog, draw with the methods of the Ui, which draw into its layer: `ui.FillRect`, `ui.DrawText`,
`ui.DrawImage` (also scaled: `ui.DrawImage(image, source, target)`). `ui.Canvas()` draws into the frame below the
layers.

## The mouse and the keys

Every widget, and every `ui.Area`, takes the mouse. What the mouse did with the one placed last:

| Call | True |
|---|---|
| `ui.Hovered()` | while the mouse is over it |
| `ui.Clicked()` | in the frame in which it was clicked with the left button |
| `ui.RightClicked()` | in the frame in which it was clicked with the right button (pressed and released on it) |
| `ui.Held()`, `ui.RightHeld()` | while the left (right) button that went down on it is held: painting into an area |

The input of the frame has all of it: `ui.Input()` is a `UiInput` with the position (`MouseX`, `MouseY`), the left
button (`MouseDown`, `MousePressed`, `MouseReleased`), the right one (`RightDown`, `RightPressed`, `RightReleased`),
the middle one (`MiddleDown`, `MiddlePressed`, `MiddleReleased`), the wheel (`Wheel`, and `WheelX` sideways), the
modifier keys (`Ctrl`, `Shift`, `Alt`), the keys pressed (`Keys`, `Pressed(Key.Plus)`) and the text typed (`Text`). A
press of any button gets a frame of its own.

**Shortcuts.** A frame collects all keys pressed since the last one, so a quick Ctrl+S (Ctrl down, S down and up, Ctrl
up) can be over before the frame is made - on a slow machine (a frame of a few tenths of a second on an A1200) that is
a normal keystroke. Each key press keeps the modifier keys held at it (`Modifiers`, `ModifiersAt(i)`), and
`Pressed(key, modifiers)` asks for a shortcut with exactly these modifiers: `Pressed(Key.S, KeyModifiers.Ctrl)` is
Ctrl+S but not Ctrl+Shift+S, which is `Pressed(Key.S, KeyModifiers.Ctrl | KeyModifiers.Shift)`. `Ctrl`, `Shift` and
`Alt` are true when the key is held at the end of the frame or was held with a key pressed in it, so the older
`Ctrl && Pressed(Key.S)` works too (but also matches Ctrl+Shift+S). The text box takes the modifiers of each key
(Shift+arrow selects, Ctrl+A/C/X/V), and so does Tab with Shift. An input that a program makes for a test adds keys
with their modifiers with `input.AddKey(Key.S, KeyModifiers.Ctrl)`; keys added to `Keys` alone count with `Ctrl`,
`Shift` and `Alt`.

```csharp
var input = ui.Input();
if (input.Pressed(Key.S, KeyModifiers.Ctrl)) Save(ref app);
if (input.Pressed(Key.S, KeyModifiers.Ctrl | KeyModifiers.Shift)) SaveAs(ref app);
```

`ui.SetCursor(cursor)` sets the mouse pointer for the frame, whatever the widgets ask for: `Cursor.Arrow`, `Text`,
`Hand`, `Crosshair` (pointing at a tile) and `Move` (moving something):

```csharp
var r = ui.Area(0, 0);
if (ui.Hovered()) ui.SetCursor(Cursor.Crosshair);
if (ui.Held()) Paint(ref app, r, ui.Input());
if (ui.RightHeld()) PaintOtherLayer(ref app, r, ui.Input());
```

`Key` has the letters, the digits (`D0` to `D9`, and `NumPad0` to `NumPad9` of the number pad), the function keys,
the keys for moving and editing, `Plus` and `Minus` (also those of the number pad, and `=` as the key of `+` on a US
keyboard), `Comma` and `Period`.

## The loop

`window.Update()` handles the events of the window and **waits for input** before it returns, so a window that nobody
touches takes no time: a frame is drawn when something happened (a click, a key, the mouse moved), when the text
cursor blinks, or when the layout has to settle. It returns `false` when the window was closed (see below).

`window.Show(ui)` ends the frame and shows it. For games, draw into an image of your own and call
`window.Show(image)`: then the next `Update` does not wait, and the loop runs as fast as frames are drawn. Both can be
combined: `ui.End()` gives the image of the frame, which the program can draw on before it shows it.

**Animations inside the Ui.** `ui.RequestFrame(milliseconds)` asks for the next frame after that time at the latest,
also without input: the next `Update` after `Show(ui)` waits at most that long, and the program sleeps in between (no
busy loop, no `Thread.Sleep`). It holds for the frame in which it is called, so a program calls it in every frame while
something moves; with several calls the shortest wins, and so does a shorter wait of the Ui's own (the text cursor,
the layout). `0` gives the next frame at once. `ui.Input().Time` is a monotonic clock in seconds on every window, for
the step of the animation:

```csharp
if (animating)
{
    int tile = (int)(ui.Input().Time * 6.0) % frames;   // a new tile every 166 ms
    ui.DrawImage(tiles, Rect.Create(tile * 16, 0, 16, 16), r);
    ui.RequestFrame(166);
}
```

`ui.WaitMilliseconds()` tells what the frame asked for (-1: wait for input).

**Closing the window.** By default `Update` returns `false` as soon as the user closes the window (its close button,
Alt+F4, the close gadget), and the program can no longer ask anything. With `window.ConfirmClose(true)` closing the
window only asks: the window stays open, the next frame's input has `CloseRequested`, and `Update` stays `true`. The
program shows its question and closes the window itself with `window.Close()` (the same as `Dispose`); the next
`Update` then returns `false`. A program that does nothing keeps its window.

```csharp
window.ConfirmClose(true);
while (window.Update())
{
    ui.Begin(window);
    if (ui.Input().CloseRequested)
        asking = true;
    // ... the window ...
    if (asking)
    {
        using (ui.Modal("quit", "Save the changes?"))
        {
            if (ui.Button("Save")) { Save(); window.Close(); }
            if (ui.Button("Don't save")) window.Close();
            if (ui.Button("Cancel")) asking = false;
        }
    }
    window.Show(ui);
}
```

This works with X11 (`WM_DELETE_WINDOW`), Win32 (`WM_CLOSE`) and AmigaOS (`IDCMP_CLOSEWINDOW`); in the browser the
page cannot be closed by the program, and `ConfirmClose` does nothing there.

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
`ui.End()` gives its image. That is how the Ui is tested ([tests/cases/stdlib_ui.cshift](../tests/cases/stdlib_ui.cshift)):
a click is `MousePressed` and `MouseReleased` in the same frame (a right click `RightPressed` and `RightReleased`),
typing is `Keys` and `Text`. The tests of the popups, combo boxes, dialogs and the layout are
[stdlib_ui_popups.cshift](../tests/cases/stdlib_ui_popups.cshift) and
[stdlib_ui_layout.cshift](../tests/cases/stdlib_ui_layout.cshift).

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

`canvas.DrawImage(image, source, x, y)` draws a part of an image (a tile of a tile set), `canvas.DrawImage(image,
source, target)` draws it scaled to a rectangle, nearest neighbour (every pixel of the image becomes a block). Opaque
pixels at a whole zoom factor are copied without arithmetic per pixel: a map view of 800 x 500 pixels with 400 tiles of
16 x 16 at zoom 2 takes about a millisecond ([tests/cases/stdlib_ui_image.cshift](../tests/cases/stdlib_ui_image.cshift)).

The text is drawn with bitmap fonts: `Font.Fixed7x13()` and `Font.Fixed10x20()` are the "fixed" fonts of X11, which
are in the public domain, so a program that embeds them owes nobody a notice. They have ASCII, Latin-1 and a few marks
(€, typographic quotes and dashes, arrows); other characters are drawn as `?`. `Font.ForScale(scale)` picks the one
for a scale (`font.Zoomed(2)` doubles the pixels). Every character has the same width, so `font.Measure(text)` is the
number of characters times `font.CharWidth()`. The font data in `stdlib/ui_fonts.cshift` is made from the BDF files by
[tools/ui/bdf2csh.py](../tools/ui/bdf2csh.py).

## In the browser

With the wasm backend the same program runs in a web page: the window is a `<canvas>`, given to the program by
[web/cshift.js](../web/cshift.js) (`run(program, { canvas })`). `cshiftc publish` makes a page of a project that
holds everything, `cshiftc serve` shows it while you edit ([wasm.md](wasm.md)):

```
cshiftc publish demo-ui        # bin/demo-ui.html: open it in a browser
```

`window.Update()` suspends the program until there is input, as in a desktop window, so an idle page costs nothing.
The scale is the page's `devicePixelRatio` (the canvas has that many pixels per CSS pixel; the option `pixelRatio`
of `run` sets another). Ctrl+C and Ctrl+X put the selected text on the system clipboard; Ctrl+V pastes from it (the
browser gives the text with its paste event). The page cannot be closed by the program; `window.Dispose()` stops
the input. `window.ConfirmClose(true)` makes the browser ask before the tab is closed or the page left
(`beforeunload`): the browser shows a question of its own (no text of the program), only after the user has done
something on the page, and the program gets no `CloseRequested`; `ConfirmClose(false)` (no unsaved changes) stops it.
`ui.RequestFrame` resumes the program after the time (at the browser's next animation frame).

**The user's files.** The program sees only the file system of the page (in memory: the `assets` of `cshift.json`,
and what it writes), so `ui.FileDialog` works with the browser:

- To open (`Open`, `OpenMany`, `Folder`), the dialog shows a button "Choose file..." (files, folder). A browser opens
  its file chooser only while it handles a click of the user, so the page opens it itself: the dialog tells the page
  where the button is, and a click on it opens the chooser in the handler of that click (Chrome, Edge, Firefox and
  Safari all allow that; a press of Enter on the button does not open it). The chosen files are copied into
  `/home/web_user/files/` and `path` is the first of them; several files land side by side, so a program can read the
  neighbours of the file it opened (`Monster_char.amb`, then `Monster_gfx.amb` from the same folder, if the user chose
  both). A folder (`webkitdirectory`; not on phones) lands with its own folders as `/home/web_user/files/<folder>/...`,
  and `path` is that folder. Cancel in the browser's chooser cancels the dialog (browsers that do not report it leave
  the dialog open: its Cancel). "Files of the page" shows the dialog of widgets for the page's own files.
- To save (`Save`), the dialog asks only for a name and gives `/home/web_user/downloads/<name>`. Every file that the
  program writes into `/home/web_user/downloads/` and closes is offered as a download (`<a download>` of a `Blob`) when
  the program waits for input again: once per file, also when it was written in several steps before that. The file
  stays in the page's memory.

**The mouse, touch and pens.** The canvas takes pointer events: the mouse, a touchpad, a pen and a finger work alike
(a finger is the left button: a tap is a click, dragging moves a slider or paints). While a button is held the canvas
captures the pointer, so a drag goes on outside of it and its release arrives; the state of the buttons follows
`event.buttons` (a release outside of the window is not missed), and a button is let go when the window loses the
focus. On the canvas the browser neither scrolls nor zooms by touch, selects text or drags the picture
(`touch-action: none`, `user-select: none`). The position is the canvas pixel under the pointer, with any device
pixel ratio (1.25 at 125 %), a scrolled page and a canvas that CSS makes smaller (a phone). Widgets also react to a
click that went down and up within one frame (a slow frame, a tap), and a click or a key gets one more frame at once,
so what it changed is shown without waiting for the next input.

This needs `--backend wasm`, which can suspend a program; with `--target wasm32-wasi` (LLVM) a program that opens a
window does not link. Under node or wasmtime there is no canvas: `Window.Open` reports `UiError.NotSupported`.

## On the Amiga

A 68000 cannot paint every pixel of a frame in 32 bits, so on AmigaOS the Ui does not draw into an image: it records
the frame as drawing commands, and the window draws them with graphics.library. Rectangles are `RectFill`s (rounded
corners and circles as a few runs of rows), lines `Move`/`Draw`, text the system font (Topaz 8, or the font of the
preferences; the Ui takes its size for the layout), and the colors of the theme become the nearest pens of the
Workbench screen (`ObtainBestPenA`). The frame is drawn into a bitmap of its own and copied into the window in one blit,
so nothing flickers. The same program runs on the Amiga and on the desktop:

```
cshiftc build demo-ui --target m68k-amigaos -o demo-ui
```

The window is on the Workbench screen and can be moved, resized and closed. It needs AmigaOS 3.0 (graphics.library and
intuition.library 39); older versions get `UiError.NotSupported`. What differs from the desktop: the mouse is followed
only while its button is held (dragging a slider, selecting text), so nothing lights up under it (as with the gadgets of
AmigaOS) and moving it costs no frame; the text cursor does not blink (the Ui asks for no frames of its own:
`UiInput.Steady`), while `ui.RequestFrame` works (it waits for the window and `timer.device` together), a whole
frame given as an image (`window.Show(image)`) is not shown, the mouse pointer keeps its shape, and the clipboard stays
inside the program. The right mouse button is the menu button (the window has no menus of Intuition), the middle one is reported
too; nothing lights up under the mouse, so tooltips do not show, and the rest of the window is not dimmed behind a
modal dialog (it still gets no input). The keyboard: Tab, Return, Esc, Backspace, Del, the cursor keys, F1 to F10,
Ctrl with a letter, `+`, `-`, `,` and `.` (the digits of the number pad come as the digits), and the wheel of
NewMouse (no horizontal wheel). The modifier keys of each key press come from the qualifier of its message, so a
shortcut typed during a slow frame is not lost (`Pressed(Key.S, KeyModifiers.Ctrl)`).

**Images.** `ui.Image`, `ui.DrawImage` and `Canvas.DrawImage` of a frame with commands are drawn, also scaled and
clipped. The window keeps each image in the pens of the screen: one byte per pixel, the pen that `ObtainBestPenA`
gives for its color (each color is asked for once, and the pens are released with the window). Pixels with an alpha
below 128 are transparent; there is no blending. This copy is made the first time the image is drawn and kept for the
next frames (the 32 images drawn last), so a frame of hundreds of tiles of one tile set maps no colors; a program that
changes the pixels of an image afterwards calls `image.Changed()`, and the copy is made again (`Image.Changes` is
also part of `Ui.CommandsHash`, so the frame is drawn again). A part is drawn by scaling it (nearest neighbour, every
whole zoom factor copies rows) into a buffer of pens that is written into the frame's bitmap with
`WriteChunkyPixels` (graphics.library 40, AmigaOS 3.1) or `WritePixelArray8`; if the part has transparent pixels, the
background is read first (`ReadPixelArray8`) and kept where they are.

The colors are those of the screen: on the Workbench with 8 or 16 colors an image becomes a rough picture in them (a
tile set looks like a sketch of itself), with 256 colors (AGA, or a graphics card) it comes close. Memory: the copy in
pens takes one byte per pixel besides the 4 of the image - a tile set of 1024 x 640 takes 640 KB more, next to its
2.5 MB as an `Image`; on a machine with little memory, an image of only the tiles in use is the better choice.

How fast: in FS-UAE (an A1200 with the AROS ROM, the 4 colors of its Workbench), an area of 320 x 192 full of tiles
of 32 x 32 (a tile set of 16 x 16 at zoom 2; 60 tiles, all of them different from the frame before) takes about 1.2 s
per frame, of which about 0.6 s is the writing of the pens by AROS (`WriteChunkyPixels`), about 0.4 s the scaling
and 0.15 s the commands of the 60 tiles; the rest of such a frame takes about 0.1 s. A 640 x 400 area is about 4 times as much. This was not
measured on a real A1200 with AmigaOS 3.x, whose `WriteChunkyPixels` may well be faster than the one of AROS.

**Speed.** A 68020 at 14 MHz (A1200) computes a frame of [demo-ui](../demo-ui/README.md) (about 30 widgets) in about a
quarter of a second; drawing it takes another tenth. A frame that draws the same as the one in the window (same
`Ui.CommandsHash`) is not drawn again, and a quick click is one frame. Floating point is software without an FPU and
costs milliseconds per operation: the Ui itself uses none in a frame, and a program for the Amiga should keep `double`
out of the code that runs for every frame too (`$"{x:F0}"` of a double costs some 40 ms on an A1200).

## Drawing with commands

`ui.BeginCommands(input, width, height, scale, font)` starts a frame that is not drawn but recorded: after `ui.End()`,
`ui.Commands()` holds the drawing operations of the frame in order (`UiCommand`: `Clear`, `FillRect`,
`FillRoundRect`, `StrokeRoundRect`, `FillCircle`, `Line`, `Text`, `Image`, `ImagePart` (a part of an image, scaled:
`Source` is the part, `Rect` where it goes), `Clip`). A command of an image holds the `Image` itself (its pixels are
shared, not copied); `Ui.CommandsHash` includes which image it is, the part and `Image.Changes`. The layers of popups and dialogs come after the rest of the frame. That is how the window of AmigaOS
works, and how a renderer of your own gets the frames (a terminal, a display without pixels to spare, a test).
`font` gives the sizes of the text; `Font.Metrics(width, height, ascent)` is a font of which only the sizes are known.

## How it works

A `Ui` keeps what has to last from one frame to the next: which widget is under the mouse ("hot"), which one the
mouse button went down on ("active"), which one has the keyboard focus, the cursor and the selection of the text box
being edited, the scroll positions and the sizes of panels and rows from the last frame. Everything else is made
again for each frame. A copy of a `Ui` shares this state (it is held in a one-element array), so `Ui` can be passed to
functions by value, and `using (ui.Row())` can end the row it began.

Popups and dialogs are drawn into layers: while a popup or a modal dialog is drawn, the drawing operations go into
the list of its layer (as `UiCommand`s), and `ui.End()` draws the layers over the frame in their order (or appends
them to the commands). Which widget gets the mouse is decided by the rectangles of the layers in the last frame (and
those already drawn in this one): a widget below a popup does not light up, a widget behind a modal dialog gets
nothing. The open popups are part of the state of the Ui; a popup that is not drawn in a frame is closed.

The window layer is the operating system part of the standard library (`stdlib/os/<layer>/ui.cshift`): Win32 on
Windows, X11 on Linux, the canvas of web/cshift.js for WebAssembly, Intuition and graphics.library on AmigaOS (from
drawing commands). One window can be open at a time.
