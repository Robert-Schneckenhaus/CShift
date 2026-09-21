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
- [x] **Codegenerator, Kern:** `selfhost/src/Sema` (Typtabelle), `Emit` (IR-Schreiber), `CodeGen` (Compiler-Zustand, Deklarationen, Typauflösung,
      Funktionsinstanzen, Werte und Referenzzählung, Konvertierungen, Ausdrücke, Aufrufe/Überladungen, Anweisungen, Laufzeit als IR-Text,
      Einstiegspunkt) und `Main.csh` als Treiber (`cshc datei.csh -o prog`). Getestet: Hello World, Arithmetik mit Überlaufprüfung,
      Kontrollfluss, Strings mit ARC, Konstanten, `extern "C"`, `?:`, Panics. **28 von 80 Fällen aus `tests/cases` bestehen mit `cshc`**
      (`selfhost/passing.txt`; `status.sh --check` in `tests/run_tests.sh` schützt vor Rückschritten).

Offen (Reihenfolge nach Nutzen; C++-Vorlage in Klammern; `bash selfhost/status.sh selfhost/bin/cshc -v` zeigt, was noch fehlt,
die Meldung `cshc does not support …` nennt das fehlende Feature):
- [ ] **Structs:** Layout (`layoutStruct`), Felder, Methoden, `this`, Initialisierer, `new T()`, Vererbung, Interfaces, Constraints,
      `verifyStruct` (`CodeGen.cpp`, `CodeGenExpr/Call.cpp`); Struct-Typen brauchen `LlvmType` (`%struct.Name`) und Größen (`sizeof` über
      `getelementptr null`-Trick im IR)
- [ ] **Arrays und String-Methoden:** `new T[]`, Indexer mit Grenzenprüfung, `Length`, `Clone`, `Substring`, `CStr`, `foreach`,
      `Array.Copy`, Per-Typ-Retain/Release (`retainFor`/`releaseFor`) für Arrays und Structs mit ARC-Feldern
- [ ] **`Error<T>`/`Optional<T>`:** `try`, `is`-Pattern, `switch`-Pattern, `error(...)`, `using`/`IDisposable`, `Main` mit `Error<int>`
- [ ] **Enums, Generics** (Instanziierung, `unify`/`inferTypeArgs`), **Funktionszeiger**, `nint`, Zeiger/`unsafe`, `sizeof`, `default(T)`
- [ ] **Standardbibliothek laden:** `stdlib/*.csh` neben `cshc` suchen oder einbetten (CShift hat kein `#embed`; z. B. beim Bauen eine
      generierte `.csh`-Datei mit den Texten), Prelude-Funktionen nur bei Bedarf übersetzen (`isPrelude`), `Main(string[] args)`, `--arc-stats`
- [ ] **Treiber:** Optionen wie `cshiftc` (`-c`, `--target`, `-l`, `-L`, `-I`), Projektdatei `cshift.json` (JSON-Parser in CShift), clang unter
      `toolchain/` neben `cshc` finden, `--emit-llvm`-Ausgabe angleichen; das Betriebssystem/Target statt `Process.IsWindows()` bestimmen
- [ ] **FFI:** `.ffi` lesen und Deklarationen erzeugen; Header über libclang (Funktionszeiger dafür nutzbar); Struct-Wrapper
- [ ] Wenn der Codegenerator größer wird: sinnvolle Aufteilung in `Sema/` (Typen, Symbole), `CodeGen/`, `Driver/`, `Ffi/`

## 2. Testen, ob der neue Compiler alles bauen kann

- [ ] Noch nicht möglich (der Codegenerator ist erst ein Teil). Vorgehen, sobald er vollständig ist:
      1. `tests/run_tests.sh` mit `cshc` statt `cshiftc` laufen lassen (`CSHIFTC=selfhost/bin/cshc`); `tests/test.csh`,
         `tests/cases/`, `tests/projects/` (dafür braucht `cshc` die Optionen des Treibers).
      2. Bootstrap: `cshiftc` baut `cshc` (Stufe 1), Stufe 1 baut `cshc` (Stufe 2), Stufe 2 noch einmal (Stufe 3);
         Stufe 2 und 3 müssen gleich sein.
      3. `demo/` und die FFI-Tests mit `cshc` bauen.

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
