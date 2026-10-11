// Text as characters and bytes: a string or StringSlice converts to ReadOnlySlice<char> without a copy (a string
// prefers a StringSlice parameter), and AsBytes() is the same view as ReadOnlySlice<uint8> for functions that take
// bytes (FileStream.Write, File.WriteAllBytes).
// expect-exit: 0
// expect-stdout: vowels 5 2 0
// expect-stdout: last n d
// expect-stdout: overload slice slice chars
// expect-stdout: bytes 6 195 169 3
// expect-stdout: written héllo, wörld

using System;

int CountVowels(ReadOnlySlice<char> chars)
{
    int n = 0;
    foreach (var c in chars)
    {
        if (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u')
            n += 1;
    }
    return n;
}

T Last<T>(ReadOnlySlice<T> items)
{
    return items[items.Length - 1];
}

string Kind(StringSlice text) { return "slice"; }
string Kind(ReadOnlySlice<char> chars) { return "chars"; }

int Main()
{
    string word = "education";
    string nothing = null;
    Console.WriteLine("vowels " + CountVowels(word).ToString() + " " + CountVowels(word[3..7]).ToString() + " " +
                      CountVowels(nothing).ToString());
    Console.WriteLine("last " + Last<char>(word) + " " + Last<char>(word[..2]));
    ReadOnlySlice<char> chars = word;
    Console.WriteLine("overload " + Kind(word) + " " + Kind(word[1..]) + " " + Kind(chars));

    ReadOnlySlice<uint8> bytes = "héllo".AsBytes();
    StringSlice part = "a, b, c".Split(',')[1].Trim();
    Console.WriteLine("bytes " + bytes.Length.ToString() + " " + bytes[1].ToString() + " " + bytes[2].ToString() + " " +
                      ((int)part.AsBytes()[0] - 'a' + 2).ToString());

    string path = "text_as_chars.tmp";
    if (File.WriteAllBytes(path, "héllo, ".AsBytes()) is error)
        return 1;
    if (FileStream.Append(path) is FileStream stream)
    {
        if (stream.Write("ab wörld!"[3..9].AsBytes()) is error)
            return 2;
        stream.Close();
    }
    if (File.ReadAllText(path) is string text)
        Console.WriteLine("written " + text);
    File.Delete(path);
    return 0;
}
