# demo-ui

A small to-do list with [System.Ui](../docs/ui.md): a menu bar, a text box and a button to add tasks, a combo box for
their priority and a number box for the days until they are due, radio buttons to filter them, a scrolling list of
check boxes and list items with a context menu (the right mouse button), a modal dialog before the done tasks are
removed, tooltips, a panel with a theme switch, a zoom slider (and Ctrl+Plus, Ctrl+Minus) and wrapped text. The
program's state is the struct `App`; `Draw` describes the window for it in every frame and changes it where the user
did something - there are no widget objects or callbacks.

```
cshiftc run demo-ui
```

Nothing has to be installed: the Ui draws with its own software renderer, and the window comes from the operating
system (Win32 on Windows, X11 on Linux).

`demo-ui --frames N` draws N frames and closes the window (for screenshots).
