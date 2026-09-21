# C-Header importieren (FFI)

Mit `using Name from "header.h";` importiert CShift die Deklarationen eines C-Headers als Namensraum. Funktionen, Structs, Enums
und Konstanten müssen nicht mehr von Hand als `extern "C"` nachgebaut werden.

```csharp
using Zlib from "zlib.h";

int Main()
{
    Console.WriteLine(Zlib.zlibVersion());          // const char* -> string
    Console.WriteLine(Zlib.Z_BEST_COMPRESSION);     // Makro -> Konstante
    Zlib.z_stream stream = default(Zlib.z_stream);  // C-Struct mit exaktem Layout
    return 0;
}
```

```
cshiftc build          # cshift.json: "links": ["z"]
cshiftc prog.csh -lz   # Einzeldatei
```

## Ablauf

1. Der Compiler parst den Header mit **libclang** und schreibt eine **`.ffi`-Datei** (JSON, leicht lesbar) nach `obj/ffi/<Name>.ffi`
   (relativ zum Projektordner bzw. zur Quelldatei). Darin stehen Funktionen, Structs, Enums und Konstanten mit CShift-Typen.
2. Aus der `.ffi`-Datei entstehen die Deklarationen des Namensraums. Der Header wird **nur neu geparst, wenn sich etwas geändert hat**
   (Inhalt – xxh3-Hash – des Headers und aller Header, die zur API gehören, Target, `-I`/`-D`, Format-Version). Sonst wird die
   Datei einfach gelesen; das kostet Millisekunden.
3. Die Bibliothek (`.a`, `.o`, `.lib`, `.so`) muss weiterhin gelinkt werden – über `links` in der `cshift.json` oder auf der Kommandozeile.

`using Name from "datei.ffi";` verwendet eine vorhandene `.ffi`-Datei direkt. Dafür ist libclang nicht nötig
(z. B. wenn Bindings mit ausgeliefert werden); nur die Wrapper-Datei für Struct-Werte (siehe unten) bindet den Header ein. Der Header wird gesucht relativ zur Quelldatei, dann in den `includePaths`
(`-I`) und schließlich in den System-Include-Verzeichnissen des `clang`.

### Voraussetzungen

* `clang` (Linker/Shims) und **libclang** (`libclang.dll` / `libclang.so` neben bzw. unter dem Verzeichnis von `clang`). `cshiftc`
  lädt libclang erst, wenn ein Header tatsächlich geparst werden muss; Umgebungsvariable `CSHIFT_LIBCLANG` überschreibt den Pfad.
* Fehler im Header (nicht gefundene Includes, unbekannte Typen) brechen den Import mit der Meldung von clang ab – sonst würden
  Typen still zu `int`. Fehlende Makros oder Pfade gibt man über `includePaths` und `defines` an.

## Projektdatei

```json
{
	"name": "app",
	"includePaths": ["third_party/sqlite"],
	"defines": ["SQLITE_OMIT_LOAD_EXTENSION"],
	"libraryPaths": ["third_party/lib"],
	"links": ["sqlite3", "third_party/lib/libminifb.a"]
}
```

| Schlüssel | Bedeutung | Kommandozeile |
|---|---|---|
| `includePaths` | Suchpfade für C-Header (relativ zur `cshift.json`) | `-I<dir>` |
| `defines` | Makros beim Parsen der Header | `-D<name>[=wert]` |
| `libraryPaths` | Suchpfade des Linkers | `-L<dir>` |
| `ffiApi` | Pfadteile von Headern, die auch aus System-Include-Pfaden zur importierten API gehören (Umbrella-Header) | `--ffi-api=<text>` |
| `links` | Eintrag ohne Pfad/Endung: Bibliotheksname (`-l<name>`); Eintrag mit Pfad oder Endung `.a .o .obj .lib .so .dylib .dll`: Datei, die direkt gelinkt wird | `-l<name>`, `datei.a` |

## Abbildung der C-Typen

| C | CShift |
|---|---|
| `char` / `signed char` / `unsigned char` | `char` / `int8` / `uint8` |
| `short`, `unsigned short` | `int16`, `uint16` |
| `int`, `unsigned int` | `int32`, `uint32` (bleibt `int`!) |
| `long`, `unsigned long` | je nach Ziel `int32`/`int64` (Windows: 32 Bit, Linux/macOS 64 Bit) |
| `long long` | `int64`, `uint64` |
| `size_t`, `uintptr_t` / `ssize_t`, `ptrdiff_t`, `intptr_t` | **`nuint`** / **`nint`** |
| `float`, `double` | `float32`, `double` |
| `_Bool`, `bool` | `bool` |
| `enum E` | `enum E` (Basistyp aus C) |
| `struct S` | `struct S` mit exakt dem C-Layout |
| `struct S` ohne Definition (opaque Handle) | nur als Zeiger `S*` verwendbar |
| `void*` | `void*` |
| Funktionszeiger `R (*)(A, B)` | `Func<A, B, R>` / `Action<A, B>` (siehe unten) |
| `const char*` | `string` |
| `union`, Bitfelder, Arrays in Structs | als Füllbytes im Layout (Größe stimmt, kein Feldzugriff) |
| `long double` | Funktion wird übersprungen |

Der Name eines Struct-/Enum-Typs ist der **typedef-Name**, sofern es einen gibt (`z_stream`, nicht `z_stream_s`).

**`nint` / `nuint`** sind Ganzzahlen in Zeigergröße (wie `IntPtr`/`UIntPtr` in C#): 64 Bit auf 64-Bit-Zielen. `int`-Werte und alles
Kleinere konvertieren implizit nach `nint`/`nuint`; `nint`/`nuint` konvertiert implizit nach `int64`/`uint64`, die Gegenrichtung
verlangt einen Cast (auf 32-Bit-Zielen ginge Information verloren). `int` und `uint` behalten ihre feste Größe von 32 Bit –
deshalb wird C-`int` bewusst auf `int32` abgebildet und nicht auf `nint`.

### Zeiger

| C-Parameter | CShift | Aufruf |
|---|---|---|
| `T* p` (Zeiger auf einen Wert) | `ref T` | `f(ref x)`; auch `null` oder ein `T*` sind erlaubt (Zeiger dürfen `NULL` sein) |
| `const T* p` | `const ref T` | `f(x)`; auch `null` oder `T*` |
| `const char* s` | `string` | `f("text")`; `null` wird zu `NULL` |
| `char* buffer` | `char*` | unsicherer Zeiger (`unsafe`) |
| `void*` | `void*` | |
| Funktionszeiger | `Action<...>` / `Func<..., R>` | eine Funktion oder `null` |
| `Handle*` (opaker Typ) | `Handle*` | unsicherer Zeiger, nur weiterreichen |
| `T**` | `ref T*` | Ausgabeparameter: `f(ref handle)` |

Rückgabewerte bleiben rohe Zeiger; nur `const char*` wird als **Kopie** zu einem `string` (`NULL` → `null`). Der Zeiger gehört weiterhin
der Bibliothek, der String ist eine eigene Kopie.

Das Feld `ref`/`constref`/`nullable` in der `.ffi`-Datei steuert dieses Verhalten pro Parameter. Ein Zeiger auf ein Array (`int* values`,
`size_t count`) wird als `ref int` abgebildet; einen Zeiger auf mehrere Elemente übergibt man als rohen `int*` (`unsafe`).

### Structs *by value*

C-Funktionen, die ein Struct als Wert nehmen oder liefern (`GeoPoint geo_add(GeoPoint a, GeoPoint b)`), sind ABI-abhängig (Register
oder Speicher, je nach Plattform und Größe). Der Compiler erzeugt dafür neben der `.ffi`-Datei ein kleines **C-Wrapper-File**
(`obj/ffi/<Name>.shim.c`), das mit `clang` übersetzt und automatisch gelinkt wird. Damit übernimmt clang die plattformspezifische
Übergabe; in CShift sieht man nur normale Funktionen mit Struct-Werten:

```csharp
Geo.GeoPoint p = Geo.geo_point_add(Geo.geo_point_make(1, 2), Geo.geo_point_make(10, 20));
```

Die Wrapper referenzieren jede solche Funktion der Bibliothek, daher muss die Bibliothek gelinkt werden, sobald der Header
solche Funktionen enthält – auch wenn man sie nicht aufruft.

### Callbacks (Funktionszeiger)

C-Funktionszeiger werden zu den eingebauten Typen `Action<...>` (ohne Ergebnis) und `Func<..., R>` (mit Ergebnis, der letzte
Typ ist das Ergebnis) – bis zu 8 Parameter, ohne Closures. Man übergibt den Namen einer CShift-Funktion oder `null`:

```csharp
using Mfb from "MiniFB.h";

// typedef void (*mfb_keyboard_func)(struct mfb_window*, mfb_key, mfb_key_mod, bool)
//   ->  Action<mfb_window*, mfb_key, mfb_key_mod, bool>
void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed && key == Mfb.mfb_key.KB_KEY_ESCAPE)
        Mfb.mfb_close(window);
}

Mfb.mfb_set_keyboard_callback(window, OnKey);
```

Ein Callback bekommt die C-Werte unverändert: Zeiger sind rohe Zeiger (`const char*` → `char*`, `const S*` → `S*`; Zugriff nur in
`unsafe`), es gibt keine `string`-/`ref`-Umwandlung. Ein Zeiger auf `void*`-Nutzerdaten (`void* user`) wird mit einem Cast
zurückgewandelt (`(int*)user`). Eine C-Funktion, die einen Funktionszeiger *liefert*, ergibt einen `Func<...>`, den man direkt
aufruft. Funktionszeiger in Structs (`GeoOps.fn`) sind ebenfalls `Action`/`Func`. Genaueres steht im README (Abschnitt Funktionszeiger).

### Konstanten und Enums

Ganzzahl-, Fließkomma- und String-Makros (`#define VERSION 3`, `(FLAG_A << 1)`) werden zu Konstanten des Namensraums; Aufzählungswerte
sind Konstanten vom Enum-Typ und über den Enum-Namen erreichbar: `Geo.GEO_GREEN`, `Geo.GeoColor.GEO_GREEN`. Funktionsartige Makros
gibt es nicht.

## Grenzen

Nicht übernommen (steht im Feld `skipped` der `.ffi`-Datei mit Begründung, die Verwendung meldet "undefined name"):

* globale Variablen des Headers, `long double`, `__int128`
* Zugriff auf Union-Felder, Bitfelder und Arrays in Structs (das Layout stimmt trotzdem)
* gepackte Structs (`#pragma pack`): der Import bricht mit einer Layout-Meldung ab
* Callbacks mit Struct-Werten als Parameter oder Ergebnis, variadische Funktionszeiger, mehr als 8 Parameter: bleiben `void*`
* Variadische Funktionen mit Struct-Werten (Variadische mit einfachen Werten wie `printf` funktionieren)
* Nur C, kein C++ (Namespaces, Klassen, Templates)

## Umbrella-Header und Bibliotheken in Systempfaden

Ein Header aus einem System-Include-Pfad (`llvm-c/Core.h`, `zlib.h`) bringt nur seine eigenen Deklarationen mit; Header, die er
einbindet, gelten als Systemheader und werden nicht übernommen. Um mehrere Header einer Bibliothek in **einen** Namensraum zu
holen, schreibt man einen eigenen Header, der sie einbindet (ein *Umbrella-Header*), und nennt in der Projektdatei die Pfadteile, die
zur API gehören sollen:

```json
{
	"includePaths": ["C:/msys64/clang64/include"],
	"ffiApi": ["llvm-c/", "llvm/Config"]
}
```

```c
/* native/llvm.h */
#include <llvm-c/Core.h>
#include <llvm-c/TargetMachine.h>
```

```csharp
using Llvm from "native/llvm.h";
```

Auf der Kommandozeile: `--ffi-api=<text>`. Ein `const char*`-Parameter (`string` in CShift) nimmt auch ein rohes `char*` an,
etwa einen Zeiger, den eine andere C-Funktion geliefert hat (`string.FromCStr(char*)` kopiert einen C-String in einen `string`).
