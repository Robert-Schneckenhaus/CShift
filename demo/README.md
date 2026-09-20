# demo

Ein kleines CShift-Projekt zum Ausprobieren der Sprache.

```
demo/
├── cshift.json     Projektdatei (Name, Quellen, Ausgabe, Optimierung, Bibliotheken)
├── src/
│   └── main.csh    Einstiegspunkt: int Main()
└── bin/            Ausgabe (wird erzeugt, nicht im Git)
```

## Bauen und starten

Voraussetzung: `cshiftc` und `clang` sind im `PATH` (siehe [../README.md](../README.md), unter Windows am einfachsten aus der
MSYS2-CLANG64-Shell bzw. mit `C:\msys64\clang64\bin` im `PATH`).

```powershell
cshiftc run          # bauen und starten
cshiftc build        # nur bauen  ->  bin/demo.exe
```

Die Befehle suchen `cshift.json` im aktuellen Ordner und darüber; sie laufen also auch aus `src/`. Von außen geht
`cshiftc run demo`.

In VS Code (mit der CShift-Extension): **Strg+Umschalt+B** baut, *Tasks: Run Task → cshiftc: run* startet das Programm.
Compilerfehler erscheinen im Problems-Panel.

## Weiterentwickeln

* Neue `.csh`-Dateien in `src/` (auch in Unterordnern) gehören automatisch zum Programm. Alle Dateien werden zusammen übersetzt,
  Typen und Funktionen sind ohne `using`/Header überall sichtbar. Mit `namespace MeinNamespace;` in der ersten Zeile und
  `using MeinNamespace;` in anderen Dateien lässt sich ordnen.
* Die Standardbibliothek (`List<T>`, `Dictionary<K,V>`, `File`, `Math`, String-Helfer, …) ist immer verfügbar; für `System`
  Typen `using System;` an den Dateianfang.
* Bibliotheken für den Linker in `"links": ["sqlite3"]` eintragen oder im Quelltext `link "sqlite3"` schreiben.

Das Format der Projektdatei ist in [../Buildkonzept.md](../Buildkonzept.md) beschrieben.
