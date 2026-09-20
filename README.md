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

## VS Code

Im Ordner `vscode-extension/` liegt eine Extension für `.csh`-Dateien (Syntax-Highlighting, Snippets, Klammern/Kommentare) – Installation siehe
[vscode-extension/README.md](vscode-extension/README.md).

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
| `Error<void>` (Ergebnis ohne Wert; `return;` oder Funktionsende = Erfolg) | ✔ (Erweiterung) |
| Top-Level-`const`, `default(T)`, `foreach` über Structs mit `Count()`/`Get(int)` | ✔ (Erweiterung) |
| Standardbibliothek: `List<T>`, `Dictionary<K,V>`, `File`, `Encoding`, `Math`, String-Helfer | ✔ (siehe unten) |

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
* **Eingebaut** (direkt vom Compiler als IR erzeugt, keine Runtime-Bibliothek): `Console.Write/WriteLine`, `Memory.Allocate/Free`,
  `Environment.Exit/Panic`, `Array.Copy`, `string.FromBytes`, `ToString()`/`CompareTo()`/`Equals()`/`GetHashCode()` auf Zahlen,
  `int.MaxValue/MinValue`. Alles Weitere steht in der Standardbibliothek (nächster Abschnitt) oder kommt über `extern "C"`.
* **`Error<void>`:** `Error<void> Save() { ... return; }`. `try Save();` prüft nur auf Fehler; `Optional<void>` gibt es nicht.
* **Konstanten:** `const double PI = 3.14;` auf oberster Ebene (Zahl, `bool`, `char`, `string`; Initialisierer aus Literalen,
  Operatoren und anderen Konstanten). Zugriff auch qualifiziert (`Math.PI`).
* **`foreach` über Structs:** funktioniert für jeden Struct mit `int Count()` und `T Get(int index)` (z. B. `List<T>`).
* **Namensauflösung** wie in C#: Namespaces der eigenen Datei und der globale Namespace gehen `using`-Namespaces vor.
* Erlaubte Zusatzsyntax: `cond ? a : b`, `new int[3][]` (Jagged Arrays), `new T[] { ... }`, `sizeof(T)`.

## Standardbibliothek

Die Standardbibliothek ist in CShift selbst geschrieben (`stdlib/*.csh`) und im Compiler eingebettet. Nur was ein Programm
tatsächlich benutzt, wird übersetzt (Generics werden pro Typ instanziiert). Beispiele stehen in `tests/cases/stdlib_*.csh`.

| Namespace | Datei | Inhalt |
|---|---|---|
| global | `core.csh` | `IDisposable`, `IComparable<T>`, `IEquatable<T>`, `IHashable`, `sqrt` |
| `System` | `list.csh`, `dictionary.csh`, `file.csh`, `encoding.csh` | `List<T>`, `Dictionary<K,V>`, `KeyValuePair<K,V>`, `File`, `Encoding` (`using System;`) |
| `Math` | `math.csh` | mathematische Funktionen und Konstanten (ohne `using`: `Math.Sqrt(2)`) |
| `String` | `string.csh` | String-Helfer, werden als Methoden auf `string` sichtbar |
| `System.Native` | `native.csh` | C-Importe (`fopen`, `sin`, …), auch für eigene Programme (`using System.Native;`) |

**`List<T>`** – wachsendes Array. Erzeugen mit `List<int>.Create()` (oder `new List<int>()`).
`Add`, `AddRange(T[])`, `Insert(i, v)`, `RemoveAt(i)`, `Remove(v)`, `Clear()`, `Get(i)`, `Set(i, v)`, `Count()`, `Capacity()`,
`IndexOf(v)`, `Contains(v)` (T: `IEquatable<T>`), `Sort()` (T: `IComparable<T>`, stabil), `Reverse()`, `ToArray()`;
`foreach (var x in list)` funktioniert. Ein ungültiger Index beendet das Programm mit einem Panic.

**`Dictionary<TKey, TValue>`** – Hashtabelle. `Create()`, `Set(k, v)`, `Add(k, v)` (`Error<void>`, Fehler bei doppeltem Schlüssel),
`TryGet(k)` (`Optional<TValue>`), `GetOrDefault(k, fallback)`, `ContainsKey(k)`, `Remove(k)`, `Clear()`, `Count()`,
`Keys()`, `Values()`, `Entries()` (`KeyValuePair<K,V>[]`). Schlüssel müssen `IEquatable` und `IHashable` erfüllen: Zahlen, `bool`,
`char`, Enums und `string` tun das eingebaut, eigene Structs definieren `bool Equals(T other)` und `int GetHashCode()`.

> Da es keine Klassen gibt, sind `List` und `Dictionary` kleine Structs, die auf gemeinsamen Speicher zeigen: Kopien
> (Zuweisung, Argumente) sehen dieselben Elemente. Der Speicher entsteht in `Create()` bzw. beim ersten `Add`/`Set`; eine leere
> Liste aus `new List<T>()` ist vor dem ersten Einfügen noch nicht mit ihren Kopien verbunden – mit `Create()` starten, wenn man sie
> vor dem ersten Element weitergibt.

**`File`** (statisch, Text standardmäßig UTF-8): `ReadAllText(path [, encoding])`, `ReadAllBytes(path)`, `WriteAllText(path, text [, encoding])`,
`WriteAllBytes(path, bytes)`, `Exists(path)`, `Delete(path)`. Lesen liefert `Error<string>` bzw. `Error<uint8[]>`, Schreiben und Löschen
`Error<void>`; ein UTF-8-BOM wird beim Textlesen übersprungen. Pfade gehen unverändert an die C-Bibliothek (unter Windows also
keine Nicht-ASCII-Zeichen im Pfad).

```csharp
using System;

Error<string> Load(string path)
{
    var text = try File.ReadAllText(path);
    try File.WriteAllText(path + ".bak", text);
    return text.Trim();
}
```

**`Encoding`** – `Encoding.UTF8()` und `Encoding.ASCII()`: `GetBytes(string)`, `GetString(uint8[] [, start, count])` (`Error<string>`:
ungültiges UTF-8 bzw. Bytes über 127 bei ASCII sind Fehler), `GetByteCount`, `Name()`. Strings sind im Speicher immer UTF-8;
`GetBytes` mit ASCII ersetzt andere Zeichen durch `?`. Weitere Kodierungen lassen sich als neue `EncodingKind` ergänzen.

**`Math`** – Konstanten `PI`, `E`, `Tau`; `Abs`/`Min`/`Max`/`Clamp` (int, int64, float, double), `Sign`; `Sqrt`, `Cbrt`, `Pow`, `Exp`,
`Log`, `Log2`, `Log10`, `Hypot`; `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan`, `Atan2`, `Sinh`, `Cosh`, `Tanh`,
`DegreesToRadians`, `RadiansToDegrees`; `Floor`, `Ceiling`, `Truncate`, `Round` (Halbe zur geraden Zahl wie in C#), `Lerp`, `IsNaN`,
`IsInfinity`. Ganzzahl-Argumente werden zu `double` (`Math.Sqrt(2)`).

**String-Helfer** (`s.Contains(x)` ≙ `String.Contains(s, x)`, statisch `string.Join(sep, parts)`): `IsNullOrEmpty`, `Contains`,
`IndexOf`, `LastIndexOf`, `StartsWith`, `EndsWith`, `Trim`, `ToUpper`/`ToLower` (nur ASCII), `Replace`, `Repeat`, `Split` (Zeichen
oder String), `Join`, `ParseInt`/`ParseInt64`/`ParseDouble` (`Error<…>`), außerdem `Equals`, `GetHashCode` (FNV-1a) und
`CompareTo` (bytesweise). Positionen sind Byte-Offsets, `string.FromBytes(bytes [, start, count])` baut einen String aus Bytes.
Neue Helfer schreibt man einfach als Funktion in `namespace String` (erster Parameter = der String).

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
| `stdlib/*.csh` | Standardbibliothek in CShift; wird von CMake als Byte-Arrays in den Compiler eingebettet (`StdlibData.cpp`) |
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

* `tests/test.csh` (+ `tests/mathlib.csh`): großes Testprogramm mit ~165 Prüfungen über alle Sprachbereiche. Ausgabe wird gegen
  `tests/test.expected` verglichen, zusätzlich muss die ARC-Bilanz aufgehen.
* `tests/cases/*.csh`: kleine Programme mit Erwartungen in Kommentaren – Compilerfehler (`err_*`), Laufzeit-Panics (`panic_*`),
  Programmverhalten (`main_*`), ARC-Stresstest, Sonderfälle (`misc_features`, `builtins`, `error_void`, `const_default`) und die
  Tests der Standardbibliothek (`stdlib_*`; `stdlib_file` legt Dateien im temporären Verzeichnis an).

## Bekannte Einschränkungen / nächste Schritte

* Standardbibliothek ist klein: keine Streams/Verzeichnisoperationen, kein `HashSet`/`Stack`/`Queue`, keine weiteren Encodings,
  keine Datums-/Zeitfunktionen, keine Formatierung (`Format`, Interpolation). Indexer (`list[i]`) gibt es nicht, es heißt `Get`/`Set`.
* Interfaces als Werttyp (dynamischer Aufruf), Funktionszeiger/Callbacks für die FFI, Lambdas, globale *Variablen* (Konstanten gehen),
  `Main(string[] args)`, Struct-Übergabe *by value* an C-Funktionen (ABI-Coercion) fehlen noch.
* Referenzzähler sind nicht atomar (kein Multithreading).
* Generische Körper werden erst bei der Instanziierung geprüft (wie C++-Templates); unbenutzte generische Funktionen werden nicht analysiert.
* Keine Debug-Informationen (DWARF/PDB).
* Fehlermeldungen: Nach Syntaxfehlern wird die semantische Analyse nicht mehr ausgeführt.
