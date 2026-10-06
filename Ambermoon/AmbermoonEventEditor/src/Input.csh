// Reading numbers and options from the console like the original (int.TryParse of .NET).
namespace AmbermoonEventEditor;

using System;

// int.TryParse(text): white space around it, a sign, decimal digits; null if it is no int
Optional<int> ParseInt(StringSlice text)
{
    var t = text.Trim();
    if (t.Length == 0)
        return null;
    bool negative = false;
    int start = 0;
    if (t[0] == '+' || t[0] == '-')
    {
        negative = t[0] == '-';
        start = 1;
    }
    if (start == t.Length)
        return null;
    int64 value = 0;
    for (var i = start; i < t.Length; i += 1)
    {
        if (!Char.IsDigit(t[i]))
            return null;
        value = value * 10 + (t[i] - '0');
        if (value > 2147483648)
            return null;
    }
    if (negative)
        value = -value;
    if (value > 2147483647 || value < -2147483648)
        return null;
    return (int)value;
}

// int.TryParse(text, NumberStyles.AllowHexSpecifier): hexadecimal digits only (up to 8 that are not leading zeros, the
// bits of an int); null if it is no such number
Optional<int> ParseHex(StringSlice text)
{
    if (text.Length == 0)
        return null;
    uint64 value = 0;
    int digits = 0;
    foreach (var c in text)
    {
        if (!Char.IsHexDigit(c))
            return null;
        if (digits > 0 || c != '0')
            digits += 1;
        value = value * 16 + (uint64)Char.HexValue(c);
        if (digits > 8)
            return null;
    }
    return (int)(uint32)value;
}

// a line of input; the original fails at the end of the input, this ends the program
string ReadLine()
{
    if (Console.ReadLine() is string line)
        return line;
    Environment.Exit(0);
    return "";
}

// reads a number (hexadecimal with an optional "$" or "0x" in front if hex)
Optional<int> ReadInt(bool hex)
{
    string input = ReadLine().ToLower();
    if (hex)
    {
        if (input.StartsWith("$"))
            input = input[1..].ToString();
        else if (input.StartsWith("0x"))
            input = input[2..].ToString();
        return ParseHex(input);
    }
    return ParseInt(input);
}

Optional<int> ReadInt()
{
    return ReadInt(false);
}

// shows the numbered options and reads one; the default for anything else
int ReadOption(int defaultOption, string[] options)
{
    for (var i = 0; i < options.Length; i += 1)
        Console.WriteLine($"{i}: {options[i]}");

    Console.Write("Enter: ");
    var option = ReadInt();

    if (option is int o && (o < 0 || o >= options.Length))
        return defaultOption;

    return option is int chosen ? chosen : defaultOption;
}
