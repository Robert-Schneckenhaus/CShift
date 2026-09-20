CShift @VERSION@ (Linux, x86-64)
================================

Installation
------------
1. Dieses Archiv an einen festen Ort entpacken, z. B. nach ~/cshift:

       tar -xf cshift-@VERSION@-linux-x64.tar.xz -C ~

2. Den Ordner (in dem cshiftc liegt) zum PATH hinzufuegen, z. B. in ~/.bashrc:

       export PATH="$HOME/cshift-@VERSION@-linux-x64:$PATH"

3. Neue Shell oeffnen und pruefen:

       cshiftc --version
       cshiftc new hello
       cshiftc run hello

Voraussetzungen
---------------
Wie bei jedem C-Werkzeug kommen die C-Bibliothek und die Linker-Dateien vom System (Ubuntu/Debian):

    sudo apt install build-essential

(gcc-Startdateien, libc6-dev, binutils). Die von clang benoetigten Bibliotheken libedit, libxml2, libzstd, zlib und
libffi sind auf den meisten Systemen vorhanden; sonst:

    sudo apt install libedit2 libxml2 libzstd1 zlib1g libffi8

clang, libclang und die LLVM-Bibliotheken liegen im Ordner "toolchain" und werden von cshiftc selbst gefunden. Eine
vorhandene LLVM-Installation wird nicht benoetigt und nicht verwendet.

Inhalt
------
cshiftc        der Compiler
toolchain/     clang, libclang, LLVM-Bibliotheken (nicht veraendern)
README.md      Sprachstand, Benutzung, Projektdatei cshift.json
FFI.md         C-Header importieren (using Name from "header.h";), Funktionszeiger
Buildkonzept.md, Sprachkonzept.md

Eigene C-Bibliotheken: siehe FFI.md und die Schluessel includePaths/libraryPaths/links in cshift.json.
