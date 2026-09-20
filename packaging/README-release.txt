CShift @VERSION@ (Windows, 64 Bit)
==================================

Installation
------------
1. Diesen Ordner an einen festen Ort entpacken, z. B. C:\Tools\cshift.
2. Den Ordner (in dem cshiftc.exe liegt) zum PATH hinzufuegen.
3. Neue Konsole oeffnen und pruefen:

       cshiftc --version
       cshiftc new hello
       cshiftc run hello

Mehr ist nicht noetig: Der Ordner "toolchain" enthaelt clang, lld, libclang sowie die C-Header und -Bibliotheken
(MinGW-w64), die cshiftc zum Linken und fuer "using Name from "header.h";" braucht. cshiftc findet sie selbst.
Eine vorhandene Installation (MSYS2, LLVM, Visual Studio) wird nicht benoetigt und nicht verwendet.

Inhalt
------
cshiftc.exe    der Compiler
toolchain\     clang/lld/libclang, Header und Bibliotheken (nicht veraendern)
README.md      Sprachstand, Benutzung, Projektdatei cshift.json
FFI.md         C-Header importieren (using Name from "header.h";), Funktionszeiger
Buildkonzept.md, Sprachkonzept.md

Eigene C-Bibliotheken: siehe FFI.md und die Schluessel includePaths/libraryPaths/links in cshift.json.
VS-Code-Extension (Syntax-Highlighting): Ordner vscode-extension im Repository.
