# CShift für VS Code

Syntax-Highlighting, Snippets und Spracheinstellungen für **CShift** (`.csh`), die native C#-artige Systemsprache dieses Repos.

## Funktionen

* Färbung von Schlüsselwörtern, Typen (`struct`/`interface`/`enum`-Namen, Generics, Constraints, Basislisten), Funktionen,
  Zahlen (Hex, Binär, `1_000`, Suffixe `u L f d`), Strings/Chars mit Escapes, Kommentaren, `link "lib"`, `namespace`/`using`
* Eingebaute Typen und Bibliotheksklassen: `Error<T>`, `Optional<T>`, `Console`, `Math`, `File`, `List`, `Dictionary`, …
* Private Felder (`_name`) bekommen einen eigenen Scope (`variable.other.private`)
* Klammer-Paare, Auto-Einrückung, `//`- und `/* */`-Kommentare umschalten, `// region`-Faltung
* Snippets (`main`, `struct`, `fn`, `foreach`, `switch`, `try`, `ifis`, `dict`, …)

## Installation

```powershell
cd vscode-extension
npx @vscode/vsce package --allow-missing-repository --skip-license
code --install-extension cshift-0.3.0.vsix
```

Oder den Ordner nach `%USERPROFILE%\.vscode\extensions\pyrdacor.cshift-0.3.0` kopieren und VS Code neu starten.

## Grammatik testen

Die Grammatik ist eine TextMate-Grammatik (`syntaxes/cshift.tmLanguage.json`). In VS Code zeigt
*Developer: Inspect Editor Tokens and Scopes* die Scopes unter dem Cursor.
