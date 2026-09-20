# CShift

CShift ist eine native, C#-artige Systemsprache (siehe [Sprachkonzept.md](Sprachkonzept.md)):
Structs statt Klassen, kein GC (ARC), keine Header, Generics per Monomorphisierung, direkte C-FFI.

Dieses Verzeichnis enthält den ersten Compiler `cshiftc`, geschrieben in C++17 mit LLVM als Backend.

```
Quelltext (.csh) ─▶ Lexer ─▶ Parser ─▶ AST ─▶ Typprüfung + Codegen ─▶ LLVM IR ─▶ Optimierung ─▶ .obj ─▶ clang (Linker) ─▶ .exe
```

```csharp
using System;

struct Vec2
{
    float X;
    float Y;

    float Length() { return sqrt(X * X + Y * Y); }
}

Error<int> Parse(string text) { /* ... */ }

int Main()
{
    var v = Vec2 { X = 3, Y = 4 };
    Console.WriteLine(v.Length());   // 5
    return 0;
}
```

## Bauen

Voraussetzung: C++17-Compiler, CMake ≥ 3.20, **LLVM-Entwicklungspakete** (Header + Bibliotheken; getestet mit
LLVM 22.1.8) und `clang` zum Linken der erzeugten Programme.

### Windows (empfohlen: MSYS2)

Visual Studio bringt keine LLVM-Bibliotheken zum Programmieren gegen die LLVM-API mit, MSYS2 schon:

```powershell
winget install MSYS2.MSYS2
# In der "MSYS2 CLANG64"-Shell einmalig:
pacman -S --needed mingw-w64-clang-x86_64-clang mingw-w64-clang-x86_64-llvm `
                   mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja

.\build.ps1          # baut nach .\build\cshiftc.exe
.\build.ps1 -Test    # baut und führt die Tests aus
```

`cshiftc.exe` braucht zur Laufzeit die DLLs und `clang` aus `C:\msys64\clang64\bin`. Am einfachsten
verwendet man ihn aus der CLANG64-Shell oder nimmt den Ordner in den `PATH` auf.

### Linux / macOS

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # ggf. -DLLVM_DIR=<llvm>/lib/cmake/llvm
cmake --build build
tests/run_tests.sh
```

## Benutzung

```
cshiftc [Optionen] datei.csh [weitere.csh ...]

  -o <datei>         Ausgabedatei
  -c                 nur Objektdatei erzeugen (kein Linken)
  --emit-llvm        LLVM IR (.ll) statt Programm ausgeben
  -O0 .. -O3         Optimierungsstufe (Standard -O2)
  --target <triple>  Zielplattform (Standard: Host)
  --cc <programm>    Linker-Treiber (Standard: clang)
  -l<name>           zusätzliche Bibliothek linken
  --run              Programm nach dem Bauen ausführen
  --arc-stats        Debug: Anzahl Heap-Allokationen/-Freigaben beim Programmende ausgeben
```

Alle übergebenen Dateien bilden ein Programm; Typen und Funktionen können in beliebiger Reihenfolge und
Datei definiert werden (keine Forward Declarations nötig).

```
cshiftc tests/test.csh tests/mathlib.csh -o test.exe --run
```

Fehler werden im Format `datei:zeile:spalte: error: text` ausgegeben.

## Sprachstand

Umgesetzt aus dem Konzept:

| Bereich | Stand |
|---|---|
| Namespaces (`namespace A.B;`), `using`, mehrere Dateien, globale Symbolauflösung | ✔ |
| Structs (Wertsemantik), Initializer, `new T()`, Methoden, `static`-Methoden, verschachtelte Structs | ✔ |
| Sichtbarkeit über `_`-Präfix (privat) für Felder und Methoden | ✔ |
| Struct-Vererbung (eine Basis, Basis liegt im Layout zuerst), Upcast, Methoden verdecken | ✔ |
| Interfaces (Methoden), mehrere pro Struct, Prüfung der Implementierung | ✔ (nur statisch, s. u.) |
| Generics: Structs und Funktionen, Monomorphisierung, Typinferenz, explizite Typargumente | ✔ |
| Constraints (`where T : IComparable<T>`), zur Compile-Zeit geprüft | ✔ |
| Enums mit Pflicht-Basistyp und expliziten Werten | ✔ |
| ARC für Strings und Arrays (Referenzsemantik, `Clone()`), auch in Structs/`Error`/`Optional` | ✔ |
| Strings: UTF-8, unveränderlich, `+`, `==`, `[i]`, `Length`, `Substring`, `CStr()` | ✔ |
| `Error<T>` / `Optional<T>`, Bool-Semantik, `is T x`, `switch`-Pattern, `try`, Verschachtelungsverbot | ✔ |
| `IDisposable` + `using` (Deklaration und Block; auch bei `return`/`break`/`continue`/`try`) | ✔ |
| `ref` / `const ref` (Wert, schreibgeschützter Alias, Alias) | ✔ |
| Primitive Typen mit Aliasen (`int`=`int32`, …), `bool`, `char` (= `uint8`) | ✔ |
| Geprüfte Integer-Arithmetik (Überlauf, Division durch 0, Array-/String-Grenzen → Panic), `unchecked` | ✔ |
| Operatoren und Rangfolge wie C# (ohne `++`/`--`), `?:`, Casts, `sizeof` | ✔ |
| `if`/`while`/`do`/`for`/`foreach` (Arrays, Strings)/`switch`/`break`/`continue`/`return` | ✔ |
| Funktionsüberladung | ✔ |
| C-FFI: `extern "C"`, variadische Funktionen (`printf`), `link "lib"`, Pointer | ✔ |
| `unsafe`: Pointer, `&`, `*`, Pointer-Arithmetik, `Memory.Allocate/Free` | ✔ |
| Einstiegspunkt: `int Main()`, `void Main()`, `Error<int> Main()` | ✔ |

### Auslegung und Erweiterungen gegenüber dem Konzept

Das Konzept lässt einiges offen; folgende Entscheidungen wurden getroffen:

* **Fehler erzeugen:** `return error("Text");` oder `error("Text", code)`; `Error<T>` hat `.Message` und `.Code`.
* **Implizite Konvertierung** `T → Error<T>` / `T → Optional<T>`; `null` steht für "kein Wert" (`Optional`).
* **Bool-Semantik** von `Error`/`Optional` gilt in Bedingungen sowie bei `!`, `&&`, `||`; nicht als Argument für einen `bool`-Parameter (`x is T` verwenden).
* **`is`/`case`-Pattern:** `x is int v` bindet den Wert; `x is Error<int> r` bindet das ganze Ergebnis. Pattern-Variablen gelten für das `if`/`while` bzw. den `case`.
* **`try` in `int Main()`:** Im Zielbild des Konzepts wird `try` in einer `int`-Funktion benutzt. Dort gibt ein Fehler
  `error: <Text>` auf stderr aus und beendet das Programm mit Code 1.
* **Ganzzahl-Arithmetik** wie in C#: Typen unter 32 Bit werden zu `int` erweitert; ein Literal passt sich dem anderen Operanden an
  (`uint8 x = 200; int y = x * 3;` ergibt 600). Explizite Casts brechen nicht ab (wrap/sättigend), nur `+ - * / %` sind geprüft.
* **Interfaces** sind vorerst nur als Constraint und in Basislisten nutzbar, nicht als Variablen-/Parametertyp
  (das bräuchte Fat-Pointer für dynamischen Aufruf ohne Boxing).
* **Methoden auf `const ref`-Objekten** arbeiten auf einer Kopie (wie C# `in`), damit der Schreibschutz gilt.
* **Standardumfang** (ohne Runtime-Bibliothek, alles wird als IR in das Programm eingebettet):
  `Console.Write/WriteLine`, `Memory.Allocate/Free`, `ToString()`/`CompareTo()` auf Zahlen, `int.MaxValue/MinValue`,
  `IDisposable`, `IComparable<T>`, `sqrt`. Weiteres über `extern "C"`.
* Erlaubte Zusatzsyntax: `cond ? a : b`, `new int[3][]` (Jagged Arrays), `new T[] { ... }`, `sizeof(T)`.

## Aufbau des Compilers

| Datei | Inhalt |
|---|---|
| `compiler/src/Lexer.*` | Tokenizer (UTF-8, Escapes, Zahlenliterale) |
| `compiler/src/Parser.*`, `AST.h` | Rekursiver Abstieg mit Backtracking für Generics, Casts, Deklarationen |
| `compiler/src/Types.*` | Internierte Typen (Pointergleichheit = Typgleichheit) |
| `compiler/src/CodeGen.*` | Symboltabellen, Typauflösung, Struct-Layout, Generics-Instanziierung, Constraints |
| `compiler/src/CodeGenExpr.cpp` | Ausdrücke, Konvertierungen, Arithmetik mit Überlaufprüfung, `is`/`try` |
| `compiler/src/CodeGenCall.cpp` | Überladungsauflösung, Typinferenz, Aufrufe, eingebaute Funktionen |
| `compiler/src/CodeGenStmt.cpp` | Anweisungen, Scopes, Cleanup (ARC, `using`), Funktionskörper |
| `compiler/src/CodeGenRuntime.cpp` | ARC-Helfer, Strings, Panic – direkt als LLVM-IR erzeugt |
| `compiler/src/Prelude.h` | In CShift geschriebene Standarddeklarationen (`IDisposable`, …) |
| `compiler/src/main.cpp` | Driver: Optimierung, Objektdatei, Linken |

Es gibt keine getrennte Typprüfungs-Phase: Typprüfung und Codegeneration laufen in einem Durchgang über den AST. Das
macht die Monomorphisierung einfach (der Körper einer generischen Funktion wird pro Typkombination erneut durchlaufen).

**Referenzzählung:** Variablen, Felder und Array-Elemente besitzen eine Referenz; Zwischenergebnisse tragen ein "+1", das beim
Speichern übernommen oder am Ende des Statements freigegeben wird. Argumente werden geborgt übergeben, die aufgerufene Funktion
behält ihre Parameter selbst. Heap-Blöcke (Strings/Arrays) haben den Kopf `{int64 refcount, int64 length}`.
Mit `--arc-stats` lässt sich prüfen, dass jede Allokation wieder freigegeben wurde.

## Tests

```
tests/run_tests.sh [pfad/zu/cshiftc] [-O0..-O3]      # bzw. .\build.ps1 -Test
```

* `tests/test.csh` (+ `tests/mathlib.csh`): großes Testprogramm mit ~160 Prüfungen über alle Sprachbereiche. Ausgabe wird gegen
  `tests/test.expected` verglichen, zusätzlich muss die ARC-Bilanz aufgehen.
* `tests/cases/*.csh`: kleine Programme mit Erwartungen in Kommentaren – Compilerfehler (`err_*`), Laufzeit-Panics (`panic_*`),
  Programmverhalten (`main_*`), ARC-Stresstest, Sonderfälle (`misc_features`).

## Bekannte Einschränkungen / nächste Schritte

* Keine Standardbibliothek jenseits des Minimums (kein `File`, keine Container – `List<T>` lässt sich aber bereits in CShift
  schreiben, siehe `tests/cases/misc_features.csh`).
* Interfaces als Werttyp (dynamischer Aufruf), Funktionszeiger/Callbacks für die FFI, `Error<void>`, Lambdas, globale Variablen/Konstanten,
  `Main(string[] args)`, Struct-Übergabe *by value* an C-Funktionen (ABI-Coercion) fehlen noch.
* Referenzzähler sind nicht atomar (kein Multithreading).
* Generische Körper werden erst bei der Instanziierung geprüft (wie C++-Templates); unbenutzte generische Funktionen werden nicht analysiert.
* Keine Debug-Informationen (DWARF/PDB).
* Fehlermeldungen: Nach Syntaxfehlern wird die semantische Analyse nicht mehr ausgeführt.
