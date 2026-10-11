// Standard library: what works for strings works for string slices too - Equals/GetHashCode/CompareTo (keys of a
// Dictionary, sorting), '+', CStr(), and the functions that take paths (File, Directory, Path, streams).
// Main returns the number of failed checks; the ARC check makes sure that the copies of CStr() are released.
// expect-exit: 0

using System;
using System.Native;

extern "C" nuint strlen(char* text);

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

int Main()
{
    int f = 0;

    // ---- IEquatable, IHashable, IComparable ----
    string text = "pear apple fig apple pear apple";
    var counts = Dictionary<StringSlice, int>.Create();
    foreach (var word in text.Split(' '))
        counts[word] = counts.GetOrDefault(word, 0) + 1;
    f += Check("Dictionary<StringSlice, int>", counts.Count() == 3 && counts["apple"] == 3 && counts["pear"] == 2);
    f += Check("hash of a slice and a string", "fig".GetHashCode() == text[11..14].GetHashCode());
    f += Check("Equals", text[0..4].Equals("pear") && !text[0..4].Equals(text[5..10]));

    var words = List<StringSlice>.Create();
    foreach (var word in "b c a".Split(' '))
        words.Add(word);
    words.Sort();
    f += Check("Sort", words[0] == "a" && words[1] == "b" && words[2] == "c");
    f += Check("CompareTo", text[5..10].CompareTo(text[0..4]) < 0 && text[0..4].CompareTo("pear") == 0);
    var set = HashSet<StringSlice>.Create();
    foreach (var word in text.Split(' '))
        set.Add(word);
    f += Check("HashSet<StringSlice>", set.Count() == 3 && set.Contains("fig"));

    // ---- '+' ----
    StringSlice first = text[0..4];
    StringSlice second = text[5..10];
    f += Check("slice + slice", first + second == "pearapple");
    f += Check("slice + number", first + 2 == "pear2");

    // ---- CStr: as it is up to the end of the string, else a copy ----
    unsafe
    {
        f += Check("CStr at the end", string.FromCStr(text[26..].CStr()) == "apple");
        f += Check("CStr in the middle", string.FromCStr(text[5..10].CStr()) == "apple");
        f += Check("CStr of an empty slice", string.FromCStr(text[3..3].CStr()) == "");
        StringSlice none = null;
        f += Check("CStr of null", string.FromCStr(none.CStr()) == "");
        string nothing = null;
        StringSlice fromNull = nothing;
        f += Check("CStr of a null string", string.FromCStr(fromNull.CStr()) == "");
        f += Check("CStr in a call", strlen(" x ".Trim().CStr()) == 1);
    }

    // ---- paths ----
    string line = "  cshift_slice_test.tmp  ";
    StringSlice path = line.Trim();
    File.Delete(path);
    f += Check("File.Exists (missing)", !File.Exists(path));
    f += Check("File.WriteAllText", !(File.WriteAllText(path, text[0..10]) is error));
    f += Check("File.Exists", File.Exists(path));
    f += Check("File.ReadAllText", File.ReadAllText(path) is string read && read == "pear apple");
    f += Check("Path.GetExtension", Path.GetExtension(path) == ".tmp");
    f += Check("Path.ChangeExtension", Path.ChangeExtension(path, "txt") == "cshift_slice_test.txt");
    f += Check("Path.Combine", Path.Combine(line[..2].Trim(), path) == "cshift_slice_test.tmp");
    if (StreamReader.Open(path) is StreamReader reader)
    {
        f += Check("StreamReader.Open", reader.ReadLine() is string l && l == "pear apple");
        reader.Close();
    }
    else
        f += Check("StreamReader.Open", false);
    f += Check("File.Delete", !(File.Delete(path) is error) && !File.Exists(path));
    f += Check("Directory.Exists", Directory.Exists(" . ".Trim()));
    f += Check("Process.GetEnv", Process.GetEnv("CSHIFT_NO_SUCH_VARIABLE x".Split(' ')[0]) == null);
    return f;
}
