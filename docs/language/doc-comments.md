# Doc comments

A comment with three slashes (`///`) documents the declaration that follows it. The VS Code extension shows it in
the hover, and `cshiftc doc` writes it into the documentation as JSON (the reference of the standard library is made
from it).

````csharp
/// A growable array.
///
/// A `List` is a small handle to shared storage: copies see the same elements. Start lists with
/// [List<T>.Create] before you hand them out.
///
/// ```
/// var names = List<string>.Create();
/// names.Add("Ann");
/// ```
struct List<T>
{
    /// Inserts `value` before the element at `index`; `index == Count()` appends.
    ///
    /// @param index  0 to `Count()`.
    /// @param value  the element to insert.
    /// @panics       when `index` is out of range.
    /// @since 0.22
    void Insert(int index, T value) { ... }
}
````

Everything that has a name can have a doc comment: structs, interfaces, unions, enums and error enums and their
values, fields, methods, functions, constants and global variables. A comment with four slashes (`////`) is an
ordinary comment again.

`//!` documents the namespace of the file (in the standard library: the introduction of the namespace's page). The
`//!` comments of all files of a namespace are put together.

## The text

The text is Markdown. Its **first sentence** is the summary: it is shown in lists and in search results. Code blocks
(```` ``` ````) without a language are CShift code.

`[Name]` links to another declaration: `[List]`, `[List<T>.Add]`, `[File.ReadAllText]`, `[System.Math]`, also with
the namespace. Type arguments do not matter (`[List<T>.Add]` is `[List.Add]`). A link that `cshiftc doc` cannot find
is an error. Brackets in code (`` `a[0]` ``) and Markdown links (`[text](url)`) are not links.

## Tags

A line that starts with `@` is a tag; the lines after it (up to an empty line or the next tag) continue it.

| Tag | Meaning |
|---|---|
| `@param name text` | a parameter; the name must be one of the function's parameters |
| `@returns text` | the result |
| `@error E.Case text` | an error the function returns (for `T!` and error enums, e.g. `@error IoError.CannotOpen`); the value must exist |
| `@panics text` | when the function ends the program with a panic |
| `@since 0.22` | the version that added the declaration |
| `@deprecated text` | the declaration should not be used any more |
| `@see [Name] text` | a related declaration |
| `@internal` | not part of the documentation (plumbing that has to be public) |

Other tags are errors.

## What is documented

Declarations whose name starts with `_` are private and are not documented, nor is anything marked `@internal`.
`extern "C"` functions (declarations of C functions, and functions that implement one for the C runtime) are left
out unless they have a doc comment, and so is `Main`. A namespace is listed when it has documented declarations or a
`//!` comment.

## cshiftc doc

```
cshiftc doc                         the standard library (the one built into cshiftc, or --stdlib <dir>)
cshiftc doc [project | files]       the declarations of a program or a library
    --require-docs                  every documented declaration needs a doc comment (an error otherwise)
    -o <file>                       write the JSON to a file instead of stdout
```

It checks the doc comments (unknown tags, `@param` names, links, `@error` values) and ends with exit code 1 if one
is wrong. The JSON has the namespaces and the declarations, each with its kind, name, signature, file and line, its
members, and its doc comment split into summary, description and tags:

```json
{"version": "0.22",
 "namespaces": [{"name": "System", "doc": {"summary": "...", ...}}],
 "items": [
  {"kind": "struct", "name": "List", "signature": "struct List<T>", "file": "list.csh", "line": 20,
   "namespace": "System", "doc": {...}, "members": [
     {"kind": "method", "name": "Insert", "signature": "void Insert(int index, T value)", "static": false,
      "file": "list.csh", "line": 82,
      "doc": {"summary": "Inserts `value` before the element at `index`; `index == Count()` appends.",
              "description": "...", "params": [{"name": "index", "text": "0 to `Count()`."}, ...],
              "returns": "", "errors": [], "panics": "when `index` is out of range.", "since": "0.22",
              "deprecated": "", "see": []}}]}]}
```

The kinds are `struct`, `interface`, `enum`, `error`, `union`, `function`, `const` and `global`; members are
`field`, `method` and (of enums) `value`. A declaration without a doc comment has `"doc": null`. Constants have their
`value` (numbers, bools and short strings), enum values theirs.
