← [Language guide](README.md)

# Projects

A single file compiles on its own (`cshiftc hello.csh -o hello`), but most programs are more than one file. A
`cshift.json` describes a project: its name, source files, output, optimization level, and libraries.

```
cshiftc new hello       # creates hello/cshift.json and hello/src/main.csh
cshiftc run hello        # builds and runs it
cshiftc build             # builds only -> bin/<name>[.exe]
cshiftc publish           # for the browser -> bin/<name>.html (one file with everything)
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

`cshiftc publish` builds the program for the browser (WebAssembly): one HTML file that opens with a double click and
can be put on any web server. The files the program reads at run time are listed in `assets` (`"assets": ["data"]`);
in the browser they are found at the same paths ([WebAssembly](../wasm.md#a-program-for-the-browser-cshiftc-publish)).

`cshiftc build`/`run`/`publish` look for `cshift.json` in the current folder and its parents, so they also work from inside
`src/`. Command-line options (`-O2`, `--target`, `-o`, …) override the file's settings.

## Libraries

Code that several programs share is a library: a project with `"type": "library"`. A program names the folders of
the libraries it uses in `dependencies`:

```json
{
	"name": "game",
	"dependencies": ["../geometry", "libs/sprites"]
}
```

```json
{
	"name": "geometry",
	"type": "library",
	"links": ["m"],
	"platforms": { "windows": { "links": ["libs/windows/fastmath.lib"] } }
}
```

The sources of a library become a part of the program, together with its `links`, `includePaths`, `libraryPaths`,
`defines` and `ffiApi` (with the entries of `platforms` for the platform the program is built for, so a library can
bring prebuilt C libraries for each platform). A library can have dependencies of its own; one that is reached twice
is used once, and a cycle is an error. A library is not compiled into a library file: CShift compiles a whole program
at once (generics are made for the types they are used with), so a library is shared as source code. Give it a
namespace of its own (`namespace Geometry;`) so its names do not collide with those of the programs that use it.
`cshiftc build` of a library checks it (`cshiftc check`); `cshiftc run` needs a program.

For the full list of keys, and where the project format is headed next (a `build.csh` for cases a single JSON file
can't express — conditional sources, code generation, multiple targets), see
[../build.md](../build.md). `demo-minifb/` and `demo-opengl/` are small, complete example projects
using C libraries through FFI.
