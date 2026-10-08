# demo-snake

Snake in CShift: a tiny software renderer draws the game into a 160 x 120 picture, which OpenGL 1.1 shows scaled up
(`glDrawPixels` with `glPixelZoom`), in a window of [GLFW](https://www.glfw.org). GLFW and OpenGL are declared by hand
(`extern "C"`), so no C headers are needed. **Arrow keys** or **WASD** steer, **Space** starts again after a crash,
**Esc** quits.

The same program runs on the desktop and in the browser:

```
cshiftc run demo-snake                                     # Linux: sudo apt install libglfw3-dev
cshiftc build demo-snake --backend wasm -o program.wasm    # WebAssembly: with web/cshift.js and web/index.html
```

In the browser (see [docs/wasm.md](../docs/wasm.md#games-in-the-browser)) the game loop stays a plain loop: the program
is suspended in `glfwPollEvents` until the browser shows the next frame. On Windows, `get-glfw.ps1` of
[demo-opengl](../demo-opengl) downloads the GLFW library (`../demo-opengl/lib`).
