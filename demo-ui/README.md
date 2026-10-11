# demo-ui

A small to-do list with [System.Ui](../docs/ui.md): a text box and a button to add tasks, radio buttons to filter them,
a scrolling list of check boxes and list items, a panel with a theme switch, a zoom slider and wrapped text. The
program's state is the struct `App`; `Draw` describes the window for it in every frame and changes it where the user
did something - there are no widget objects or callbacks.

```
cshiftc run demo-ui
```

Nothing has to be installed: the Ui draws with its own software renderer, and the window comes from the operating
system (Win32 on Windows, X11 on Linux).

`demo-ui --frames N` draws N frames and closes the window (for screenshots).
