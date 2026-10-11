# CShift in GitHub Linguist (draft)

A draft for adding CShift to [GitHub Linguist](https://github.com/github-linguist/linguist), the library behind the
language statistics and the highlighting on GitHub. **Nothing of this is submitted yet**: Linguist only accepts
languages that are already widely used on GitHub (see [what is missing](#what-is-missing)). Until then the repository's
`.gitattributes` counts `.csh` files as C# (`*.csh linguist-language=C#`).

| File | For Linguist |
|---|---|
| [languages.yml](languages.yml) | the entry for `lib/linguist/languages.yml` |
| [heuristics.yml](heuristics.yml) | the rule for `lib/linguist/heuristics.yml` that tells CShift from the C shell |
| [samples/CShift/](samples/CShift) | the samples for `samples/CShift/` (real code of this repository, MIT) |
| [evaluate.py](evaluate.py) | measures the heuristic (below) |

The grammar (`tm_scope: source.cshift`) is the one of the VS Code extension
([vscode-extension/syntaxes](../vscode-extension/syntaxes/cshift.tmLanguage.json)), published on its own for
`script/add-grammar` as [cshift-grammar](https://github.com/Robert-Schneckenhaus/cshift-grammar) (MIT).

## .csh is the C shell's

In Linguist, `.csh` belongs to **Tcsh** (the C shell, `tm_scope: source.shell`). Without a rule, every CShift file
on GitHub counts as a shell script. A second language for an extension needs

* a rule in `heuristics.yml` that decides between them by the content ([heuristics.yml](heuristics.yml)),
* at least two samples of **each** language with that extension: Linguist has one Tcsh sample
  (`samples/Tcsh/regtest_nmmnest.csh`), so the pull request has to add a second one (a real C shell script under a
  free license).

A file with a shebang (`#!/bin/csh`, `#!/bin/tcsh`) is decided by its interpreter before any heuristic, so only `.csh`
files without one reach the rule.

### The rule

A `.csh` file is CShift if a line starts like a declaration of a C#-like language, which the C shell does not have:

| Pattern | Example |
|---|---|
| a file-scoped namespace | `namespace Game.Map;` |
| `using` of a namespace | `using System;` |
| the import of a C header | `using Gl from "GL/gl.h";` |
| a type declaration | `struct Vec2 {`, `interface IShape`, `union Shape : IShape`, `error FileError`, `struct List<T>` |
| a constant | `const int Size = 16;` |
| the entry point | `int Main(`, `void Main(` |
| a function definition alone on its line | `static Mat4 Identity()` |

Everything else stays Tcsh (the rule without a pattern).

### How reliable it is

Measured with [evaluate.py](evaluate.py) on 2026-10-11 (the C shell scripts as stored in git, line ends `\n`):

| Corpus | Files | Taken as CShift |
|---|---|---|
| C shell scripts: 110 `.csh` files from GitHub code search (queries `setenv`, `foreach`, `endif`, `echo` with `extension:csh`, 40 repositories, among them ENCODE-DCC/kentUtils, DOI-USGS/COAWST, YottaDB/YDBTest) and Linguist's Tcsh sample | 111 | **0** (no false positive) |
| all `.csh` files of this repository (stdlib, compiler, tests, demos) | 536 | **533** (99.4 %) |

The three files it misses are unusual for CShift: two declare the built-in types (`struct int32`, lowercase names) and
one holds only a global variable (`int First = Second + 1;`). With patterns for those the rule would start to look at
shell-like lines (an assignment), so they are left out on purpose: a CShift file that only has such lines falls back to
Tcsh.

Limits of the measurement:

* the C shell corpus comes from search queries for C shell words, so scripts that use few of them are fewer in it.
  The patterns describe lines that the C shell does not have (`namespace X;`, `using X;`, `struct X {`,
  `const T x =`, a type and a name before `(`); the riskiest is the function pattern, which a csh line could only
  match as a command of two words with parentheses after them, alone on its line;
* the CShift corpus is code of one author; code by others may use other styles (but the patterns only need one line);
* Linguist compiles the patterns as Ruby regular expressions; they use nothing that Ruby and Python treat differently
  (`^`/`$` are line based in Ruby, `re.M` in the script).

To measure again: put C shell scripts into a folder and run `python -I linguist/evaluate.py <folder> .`.

## What is missing

1. **Usage on GitHub (the main obstacle).** Linguist requires *at least 2000 files with the extension indexed by
   GitHub Search in the last year*, excluding forks, *with a reasonable distribution across unique `:user/:repo`
   combinations*; files of the language owner may be filtered out (`-user:...`). On 2026-10-11 GitHub Search found 128
   files for `"using System;" extension:csh` and 445 for `"int Main(" extension:csh`, almost all in one repository
   (Pyrdacor/Ambermoon, whose tools are written in CShift); this repository was not in the index. Linguist closes
   pull requests for languages below the threshold.
2. A second **Tcsh sample** (see above).
3. Adding the grammar ([cshift-grammar](https://github.com/Robert-Schneckenhaus/cshift-grammar), MIT, one of the
   [allowed licenses](https://github.com/github-linguist/linguist/blob/main/vendor/README.md)) in the pull request:
   `script/add-grammar https://github.com/Robert-Schneckenhaus/cshift-grammar`.
4. `language_id` (assigned by `script/update-ids`) and the color checked by Linguist's tests (`#391ab2` was chosen as
   far as possible from the colors of the other languages).
5. The pull request itself: the entry, the heuristic, the samples (their license stated: MIT, from this repository),
   `bundle exec rake test`, and the GitHub search link that shows the usage.
