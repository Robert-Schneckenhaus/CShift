# demo-amiga-ndk

A rotating wireframe cube in an Intuition window, written in CShift against the AmigaOS NDK 3.2. It shows how an
Amiga program uses the operating system:

* the library functions come from the NDK's **SFD files**:
  `using Intui from "intuition_lib.sfd";`, `using Gfx from "graphics_lib.sfd";`, `using Exec from "exec_lib.sfd";`.
  The compiler calls them with their register arguments through the library base, and opens the libraries when the
  program starts;
* the structures, flags and tags come from the NDK's **C headers**: `using I from "intuition/intuition.h";`
  (`I.Window`, `I.WA_Width`, `I.IDCMP_CLOSEWINDOW`, ...);
* the rotation uses [`FastTrig`](../docs/stdlib.md) (sine tables and fixed point, no floating point).

The window is opened with `OpenWindowTags`, so the program needs Kickstart 2.0 (intuition.library 36) or later. The
**close gadget** ends it; the cube is corrected for the pixel aspect of the screen (hires pixels are twice as high as
wide).

```
demo-amiga-ndk/
├── cshift.json        project file ("target": "m68k-amigaos")
├── src/
│   └── main.csh       the window, the projection and the drawing
└── bin/, obj/         the Amiga executable and the imported headers (generated, not in git)
```

## Building

The NDK 3.2 (`NDK3.2.lha` from Hyperion, unpacked) is needed for its SFD files and C headers. Tell the compiler where
it is in one of three ways:

```
cshiftc build demo-amiga-ndk --ndk /path/to/NDK3.2
CSHIFT_NDK=/path/to/NDK3.2 cshiftc build demo-amiga-ndk
"ndk": "../NDK3.2" in cshift.json (relative to the project)
```

The result is `bin/demo-amiga-ndk`. CShift's own 68000 backend builds it; clang is only used (as libclang) to read the
C headers.

## Running

Copy `bin/demo-amiga-ndk` to the Amiga (or a hard disk folder of an emulator) and start it from the Shell:

```
demo-amiga-ndk         runs until the window is closed
demo-amiga-ndk 300     runs for 300 frames
```

SFD import and the NDK are described in [../docs/amiga.md](../docs/amiga.md#amigaos-libraries-from-sfd-files).
