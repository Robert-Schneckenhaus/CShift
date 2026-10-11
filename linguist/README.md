# CShift in GitHub Linguist (draft)

A draft for adding CShift to [GitHub Linguist](https://github.com/github-linguist/linguist), the library behind the
language statistics and the highlighting on GitHub. **Nothing of this is submitted yet**: Linguist only accepts
languages that are already widely used on GitHub (see [what is missing](#what-is-missing)). Until then the repository's
`.gitattributes` counts CShift as C# (`*.cshift linguist-language=C#`).

| File | For Linguist |
|---|---|
| [languages.yml](languages.yml) | the entry for `lib/linguist/languages.yml` |
| [samples/CShift/](samples/CShift) | the samples for `samples/CShift/` (real code of this repository, MIT) |

The grammar (`tm_scope: source.cshift`) is the one of the VS Code extension
([vscode-extension/syntaxes](../vscode-extension/syntaxes/cshift.tmLanguage.json)), published on its own for
`script/add-grammar` as [cshift-grammar](https://github.com/Robert-Schneckenhaus/cshift-grammar) (MIT).

## The extension: .cshift

CShift files end in `.cshift`, an extension that no other language uses (none in Linguist, no files on GitHub before
CShift). So Linguist needs no heuristic for it, and GitHub Search counts CShift files exactly (`extension:cshift`).

Until 0.31 the extension was `.csh`, which Linguist gives to **Tcsh** (the C shell); the compiler still reads it. A
heuristic that told the two apart by their content was tried first: on 111 C shell scripts from GitHub it took none for
CShift, and it recognized 533 of 536 CShift files. Editors, syntax highlighters and `file` would still have taken
`.csh` for the C shell, though, and GitHub Search could not have counted CShift files by their extension, so the
extension was changed instead. The compiler's own sources (`selfhost/src`) keep `.csh` until the release that builds
them (stage 0) reads `.cshift`.

## What is missing

1. **Usage on GitHub (the main obstacle).** Linguist requires *at least 2000 files with the extension indexed by
   GitHub Search in the last year*, excluding forks, *with a reasonable distribution across unique `:user/:repo`
   combinations*; files of the language owner may be filtered out (`-user:...`). The count is `extension:cshift` in
   GitHub Search. Linguist closes pull requests for languages below the threshold.
2. Adding the grammar ([cshift-grammar](https://github.com/Robert-Schneckenhaus/cshift-grammar), MIT, one of the
   [allowed licenses](https://github.com/github-linguist/linguist/blob/main/vendor/README.md)) in the pull request:
   `script/add-grammar https://github.com/Robert-Schneckenhaus/cshift-grammar`.
3. `language_id` (assigned by `script/update-ids`) and the color checked by Linguist's tests (`#391ab2` was chosen as
   far as possible from the colors of the other languages).
4. The pull request itself: the entry, the samples (their license stated: MIT, from this repository),
   `bundle exec rake test`, and the GitHub search link that shows the usage.
