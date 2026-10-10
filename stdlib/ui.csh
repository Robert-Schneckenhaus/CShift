namespace System.Ui;

using System;
using System.Image;

//! User interfaces in immediate mode: the program describes its whole window again for every frame, from its own
//! state, and a widget reports what the user did with it as its result. There are no widget objects, callbacks or
//! events to unsubscribe, and the state stays in the program's own structs.
//!
//! ```
//! using System.Ui;
//!
//! struct App { int Count; string Name; bool Loud; }
//!
//! void Draw(Ui ui, ref App app)
//! {
//!     ui.Label($"Count: {app.Count}");
//!     using (ui.Row())
//!     {
//!         if (ui.Button("-")) app.Count -= 1;
//!         if (ui.Button("+")) app.Count += 1;
//!     }
//!     ui.TextBox("name", ref app.Name);
//!     ui.Checkbox("Loud", ref app.Loud);
//! }
//!
//! int Main()
//! {
//!     var window = try Window.Open("Counter", 320, 200);
//!     var ui = Ui.Create();
//!     var app = App { Name = "World" };
//!     while (window.Update())
//!     {
//!         ui.Begin(window);
//!         Draw(ui, ref app);
//!         window.Show(ui);
//!     }
//!     return 0;
//! }
//! ```
//!
//! A [Ui] draws into an [Image] with the software renderer of [Canvas], so it also works without a window (tests,
//! screenshots: [Ui.Begin] with a [UiInput] of your own). Sizes are in pixels at a scale of 1 (96 dpi); a [Window]
//! reports the scale of its screen, and the Ui picks a font and the sizes for it.

/// The keys that [UiInput.Keys] reports.
enum Key : int32
{
    /// No key.
    None,
    /// Enter (also the one of the number pad).
    Enter,
    /// Escape.
    Escape,
    /// Backspace.
    Backspace,
    /// Delete.
    Delete,
    /// Tab (with Shift: [UiInput.Shift]).
    Tab,
    /// The space bar.
    Space,
    /// Insert.
    Insert,
    /// Arrow left.
    Left,
    /// Arrow right.
    Right,
    /// Arrow up.
    Up,
    /// Arrow down.
    Down,
    /// Home.
    Home,
    /// End.
    End,
    /// Page up.
    PageUp,
    /// Page down.
    PageDown,
    /// The letter A.
    A,
    /// The letter B.
    B,
    /// The letter C.
    C,
    /// The letter D.
    D,
    /// The letter E.
    E,
    /// The letter F.
    F,
    /// The letter G.
    G,
    /// The letter H.
    H,
    /// The letter I.
    I,
    /// The letter J.
    J,
    /// The letter K.
    K,
    /// The letter L.
    L,
    /// The letter M.
    M,
    /// The letter N.
    N,
    /// The letter O.
    O,
    /// The letter P.
    P,
    /// The letter Q.
    Q,
    /// The letter R.
    R,
    /// The letter S.
    S,
    /// The letter T.
    T,
    /// The letter U.
    U,
    /// The letter V.
    V,
    /// The letter W.
    W,
    /// The letter X.
    X,
    /// The letter Y.
    Y,
    /// The letter Z.
    Z,
    /// The digit 0 (of the main keyboard).
    D0,
    /// The digit 1 (of the main keyboard).
    D1,
    /// The digit 2 (of the main keyboard).
    D2,
    /// The digit 3 (of the main keyboard).
    D3,
    /// The digit 4 (of the main keyboard).
    D4,
    /// The digit 5 (of the main keyboard).
    D5,
    /// The digit 6 (of the main keyboard).
    D6,
    /// The digit 7 (of the main keyboard).
    D7,
    /// The digit 8 (of the main keyboard).
    D8,
    /// The digit 9 (of the main keyboard).
    D9,
    /// The function key F1.
    F1,
    /// The function key F2.
    F2,
    /// The function key F3.
    F3,
    /// The function key F4.
    F4,
    /// The function key F5.
    F5,
    /// The function key F6.
    F6,
    /// The function key F7.
    F7,
    /// The function key F8.
    F8,
    /// The function key F9.
    F9,
    /// The function key F10.
    F10,
    /// The function key F11.
    F11,
    /// The function key F12.
    F12
}

/// The shape of the mouse pointer that a frame asks for (see [Ui.Cursor]).
enum Cursor : int32
{
    /// The normal arrow.
    Arrow = 0,
    /// Over text that can be edited.
    Text = 1,
    /// Over something that can be clicked.
    Hand = 2
}

/// What the user did since the last frame: the state of the mouse and the keys that were pressed. A [Window] fills
/// it in ([Window.Input]); for tests and screenshots a program can make its own.
struct UiInput
{
    /// The position of the mouse in pixels of the frame (-1 when it is outside).
    int MouseX;
    /// The position of the mouse in pixels of the frame (-1 when it is outside).
    int MouseY;
    /// The left mouse button is held down.
    bool MouseDown;
    /// The left button went down since the last frame.
    bool MousePressed;
    /// The left button went up since the last frame (with MousePressed: a click within one frame).
    bool MouseReleased;
    /// The mouse wheel, in notches since the last frame: positive when turned away from the user (scroll up).
    int Wheel;
    /// The keys pressed since the last frame, in order, including the repeats of a key that is held.
    List<Key> Keys;
    /// The characters typed since the last frame (UTF-8).
    string Text;
    /// A Ctrl key is held down.
    bool Ctrl;
    /// A Shift key is held down.
    bool Shift;
    /// An Alt key is held down.
    bool Alt;
    /// Seconds since an arbitrary moment (for the blinking of the text cursor).
    double Time;

    /// No mouse button, no keys, the mouse outside of everything.
    static UiInput Create()
    {
        return UiInput { MouseX = -1, MouseY = -1, Keys = List<Key>.Create(), Text = "" };
    }

    /// True if the key was pressed since the last frame.
    bool Pressed(Key key)
    {
        if (!Keys.IsCreated())
            return false;
        foreach (var k in Keys)
        {
            if (k == key)
                return true;
        }
        return false;
    }
}

/// The colors of a [Ui]: [Theme.Light] (the default) or [Theme.Dark], or your own.
struct Theme
{
    /// The window.
    Color Background;
    /// Panels.
    Color Panel;
    /// The lines around controls and panels.
    Color Border;
    /// Text.
    Color Text;
    /// Text that is less important (titles of panels, disabled things).
    Color TextMuted;
    /// Buttons, the tracks of sliders and progress bars.
    Color Control;
    /// Buttons and the like under the mouse.
    Color ControlHover;
    /// Buttons and the like while they are pressed.
    Color ControlPressed;
    /// Checked boxes, the filled part of sliders and progress bars, the selected item of a list.
    Color Accent;
    /// Text and marks on the accent color.
    Color AccentText;
    /// The background of text boxes and scroll areas.
    Color Input;
    /// The outline of the control that has the keyboard focus.
    Color Focus;
    /// Selected text, and list items under the mouse.
    Color Selection;

    /// Dark text on light gray (the default).
    static Theme Light()
    {
        return Theme
        {
            Background = Color.FromRgb(243, 243, 243),
            Panel = Color.FromRgb(251, 251, 251),
            Border = Color.FromRgb(200, 200, 200),
            Text = Color.FromRgb(28, 28, 28),
            TextMuted = Color.FromRgb(110, 110, 110),
            Control = Color.FromRgb(253, 253, 253),
            ControlHover = Color.FromRgb(236, 240, 246),
            ControlPressed = Color.FromRgb(214, 222, 234),
            Accent = Color.FromRgb(0, 103, 192),
            AccentText = Color.FromRgb(255, 255, 255),
            Input = Color.FromRgb(255, 255, 255),
            Focus = Color.FromRgb(0, 103, 192),
            Selection = Color.FromRgb(204, 228, 247)
        };
    }

    /// Light text on dark gray.
    static Theme Dark()
    {
        return Theme
        {
            Background = Color.FromRgb(32, 32, 32),
            Panel = Color.FromRgb(43, 43, 43),
            Border = Color.FromRgb(70, 70, 70),
            Text = Color.FromRgb(232, 232, 232),
            TextMuted = Color.FromRgb(160, 160, 160),
            Control = Color.FromRgb(55, 55, 55),
            ControlHover = Color.FromRgb(66, 66, 66),
            ControlPressed = Color.FromRgb(46, 46, 46),
            Accent = Color.FromRgb(76, 194, 255),
            AccentText = Color.FromRgb(0, 0, 0),
            Input = Color.FromRgb(28, 28, 28),
            Focus = Color.FromRgb(76, 194, 255),
            Selection = Color.FromRgb(38, 79, 120)
        };
    }
}

/// The end of a group that [Ui.Row], [Ui.Columns], [Ui.Panel], [Ui.Scroll] and [Ui.Id] started: `using (ui.Row())
/// { ... }` ends it when the block is left.
struct UiScope : IDisposable
{
    /// The Ui it belongs to (internal).
    _UiState[] State;

    /// Ends the group.
    void Dispose()
    {
        State[0].EndScope();
    }
}

/// The user interface: one value for the whole program, created once and given every frame to the code that draws
/// it. Copies share the same state (it is held by reference), so a Ui can be passed to functions by value.
///
/// A frame is [Ui.Begin], the widgets and groups, then [Ui.End] (or [Window.Show], which calls it). Widgets are laid
/// out from top to bottom; [Ui.Row] puts them side by side, [Ui.Columns] into a grid. Every widget has an id, made from its
/// label and the groups around it: two widgets with the same label in the same group need different ids, either with
/// `##` (only what is before it is shown: `"Delete##3"`) or with `using (ui.Id(i))`.
struct Ui
{
    _UiState[] _S;

    /// A new Ui with the light theme.
    static Ui Create()
    {
        var s = new _UiState[1];
        s[0] = _UiState.Create();
        return Ui { _S = s };
    }

    // ---- frames ----

    /// Starts a frame for a window: its input, size and scale.
    void Begin(Window window)
    {
        _S[0].Begin(window.Input(), window.Width(), window.Height(), window.Scale());
    }

    /// Starts a frame of the given size in pixels; `scale` is 1 at 96 dpi.
    void Begin(UiInput input, int width, int height, double scale)
    {
        _S[0].Begin(input, width, height, scale);
    }

    /// Ends the frame and gives the image it drew (the same image every frame, as long as the size stays).
    Image End()
    {
        _S[0].End();
        return _S[0].Frame;
    }

    /// The image of the last frame.
    Image Frame() { return _S[0].Frame; }

    /// The mouse pointer that the last frame asks for.
    Cursor Cursor() { return _S[0].WantCursor; }

    /// How long the program may wait for input before it draws the next frame: 0 if the layout is not settled yet
    /// (a panel changed its size), the time until the text cursor blinks, or -1 (no limit).
    int WaitMilliseconds() { return _S[0].WaitMs; }

    /// Uses other colors from the next widget on.
    void SetTheme(Theme theme) { _S[0].Theme = theme; }

    /// The colors in use.
    Theme GetTheme() { return _S[0].Theme; }

    /// The scale of the current frame (1 = 96 dpi).
    double Scale() { return _S[0].Scale; }

    /// The font of the current frame.
    Font Font() { return _S[0].Font; }

    /// The input of the current frame.
    UiInput Input() { return _S[0].In; }

    /// The canvas that the current frame draws on, for drawing of your own (see [Ui.Area]).
    Canvas Canvas() { return _S[0].Canvas; }

    /// Takes a rectangle of the layout for drawing of your own: `width` (0: as wide as there is room) x `height`
    /// pixels at scale 1. Returns it in pixels of the frame.
    Rect Area(int width, int height)
    {
        int w = _S[0].Px(width);
        return _S[0].Place(w, _S[0].Px(height), width <= 0);
    }

    // ---- groups ----

    /// The widgets in the block go side by side, each as wide as it needs (text boxes, sliders and the like take the
    /// rest of the line).
    UiScope Row() { _S[0].BeginLayout(1, 0); return UiScope { State = _S }; }

    /// The widgets in the block go below each other (inside a [Ui.Row]: a column in it).
    UiScope Column() { _S[0].BeginLayout(0, 0); return UiScope { State = _S }; }

    /// The widgets in the block go into a grid of `count` columns of equal width, row by row.
    UiScope Columns(int count) { _S[0].BeginLayout(2, Math.Max(1, count)); return UiScope { State = _S }; }

    /// A framed group with a title (empty: none); the widgets in the block go below each other.
    UiScope Panel(string title) { _S[0].BeginPanel(title); return UiScope { State = _S }; }

    /// An area of the given height (pixels at scale 1) whose content scrolls: with the mouse wheel and a scroll bar.
    UiScope Scroll(string id, int height) { _S[0].BeginScroll(id, height); return UiScope { State = _S }; }

    /// Makes the ids of the widgets in the block different from those of the same widgets elsewhere (lists).
    UiScope Id(int value) { _S[0].BeginId(value.ToString()); return UiScope { State = _S }; }

    /// The same with a text.
    UiScope Id(string value) { _S[0].BeginId(value); return UiScope { State = _S }; }

    // ---- widgets ----

    /// Text in one line.
    void Label(string text) { _S[0].Label(text, false); }

    /// Text in the muted color of the theme.
    void Note(string text) { _S[0].Label(text, true); }

    /// Text that is wrapped at the width of the layout (also at line ends).
    void Text(string text) { _S[0].Paragraph(text); }

    /// A button; true in the frame in which it was clicked (also with Enter or Space when it has the focus).
    bool Button(string label) { return _S[0].Button(label); }

    /// A check box; true in the frame in which the user changed `value`.
    bool Checkbox(string label, ref bool value) { return _S[0].Checkbox(label, ref value); }

    /// One of a group of options: `value` becomes `option` when it is chosen; true in that frame.
    bool Radio(string label, ref int value, int option) { return _S[0].Radio(label, ref value, option); }

    /// A slider from `min` to `max`; true in the frames in which the user changed `value`. With the keyboard: the
    /// arrow keys move it by 1/100 of the range.
    bool Slider(string id, ref double value, double min, double max) { return _S[0].Slider(id, ref value, min, max, false); }

    /// A slider for whole numbers.
    bool Slider(string id, ref int value, int min, int max)
    {
        double v = (double)value;
        bool changed = _S[0].Slider(id, ref v, (double)min, (double)max, true);
        value = (int)Math.Round(v);
        return changed;
    }

    /// A line of editable text; true in the frames in which the user changed `text`. Keys: the arrows, Home, End,
    /// Backspace, Delete, with Shift to select; Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V; Escape ends the editing.
    bool TextBox(string id, ref string text) { return _S[0].TextBox(id, ref text); }

    /// True in the frame in which Enter was pressed in the text box with this id.
    bool Submitted(string id) { return _S[0].Submitted(id); }

    /// A bar that is filled from 0.0 to 1.0.
    void ProgressBar(double fraction) { _S[0].ProgressBar(fraction); }

    /// A line of a list that can be selected; true in the frame in which it was clicked.
    bool ListItem(string label, bool selected) { return _S[0].ListItem(label, selected); }

    /// An image, in its own size.
    void Image(Image image) { _S[0].ImageWidget(image); }

    /// A horizontal line.
    void Separator() { _S[0].Separator(); }

    /// Empty space of the given size (pixels at scale 1): down in a column, to the right in a row.
    void Space(int size) { _S[0].Space(size); }

    /// The rectangle of the widget (or group) that was placed last, in pixels of the frame.
    Rect LastRect() { return _S[0].Last; }

    /// True if the widget with this id (a label with its `##` part) is under the mouse in this frame - for widgets
    /// that come before; it is known once they are drawn.
    bool IsHovered(string id) { return _S[0].Hot == _S[0].IdOf(id); }

    /// True if the widget with this id has the keyboard focus.
    bool HasFocus(string id) { return _S[0].Focus == _S[0].IdOf(id); }

    /// Gives the keyboard focus to the widget with this id from the next frame on (0 ids: none).
    void SetFocus(string id) { _S[0].FocusNext = _S[0].IdOf(id); _S[0].FocusSet = true; _S[0].Again = true; }
}

// A group that is open: where the next widget goes, and what to do at its end.
struct _UiLayout
{
    int Kind;        // 0 column, 1 row, 2 grid
    int Columns;     // grid: the number of columns
    Rect Area;       // the room of the content (Height is not limited)
    int X;           // where the next widget goes
    int Y;
    int LineHeight;  // row and grid: the tallest widget of the current line
    int Index;       // grid: the cell of the current line
    int Right;       // the rightmost and lowest pixel used so far
    int Bottom;
    int Scope;       // 0 layout, 1 panel, 2 scroll area, 3 id
    uint32 Id;       // panel, scroll area: its id; the seed of the ids inside
    Rect Outer;      // panel, scroll area: its frame
    Rect SavedClip;
    int ScrollOffset;
    uint32 RowKey;   // row: its key in RowMemos
    int FillWidth;   // row: the width of a widget that fills (from the last frame), 0: the rest of the line
    int Fixed;       // row: the widths of the widgets that do not fill, so far
    int Fills;       // row: the number of widgets that fill
    int Items;       // row: the number of widgets
}

// What a row needed in the last frame: the widths of its widgets that do not fill, and how many fill the rest.
struct _UiRowMemo : IEquatable<_UiRowMemo>
{
    int Fixed;
    int Fills;
    int Items;

    bool Equals(_UiRowMemo other)
    {
        return Fixed == other.Fixed && Fills == other.Fills && Items == other.Items;
    }
}

struct _UiScroll
{
    int Offset;
    int ContentHeight;
}

// The state of a Ui (shared by its copies through a one-element array).
struct _UiState
{
    Image Frame;
    Canvas Canvas;
    Theme Theme;
    Font Font;
    double Scale;
    UiInput In;
    bool InFrame;               // between Begin and End
    bool PrevMouseDown;

    // the metrics of the current scale
    int ControlHeight;
    int Pad;
    int Spacing;
    int Margin;
    int Radius;
    int Line;        // the thickness of lines (1 at scale 1)

    List<_UiLayout> Layouts;
    List<uint32> FocusOrder;    // the focusable widgets of this frame, in order
    Dictionary<uint32, int> PanelHeights;
    Dictionary<uint32, _UiScroll> Scrolls;
    Dictionary<uint32, _UiRowMemo> RowMemos;
    int RowCount;               // rows begun in this frame (their keys)

    Rect Last;                  // the widget placed last
    uint32 Hot;                 // under the mouse (in this frame, so far)
    uint32 Active;              // the mouse went down on it and has not gone up yet
    uint32 Focus;               // gets the keys
    uint32 FocusNext;
    bool FocusSet;
    bool FocusVisible;          // the focus came with the keyboard: show it (not after a click)
    bool Claimed;               // a widget took this frame's mouse press
    bool WheelUsed;
    bool Again;                 // the layout changed: draw another frame at once
    Cursor WantCursor;
    int WaitMs;

    // the text box being edited (the one with the focus)
    uint32 EditId;
    int Caret;                  // byte index into the text
    int Anchor;                 // the other end of the selection
    int ScrollX;                // how far the text is scrolled to the left, in pixels
    double BlinkStart;
    uint32 SubmittedId;
    int DragOffset;             // scroll bars: where the thumb was grabbed

    static _UiState Create()
    {
        return _UiState
        {
            Frame = Image.Create(0, 0),
            Theme = Theme.Light(),
            Font = Font.Fixed7x13(),
            Scale = 0.0,
            In = UiInput.Create(),
            Layouts = List<_UiLayout>.Create(),
            FocusOrder = List<uint32>.Create(),
            PanelHeights = Dictionary<uint32, int>.Create(),
            Scrolls = Dictionary<uint32, _UiScroll>.Create(),
            RowMemos = Dictionary<uint32, _UiRowMemo>.Create(),
            WaitMs = -1
        };
    }

    // pixels at scale 1 -> pixels of the frame
    int Px(int size)
    {
        return (int)Math.Round((double)size * Scale);
    }

    // ---- frames ----

    void Begin(UiInput input, int width, int height, double scale)
    {
        double s = scale > 0 ? scale : 1.0;
        if (s != Scale)
        {
            Scale = s;
            Font = Font.ForScale(s);
            int lh = Font.LineHeight();
            Pad = Px(4);
            ControlHeight = lh + 2 * Px(5);
            Spacing = Px(6);
            Margin = Px(10);
            Radius = Px(4);
            Line = Math.Max(1, Px(1));
        }
        int w = Math.Max(1, width);
        int h = Math.Max(1, height);
        if (Frame.Width != w || Frame.Height != h)
            Frame = Image.Create(w, h);
        Canvas = Canvas.Create(Frame);
        Canvas.Clear(Theme.Background);
        In = input;
        InFrame = true;
        if (!In.Keys.IsCreated())
            In.Keys = List<Key>.Create();
        if (FocusSet)
        {
            Focus = FocusNext;
            FocusSet = false;
        }
        Hot = 0u;
        FocusOrder.Clear();
        Claimed = false;
        WheelUsed = false;
        Again = false;
        WantCursor = Cursor.Arrow;
        WaitMs = -1;
        SubmittedId = 0u;
        RowCount = 0;
        Layouts.Clear();
        var root = _UiLayout { Kind = 0, Area = Rect.Create(Margin, Margin, w - 2 * Margin, h - 2 * Margin), Scope = 0 };
        root.X = root.Area.X;
        root.Y = root.Area.Y;
        root.Right = root.X;
        root.Bottom = root.Y;
        root.SavedClip = Canvas.Clip;
        Layouts.Add(root);
    }

    void End()
    {
        if (!InFrame)
            return; // ended already (ui.End() and then Window.Show(ui))
        InFrame = false;
        while (Layouts.Count() > 1)
            EndScope();
        // Tab moves the focus along the focusable widgets of this frame
        if (In.Pressed(Key.Tab) && FocusOrder.Count() > 0)
        {
            int index = FocusOrder.IndexOf(Focus);
            int count = FocusOrder.Count();
            int next = index < 0 ? (In.Shift ? count - 1 : 0) : (In.Shift ? (index + count - 1) % count : (index + 1) % count);
            FocusNext = FocusOrder.Get(next);
            FocusSet = true;
            FocusVisible = true;
            Again = true;
        }
        if (In.MousePressed && !Claimed)
            Focus = 0u; // a click on nothing
        if (In.MouseReleased || !In.MouseDown)
            Active = 0u;
        if (Focus != EditId)
            EditId = 0u;
        PrevMouseDown = In.MouseDown;
        if (Again)
            WaitMs = 0;
    }

    // ---- ids ----

    uint32 Seed()
    {
        return Layouts.Count() > 0 ? Layouts.Get(Layouts.Count() - 1).Id : 0u;
    }

    uint32 IdOf(string label)
    {
        uint32 h = Seed() ^ 2166136261u;
        for (var i = 0; i < label.Length; i += 1)
            h = unchecked((h ^ (uint32)label[i]) * 16777619u);
        return h == 0u ? 1u : h;
    }

    // ---- layout ----

    _UiLayout Top() { return Layouts.Get(Layouts.Count() - 1); }

    void SetTop(_UiLayout layout) { Layouts.Set(Layouts.Count() - 1, layout); }

    // where the next widget goes, and how wide it may be
    Rect Slot()
    {
        var l = Top();
        switch (l.Kind)
        {
        case 1:
            return Rect.Create(l.X, l.Y, Math.Max(0, l.Area.X + l.Area.Width - l.X), 0);
        case 2:
        {
            int cell = (l.Area.Width - (l.Columns - 1) * Spacing) / l.Columns;
            return Rect.Create(l.Area.X + l.Index * (cell + Spacing), l.Y, cell, 0);
        }
        default:
            return Rect.Create(l.X, l.Y, l.Area.Width, 0);
        }
    }

    // the widget at the slot took width x height: move on
    void Commit(int width, int height)
    {
        var l = Top();
        switch (l.Kind)
        {
        case 1:
            l.LineHeight = Math.Max(l.LineHeight, height);
            l.Right = Math.Max(l.Right, l.X + width);
            l.X += width + Spacing;
            l.Bottom = Math.Max(l.Bottom, l.Y + l.LineHeight);
            break;
        case 2:
            l.LineHeight = Math.Max(l.LineHeight, height);
            l.Bottom = Math.Max(l.Bottom, l.Y + l.LineHeight);
            l.Right = l.Area.X + l.Area.Width;
            l.Index += 1;
            if (l.Index >= l.Columns)
            {
                l.Index = 0;
                l.Y += l.LineHeight + Spacing;
                l.LineHeight = 0;
            }
            break;
        default:
            l.Right = Math.Max(l.Right, l.X + width);
            l.Bottom = Math.Max(l.Bottom, l.Y + height);
            l.Y += height + Spacing;
            break;
        }
        SetTop(l);
    }

    // a widget of a natural width (fill: as wide as there is room)
    Rect Place(int width, int height, bool fill)
    {
        var slot = Slot();
        int w = fill ? slot.Width : Math.Min(width, Math.Max(slot.Width, 0));
        var l = Top();
        if (l.Kind == 1)
        {
            // in a row, a widget that fills gets what the others left in the last frame
            if (fill)
            {
                w = l.FillWidth > 0 ? Math.Min(l.FillWidth, Math.Max(slot.Width, 0)) : slot.Width;
                if (w <= 0)
                    w = width;
                l.Fills += 1;
            }
            else
            {
                w = width; // its own width: what is too wide goes past the end of the line
                l.Fixed += w;
            }
            l.Items += 1;
            SetTop(l);
        }
        var r = Rect.Create(slot.X, slot.Y, Math.Max(0, w), height);
        Commit(r.Width, r.Height);
        Last = r;
        return r;
    }

    void BeginLayout(int kind, int columns)
    {
        var slot = Slot();
        var l = _UiLayout { Kind = kind, Columns = columns, Area = Rect.Create(slot.X, slot.Y, slot.Width, 0), Scope = 0, Id = Seed() };
        l.X = slot.X;
        l.Y = slot.Y;
        l.Right = slot.X;
        l.Bottom = slot.Y;
        l.SavedClip = Canvas.Clip;
        if (kind == 1)
        {
            l.RowKey = unchecked(Seed() * 31u + (uint32)RowCount * 2654435761u + 7u);
            RowCount += 1;
            var memo = RowMemos.GetOrDefault(l.RowKey, _UiRowMemo { });
            if (memo.Fills > 0)
                l.FillWidth = Math.Max(Px(20), (slot.Width - memo.Fixed - Spacing * (memo.Items - 1)) / memo.Fills);
        }
        Layouts.Add(l);
    }

    void BeginId(string value)
    {
        var top = Top();
        uint32 id = IdOf("#id:" + value);
        var l = top;
        l.Scope = 3;
        l.Id = id;
        l.SavedClip = Canvas.Clip;
        Layouts.Add(l);
    }

    void BeginPanel(string title)
    {
        uint32 id = IdOf("#panel:" + title);
        var slot = Slot();
        int cached = PanelHeights.GetOrDefault(id, 0);
        var outer = Rect.Create(slot.X, slot.Y, slot.Width, cached);
        Canvas.FillRoundRect(outer, Radius, Theme.Panel);
        int top = outer.Y + Margin;
        if (title.Length > 0)
        {
            Canvas.Text(Font, outer.X + Margin, top, title, Theme.TextMuted);
            top += Font.LineHeight() + Spacing;
        }
        var l = _UiLayout { Kind = 0, Area = Rect.Create(outer.X + Margin, top, Math.Max(0, outer.Width - 2 * Margin), 0), Scope = 1, Id = id, Outer = outer };
        l.X = l.Area.X;
        l.Y = top;
        l.Right = l.X;
        l.Bottom = top;
        l.SavedClip = Canvas.Clip;
        Layouts.Add(l);
    }

    void BeginScroll(string name, int height)
    {
        uint32 id = IdOf("#scroll:" + name);
        var slot = Slot();
        var outer = Rect.Create(slot.X, slot.Y, slot.Width, Px(height));
        var state = Scrolls.GetOrDefault(id, _UiScroll { });
        Canvas.FillRoundRect(outer, Radius, Theme.Input);
        int bar = Px(10);
        int top = outer.Y + Pad - state.Offset;
        var l = _UiLayout { Kind = 0, Area = Rect.Create(outer.X + Pad, top, Math.Max(0, outer.Width - 2 * Pad - bar), 0), Scope = 2, Id = id, Outer = outer };
        l.X = l.Area.X;
        l.Y = top;
        l.Right = l.X;
        l.Bottom = top;
        l.SavedClip = Canvas.Clip;
        l.ScrollOffset = state.Offset;
        Layouts.Add(l);
        Canvas.SetClip(outer.Shrink(Line).Intersect(l.SavedClip));
    }

    void EndScope()
    {
        if (Layouts.Count() <= 1)
            return; // more ends than beginnings
        var l = Top();
        Layouts.RemoveAt(Layouts.Count() - 1);
        Canvas.Clip = l.SavedClip;
        switch (l.Scope)
        {
        case 1:
        {
            int height = l.Bottom - l.Outer.Y + Margin;
            if (l.Bottom == l.Area.Y)
                height = l.Area.Y - l.Outer.Y + Margin - Spacing; // empty
            if (PanelHeights.GetOrDefault(l.Id, -1) != height)
            {
                PanelHeights.Set(l.Id, height);
                Again = true;
            }
            var outer = Rect.Create(l.Outer.X, l.Outer.Y, l.Outer.Width, height);
            Canvas.StrokeRoundRect(outer, Radius, Line, Theme.Border);
            Commit(outer.Width, outer.Height);
            Last = outer;
            break;
        }
        case 2:
            EndScroll(l);
            break;
        case 3:
            break; // the layout of an id scope is the one it copied: hand on where it got to
        default:
            if (l.Kind == 1)
            {
                var memo = _UiRowMemo { Fixed = l.Fixed, Fills = l.Fills, Items = l.Items };
                if (!RowMemos.GetOrDefault(l.RowKey, _UiRowMemo { Items = -1 }).Equals(memo))
                {
                    RowMemos.Set(l.RowKey, memo);
                    Again = true;
                }
            }
            Commit(Math.Max(0, l.Right - l.Area.X), Math.Max(0, l.Bottom - l.Area.Y));
            break;
        }
        if (l.Scope == 3)
        {
            var parent = Top();
            parent.X = l.X;
            parent.Y = l.Y;
            parent.LineHeight = l.LineHeight;
            parent.Index = l.Index;
            parent.Right = l.Right;
            parent.Bottom = l.Bottom;
            parent.Fixed = l.Fixed;
            parent.Fills = l.Fills;
            parent.Items = l.Items;
            SetTop(parent);
        }
    }

    void EndScroll(_UiLayout l)
    {
        var outer = l.Outer;
        int content = l.Bottom - (outer.Y + Pad - l.ScrollOffset) + Pad;
        int view = outer.Height;
        int maxOffset = Math.Max(0, content - view);
        int offset = l.ScrollOffset;
        var mouseInside = outer.Contains(In.MouseX, In.MouseY) && Canvas.Clip.Contains(In.MouseX, In.MouseY);
        if (mouseInside && In.Wheel != 0 && !WheelUsed && maxOffset > 0)
        {
            offset -= In.Wheel * Font.LineHeight() * 3;
            WheelUsed = true;
        }
        // the scroll bar
        int bar = Px(10);
        var track = Rect.Create(outer.X + outer.Width - bar - Line, outer.Y + Line, bar, outer.Height - 2 * Line);
        uint32 barId = l.Id ^ 0x5bd1e995u;
        if (maxOffset > 0)
        {
            int thumbHeight = Math.Max(Px(20), track.Height * view / Math.Max(1, content));
            int room = Math.Max(1, track.Height - thumbHeight);
            int thumbY = track.Y + (int)((int64)room * Math.Clamp(offset, 0, maxOffset) / maxOffset);
            var thumb = Rect.Create(track.X + Px(2), thumbY, bar - Px(4), thumbHeight);
            bool hot = Interact(barId, track, false);
            if (hot && In.MousePressed)
            {
                DragOffset = thumb.Contains(In.MouseX, In.MouseY) ? In.MouseY - thumb.Y : thumbHeight / 2;
            }
            if (Active == barId && In.MouseDown)
                offset = (int)((int64)(In.MouseY - DragOffset - track.Y) * maxOffset / room);
            offset = Math.Clamp(offset, 0, maxOffset);
            thumbY = track.Y + (int)((int64)room * offset / maxOffset);
            thumb.Y = thumbY;
            Color color = Active == barId ? Theme.TextMuted : Hot == barId ? Theme.TextMuted : Theme.Border;
            Canvas.FillRoundRect(thumb, thumb.Width / 2, color);
        }
        offset = Math.Clamp(offset, 0, maxOffset);
        if (offset != l.ScrollOffset)
            Again = true;
        Scrolls.Set(l.Id, _UiScroll { Offset = offset, ContentHeight = content });
        Canvas.StrokeRoundRect(outer, Radius, Line, Theme.Border);
        Commit(outer.Width, outer.Height);
        Last = outer;
    }

    // ---- interaction ----

    // Tracks the mouse for a widget: true if it is under the mouse. A press on it makes it active (and focused, if
    // focusable); the caller checks Active and In.MouseReleased for a click.
    bool Interact(uint32 id, Rect r, bool focusable)
    {
        if (focusable)
            FocusOrder.Add(id);
        bool inside = r.Contains(In.MouseX, In.MouseY) && Canvas.Clip.Contains(In.MouseX, In.MouseY);
        bool hot = inside && (Active == 0u || Active == id);
        if (hot)
            Hot = id;
        if (hot && In.MousePressed && !Claimed)
        {
            Active = id;
            Claimed = true;
            Focus = focusable ? id : 0u;
            FocusVisible = false;
        }
        return hot;
    }

    bool Clicked(uint32 id, bool hot)
    {
        return Active == id && In.MouseReleased && hot;
    }

    bool Activated(uint32 id)
    {
        return Focus == id && (In.Pressed(Key.Enter) || In.Pressed(Key.Space));
    }

    void FocusRing(Rect r, int radius)
    {
        if (!FocusVisible)
            return;
        Canvas.StrokeRoundRect(r.Shrink(-Line - Line), radius + Line + Line, Line + Line, Theme.Focus);
    }

    // the part of a label before "##"
    static string Shown(string label)
    {
        int cut = label.IndexOf("##");
        return cut >= 0 ? label.Substring(0, cut) : label;
    }

    int TextY(Rect r)
    {
        return r.Y + (r.Height - Font.LineHeight()) / 2;
    }

    // ---- widgets ----

    void Label(string text, bool muted)
    {
        var r = Place(Font.Measure(text), ControlHeight, false);
        Canvas.Text(Font, r.X, TextY(r), text, muted ? Theme.TextMuted : Theme.Text);
    }

    void Paragraph(string text)
    {
        var slot = Slot();
        int cw = Font.CharWidth();
        int perLine = Math.Max(1, slot.Width / Math.Max(1, cw));
        var lines = List<string>.Create();
        foreach (var part in text.Split('\n'))
            Wrap(part, perLine, lines);
        int lh = Font.LineHeight() + Px(2);
        int widest = 0;
        foreach (var line in lines)
            widest = Math.Max(widest, Font.Measure(line));
        var r = Place(widest, lines.Count() * lh, false);
        int y = r.Y;
        foreach (var line in lines)
        {
            Canvas.Text(Font, r.X, y + Px(1), line, Theme.Text);
            y += lh;
        }
    }

    // breaks a line at spaces so that no part is longer than perLine characters (a longer word is cut)
    static void Wrap(StringSlice text, int perLine, List<string> lines)
    {
        StringSlice rest = text;
        while (_CountChars(rest) > perLine)
        {
            int cut = ByteOfChar(rest, perLine);
            int space = rest.Substring(0, Math.Min(cut + 1, rest.Length)).LastIndexOf(' ');
            if (space > 0)
            {
                lines.Add(rest.Substring(0, space).ToString());
                rest = rest.Substring(space + 1);
            }
            else
            {
                lines.Add(rest.Substring(0, cut).ToString());
                rest = rest.Substring(cut);
            }
        }
        lines.Add(rest.ToString());
    }

    // the byte index of the character with the given number (the length if there are fewer)
    static int ByteOfChar(StringSlice text, int index)
    {
        int count = 0;
        for (var i = 0; i < text.Length; i += 1)
        {
            if (((int)text[i] & 0xC0) != 0x80)
            {
                if (count == index)
                    return i;
                count += 1;
            }
        }
        return text.Length;
    }

    bool Button(string label)
    {
        uint32 id = IdOf(label);
        string shown = Shown(label);
        var r = Place(Font.Measure(shown) + 2 * Px(14), ControlHeight, false);
        bool hot = Interact(id, r, true);
        bool clicked = Clicked(id, hot) || Activated(id);
        if (hot)
            WantCursor = Cursor.Hand;
        Color fill = Active == id && hot ? Theme.ControlPressed : hot ? Theme.ControlHover : Theme.Control;
        Canvas.FillRoundRect(r, Radius, fill);
        Canvas.StrokeRoundRect(r, Radius, Line, Theme.Border);
        if (Focus == id)
            FocusRing(r, Radius);
        int tw = Font.Measure(shown);
        Canvas.Text(Font, r.X + (r.Width - tw) / 2, TextY(r), shown, Theme.Text);
        return clicked;
    }

    bool Checkbox(string label, ref bool value)
    {
        uint32 id = IdOf(label);
        string shown = Shown(label);
        int box = Font.LineHeight() + Px(3);
        int gap = shown.Length > 0 ? Px(8) : 0;
        var r = Place(box + gap + Font.Measure(shown), ControlHeight, false);
        bool hot = Interact(id, r, true);
        bool changed = Clicked(id, hot) || Activated(id);
        if (changed)
            value = !value;
        if (hot)
            WantCursor = Cursor.Hand;
        var b = Rect.Create(r.X, r.Y + (r.Height - box) / 2, box, box);
        if (value)
        {
            Canvas.FillRoundRect(b, Radius, Theme.Accent);
            double s = (double)box;
            double w = Math.Max(1.5, 2.0 * Scale);
            Canvas.Line((double)b.X + s * 0.25, (double)b.Y + s * 0.52, (double)b.X + s * 0.43, (double)b.Y + s * 0.70, w, Theme.AccentText);
            Canvas.Line((double)b.X + s * 0.43, (double)b.Y + s * 0.70, (double)b.X + s * 0.76, (double)b.Y + s * 0.32, w, Theme.AccentText);
        }
        else
        {
            Canvas.FillRoundRect(b, Radius, hot ? Theme.ControlHover : Theme.Input);
            Canvas.StrokeRoundRect(b, Radius, Line, hot ? Theme.TextMuted : Theme.Border);
        }
        if (Focus == id)
            FocusRing(b, Radius);
        Canvas.Text(Font, b.X + box + gap, TextY(r), shown, Theme.Text);
        return changed;
    }

    bool Radio(string label, ref int value, int option)
    {
        uint32 id = IdOf(label);
        string shown = Shown(label);
        int box = Font.LineHeight() + Px(3);
        int gap = shown.Length > 0 ? Px(8) : 0;
        var r = Place(box + gap + Font.Measure(shown), ControlHeight, false);
        bool hot = Interact(id, r, true);
        bool changed = (Clicked(id, hot) || Activated(id)) && value != option;
        if (changed)
            value = option;
        if (hot)
            WantCursor = Cursor.Hand;
        double cx = (double)r.X + (double)box / 2.0;
        double cy = (double)r.Y + (double)r.Height / 2.0;
        double radius = (double)box / 2.0;
        if (value == option)
        {
            Canvas.FillCircle(cx, cy, radius, Theme.Accent);
            Canvas.FillCircle(cx, cy, radius * 0.4, Theme.AccentText);
        }
        else
        {
            Canvas.FillCircle(cx, cy, radius, hot ? Theme.TextMuted : Theme.Border);
            Canvas.FillCircle(cx, cy, radius - (double)Line, hot ? Theme.ControlHover : Theme.Input);
        }
        if (Focus == id)
            FocusRing(Rect.Create(r.X, r.Y + (r.Height - box) / 2, box, box), box / 2);
        Canvas.Text(Font, r.X + box + gap, TextY(r), shown, Theme.Text);
        return changed;
    }

    bool Slider(string name, ref double value, double min, double max, bool whole)
    {
        uint32 id = IdOf(name);
        var r = Place(Px(160), ControlHeight, true);
        bool hot = Interact(id, r, true);
        double range = max - min;
        double old = value;
        int thumb = Px(8);
        int left = r.X + thumb;
        int width = Math.Max(1, r.Width - 2 * thumb);
        if (Active == id && In.MouseDown && range != 0)
            value = min + (double)(In.MouseX - left) / (double)width * range;
        if (Focus == id && range != 0)
        {
            double step = whole ? Math.Max(1.0, Math.Round(range / 100.0)) : range / 100.0;
            foreach (var key in In.Keys)
            {
                if (key == Key.Left || key == Key.Down)
                    value -= step;
                else if (key == Key.Right || key == Key.Up)
                    value += step;
                else if (key == Key.Home)
                    value = min;
                else if (key == Key.End)
                    value = max;
            }
        }
        value = range >= 0 ? Math.Clamp(value, min, max) : Math.Clamp(value, max, min);
        if (whole)
            value = Math.Round(value);
        if (hot)
            WantCursor = Cursor.Hand;
        double t = range != 0 ? (value - min) / range : 0.0;
        int cy = r.Y + r.Height / 2;
        int trackHeight = Math.Max(2, Px(4));
        var track = Rect.Create(left, cy - trackHeight / 2, width, trackHeight);
        Canvas.FillRoundRect(track, trackHeight / 2, Theme.Border);
        int x = left + (int)Math.Round(t * (double)width);
        Canvas.FillRoundRect(Rect.Create(left, track.Y, x - left, trackHeight), trackHeight / 2, Theme.Accent);
        double radius = (double)thumb;
        Canvas.FillCircle((double)x, (double)cy, radius, Theme.Border);
        Canvas.FillCircle((double)x, (double)cy, radius - (double)Line, Theme.Control);
        Canvas.FillCircle((double)x, (double)cy, radius * (Active == id ? 0.45 : hot ? 0.6 : 0.5), Theme.Accent);
        if (Focus == id)
            FocusRing(Rect.Create(x - thumb, cy - thumb, 2 * thumb, 2 * thumb), thumb);
        return value != old;
    }

    void ProgressBar(double fraction)
    {
        int height = Math.Max(4, Px(6));
        var r = Place(Px(160), ControlHeight, true);
        var track = Rect.Create(r.X, r.Y + (r.Height - height) / 2, r.Width, height);
        Canvas.FillRoundRect(track, height / 2, Theme.Border);
        int filled = (int)Math.Round(Math.Clamp(fraction, 0.0, 1.0) * (double)track.Width);
        if (filled > 0)
            Canvas.FillRoundRect(Rect.Create(track.X, track.Y, filled, height), height / 2, Theme.Accent);
    }

    bool ListItem(string label, bool selected)
    {
        uint32 id = IdOf(label);
        string shown = Shown(label);
        var r = Place(Font.Measure(shown) + 2 * Pad, ControlHeight, true);
        bool hot = Interact(id, r, true);
        bool clicked = Clicked(id, hot) || Activated(id);
        if (selected)
            Canvas.FillRoundRect(r, Radius, Theme.Accent);
        else if (hot)
            Canvas.FillRoundRect(r, Radius, Theme.Selection);
        if (Focus == id)
            FocusRing(r, Radius);
        Canvas.Text(Font, r.X + Pad, TextY(r), shown, selected ? Theme.AccentText : Theme.Text);
        return clicked;
    }

    void ImageWidget(Image image)
    {
        var r = Place(image.Width, image.Height, false);
        Canvas.DrawImage(image, r.X, r.Y);
    }

    void Separator()
    {
        var r = Place(0, Spacing, true);
        Canvas.FillRect(Rect.Create(r.X, r.Y + r.Height / 2, r.Width, Line), Theme.Border);
    }

    void Space(int size)
    {
        int px = Px(size);
        Commit(Top().Kind == 1 ? px : 0, Top().Kind == 1 ? 0 : Math.Max(0, px - Spacing));
    }

    // ---- text boxes ----

    bool Submitted(string name)
    {
        return SubmittedId != 0u && SubmittedId == IdOf(name);
    }

    bool TextBox(string name, ref string text)
    {
        uint32 id = IdOf(name);
        var r = Place(Px(200), ControlHeight, true);
        bool hot = Interact(id, r, true);
        if (hot || Active == id)
            WantCursor = Cursor.Text;
        var inner = Rect.Create(r.X + Px(6), r.Y, Math.Max(0, r.Width - 2 * Px(6)), r.Height);
        int cw = Font.CharWidth();
        string old = text;
        if (Focus == id && EditId != id)
        {
            // the box got the focus: the cursor at the end
            EditId = id;
            Caret = text.Length;
            Anchor = Caret;
            ScrollX = 0;
            BlinkStart = In.Time;
        }
        if (Focus == id)
        {
            Caret = Math.Clamp(Caret, 0, text.Length);
            Anchor = Math.Clamp(Anchor, 0, text.Length);
            if (Active == id && In.MouseDown)
            {
                int column = Math.Max(0, (In.MouseX - inner.X + ScrollX + cw / 2) / Math.Max(1, cw));
                int at = ByteOfChar(text, column);
                Caret = at;
                if (In.MousePressed)
                    Anchor = at;
                BlinkStart = In.Time;
            }
            EditKeys(id, ref text);
        }
        // keep the cursor visible
        if (Focus == id)
        {
            int caretX = _CountChars(text.Substring(0, Caret)) * cw;
            if (caretX - ScrollX > inner.Width - cw)
                ScrollX = caretX - inner.Width + cw;
            if (caretX - ScrollX < 0)
                ScrollX = caretX;
            ScrollX = Math.Max(0, ScrollX);
        }
        int scroll = Focus == id ? ScrollX : 0;
        Canvas.FillRoundRect(r, Radius, Theme.Input);
        Canvas.StrokeRoundRect(r, Radius, Line, Focus == id ? Theme.Focus : hot ? Theme.TextMuted : Theme.Border);
        if (Focus == id)
            Canvas.StrokeRoundRect(r, Radius, Line + Line, Theme.Focus);
        var saved = Canvas.Clip;
        Canvas.SetClip(inner.Intersect(saved));
        int ty = TextY(r);
        if (Focus == id && Caret != Anchor)
        {
            int a = _CountChars(text.Substring(0, Math.Min(Caret, Anchor)));
            int b = _CountChars(text.Substring(0, Math.Max(Caret, Anchor)));
            Canvas.FillRect(Rect.Create(inner.X - scroll + a * cw, ty, (b - a) * cw, Font.LineHeight()), Theme.Selection);
        }
        Canvas.Text(Font, inner.X - scroll, ty, text, Theme.Text);
        if (Focus == id)
        {
            double since = In.Time - BlinkStart;
            double phase = since - Math.Floor(since / 1.06) * 1.06;
            if (phase < 0.53)
            {
                int x = inner.X - scroll + _CountChars(text.Substring(0, Caret)) * cw;
                Canvas.FillRect(Rect.Create(x, ty - Px(1), Line, Font.LineHeight() + Px(2)), Theme.Text);
            }
            int next = (int)((0.53 - (phase < 0.53 ? phase : phase - 0.53)) * 1000.0) + 1;
            WaitMs = WaitMs < 0 ? next : Math.Min(WaitMs, next);
        }
        Canvas.Clip = saved;
        return text != old;
    }

    void EditKeys(uint32 id, ref string text)
    {
        foreach (var key in In.Keys)
        {
            bool select = In.Shift;
            switch (key)
            {
            case Key.Left:
                if (Caret != Anchor && !select)
                    Caret = Math.Min(Caret, Anchor);
                else
                    Caret = PrevChar(text, Caret);
                break;
            case Key.Right:
                if (Caret != Anchor && !select)
                    Caret = Math.Max(Caret, Anchor);
                else
                    Caret = NextChar(text, Caret);
                break;
            case Key.Home:
                Caret = 0;
                break;
            case Key.End:
                Caret = text.Length;
                break;
            case Key.Backspace:
                if (Caret == Anchor)
                    Anchor = PrevChar(text, Caret);
                text = Cut(text);
                select = false;
                break;
            case Key.Delete:
                if (Caret == Anchor)
                    Anchor = NextChar(text, Caret);
                text = Cut(text);
                select = false;
                break;
            case Key.A:
                if (In.Ctrl)
                {
                    Anchor = 0;
                    Caret = text.Length;
                    select = true;
                }
                break;
            case Key.C:
            case Key.X:
                if (In.Ctrl && Caret != Anchor)
                {
                    Clipboard.SetText(text.Substring(Math.Min(Caret, Anchor), Math.Abs(Caret - Anchor)));
                    if (key == Key.X)
                    {
                        text = Cut(text);
                        select = false;
                    }
                    else
                        select = true;
                }
                break;
            case Key.V:
                if (In.Ctrl)
                {
                    text = Insert(text, OneLine(Clipboard.GetText()));
                    select = false;
                }
                break;
            case Key.Enter:
                SubmittedId = id;
                break;
            case Key.Escape:
                Focus = 0u;
                break;
            default:
                continue; // other keys leave the text and the selection alone
            }
            if (!select)
                Anchor = Caret;
            BlinkStart = In.Time;
        }
        if (In.Text.Length > 0 && !In.Ctrl)
        {
            text = Insert(text, OneLine(In.Text));
            Anchor = Caret;
            BlinkStart = In.Time;
        }
    }

    // removes the selection (Caret..Anchor) and puts the cursor there
    string Cut(string text)
    {
        int a = Math.Min(Caret, Anchor);
        int b = Math.Max(Caret, Anchor);
        Caret = a;
        Anchor = a;
        if (a == b)
            return text;
        return text.Substring(0, a) + text.Substring(b);
    }

    // replaces the selection with the inserted text
    string Insert(string text, string inserted)
    {
        string rest = Cut(text);
        string result = rest.Substring(0, Caret) + inserted + rest.Substring(Caret);
        Caret += inserted.Length;
        Anchor = Caret;
        return result;
    }

    // without control characters (a line end becomes a space)
    static string OneLine(string text)
    {
        var sb = StringBuilder.Create();
        for (var i = 0; i < text.Length; i += 1)
        {
            char c = text[i];
            if (c == '\n' || c == '\t')
                sb.Append(' ');
            else if (c >= 32 || (int)c >= 128)
                sb.Append(c);
        }
        return sb.ToString();
    }

    static int PrevChar(StringSlice text, int index)
    {
        int i = Math.Max(0, index - 1);
        while (i > 0 && ((int)text[i] & 0xC0) == 0x80)
            i -= 1;
        return i;
    }

    static int NextChar(StringSlice text, int index)
    {
        int i = Math.Min(text.Length, index + 1);
        while (i < text.Length && ((int)text[i] & 0xC0) == 0x80)
            i += 1;
        return i;
    }
}
