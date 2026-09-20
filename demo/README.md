# demo

Ein kleines CShift-Projekt zum Ausprobieren der Sprache: ein Fenster mit animiertem Plasma, gezeichnet über die C-Bibliothek
[MiniFB](https://github.com/emoon/minifb). Es zeigt den C-Header-Import (`using Mfb from "MiniFB.h";`) und Callbacks
(`Action<…>`/`Func<…>`): MiniFB ruft `OnKey` und `OnClose` in `src/main.csh` auf. Mit **Esc** wird das Fenster geschlossen.

```
demo/
├── cshift.json        Projektdatei (Quellen, Header-Pfad, Bibliotheken)
├── src/
│   └── main.csh       Einstiegspunkt: int Main()
├── include/           MiniFB-Header (MIT-Lizenz: include/LICENSE-MiniFB)
├── build-minifb.ps1   baut libminifb.a
├── libminifb.a        (wird von build-minifb.ps1 erzeugt, nicht im Git)
└── bin/, obj/         Ausgabe und FFI-Zwischenstand (werden erzeugt, nicht im Git)
```

## Bauen und starten

Voraussetzung: `cshiftc` und `clang` sind im `PATH` (siehe [../README.md](../README.md), unter Windows am einfachsten aus der
MSYS2-CLANG64-Shell bzw. mit `C:\msys64\clang64\bin` im `PATH`).

Einmalig die Bibliothek bauen (braucht zusätzlich `cmake`, `ninja` und `llvm-ar` aus MSYS2 CLANG64 und einen MiniFB-Checkout):

```powershell
.\build-minifb.ps1 -Source C:\pfad\zu\minifb
```

Dann:

```powershell
cshiftc run          # bauen und starten
cshiftc build        # nur bauen  ->  bin/demo.exe
```

Die Befehle suchen `cshift.json` im aktuellen Ordner und darüber; sie laufen also auch aus `src/`. Von außen geht
`cshiftc run demo`.

In VS Code (mit der CShift-Extension): **Strg+Umschalt+B** baut, *Tasks: Run Task → cshiftc: run* startet das Programm.
Compilerfehler erscheinen im Problems-Panel.

Die Bibliothek muss mit clang gebaut sein (COFF-Objekte). Eine mit tcc gebaute `libminifb.a` enthält ELF-Objekte und lässt sich
nicht linken (`unknown file type`).

## Wie der Header eingebunden wird

* `"includePaths": ["include"]` sagt dem Compiler, wo `MiniFB.h` liegt. Beim ersten Bauen parst er den Header mit libclang und legt
  `obj/ffi/Mfb.ffi` an; danach wird nur noch neu geparst, wenn sich der Header ändert.
* `"links"` enthält die Bibliothek (`libminifb.a`, eine Datei) und die Windows-Bibliotheken (`gdi32`, `opengl32`, `user32`, `winmm`).
* Alles aus dem Header steht im Namensraum `Mfb`: `Mfb.mfb_open_ex(...)`, `Mfb.mfb_window*`, `Mfb.MFB_WF_RESIZABLE`, ….
  Details: [../FFI.md](../FFI.md).

## Weiterentwickeln

* Neue `.csh`-Dateien in `src/` (auch in Unterordnern) gehören automatisch zum Programm. Alle Dateien werden zusammen übersetzt,
  Typen und Funktionen sind ohne `using`/Header überall sichtbar. Mit `namespace MeinNamespace;` in der ersten Zeile und
  `using MeinNamespace;` in anderen Dateien lässt sich ordnen.
* Die Standardbibliothek (`List<T>`, `Dictionary<K,V>`, `File`, `Math`, String-Helfer, …) ist immer verfügbar.
* Weitere Callbacks (`mfb_set_mouse_move_callback`, `mfb_set_resize_callback`, …) sind Funktionen mit dem passenden `Action<…>`-Typ.

Das Format der Projektdatei ist in [../Buildkonzept.md](../Buildkonzept.md) beschrieben.
