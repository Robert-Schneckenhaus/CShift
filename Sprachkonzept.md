# Native C#-artige Systemsprache

## 1. Ziel

Die Sprache verbindet die Ausdrucksstärke und Lesbarkeit von C# mit einer nativen Ausführung ähnlich C.

Ziele:

* native ausführbare Programme
* kein Garbage Collector
* kein IL
* kein JIT
* keine verpflichtende Runtime
* keine Header-Dateien
* keine Include Guards
* keine Forward Declarations
* automatische Symbol- und Typauflösung
* C#-ähnliche Syntax
* Structs statt Klassen
* Interfaces
* Generics
* deterministisches Ressourcenmanagement
* direkte C-FFI
* möglichst geringe Sprachkomplexität

Grundidee:

> C#-artige Produktivität mit nativer C-artiger Ausführung.

---

## 2. Grundprinzipien

Die Sprache verwendet eine C#-ähnliche Syntax, verzichtet aber bewusst auf zentrale Konzepte von .NET und C++.

Nicht vorhanden sind:

* Klassen
* CLR/.NET
* IL
* JIT
* Garbage Collection
* Header-Dateien
* Include Guards
* Forward Declarations
* Rust-artiges Ownership-/Borrow-System
* Move-Semantik
* Copy-/Move-Konstruktoren

Der Compiler erzeugt direkt nativen Maschinencode bzw. native Objektdateien.

---

## 3. Dateien und Namespaces

Namespaces:

```csharp
namespace MyApp.Graphics;
```

Verwendung:

```csharp
using MyApp.Graphics;
```

Typen und Funktionen können in beliebigen Quelldateien definiert werden.

Der Compiler analysiert das gesamte Programm und löst Symbole und Typen global auf.

Es sind keine Header-Dateien oder Forward Declarations notwendig.

---

## 4. Structs

Structs sind zentrale Datentypen der Sprache.

Sie sind Werttypen und besitzen standardmäßig Wertsemantik.

```csharp
struct Vec2
{
    float X;
    float Y;
}

var a = Vec2
{
    X = 10,
    Y = 20
};

var b = a;
```

`b` enthält eine Kopie von `a`.

Structs können andere Structs enthalten.

Die Verwendung von `new` bei einem normalen Struct bedeutet keine implizite Heap-Allokation.

Die konkrete Platzierung eines Wertes — Stack, Register, Inline innerhalb eines anderen Structs usw. — ist eine Implementierungsentscheidung des Compilers.

---

## 5. Feldsichtbarkeit

Es gibt keine `public`- oder `private`-Schlüsselwörter für Felder.

Stattdessen gilt:

* Feldnamen, die mit `_` beginnen, sind privat.
* Alle anderen Felder sind öffentlich.

Beispiel:

```csharp
struct Player
{
    int Health;
    int _internalState;
}
```

`Health` ist öffentlich, `_internalState` ist privat.

---

## 6. Keine Properties

Die Sprache besitzt keine Properties.

Es gibt ausschließlich:

* Felder
* Methoden

Getter- und Setter-Logik wird explizit als Methode geschrieben:

```csharp
float GetLength()
{
    return ...
}
```

---

## 7. Struct-Vererbung

Ein Struct kann genau ein anderes Struct als Basistyp besitzen.

```csharp
struct Animal
{
    int Age;
}

struct Dog : Animal
{
    string Name;
}
```

Mehrfachvererbung von Structs ist nicht erlaubt.

Ein Struct kann zusätzlich beliebig viele Interfaces implementieren:

```csharp
struct Dog : Animal, IAnimal, IDisposable
{
}
```

Struct-Vererbung ist Teil des Speicherlayouts. Es existiert keine versteckte Objekt-Hierarchie.

---

## 8. Interfaces

Interfaces definieren ausschließlich Methoden.

Sie besitzen:

* keine Felder
* keine Properties

Beispiel:

```csharp
interface IDisposable
{
    void Dispose();
}
```

Ein Struct kann mehrere Interfaces implementieren.

Die Verwendung eines Interfaces darf keine versteckte Boxing-Allokation erzeugen.

---

## 9. Speicherklassen

Die Sprache unterscheidet drei grundlegende Kategorien:

### 1. Werte

Normale Structs und primitive Typen.

Sie besitzen Wertsemantik und werden kopiert.

### 2. Verwaltete dynamische Daten

Beispielsweise:

* Arrays
* Strings
* dynamische Container
* Ressourcen-Handles

Diese besitzen Referenzsemantik und werden durch ARC verwaltet.

### 3. Manuelle Speicherverwaltung

Explizite Speicherverwaltung ist ausschließlich in `unsafe`-Code erlaubt.

---

## 10. ARC

Verwaltete dynamische Daten verwenden Automatic Reference Counting (ARC).

Beim Kopieren einer verwalteten Referenz wird der Referenzzähler erhöht.

Beim Freigeben wird er verringert.

Bei null Referenzen wird der Speicher freigegeben.

Beispiel:

```csharp
var a = new int[100];
var b = a;
```

`a` und `b` referenzieren dasselbe Array.

Primitive Werte und normale Structs besitzen keinen Referenzzähler.

ARC ist deterministisch und keine Garbage Collection.

---

## 11. Wert- und Referenzkopie

Structs werden vollständig kopiert:

```csharp
var b = a;
```

Verwaltete dynamische Daten werden dagegen als Referenz kopiert:

```csharp
var b = a;
```

Dabei wird lediglich die Referenz geteilt und deren ARC-Zähler erhöht.

Es gibt keine implizite Deep Copy.

Eine unabhängige Kopie erfolgt explizit:

```csharp
var b = a.Clone();
```

---

## 12. Kein implizites Ownership-System

Die Sprache besitzt:

* keinen Borrow Checker
* keine Lifetime-Parameter
* keine Move-Semantik
* keine Copy-/Move-Konstruktoren
* keinen impliziten Ownership-Transfer

Normale Struct-Zuweisung bedeutet Wertkopie.

Bei verwalteten dynamischen Daten bedeutet Zuweisung Referenzkopie.

---

## 13. `ref`

`ref` erzeugt einen expliziten Alias auf bestehenden Speicher.

Es findet kein Ownership-Transfer statt.

```csharp
void Modify(ref Vec2 value)
{
    value.X += 1;
}
```

Aufruf:

```csharp
Modify(ref position);
```

Ein `ref`-Alias darf nicht länger leben als sein Ziel.

Eine Funktion darf beispielsweise keine Referenz auf eine lokale Variable zurückgeben, deren Gültigkeitsbereich bereits endet.

`ref` beschreibt Aliasing, nicht Ownership.

---

## 14. Ressourcen und `IDisposable`

Ressourcen sind nicht dasselbe wie Speicher.

Ressourcen können beispielsweise sein:

* Dateien
* Sockets
* Mutexes
* Betriebssystem-Handles
* GPU-Ressourcen
* Memory Mappings

Das Standardinterface lautet:

```csharp
interface IDisposable
{
    void Dispose();
}
```

`Dispose()` ist eine normale Methode.

Es gibt kein allgemeines Ownership-System für Ressourcen.

---

## 15. Kopierbare Ressourcen-Handles

Ein Ressourcen-Struct enthält eine verwaltete Referenz auf die eigentliche Ressource.

Beispielhaft:

```text
File
 ↓
managed handle
 ↓
OS file handle
```

Beim Kopieren eines Ressourcen-Structs wird die verwaltete Referenz kopiert.

Dadurch können mehrere Struct-Werte dieselbe Ressource referenzieren.

Es wird kein zweiter OS-Handle erzeugt.

---

## 16. Dispose-Semantik

`Dispose()` gibt die Ressource für die aktuelle Referenz frei.

Existieren weitere Referenzen auf dieselbe Ressource, bleibt die zugrunde liegende Ressource erhalten.

Beispiel:

```csharp
var a = File.Open("test.txt");
var b = a;

a.Dispose();
```

`b` referenziert weiterhin dieselbe Ressource.

Die physische Ressource wird erst freigegeben, wenn keine gültigen Referenzen mehr vorhanden sind.

---

## 17. `using`

`using` garantiert, dass `Dispose()` beim Verlassen des Gültigkeitsbereichs aufgerufen wird.

Das gilt auch bei:

* `return`
* `break`
* `continue`
* Fehlerweitergabe über `try`

Bei mehreren verschachtelten `using`-Deklarationen erfolgt die Bereinigung in umgekehrter Reihenfolge.

Deklarationsform:

```csharp
using file = File.Open("test.txt");
```

---

## 18. Scoped `using`

Zusätzlich existiert die Blockform:

```csharp
using (var file = File.Open("test.txt"))
{
    file.Write("Hello");
}
```

Sie besitzt dieselbe Semantik wie die deklarative Form.

`using` garantiert den Aufruf von `Dispose()`, nicht zwingend die sofortige physische Zerstörung der zugrunde liegenden Ressource, wenn weitere Referenzen existieren.

---

## 19. Einschränkungen beim Kopieren von Ressourcen

Das Kopieren eines Ressourcen-Structs darf:

* keinen zweiten OS-Handle erzeugen
* keine implizite Kopie der Ressource erzeugen
* keinen Ownership-Transfer auslösen
* keinen versteckten Move erzeugen

Es bleibt eine normale Struct-Kopie mit gemeinsam genutzter verwalteter Ressource.

---

## 20. Manuelle Speicherverwaltung

Manuelle Speicherverwaltung ist ausschließlich in `unsafe` erlaubt.

Beispiel:

```csharp
unsafe
{
    var memory = Memory.Allocate(1024);

    // ...

    Memory.Free(memory);
}
```

Manuell reservierter Speicher gehört nicht zu ARC.

Der Programmierer ist für dessen Freigabe verantwortlich.

---

## 21. Arrays

Arrays sind verwaltete dynamische Daten.

Sie besitzen:

* Referenzsemantik
* ARC
* feste Länge nach Erstellung

```csharp
var a = new int[10];
var b = a;
```

`a` und `b` referenzieren dasselbe Array.

Eine unabhängige Kopie erfolgt explizit:

```csharp
var b = a.Clone();
```

---

## 22. Strings

Strings sind:

* unveränderlich
* verwaltet durch ARC
* UTF-8

Eine Änderung erzeugt einen neuen String.

---

## 23. `Error<T>`

`Error<T>` ist ein eingebauter Typ, der entweder einen erfolgreichen Wert vom Typ `T` oder einen Fehler enthält.

Beispiel:

```csharp
Error<File> OpenFile(string path)
{
    ...
}

var result = OpenFile("test.txt");

if (result is File file)
{
    file.Read();
}

if (!result)
{
    // error
}
```

Die Bool-Semantik lautet:

* `true` → Wert vorhanden
* `false` → Fehler

---

## 24. `try`

`try` propagiert `Error<T>` automatisch.

```csharp
var file = try OpenFile("test.txt");
```

Falls ein Fehler vorliegt, wird die aktuelle Funktion sofort mit diesem Fehler beendet.

Die aufrufende Funktion muss einen kompatiblen `Error<T>`-Typ zurückgeben.

Beispiel:

```csharp
Error<string> ReadConfig()
{
    var file = try OpenFile("config.txt");
    var text = try file.ReadAllText();

    return text;
}
```

`try` funktioniert ausschließlich mit `Error<T>`.

---

## 25. `Optional<T>`

`Optional<T>` repräsentiert einen optional vorhandenen Wert.

Beispiel:

```csharp
var result = FindUser(42);

if (result is User user)
{
    user.Login();
}

if (!result)
{
    // absent
}
```

Die Bool-Semantik entspricht `Error<T>`:

* `true` → Wert vorhanden
* `false` → kein Wert

`try` darf nicht mit `Optional<T>` verwendet werden.

---

## 26. Keine verschachtelten `Error`-/`Optional`-Typen

Folgende Kombinationen sind nicht erlaubt:

```text
Error<Error<T>>
Error<Optional<T>>
Optional<Error<T>>
Optional<Optional<T>>
```

Dadurch bleiben Fehler und optionale Werte eindeutig und einfach verwendbar.

---

## 27. Generics

Generics verwenden eine C#-ähnliche Syntax:

```csharp
struct Pair<T>
{
    T First;
    T Second;
}

T Max<T>(T a, T b)
{
    ...
}
```

Der Compiler verwendet Monomorphisierung.

Für jede tatsächlich verwendete Typkombination wird eine native Spezialisierung erzeugt.

Beispielsweise:

```text
Max<int>
Max<double>
```

führen zu entsprechenden nativen Implementierungen.

Es gibt keinen generischen Runtime-Mechanismus.

---

## 28. Generic Constraints

Generische Typen können über Interfaces eingeschränkt werden:

```csharp
T Max<T>(T a, T b)
    where T : IComparable<T>
{
    ...
}
```

Der Compiler überprüft die erforderlichen Operationen zur Compile-Zeit.

Die erzeugte Spezialisierung ist vollständig nativ.

---

## 29. Enums

Enums besitzen immer einen expliziten Integer-Basistyp.

```csharp
enum Color : uint8
{
    Red,
    Green,
    Blue
}
```

Dadurch sind Größe und ABI-Repräsentation deterministisch.

---

## 30. Keine Klassen

Die Sprache besitzt keine Klassen und keine allgemeine Objekt-Hierarchie.

Die zentralen Typkategorien sind:

* Structs
* Interfaces
* Enums
* primitive Typen
* Arrays
* Strings
* generische Typen

---

## 31. C-FFI und ABI

Die primäre externe ABI ist die C-ABI.

Ziel ist, praktisch jede normale C-Bibliothek direkt verwenden zu können.

Beispiel:

```csharp
extern "C" int strlen(char* str);

extern "C" Window* create_window(
    int width,
    int height
);
```

Unterstützt werden:

* C-Funktionen
* C-Pointer
* C-Integer-Typen
* Floating-Point-Typen
* C-Structs
* C-Enums
* Pointer + Länge
* Callbacks
* globale C-Symbole

---

## 32. C-Structs und Layout

FFI-Structs besitzen ein definiertes natives Speicherlayout.

Beispiel:

```csharp
struct Vec3
{
    float X;
    float Y;
    float Z;
}
```

Bei drei `float32`-Feldern ist das Layout beispielsweise:

```text
X: offset 0
Y: offset 4
Z: offset 8
size: 12
```

Damit kann das Struct direkt an C-Funktionen übergeben werden.

---

## 33. FFI und `unsafe`

C-FFI kann sowohl sichere als auch unsichere Typen verwenden.

Direkte Pointer-Operationen und direkter Speicherzugriff benötigen `unsafe`.

Beispiel:

```csharp
unsafe
{
    char* text = ...
}
```

---

## 34. Build-System

Der Compiler erzeugt native Objektdateien bzw. native ausführbare Dateien.

Das Build-System übernimmt:

* Kompilierung
* Generics-Monomorphisierung
* Optimierung
* Linken
* Einbinden von C- und Systembibliotheken
* FFI-Auflösung
* Debug-Informationen

Bibliotheken können beispielsweise eingebunden werden:

```text
link "sqlite3"
link "user32"
link "opengl"
```

---

## 35. Zielbild

Ein vollständiges kleines Programm kann beispielsweise so aussehen:

```csharp
using System;

namespace Example;

Error<string> LoadFile(string path)
{
    using file = try File.Open(path);
    return try file.ReadAllText();
}

int Main()
{
    var text = try LoadFile("hello.txt");

    Console.WriteLine(text);

    return 0;
}
```

Das Programm wird als natives Programm ohne GC, .NET, IL oder JIT ausgeführt.

Fehlerbehandlung erfolgt über `Error<T>` und `try`.

Ressourcen werden über `using` und `IDisposable` deterministisch behandelt.

---

## 36. Sprachphilosophie

Die Sprache soll einen möglichst kleinen, praktischen Sprachkern besitzen.

Der Programmierer soll sich auf die Anwendung konzentrieren können, ohne dabei auf native Kontrolle verzichten zu müssen.

Die zentrale Idee lautet:

> C#-artige Produktivität mit nativer C-artiger Ausführung.

---

# Typen, Ausdrücke und Kontrollfluss

## 37. Primitive Typen

Die Sprache besitzt explizit größendefinierte Integer:

```text
int8
int16
int32
int64

uint8
uint16
uint32
uint64
```

Floating-Point:

```text
float32
float64
```

Weitere primitive Typen:

```text
bool
char
```

`char` ist ein UTF-8-Code-Unit-Typ und entspricht einem `uint8`.

Typ-Aliase für typische Programmierung:

```text
int    = int32
uint   = uint32
float  = float32
double = float64
```

Für C-FFI bleiben die expliziten Typen verfügbar.

Integer-Arithmetik ist standardmäßig geprüft.

Beispiel:

```csharp
int x = int.MaxValue;
x = x + 1;
```

Ein Überlauf führt zu einem Laufzeitfehler.

Für bewusst gewünschtes Wraparound existiert ein expliziter `unchecked`-Mechanismus.

---

## 38. `bool`

`bool` besitzt genau zwei Werte:

```text
true
false
```

Nur `bool` darf direkt als Bedingung verwendet werden.

Erlaubt:

```csharp
if (x > 10)
{
}
```

Nicht erlaubt:

```csharp
if (x)
{
}
```

Es gibt keine implizite Konvertierung von Integern, Pointern oder anderen Typen nach `bool`.

---

## 39. Operatoren

### Arithmetische Operatoren

```text
+
-
*
/
%
```

### Vergleich

```text
==
!=
<
>
<=
>=
```

### Logik

```text
&&
||
!
```

### Bitoperationen

```text
&
|
^
~
<<
>>
```

### Zuweisungen

```text
=
+=
-=
*=
/=
%=
&=
|=
^=
<<=
>>=
```

---

## 40. Keine `++` und `--`

Die Sprache besitzt keine `++`- und `--`-Operatoren.

Statt:

```csharp
i++;
```

wird geschrieben:

```csharp
i += 1;
```

Dadurch entfällt die zusätzliche Präfix-/Postfix-Semantik.

---

## 41. Operatorrangfolge

Die Operatorrangfolge orientiert sich an C#:

```text
()
!
~

*
/
%

+
-

<<
>>

<
>
<=
>=

==
!=

&

^

|

&&

||

=
+=
-= ...
```

Klammern können jederzeit verwendet werden:

```csharp
var x = (a + b) * c;
```

---

## 42. Kontrollfluss

### `if`

```csharp
if (health > 0)
{
    Update();
}
else
{
    Die();
}
```

Ein einzelnes Statement darf ohne Block verwendet werden:

```csharp
if (ready)
    Start();
```

### `while`

```csharp
while (running)
{
    Update();
}
```

### `do`

```csharp
do
{
    Update();
}
while (running);
```

### `for`

```csharp
for (var i = 0; i < 10; i += 1)
{
    Print(i);
}
```

### `foreach`

```csharp
foreach (var item in items)
{
    Process(item);
}
```

---

## 43. `switch`

Die Sprache besitzt einen C#-ähnlichen `switch`:

```csharp
switch (color)
{
    case Color.Red:
        Print("red");
        break;

    case Color.Green:
        Print("green");
        break;

    default:
        Print("other");
        break;
}
```

Zusätzlich ist Pattern Matching möglich:

```csharp
switch (result)
{
    case Error<int> r:
        ...
}
```

---

## 44. `break` und `continue`

Schleifen unterstützen:

```csharp
break;
continue;
```

`break` beendet die unmittelbar umgebende Schleife bzw. den entsprechenden `switch`.

`continue` startet die nächste Iteration.

Labels für `break` oder `continue` sind nicht vorgesehen.

---

## 45. `return`

Normale Rückgabe:

```csharp
int Add(int a, int b)
{
    return a + b;
}
```

Bei `void`:

```csharp
void DoSomething()
{
    return;
}
```

Am Ende einer `void`-Funktion darf `return` weggelassen werden.

---

## 46. Struct-Initialisierung

Es gibt zwei grundlegende Formen.

### Default-Initialisierung

```csharp
var player = new Player();
```

Alle Felder erhalten ihren Default-Wert.

Typische Default-Werte:

```text
int       → 0
float     → 0
bool      → false
Pointer   → null
string    → null
Optional  → kein Wert
```

### Initializer

```csharp
var player = Player
{
    Health = 100,
    Position = Vec2
    {
        X = 10,
        Y = 20
    }
};
```

Der Initializer schreibt direkt die Struct-Felder.

---

## 47. Keine Konstruktoren

Structs besitzen keine Konstruktoren.

Nicht vorgesehen:

```csharp
new Player(100, 20)
```

Stattdessen:

```csharp
Player
{
    Health = 100,
    Position = Vec2
    {
        X = 20,
        Y = 30
    }
}
```

Komplexere Initialisierung erfolgt über normale Funktionen:

```csharp
Player CreatePlayer(int health)
{
    return Player
    {
        Health = health
    };
}
```

---

## 48. Funktionen

Freie Funktionen können überladen werden:

```csharp
void Print(int value)
{
}

void Print(string value)
{
}

void Print(float value)
{
}
```

Der Compiler wählt anhand der Argumenttypen die passende Funktion.

Ein `static`-Schlüsselwort ist für freie Funktionen nicht erforderlich.

Structs können Methoden besitzen:

```csharp
struct Vec2
{
    float X;
    float Y;

    float Length()
    {
        return sqrt(X * X + Y * Y);
    }
}
```

---

## 49. Parameter

Parameter werden standardmäßig per Wert übergeben:

```csharp
void Process(Vec2 position)
{
}
```

Für explizite Aliase gibt es `ref`:

```csharp
void Move(ref Vec2 position)
{
    position.X += 1;
}
```

Aufruf:

```csharp
Move(ref position);
```

Zusätzlich gibt es `const ref` für einen schreibgeschützten Alias:

```csharp
float Length(const ref Vec2 value)
{
    return sqrt(value.X * value.X + value.Y * value.Y);
}
```

Die drei grundlegenden Formen sind damit:

```text
T           → Wertkopie
const ref T → schreibgeschützter Alias
ref T       → veränderbarer Alias
```

`const ref` übergibt keinen Wert und erzeugt keine Kopie. Die Funktion erhält lediglich einen Alias auf den vorhandenen Speicher.

Innerhalb der Funktion darf der referenzierte Wert nicht verändert werden.

`const ref` ist kein Ownership-Konzept.

---

## 50. Kein `out`

Die Sprache besitzt keine `out`-Parameter.

Nicht vorgesehen:

```csharp
bool TryParse(string text, out int value)
{
}
```

Stattdessen werden die eingebauten Ergebnis-Typen verwendet:

```csharp
Error<int> Parse(string text)
{
    ...
}
```

oder:

```csharp
Optional<int> Parse(string text)
{
    ...
}
```

Dadurch bleibt die Parametersemantik auf drei Fälle reduziert:

```text
Wert
const ref
ref
```

und Ergebniswerte werden über normale Rückgabewerte bzw. `Error<T>` und `Optional<T>` modelliert.
