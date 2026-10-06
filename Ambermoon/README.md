# Ambermoon tools in CShift

Ports of the command line tools of [Ambermoon](https://github.com/Pyrdacor/Ambermoon) (`AmbermoonTools`) and of the
parts of their libraries from [Ambermoon.net](https://github.com/Pyrdacor/Ambermoon.net) that they need. The tools
read and write the data files of the Amiga game Ambermoon.

| Folder | What it is | Port of |
|---|---|---|
| `Ambermoon.Common/` | library: directions, the texts of enums and floats as .NET writes them | `Ambermoon.Common` (parts) |
| `Ambermoon.Data.Common/` | library: the events of maps and characters, the enumerations they use | `Ambermoon.Data.Common` (parts) |
| `Ambermoon.Data.Legacy/` | library: big-endian readers and writers, the file formats (JH, LOB, VOL1, AMNC, AMNP, AMBR, AMPC), the LOB compressions, the events | `Ambermoon.Data.Legacy` (parts) |
| `Ambermoon.Data.Descriptions/` | library: descriptions of the values of all event types (for editors) | `AmbermoonTools/Ambermoon.Data.Descriptions` |
| `AmbermoonPack/` | packs files into the formats of the game and unpacks them | `AmbermoonTools/AmbermoonPack` |
| `AmbermoonEventEditor/` | edits the events of maps, NPCs and party members | `AmbermoonTools/AmbermoonEventEditor` |
| `tests/` | tests with expected results of the original tools | |

## Building

```
cshiftc build Ambermoon/AmbermoonPack          # -> Ambermoon/AmbermoonPack/bin/AmbermoonPack
cshiftc build Ambermoon/AmbermoonEventEditor   # -> Ambermoon/AmbermoonEventEditor/bin/AmbermoonEventEditor
```

The tools need a compiler from this repository (newer than 0.26): the event editor reads its commands with
`Console.ReadLine()`. `bash Ambermoon/tests/run.sh [path/to/cshiftc]` builds both tools and compares their results
with those of the original tools (`tests/run_tests.sh` runs it too).

## Usage

The command lines are the ones of the originals:

```
AmbermoonPack UNPACK 2Map_data.amb maps              # the files of a container as maps/001, maps/002, ...
AmbermoonPack AMPC maps 2Map_data.amb -c3 -v         # packs them again (best of three LOB compressions)
AmbermoonPack REPACK Monster_char.amb out.amb -c2    # a container in another compression
AmbermoonPack JH+LOB Dict Dict.amb 0xd2e7           # JH-encrypted LOB with the key 0xd2e7

AmbermoonEventEditor maps/258 0                      # the events of map 258 (0: map, 1: NPC, 2: party member)
```

## How the port was checked

* **AmbermoonPack**: UNPACK of all files of the game, and packing of all 65 unpacked containers and files with combinations of the
  compressions (`-c0` to `-c5`), the dictionary compressions (`-d1` to `-d4`) and all types: 491 runs, the files and
  the console output (`-v` included) are the same byte for byte as those of the original (built from the sources of
  Ambermoon.net).
* **AmbermoonEventEditor**: the listings of all maps, NPCs and party members, and 1200 random editing sessions (all
  commands, random answers, saved at the end): the output and the saved files are the same as those of the original
  (with the crashes of the original that are fixed here fixed the same way in it, see below).

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
