# CShift for VS Code

Syntax highlighting, snippets and language settings for **CShift** (`.csh`), this repo's native, C#-like systems
language.

## Features

* Highlighting for keywords, types (`struct`/`interface`/`enum` names, generics, constraints, base lists), functions,
  numbers (hex, binary, `1_000`, suffixes `u L f d`), strings/chars with escapes, comments, `link "lib"`,
  `namespace`/`using`
* Built-in types and library classes: `Error<T>`, `Optional<T>`, `Console`, `Math`, `File`, `List`, `Dictionary`, …
* Private fields (`_name`) get their own scope (`variable.other.private`)
* Bracket pairs, auto-indent, toggling `//` and `/* */` comments, `// region` folding
* Snippets (`main`, `struct`, `fn`, `foreach`, `switch`, `try`, `ifis`, `dict`, …)

## Installation

```powershell
cd vscode-extension
npx @vscode/vsce package --allow-missing-repository --skip-license
code --install-extension cshift-0.3.0.vsix
```

Or copy the folder to `%USERPROFILE%\.vscode\extensions\pyrdacor.cshift-0.3.0` and restart VS Code.

## Testing the grammar

The grammar is a TextMate grammar (`syntaxes/cshift.tmLanguage.json`). In VS Code, *Developer: Inspect Editor Tokens
and Scopes* shows the scopes under the cursor.
