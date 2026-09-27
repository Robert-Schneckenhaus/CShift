// Without a wildcard, embed_filenames gives one name: a string.
// expect-error: embed_filenames("embed/empty.txt") gives a string, so the constant must be 'const string', not 'ReadOnlySlice<string>'

const ReadOnlySlice<string> Names = embed_filenames("embed/empty.txt");
