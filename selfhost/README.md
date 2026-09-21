# selfhost: der CShift-Compiler in CShift

Ziel: den Compiler (`compiler/`, C++ mit LLVM) in CShift selbst zu schreiben, sodass er sich am Ende selbst übersetzt.

**Stand:** Lexer und Parser sind vollständig und gegen den C++-Compiler abgesichert. Der Codegenerator läuft für den Kern der
Sprache (Funktionen, Zahlen, `bool`, `char`, Strings mit Referenzzählung, Kontrollfluss, `Console`); von den 80 Testfällen in
`tests/cases` besteht `cshc` 28, 48 brauchen noch nicht portierte Sprachteile (Structs, Arrays, `Error<T>`, Generics,
Standardbibliothek …). Der Rest der Liste steht unten und in [../Todo.md](../Todo.md).

```
selfhost/
├── cshift.json              Projekt "cshc" (baut mit: cshiftc build selfhost)
├── src/
│   ├── Main.csh             Kommandozeile: cshc [Optionen] datei.csh ... | --tokens | --ast
│   ├── Syntax/              namespace CShift.Syntax
│   │   ├── Location.csh     SourceLoc, Diagnostics
│   │   ├── Token.csh, Lexer.csh      Lexer (Portierung von compiler/src/Lexer.cpp)
│   │   ├── Ast.csh          Syntaxbaum: Knotentypen und die Arenen (struct Ast)
│   │   ├── Parser.csh       Parser (Portierung von compiler/src/Parser.cpp)
│   │   └── TokenDump.csh, AstDump.csh    Textausgaben für den Vergleich mit dem C++-Compiler
│   ├── Sema/                namespace CShift.Sema
│   │   └── Types.csh        Typtabelle: Typen sind Ganzzahlen (Ids), internierte Typen vergleicht man mit ==
│   ├── Emit/                namespace CShift.Emit
│   │   └── IrWriter.csh     schreibt LLVM-IR als Text (Blöcke, Instruktionen, Konstanten, Deklarationen)
│   └── CodeGen/             namespace CShift.CodeGen
│       ├── Compiler.csh     Zustand des Compilers, Deklarationen, Typauflösung, Funktionsinstanzen (CodeGen.cpp)
│       ├── Values.csh       Werte, Referenzzählung, Konvertierungen (erste Hälfte von CodeGenExpr.cpp)
│       ├── Expr.csh         Ausdrücke (CodeGenExpr.cpp)
│       ├── Call.csh         Aufrufe, Überladungsauflösung, Console/Environment (CodeGenCall.cpp)
│       ├── Stmt.csh         Anweisungen, Scopes, Funktionskörper (CodeGenStmt.cpp)
│       ├── Runtime.csh      die Laufzeit als IR-Text: Strings, ARC, Panic (CodeGenRuntime.cpp)
│       └── Module.csh       Programm übersetzen, Einstiegspunkt
├── compare.sh               Frontend: vergleicht cshc mit dem C++-Compiler (Tokens und Syntaxbaum)
├── status.sh, passing.txt   Codegenerator: welche Fälle aus tests/cases bestehen
└── DEPENDENCIES.md          Analyse: was der neue Compiler zur Laufzeit braucht und was sich sparen lässt
```

## Bauen und benutzen

```
cshiftc build selfhost                                  # -> selfhost/bin/cshc
selfhost/bin/cshc hallo.csh -o hallo                    # .ll schreiben, clang optimiert/übersetzt/linkt
selfhost/bin/cshc --emit-llvm hallo.csh -o hallo.ll     # nur das IR
selfhost/bin/cshc --tokens datei.csh | --ast datei.csh  # Dumps (Vergleich mit cshiftc --dump-tokens / --dump-ast)
```

`cshc` schreibt **LLVM-IR als Text** (`.ll`) und ruft `clang` (aus dem `PATH` oder `--cc`) auf, das optimiert, Maschinencode erzeugt
und linkt. So braucht `cshc` selbst kein LLVM (kein 100-MB-Link, keine `unsafe`-Hülle um die LLVM-C-API); wie der C++-Compiler
erzeugt er dieselbe Art IR (Vorlage: `cshiftc --emit-llvm`).

## Prüfen

* **Frontend:** `bash selfhost/compare.sh <cshiftc> selfhost/bin/cshc` – Token- und Syntaxbaum-Dump samt Fehlermeldungen für
  alle 110 `.csh`-Dateien des Repositorys (auch die Quellen von `selfhost/`) müssen mit denen des C++-Compilers übereinstimmen.
* **Codegenerator:** `bash selfhost/status.sh selfhost/bin/cshc -v` übersetzt `tests/cases/*.csh` mit `cshc` und sortiert:
  *pass*, *unsupported* (`cshc does not support …`, ein noch nicht portiertes Feature) und *FAIL* (echter Unterschied).
  Die bestehenden Fälle stehen in `passing.txt`; `status.sh --check` (Teil von `tests/run_tests.sh`) schlägt fehl, wenn einer
  davon nicht mehr besteht. Neue bestandene Fälle trägt man dort ein (`status.sh -v` liefert die Liste).

## Entwurfsentscheidungen

* **Syntaxbaum in Arenen.** CShift hat keine Klassen mit Referenzsemantik, und ein Struct kann sich nicht selbst enthalten.
  Jede Knotenart hat deshalb eine `List<...>` in `struct Ast`; Knoten verweisen über kleine Handles (`Expr`, `Stmt`, `TypeRef`)
  aufeinander. Der Nullwert (alles 0) bedeutet "kein Knoten". `ast.GetCall(e)` liefert den `CallExpr`.
* **Typen als Ganzzahlen.** Ein Typ ist eine Id in `TypeContext`; wie in C++ ist jeder Typ genau einmal vorhanden (interniert),
  Typgleichheit ist `==`. Deklarationen (Funktionen, Structs, …) sind Indizes in Listen des `Compiler`.
* **Der Compiler ist ein Handle.** Structs lassen sich nicht auf Dateien verteilen; die C++-Memberfunktionen von `CodeGen` werden zu
  freien Funktionen `Emit…(Compiler cg, …)` in mehreren Dateien. Der ganze veränderliche Zustand steckt in Listen, Dictionaries und
  kleinen Arrays (`cg.St[0]`, `cg.Fn[0]`), sodass Kopien des `Compiler` denselben Zustand sehen (ein Feld einer Kopie neu
  zuzuweisen wirkt nicht auf die anderen).
* **Nur ein Fehler.** `Fail(...)` gibt den ersten Fehler aus und beendet. Im Parser gibt es `Error<T>` und `try` statt
  Exceptions (Backtracking stellt die Position wieder her).
* **Code, der später ergänzt werden muss.** `IrWriter.Mark()/TakeSince()/AppendCode()` schneiden erzeugten Code aus und fügen ihn
  später wieder ein (für `?:`, dessen Zweige die gemeinsame Typkonvertierung erst kennen, wenn beide fertig sind).

## Gefundene Lücken (behoben)

Beim Portieren fehlten diese Dinge in der Sprache bzw. der Standardbibliothek; sie sind jetzt vorhanden:

* `int Main(string[] args)`, `string.FromCStr(char*)`, `Console.WriteError(Line)`
* `Char.*`, `StringBuilder` (mit `Substring`/`Truncate`), `HashSet<T>`, `Process.Run`
* FFI: `ffiApi` in der Projektdatei (Umbrella-Header), `char*` für `const char*`-Parameter

Bekannte Unbequemlichkeiten (bisher ohne Blocker): ein Pattern-Variablenbereich endet mit dem `if`; Listenelemente lassen sich nur
als Kopie holen (`Get`/`Set`); ein großer Struct lässt sich nicht auf mehrere Dateien verteilen; `Dictionary` und `List` sind Structs
(kein `null`, "keine Umgebung" ist ein leeres Dictionary).

## Was noch fehlt

Die C++-Dateien geben den Umfang vor; als CShift dürften es ähnlich viele Zeilen werden. Reihenfolge nach Nutzen für die Tests:

| Schritt | Inhalt | C++-Vorlage |
|---|---|---|
| 1 | Structs: Layout, Felder, Methoden, `this`, Initialisierer, Vererbung, Interfaces, Constraints | `CodeGen.cpp`, `CodeGenExpr/Call.cpp` |
| 2 | Arrays und Strings-Methoden (`Length`, Indexer, `Substring`, `CStr`), `new T[]`, `foreach`, Grenzenprüfung | `CodeGenExpr.cpp`, `CodeGenRuntime.cpp` |
| 3 | `Error<T>`, `Optional<T>`, `try`, `is`-Pattern, `switch`, `using`/`IDisposable` | `CodeGenExpr.cpp`, `CodeGenStmt.cpp` |
| 4 | Enums, Generics (Instanziierung, Typinferenz), Funktionszeiger, `nint`, Zeiger/`unsafe` | `CodeGen*.cpp` |
| 5 | Standardbibliothek laden (`stdlib/*.csh` neben `cshc` oder eingebettet), `Main(string[] args)`, `--arc-stats` | `main.cpp`, `StdlibData` |
| 6 | Treiber: Projektdatei (`cshift.json`, JSON-Parser in CShift), Optionen wie `cshiftc`, clang finden (`toolchain/`) | `main.cpp`, `Project.cpp` |
| 7 | FFI: `.ffi` lesen, Header über libclang, Struct-Wrapper | `FfiImport.cpp`, `FfiGenerator.cpp` |

Danach `tests/test.csh` und `tests/projects/` mit `cshc` und schließlich der Bootstrap (`cshc` baut `selfhost/` und das Ergebnis
baut es noch einmal; die beiden Ergebnisse müssen gleich sein).
