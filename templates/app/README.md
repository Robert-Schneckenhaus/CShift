# app

A program in [CShift](https://github.com/Robert-Schneckenhaus/CShift), a native, C#-like systems language.

```
cshiftc run          # build and run
cshiftc build        # bin/app (bin/app.exe on Windows)
```

| | |
|---|---|
| `cshift.json` | the project: its name, sources, output, libraries ([projects](https://robert-schneckenhaus.github.io/CShift/)) |
| `src/main.cshift` | the program, starting at `Main` |
| `.github/workflows/build.yml` | builds and runs it on Linux and Windows with the latest release of CShift |
| `.gitattributes` | GitHub counts CShift as C# in its language statistics (it does not know CShift yet) |

## Getting started

1. Install CShift: download the archive or the standalone compiler for your system from the
   [releases](https://github.com/Robert-Schneckenhaus/CShift/releases) (see its README).
2. Rename the program: `"name"` and `"output"` in `cshift.json`, and the program in the workflow (`bin/app`).
3. `cshiftc run`.

The language: the [documentation](https://robert-schneckenhaus.github.io/CShift/) and the
[playground](https://robert-schneckenhaus.github.io/CShift/v0/playground/) in the browser.
