// The standard library's typed errors: File.* returns IoError<T>, the number parsers ParseError<T>, Encoding.GetString
// EncodingError<string>. The codes can be matched directly, and a typed result still converts to a plain Error<T>.
// expect-exit: 0
// expect-stdout: cannot open 1
// expect-stdout: invalid text
// expect-stdout: parse Invalid OutOfRange 42
// expect-stdout: encoding NotAscii
// expect-stdout: plain 1
// expect-stdout: exists AlreadyExists

using System;

Error<string> Plain(string path)
{
    return File.ReadAllText(path);       // IoError<string> -> Error<string>
}

int Main()
{
    switch (File.ReadAllText("does/not/exist.txt"))
    {
        case string text:
            Console.WriteLine("read");
            break;
        case IoError.CannotOpen:
            Console.WriteLine("cannot open " + (int)IoError.CannotOpen);
            break;
        case error e:
            Console.WriteLine("other " + e.Message);
            break;
    }

    try File.WriteAllBytes("stdlib_errors.bin", new uint8[] { 0x68, 0xFF });
    if (File.ReadAllText("stdlib_errors.bin") is IoError code && code == IoError.InvalidText)
        Console.WriteLine("invalid text");

    string codes = "";
    if ("abc".ParseInt() is ParseError p1)
        codes += p1;
    if ("99999999999".ParseInt() is ParseError p2)
        codes += " " + p2;
    if ("42".ParseInt() is int n)
        codes += " " + n;
    Console.WriteLine("parse " + codes);

    if (Encoding.ASCII().GetString(new uint8[] { 72, 200 }) is error e2)
        Console.WriteLine("encoding " + e2.Code);

    if (Plain("does/not/exist.txt") is error e3)
        Console.WriteLine("plain " + e3.Code);

    if (File.Copy("stdlib_errors.bin", "stdlib_errors.bin") is IoError c2)
        Console.WriteLine("exists " + c2);
    try File.Delete("stdlib_errors.bin");
    return 0;
}
