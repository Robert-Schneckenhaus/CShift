// Without a wildcard, embed_filenames checks that the file exists.
// expect-error: embed_filenames: cannot find the file 'embed/texts/missing.txt' (looked for

const string Name = embed_filenames("embed/texts/missing.txt");
