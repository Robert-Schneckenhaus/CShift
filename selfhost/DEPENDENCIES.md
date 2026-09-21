# Abhängigkeiten eines selbstgebauten Compilers (Analyse)

Frage aus der Todo-Liste: Was braucht der neue Compiler, wenn man ihn ausliefert? Lässt sich das reduzieren, oder lassen sich
Abhängigkeiten selbst in CShift schreiben? Das hier ist eine Einschätzung, noch keine Umsetzung.

## Was der aktuelle Compiler braucht

| Ebene | Wozu | Größe (Windows) |
|---|---|---|
| **LLVM** (statisch in `cshiftc` gelinkt) | IR bauen, optimieren, Objektdateien erzeugen | ~120 MB im Programm |
| **clang** | Linker-Treiber (findet Startdateien, ruft lld), C-Compiler für die Struct-Wrapper des FFI | `clang.exe` klein, aber `libLLVM` (150 MB) + `libclang-cpp` (60 MB) |
| **lld** | eigentliches Linken | 6 MB |
| **libclang** | C-Header lesen (`using X from "h.h"`) | 35 MB (+ die beiden LLVM-DLLs) |
| **C-Bibliothek und -Header** | Laufzeit der erzeugten Programme (`malloc`, `printf`, `fopen`, …) und Header für den FFI | Windows: MinGW-w64 (~70 MB, im Release enthalten); Linux: `libc6-dev` des Systems |
| **C++-Compiler, CMake** | nur zum *Bauen* von `cshiftc` | nicht zur Laufzeit |

## Der Compiler in CShift: was ändert sich

1. **C++ und CMake entfallen zum Bauen.** `cshc` baut sich mit `cshiftc build selfhost` (später mit sich selbst). Übrig bleibt
   das Henne-Ei-Problem: die erste Stufe ("Stage 0") braucht einen bereits vorhandenen Compiler. Lösungen: ein mitgeliefertes
   fertiges `cshc` (Release) als Seed, oder der Seed liegt als LLVM-IR/Objektdatei im Repository. Danach ist C++ nicht mehr nötig.
2. **LLVM steckt nur noch in clang.** Der Backend-Teil (Codegenerierung für x86-64/ARM, Optimierer, Objektformate) ist keine Aufgabe für eine
   Neuschreibung in CShift – das wären Jahre. `cshc` muss LLVM aber gar nicht einbinden: Es schreibt die IR als **Text** (`.ll`) und
   übergibt sie an `clang`, das optimiert, den Objektcode erzeugt und linkt (so arbeitet `selfhost/` bereits). Damit entfällt der
   statische LLVM-Link im Compiler (`cshiftc` ist heute ~120 MB, `cshc` einige MB); LLVM bleibt nur als Teil der mitgelieferten
   Toolchain (`clang` + `libLLVM`). Die Alternative – die LLVM-C-API direkt aus CShift aufzurufen (per FFI funktioniert das:
   ein CShift-Programm erzeugte so ein lauffähiges Programm) – brächte einen 100-MB-Link und eine `unsafe`-Hülle um jeden Aufruf
   und wurde deshalb verworfen. Nachteil des Text-Wegs: clang muss beim Übersetzen jedes Programms vorhanden sein (ist es ohnehin
   zum Linken), und IR-Text zu schreiben und zu parsen ist etwas langsamer als die API.
3. **clang als Linker-Treiber lässt sich durch lld ersetzen.** `cshc` würde `ld.lld` (bzw. `lld-link`) selbst mit den richtigen
   Startdateien und Bibliotheken aufrufen. Windows/MinGW ist überschaubar (`crt2.o`, `libmingw32`, `libmoldname`, `libmingwex`,
   `libmsvcrt`/`libucrt`, `libkernel32`, … plus `libclang_rt.builtins`); auf Linux hängt es an der Distribution
   (Multiarch-Pfade, gcc-Startdateien `crtbegin.o`, dynamischer Loader) – dort ist der clang-Treiber die pragmatische Lösung.
   Einschätzung: Windows ja (klein), Linux erst später oder gar nicht.
4. **Der C-Compiler für die Struct-Wrapper ist ersetzbar.** Sie existieren nur, weil C-Funktionen mit Structs *by value* plattform-
   abhängig aufgerufen werden. `cshc` kann diese Aufrufe direkt als IR erzeugen, wenn es die Aufrufkonvention selbst umsetzt
   (SysV x86-64: Klassifizierung in INTEGER/SSE/MEMORY; Win64: 1/2/4/8 Byte in Registern, sonst per Zeiger). Das ist überschaubar
   (je Konvention einige hundert Zeilen) und entfernt die Abhängigkeit von `clang` beim FFI. Aufwand mittel, Nutzen: kein C-Compiler mehr zur Laufzeit.
5. **libclang ist optional und sollte es bleiben.** Es wird nur für `using X from "header.h"` gebraucht und wird zur Laufzeit
   geladen. Einen C-Präprozessor und C-Parser in CShift zu schreiben, der echte Header (`windows.h`, glibc, SDL, …) versteht, wäre
   sehr groß und nie vollständig (Makros, Attribute, `__declspec`, Bitfelder, Layout je Plattform). Empfehlung: libclang behalten;
   wer keinen Header importieren will, braucht sie nicht, und die erzeugten `.ffi`-Dateien lassen sich mit dem Projekt ausliefern
   (der Compiler liest sie ohne libclang). Ein `.ffi` ist ein einfaches JSON: das Lesen ist mit einem JSON-Parser (klein, in
   CShift schreibbar) erledigt.
6. **Die C-Bibliothek der erzeugten Programme bleibt.** Sie ist unter Linux die ABI zum System und unter Windows (ucrt) Teil des
   Betriebssystems. Sie zu ersetzen hieße: eigene Zahlenformatierung (`double` → Text braucht einen Algorithmus wie Ryu),
   `strtod`, die Mathefunktionen und einen eigenen Speicherverwalter über `HeapAlloc`/`mmap` – machbar, aber ein eigenes
   Teilprojekt und kaum Gewinn.
7. **Was ohnehin schon in CShift/IR steckt:** die Standardbibliothek (List, Dictionary, File, String, …) ist CShift-Code, ARC,
   Strings und Panics werden als IR erzeugt – es gibt keine mitgelieferte Laufzeitbibliothek.

## Einschätzung

| Abhängigkeit | ersetzbar? | Aufwand | Empfehlung |
|---|---|---|---|
| C++-Compiler, CMake (zum Bauen) | ja, durch den Compiler selbst | klein, sobald Codegen steht (Seed nötig) | ja |
| LLVM (Optimierer, Codegenerierung) | nein, aber nur noch in clang: `cshc` schreibt IR-Text | – | clang behalten; `cshc` braucht kein LLVM mehr |
| clang als Linker-Treiber | Windows ja (lld direkt), Linux schwer | klein bis mittel | Windows später umstellen |
| clang als C-Compiler für FFI-Wrapper | ja (eigene ABI-Umsetzung) | mittel | lohnt, wenn clang sonst entfallen soll |
| libclang (Header lesen) | technisch ja, praktisch nein | sehr groß | optional lassen; `.ffi` mitliefern |
| C-Bibliothek | ja, aber sinnlos | groß | behalten |

Ausgeliefert würde damit: **`cshc` (klein, ohne LLVM) + die Toolchain aus `clang` und `libLLVM`** (Windows zusätzlich MinGW-Header/-Bibliotheken;
Linux `build-essential`), optional `libclang`. Fällt clang als Linker-Treiber (Punkt 3) und als C-Compiler für die FFI-Wrapper (Punkt 4)
weg, bleibt für das Übersetzen nur noch `clang` selbst (Optimierung und Objektcode aus dem IR) plus lld; ein eigener Ersatz
für LLVM lohnt nicht.
