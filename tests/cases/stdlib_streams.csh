// FileStream, StreamReader, StreamWriter; File.Move, File.GetLastWriteTimeUtc; Directory.Delete, Directory.Move
// expect-stdout: [line one]
// expect-stdout: [zwei]
// expect-stdout: []
// expect-stdout: [drei]
// expect-stdout: end true
// expect-stdout: length 22, at 5: o, position 6
// expect-stdout: bytes 1 2 3 255, read 4, then 0
// expect-stdout: rest: line one|zwei||drei!|
// expect-stdout: moved true, exists already: true
// expect-stdout: recent true
// expect-stdout: not empty true
// expect-stdout: directory gone true
using System;

int Main()
{
    string text = "cshift_streams_test.txt";
    try File.WriteAllText(text, "line one\r\nzwei\n\ndrei");
    {
        using var reader = try StreamReader.Open(text);
        while (reader.ReadLine() is string line)
            Console.WriteLine("[" + line + "]");
        Console.WriteLine("end " + reader.EndOfStream().ToString());
    }
    {
        using var writer = try StreamWriter.Append(text);
        try writer.WriteLine("!");
    }
    {
        using var stream = try FileStream.OpenRead(text);
        int64 length = stream.Length();
        stream.Seek(5, SeekOrigin.Begin);
        char c = (char)stream.ReadByte();
        Console.WriteLine($"length {length}, at 5: {c}, position {stream.Position()}");
    }

    string data = "cshift_streams_test.bin";
    {
        using var stream = try FileStream.Create(data);
        try stream.Write([1, 2, 3, 255]);
    }
    {
        using var stream = try FileStream.OpenRead(data);
        var buffer = new uint8[10];
        int got = stream.Read(buffer, 0, 10);
        Console.WriteLine($"bytes {buffer[0]} {buffer[1]} {buffer[2]} {buffer[3]}, read {got}, then {stream.Read(buffer, 0, 10)}");
    }
    {
        using var reader = try StreamReader.Open(text);
        Console.WriteLine("rest: " + reader.ReadToEnd().Replace("\r", "").Replace("\n", "|"));
    }

    string moved = "cshift_streams_moved.txt";
    try File.Move(text, moved, true);
    try File.WriteAllText(text, "again");
    bool refused = false;
    switch (File.Move(text, moved))
    {
    case IoError.AlreadyExists:
        refused = true;
        break;
    default:
        break;
    }
    Console.WriteLine($"moved {File.Exists(moved)}, exists already: {refused}");
    var written = try File.GetLastWriteTimeUtc(moved);
    Console.WriteLine("recent " + (DateTime.UtcNow().Subtract(written).Duration().TotalMinutes() < 10.0).ToString());

    Directory.Create("cshift_streams_dir/sub");
    try File.WriteAllText("cshift_streams_dir/sub/x.txt", "x");
    switch (Directory.Delete("cshift_streams_dir"))
    {
    case IoError.CannotDelete:
        Console.WriteLine("not empty true");
        break;
    default:
        Console.WriteLine("not empty false");
        break;
    }
    try Directory.Move("cshift_streams_dir", "cshift_streams_dir2");
    try Directory.Delete("cshift_streams_dir2", true);
    Console.WriteLine("directory gone " + (!Directory.Exists("cshift_streams_dir2") && !Directory.Exists("cshift_streams_dir")).ToString());

    try File.Delete(text);
    try File.Delete(moved);
    try File.Delete(data);
    return 0;
}
