// Standard library: File and Encoding. The program runs in a temporary directory.
// Main returns the number of failed checks.
// expect-exit: 0

using System;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

// Checks that an Error<void> result reports success.
int Succeeded(string name, Error<void> result)
{
    if (result)
        return 0;
    Console.WriteLine("FAIL: " + name + ": " + result.Message);
    return 1;
}

int Main()
{
    int f = 0;
    string path = "cshift_stdlib_test.tmp";

    File.Delete(path); // result ignored: the file usually does not exist
    f += Check("Exists (missing)", !File.Exists(path));

    // ---- text ----
    string content = "Hello, Wörld!\nLine 2\n";
    f += Succeeded("WriteAllText", File.WriteAllText(path, content));
    f += Check("Exists", File.Exists(path));
    if (File.ReadAllText(path) is string text)
        f += Check("ReadAllText", text == content);
    else
        f += 1;

    // ---- bytes ----
    if (File.ReadAllBytes(path) is uint8[] bytes)
        f += Check("ReadAllBytes", bytes.Length == 22 && bytes[0] == 72 && bytes[8] == 0xC3 && bytes[9] == 0xB6 && bytes[21] == 10);
    else
        f += 1;

    // ---- overwrite with something shorter ----
    f += Succeeded("overwrite", File.WriteAllText(path, "short"));
    if (File.ReadAllText(path) is string shorter)
        f += Check("overwritten", shorter == "short");
    else
        f += 1;

    // ---- binary data larger than the read buffer ----
    var data = new uint8[100000];
    for (var i = 0; i < data.Length; i += 1)
        data[i] = (uint8)(i % 251);
    f += Succeeded("WriteAllBytes big", File.WriteAllBytes(path, data));
    if (File.ReadAllBytes(path) is uint8[] readBack)
    {
        bool same = readBack.Length == 100000;
        for (var i = 0; same && i < data.Length; i += 1)
            same = readBack[i] == data[i];
        f += Check("binary round trip", same);
    }
    else
        f += 1;

    // ---- empty file ----
    f += Succeeded("write empty", File.WriteAllBytes(path, new uint8[0]));
    if (File.ReadAllBytes(path) is uint8[] empty)
        f += Check("read empty bytes", empty.Length == 0);
    else
        f += 1;
    if (File.ReadAllText(path) is string emptyText)
        f += Check("read empty text", emptyText == "");
    else
        f += 1;

    // ---- encodings ----
    f += Succeeded("write ASCII", File.WriteAllText(path, "café", Encoding.ASCII()));
    if (File.ReadAllText(path, Encoding.ASCII()) is string ascii)
        f += Check("ASCII text", ascii == "caf?");
    else
        f += 1;

    // A UTF-8 byte order mark is skipped by ReadAllText but kept by ReadAllBytes.
    f += Succeeded("write BOM", File.WriteAllBytes(path, new uint8[] { 0xEF, 0xBB, 0xBF, 104, 105 }));
    if (File.ReadAllText(path) is string bomText)
        f += Check("BOM skipped", bomText == "hi");
    else
        f += 1;
    if (File.ReadAllBytes(path) is uint8[] bomBytes)
        f += Check("BOM kept in bytes", bomBytes.Length == 5);
    else
        f += 1;

    // Invalid UTF-8 is an error, not garbage.
    f += Succeeded("write invalid", File.WriteAllBytes(path, new uint8[] { 104, 0xFF }));
    var invalid = File.ReadAllText(path);
    f += Check("invalid UTF-8 file", !invalid && invalid.Message.Contains("UTF-8"));

    // ---- errors ----
    var missing = File.ReadAllText("no_such_directory/none.txt");
    f += Check("missing file", !missing && missing.Message.Contains("cannot open") && missing.Code == 1);
    var noBytes = File.ReadAllBytes("no_such_directory/none.bin");
    f += Check("missing file (bytes)", !noBytes);
    var cannotCreate = File.WriteAllText("no_such_directory/x.txt", "a");
    f += Check("cannot create", !cannotCreate && cannotCreate.Message.Contains("cannot create"));

    // ---- delete ----
    f += Succeeded("Delete", File.Delete(path));
    f += Check("deleted", !File.Exists(path));
    f += Check("Delete missing fails", !File.Delete(path));

    return f;
}
