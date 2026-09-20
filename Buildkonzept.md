# Projekte und Build

Das Sprachkonzept (§34) legt fest, *was* der Build erledigt (Kompilieren, Monomorphisierung, Optimieren, Linken, FFI, Bibliotheken),
aber nicht, *wie* man ein Projekt beschreibt. Dieses Dokument füllt die Lücke.

## Grundmodell

* Ein Programm besteht aus **allen** übergebenen `.csh`-Dateien; es gibt keine Header und keine Übersetzungseinheiten im C-Sinn.
  Der Compiler analysiert das ganze Programm auf einmal (Symbole werden global aufgelöst, Generics pro Typkombination erzeugt)
  und schreibt **eine** Objektdatei, die er anschließend linkt.
* Deshalb braucht ein Projekt im Kern nur: den Namen, die Quelldateien, das Ziel (Programm oder Objektdatei), die Optimierung
  und zusätzliche Bibliotheken.
* Inkrementelle Builds oder Abhängigkeiten zwischen Projekten gibt es (noch) nicht. Ein Rebuild ist bei der aktuellen
  Programmgröße schnell (Größenordnung 0,2 s).

## Stufe 1 (umgesetzt): deklarative Projektdatei `cshift.json`

```json
{
	"name": "demo",
	"version": "0.1.0",
	"type": "executable",
	"sources": ["src"],
	"output": "bin/demo",
	"optimize": 2,
	"links": ["sqlite3"],
	"target": "x86_64-w64-windows-gnu"
}
```

| Schlüssel | Bedeutung | Standard |
|---|---|---|
| `name` | Projektname (Buchstaben, Ziffern, `_ - .`); Pflicht | – |
| `version` | Version (nur Information) | – |
| `type` | `"executable"` (Programm linken) oder `"object"` (nur Objektdatei) | `"executable"` |
| `sources` | Liste aus Dateien und Ordnern; Ordner werden rekursiv nach `*.csh` durchsucht, Pfade relativ zur `cshift.json` | `["src"]` |
| `output` | Ausgabepfad ohne Endung (`.exe`/`.obj`/`.o` je nach Plattform ergänzt) | `"bin/<name>"` |
| `optimize` | 0–3 (wie `-O0` … `-O3`) | `2` |
| `links` | Bibliotheken für den Linker: Name (`-l<name>`) oder Datei (`libs/libminifb.a`, `x.o`, `x.lib`; Pfad oder Endung); zusätzlich zu `link "name"` im Quelltext | `[]` |
| `includePaths` | Suchpfade für C-Header (`using X from "h.h"`), relativ zur `cshift.json` | `[]` |
| `defines` | Makros beim Parsen von C-Headern (`NAME`, `NAME=wert`) | `[]` |
| `libraryPaths` | Suchpfade des Linkers (`-L`) | `[]` |
| `target` | Target-Triple | Host |

Unbekannte Schlüssel erzeugen eine Warnung, falsche Werte einen Fehler mit Dateinamen. `$schema` ist erlaubt; die VS-Code-Extension
liefert ein Schema mit, das `cshift.json` automatisch validiert und vervollständigt.

### Befehle

```
cshiftc new <ordner>           neues Projekt (cshift.json, src/main.csh, .gitignore)
cshiftc build [projekt]        bauen
cshiftc run   [projekt]        bauen und starten
cshiftc [Optionen] a.csh b.csh Einzeldateien ohne Projekt (wie bisher)
```

`projekt` ist ein Ordner mit `cshift.json` oder der Pfad zur Datei. Ohne Angabe wird `cshift.json` im aktuellen Ordner und in
den Elternordnern gesucht. Optionen der Kommandozeile (`-O2`, `--target`, `-o`, `--cc`, `-l…`, `-v`) überschreiben die Datei.

### Warum JSON?

* **Kein Code nötig**, um das Projekt zu lesen: Der Compiler versteht es direkt (LLVM bringt einen JSON-Parser mit, es entsteht
  keine neue Abhängigkeit). Bei YAML müsste ein Parser mitgebracht werden, Makefiles sind plattformabhängig und für ein
  Ein-Programm-Modell zu mächtig.
* **Editor-Unterstützung** über JSON-Schema (Vervollständigung, Fehler beim Tippen).
* Als reines Datenmodell ist es später auch das Zwischenformat für Stufe 2.

## Stufe 2 (Idee): Build in der Sprache selbst, wie bei Zig

Für Fälle, die eine Datei nicht ausdrücken kann (bedingte Quellen je Plattform, Codegenerierung vor dem Build, mehrere Ziele,
Abhängigkeiten, Tests), liegt neben oder statt der `cshift.json` eine `build.csh`:

```csharp
using System.Build;

Error<void> Build(ref Builder b)
{
    var exe = b.AddExecutable("demo");
    exe.AddSources("src");
    exe.Link("sqlite3");
    exe.SetOptimize(2);

    if (b.Target().IsWindows())
        exe.AddSources("platform/windows");

    var tests = b.AddExecutable("demo-tests");
    tests.AddSources("src", "tests");
    b.AddRunStep("test", tests);
    return;
}
```

So würde es funktionieren:

1. `cshiftc build` findet eine `build.csh` und übersetzt sie **zusammen mit der Standardbibliothek und einem kleinen
   `System.Build`-Modul** zu einem temporären Programm.
2. Dieses Programm wird ausgeführt; `Build(...)` beschreibt die Ziele. Das Ergebnis ist genau das Datenmodell aus Stufe 1
   (also eine oder mehrere Projektbeschreibungen mit denselben Feldern), das der Compiler anschließend baut.
3. Die Sprache selbst ist die Skriptsprache; es gibt kein zweites Format zu lernen.

Voraussetzungen, die dafür noch fehlen: `Process`/`Environment`-Funktionen in der Standardbibliothek (Umgebungsvariablen, Programme
starten, Plattformabfrage), ein Zwischenformat zwischen Build-Programm und Compiler (dafür ist das JSON-Schema gedacht),
Kommandozeilenargumente (`Main(string[] args)`), sowie Schritte mit Namen (`cshiftc build test`). Bis dahin bleibt `cshift.json` der
Standardweg; Stufe 2 ersetzt ihn nicht, sondern ergänzt ihn für Sonderfälle.

## Offene Punkte

* Mehrere Ziele in einer `cshift.json` (z. B. Programm + Tests), `cshiftc test`.
* Abhängigkeiten zwischen Projekten und Paketen (Quellordner anderer Projekte einbinden).
* Zwischenverzeichnis `obj/`, inkrementelle Builds (erst sinnvoll bei getrennten Übersetzungseinheiten).
* Variablen/Bedingungen in der Projektdatei (`"sources"` je Plattform) – oder gleich über `build.csh`.
