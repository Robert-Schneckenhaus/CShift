← [Language guide](README.md)

# Projects

A single file compiles on its own (`cshiftc hello.csh -o hello`), but most programs are more than one file. A
`cshift.json` describes a project: its name, source files, output, optimization level, and libraries.

```
cshiftc new hello       # creates hello/cshift.json and hello/src/main.csh
cshiftc run hello        # builds and runs it
cshiftc build             # builds only -> bin/<name>[.exe]
```

```json
{
	"name": "demo",
	"sources": ["src"],
	"output": "bin/demo",
	"optimize": 2,
	"links": []
}
```

`sources` lists files and folders (folders are searched recursively for `.csh` files); every file in the project is
compiled together as one program, so types and functions are visible everywhere without any `using`/header. `links`
pulls in libraries, and `includePaths`/`defines`/`libraryPaths`/`ffiApi` configure [C header imports](ffi-and-interop.md).

`cshiftc build`/`run` look for `cshift.json` in the current folder and its parents, so they also work from inside
`src/`. Command-line options (`-O2`, `--target`, `-o`, …) override the file's settings.

For the full list of keys, and where the project format is headed next (a `build.csh` for cases a single JSON file
can't express — conditional sources, code generation, multiple targets), see
[../../BuildDesign.md](../../BuildDesign.md). `demo/` is a small, complete example project using a C library through
FFI.
