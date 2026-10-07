# Ambermoon tools in CShift

Ports of the command line tools of [Ambermoon](https://github.com/Pyrdacor/Ambermoon) (`AmbermoonTools`) and of the
parts of their libraries from [Ambermoon.net](https://github.com/Pyrdacor/Ambermoon.net) that they need. The tools
read and write the data files of the Amiga game Ambermoon.

| Folder | What it is | Port of |
|---|---|---|
| `Ambermoon.Common/` | library: directions, the texts of enums and floats as .NET writes them, numbers, files and texts read as .NET reads them | `Ambermoon.Common` (parts) |
| `Ambermoon.Data.Common/` | library: events, maps, tilesets, characters, items, graphics, texts and the enumerations they use | `Ambermoon.Data.Common` (parts) |
| `Ambermoon.Data.Legacy/` | library: big-endian readers and writers, the file formats (JH, LOB, VOL1, AMNC, AMNP, AMBR, AMPC), the LOB compressions, loading the game data from folders and ADF disk images, Amiga executables (also imploded), the data of the executable (names, messages, items, ...), Text.amb, maps, characters, events | `Ambermoon.Data.Legacy` (parts) |
| `Ambermoon.Data.Descriptions/` | library: descriptions of the values of all event types (for editors) | `AmbermoonTools/Ambermoon.Data.Descriptions` |
| `AmbermoonTextPacks/` | library: the intro and extro text packs of the remake (shared by the three text pack tools) | the packing code of the text packers |
| `AmbermoonPack/` | packs files into the formats of the game and unpacks them | `AmbermoonTools/AmbermoonPack` |
| `AmbermoonEventEditor/` | edits the events of maps, NPCs and party members | `AmbermoonTools/AmbermoonEventEditor` |
| `HexValueChanger/` | changes bytes at an offset in one or many files | `AmbermoonTools/HexValueChanger` |
| `AmbermoonDiskExtract/` | extracts the files of the game from its ADF disk images | `AmbermoonTools/AmbermoonDiskExtract` |
| `AmbermoonListExtractor/` | writes the party members of the game as a Markdown table | `AmbermoonTools/AmbermoonListExtractor` |
| `AmbermoonIntroTextPacker/` | packs the intro texts of a translation into `Intro_texts.amb` | `AmbermoonTools/AmbermoonIntroTextPacker` |
| `AmbermoonExtroTextPacker/` | packs the extro texts of a translation into `Extro_texts.amb` | `AmbermoonTools/AmbermoonExtroTextPacker` |
| `AmbermoonExtroIntroTextPackCreator/` | makes both text packs of a language from the texts in the Ambermoon repository | `AmbermoonTools/AmbermoonExtroIntroTextPackCreator` |
| `tests/` | tests with expected results of the original tools | |

## Building

```
cshiftc build Ambermoon/AmbermoonPack          # -> Ambermoon/AmbermoonPack/bin/AmbermoonPack
cshiftc build Ambermoon/AmbermoonEventEditor   # -> Ambermoon/AmbermoonEventEditor/bin/AmbermoonEventEditor
```

and the same for the other tools. They need a compiler from this repository (newer than 0.26): the event editor and
HexValueChanger read their commands with `Console.ReadLine()`, and the extro text packer needs a fix of conditional
expressions. `bash Ambermoon/tests/run.sh [path/to/cshiftc]` builds all tools and compares their results with those
of the original tools (`tests/run_tests.sh` runs it too).

## Usage

The command lines are the ones of the originals:

```
AmbermoonPack UNPACK 2Map_data.amb maps              # the files of a container as maps/001, maps/002, ...
AmbermoonPack AMPC maps 2Map_data.amb -c3 -v         # packs them again (best of three LOB compressions)
AmbermoonPack REPACK Monster_char.amb out.amb -c2    # a container in another compression
AmbermoonPack JH+LOB Dict Dict.amb 0xd2e7           # JH-encrypted LOB with the key 0xd2e7

AmbermoonEventEditor maps/258 0                      # the events of map 258 (0: map, 1: NPC, 2: party member)

HexValueChanger -r saves '*.sav'                     # the same bytes changed in all files *.sav below saves/
AmbermoonIntroTextPacker Czech                       # Czech/IntroTexts/*.txt -> Czech/Intro_texts.amb
AmbermoonExtroTextPacker Czech "<KLIK>" "DANIEL ZIMA"  # Czech/ExtroTextGroups/ -> Czech/Extro_texts.amb
AmbermoonExtroIntroTextPackCreator czech 1.00 out    # in the Ambermoon repository: out/Intro_texts.amb, out/Extro_texts.amb
AmbermoonDiskExtract adfs extracted                 # the files of the ADF images in adfs/ (-u: decompressed)
AmbermoonListExtractor Amberfiles lists              # lists/PartyMembers.md
```

## How the port was checked

* **AmbermoonPack**: UNPACK of all files of the game, and packing of all 65 unpacked containers and files with combinations of the
  compressions (`-c0` to `-c5`), the dictionary compressions (`-d1` to `-d4`) and all types: 491 runs, the files and
  the console output (`-v` included) are the same byte for byte as those of the original (built from the sources of
  Ambermoon.net).
* **AmbermoonEventEditor**: the listings of all maps, NPCs and party members, and 1200 random editing sessions (all
  commands, random answers, saved at the end): the output and the saved files are the same as those of the original
  (with the crashes of the original that are fixed here fixed the same way in it, see below).
* **The text pack tools**: the packs of all translations in the Ambermoon repository (Czech, English, Polish; with
  their translators and click texts), and texts in all encodings that .NET reads (byte order marks of UTF-8, UTF-16
  and UTF-32, invalid UTF-8): the same files and output as the originals.
* **HexValueChanger**: sessions with all commands on one file and on file patterns, also recursive.
* **The game data** (loading, ADF images, imploded executables, the data of the executable, Text.amb): everything
  that is read (files, names, messages, texts, glyphs, cursors, palettes, user interface graphics, buttons, items)
  is the same as in the original for English 1.07 (the old executable) and 1.20 and German 1.20, extracted and as ADF
  images. Loading is about 20 times faster.
* **AmbermoonDiskExtract**: the files of the ADF images of English 1.07 and 1.20 and German 1.20, encoded and
  decompressed (see below for the three files that differ); 300 times faster (the original recompresses with its slow
  LOB compression).
* **AmbermoonListExtractor**: the party members of English and German 1.20 (extracted and ADF).

## Different from the original

The output is the same (the texts of .NET included: enum names, `[Flags]` combinations, the rounding of `0.00`
formats). What is different:

**Faster.** The match trie of the LOB compressions is the same algorithm, but stored in arrays and a hash table
instead of objects and sorted dictionaries, and without the copy of all nodes at every byte that the original makes
when it removes old matches. Packing is 60 to 300 times faster:

| | original | CShift |
|---|---|---|
| `AMNP 1Map_data.amb -c0` | 134 s | 0.44 s |
| `AMNP Monster_gfx.amb -c0` | 55 s | 0.16 s |
| `AMNP Music.amb -c2` | 11.7 s | 0.19 s |
| `AMNP 2Wall3D.amb -c1` | 11.1 s | 0.13 s |
| `UNPACK 1Map_data.amb` | 0.11 s | 0.02 s |

**Fixed failures of the original** (it ends with an exception in these cases):

* AmbermoonPack: `JH+AMBR` packs (with a key like `JH`), and `REPACK` of JH+AMBR files works; the original fails with
  "File type 'JHPlusAMBR' is no valid container format". Extended LOB (`-c1`) of exactly 256 literals at the start.
  `UNITEM` of a file without file 1, `PKITEM` of a folder without numbered files, empty arguments. Damaged files give
  an error message (in the original some cases end with an exception). UNITEM unpacks in memory (the original leaves a
  temporary folder behind).
* AmbermoonEventEditor: maps with a ChangeBuffs event for all buffs (maps 296 and 403: the original cannot list them;
  this shows "All"); `connect` with an index outside of the events; `edit` with a new event type that is aborted;
  `reorder`, `copychain` and `graph` with branches to indices outside of the events; chains that are loops (`chain`,
  `remove`); "Make the successor the new chain start" for an event without a successor (only offered when there is
  one); files that are too short; the end of the input (ends the program).
* HexValueChanger: the documented inputs that did nothing work: Enter keeps a byte, `~` inverts it (the original
  rejects both as invalid), and an invalid length is 1 as the message says (the original then asks for no byte). A
  mask that is out of range is asked again without applying the operation to the next value. Bytes behind the end of
  a file (or before its start) are left out with a message (the original ends with an exception, also when only one
  of several files is too short). A file or folder that does not exist gives an error message; the end of the input
  ends the program (the original asks for the offset again forever).
* The text packers: file and folder names without a number give an error message (the original ends with an
  exception).
* AmbermoonExtroIntroTextPackCreator: an output folder given as a relative path is written (the original changes the
  current folder to its temporary folder first, so the files end up there and are deleted with it). The usage line
  names the tool (the original says "AmbermoonReleaseCreator"). Missing source folders or files give an error message.

* AmbermoonDiskExtract writes the files that are on the disks. The original writes `2Wall3D.amb`, `2Object3D.amb`
  and `3Object3D.amb` changed: when it loads the game data, it loads the labyrinths, which merges the textures of
  `3Wall3D.amb` and `3Object3D.amb` into the containers of `2Wall3D.amb` and `2Object3D.amb` and moves the positions
  of readers that it then writes from. Without a destination folder the files are written into the current folder (the
  original writes them into the folder of the program).
* AmbermoonListExtractor: game data without a party member's map character gives an error message (English 1.07: the
  original ends with an exception). The original does not compile with the current library (it uses
  `NumberOfFreeHands`, now `NumberOfOccupiedHands`).
* Damaged ADF images and data give error messages where the original ends with an exception (the French 1.17 images
  in the Ambermoon repository have a damaged `2Object3D.amb`: both fail).

**Faster and simpler.** AmbermoonExtroIntroTextPackCreator packs the texts itself (with `AmbermoonTextPacks`): the
original copies them into a temporary folder in the layout of the packers, builds both packers with `dotnet publish`
and runs them. The texts and the packs are the same; translator names are passed as they are (the original quotes
them for a command line, which breaks names with quotes).

The game data is loaded when it is needed: `GameData` loads the files (from the folder or the ADF images), and the
parts are made from them on demand (`ExecutableData.FromGameData`, `MapManager.Create`, maps by `GetMap`). The
original makes all parts when it loads the data (graphics, all maps and labyrinths, songs, the intro and extro, ...).

**Small differences.**

* AmbermoonPack sorts file names byte by byte; the original uses the sort order of the current culture (this only
  matters for names that are not numbers, in different case). A type is a name in capitals or a number (the original
  also takes lists like "LOB,AMBR").
* The library: `DataReader` and `DataWriter` are values (passed as `ref`); reading past the end gives zeros and sets
  `Overrun()` instead of throwing. `FileWriter.WriteJH` does not encrypt the caller's array in place. Events are a union
  of the event kinds in an `EventStore` with ids instead of objects with references.

Kept as in the original (it is what the original does, not a failure): the descriptions use a display mapping only the
first time a value is shown (the original sets it to null "to avoid recursive loops" and never back), display names
that the editor changes stay changed, and JH+LOB always uses the LOB of the original game.
