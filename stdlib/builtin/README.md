# The built-in types

The files in this folder declare the types, functions and namespaces that the compiler provides itself (`string`,
the numbers, arrays, slices, `Console`, `Thread`, ...), with their doc comments. They are not compiled: `cshiftc doc`
reads them for the reference ([docs/language/doc-comments.md](../../docs/language/doc-comments.md)), and the hover in
VS Code shows their comments for the built-in names. Static fields (`int.MaxValue`) are allowed only here.

When the compiler gets a new built-in member, declare it here as well.
