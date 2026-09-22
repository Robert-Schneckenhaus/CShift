// EmbedText / EmbedNames / EmbedTexts: files are read when the program is compiled (paths relative to this file).
// expect-exit: 0
// expect-stdout: names: a.txt b.txt
// expect-stdout: text: first file|line two|
// expect-stdout: second
int Main()
{
    string[] names = EmbedNames("embed_data", ".txt");
    string[] texts = EmbedTexts("embed_data", ".txt");
    string all = "";
    foreach (var n in names)
        all += " " + n;
    Console.WriteLine("names:" + all);
    Console.WriteLine("text: " + EmbedText("embed_data/a.txt").Replace("\n", "|"));
    Console.WriteLine(texts[1]);
    if (names.Length != 2 || texts.Length != 2)
        return 1;
    return 0;
}
