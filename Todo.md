# Todo

## 1. CShift-Compiler in CShift selbst bauen (Ordner `selfhost/`)

Auftrag: Neuer Ordner, in dem der Compiler mit CShift gebaut wird. Fehlende Komponenten (Collections, Stringoperationen, …)
vorher der Stdlib hinzufügen. Projekt sinnvoll strukturieren (Namespaces). Wenn es zu schwierig ist oder wichtige Sprachfeatures
fehlen: Bescheid sagen, dann gemeinsam entscheiden.

**Stand:** siehe [selfhost/README.md](selfhost/README.md) (Aufbau, Entwurfsentscheidungen, Prüfstrategie).

Erledigt:
- [x] Stdlib/Sprache ergänzt, was der Compiler braucht: `Main(string[] args)`, `string.FromCStr`, `Console.WriteError(Line)`,
      `Char.*`, `StringBuilder`, `HashSet<T>`, `Process.Run`; FFI: `ffiApi` (Umbrella-Header), `char*` für `const char*`-Parameter.
- [x] **Frontend:** Lexer, Syntaxbaum (Arenen) und Parser in CShift (`selfhost/src/Syntax/`). Tokens und Syntaxbaum sind für alle 110 `.csh`-Dateien
      des Repos (inkl. Syntaxfehler-Tests und der eigenen Quellen) identisch zum C++-Compiler (`selfhost/compare.sh`, Teil von `tests/run_tests.sh`).
- [x] **Entwurf des Backends:** `cshc` schreibt LLVM-IR als **Text** und ruft clang auf (kein LLVM im Compiler, siehe selfhost/README.md und
      selfhost/DEPENDENCIES.md). Die LLVM-C-API per FFI wäre möglich gewesen (Spike lief), ist aber schwerer.
- [x] **Codegenerator:** `selfhost/src/Sema` (Typtabelle), `Emit` (IR-Schreiber), `CodeGen` (Compiler-Zustand, Typauflösung, Funktionsinstanzen,
      Werte und Referenzzählung, Ausdrücke, Aufrufe/Überladungen, Anweisungen, Structs, Arrays, `Error<T>`/`Optional<T>`, `switch`, Enums,
      Generics und Interfaces mit Constraints, `using`/`IDisposable`, Zeiger/`unsafe`, Funktionszeiger, Laufzeit als IR-Text) und `Main.csh` als Treiber
      (`cshc [--stdlib dir] datei.csh -o prog`). Die Standardbibliothek (`stdlib/*.csh`) wird als Prelude geladen.
      **alle 80 Fälle aus `tests/cases` bestehen mit `cshc`** ( `--arc-stats` prüft `live=0`), außerdem `tests/test.csh`
      (Ausgabe identisch zu `test.expected`). `selfhost/passing.txt` + `status.sh --check` schützen vor Rückschritten.
- [x] **Bootstrap:** `cshc` übersetzt seine eigenen Quellen (`selfhost/bootstrap.sh`): Stufe 1 (mit dem C++-Compiler gebaut) und Stufe 2 (von `cshc`
      gebaut) erzeugen für die Quellen von `cshc` **identisches LLVM-IR** (Fixpunkt), Stufe 2 besteht dieselben Testfälle. Teil von `tests/run_tests.sh`.

Offen (`bash selfhost/status.sh selfhost/bin/cshc -v` zeigt, was noch fehlt; die Meldung `cshc does not support …` nennt das Feature):
- [x] **Treiber / Projekte** (fertig bis auf FFI): `cshc [Optionen] Dateien`, `cshc new|build|run` mit `cshift.json`, `-c`, `--target`, `-l/-L/-I/-D`, Bibliotheken als Eingaben;
      Stdlib um `Directory`, `Path`, `Process.RunCapture/GetEnv` ergänzt; JSON-Parser in CShift; die Stdlib ist in `cshc` eingebettet
      (`selfhost/src/Driver/EmbeddedStdlib.csh`, erzeugt mit `cshc --gen-stdlib stdlib <datei>`; `run_tests.sh` prüft, dass sie aktuell ist).
      `tests/projects` bauen mit `cshc` (`selfhost/projects.sh`).
- [ ] clang finden wie `cshiftc`: das mitgelieferte `toolchain/` neben `cshc` (dafür fehlt der Pfad der eigenen Exe; bisher `--cc`, `CSHIFT_CC`, PATH, MSYS2-Ordner).
- [x] **FFI (Lesen)**: `using X from "h.h"` und `from "x.ffi"` mit `cshc`: `.ffi` laden (`Driver/Ffi.csh`), C-Structs mit explizitem Layout (`CodeGen/Layout.csh`), Marshalling
      (`cstring`, `nullable`, `retCString`, `retOut`), ABI-Attribute für kleine Ganzzahlen, Shims mit clang übersetzen und linken. `tests/projects` (8 von 8) und `demo/` bauen mit `cshc`.
- [ ] **FFI (Erzeugen)**: die `.ffi`-Datei aus einem Header erzeugt bisher der C++-Compiler als Hilfsprogramm (`cshiftc --ffi-prepare`, gefunden über
      `--ffi-tool`, `CSHIFT_FFI_TOOL` oder PATH). Für einen C++-freien `cshc` müsste `FfiGenerator.cpp` (1600 Zeilen, libclang) nach CShift portiert werden
      (libclang per FFI aus CShift ansprechen) oder die `.ffi`-Dateien werden mitgeliefert.
- [ ] Wenn `cshc` `cshiftc` vollständig ersetzen kann: Release-Workflow und Doku umstellen (C++ nur noch als Stufe 0).

## 2. Testen, ob der neue Compiler alles bauen kann

- [x] `tests/cases/` (80 von 80), `tests/test.csh` (Ausgabe identisch, keine Leaks) und der Bootstrap laufen mit `cshc` (`tests/run_tests.sh`, Abschnitt selfhost;
      `selfhost/bootstrap.sh`: Stufe 1 = mit `cshiftc` gebaut, Stufe 2 = von `cshc` gebaut, gleiches IR für die Quellen von `cshc`).
- [x] `tests/projects/` (8 von 8, `selfhost/projects.sh`) und `demo/` bauen mit `cshc` (Header-Import über das C++-Hilfsprogramm, siehe Abschnitt 1).

## 3. Abhängigkeiten des neuen Compilers (Analyse)

- [x] Analyse steht in [selfhost/DEPENDENCIES.md](selfhost/DEPENDENCIES.md). Kurz: `cshc` braucht durch den IR-Text-Weg selbst kein LLVM mehr
      (nur clang zum Übersetzen/Linken); C++/CMake entfallen zum Bauen (Seed für Stage 0 nötig); clang als Linker-Treiber lässt sich unter
      Windows durch lld ersetzen; der C-Compiler für die FFI-Struct-Wrapper durch eigene ABI-Umsetzung; libclang bleibt optional
      (`.ffi` mitliefern); die C-Bibliothek bleibt.
- [ ] Umsetzung (nur auf Wunsch): lld statt clang unter Windows; eigene ABI-Umsetzung für Structs *by value* statt der C-Wrapper.

## Weitere offene Punkte (aus früheren Sitzungen)

- [ ] Release-Workflow (`.github/workflows/release.yml`) auf Linux noch nicht vollständig durchgelaufen (Build und Tests liefen,
      "Assemble" und "Test the assembled folder" zuletzt offen). In der Linux-Job-Umgebung ist `CSHIFT_SKIP_SELFHOST=1` gesetzt:
      nach dem ersten grünen Lauf entfernen, damit die selfhost-Prüfungen auch dort gelten (sie brauchen `clang` im `PATH`).
- [ ] `demo/`: `libminifb.a` wird nicht eingecheckt (`demo/build-minifb.ps1` baut sie); Callbacks funktionieren, Lambdas gibt es nicht.
- [ ] Sprache: Lambdas/Closures, globale Variablen, Interfaces als Werttyp, `List<T>`-Indexer sind weiter offen (siehe README, "Bekannte Einschränkungen").
