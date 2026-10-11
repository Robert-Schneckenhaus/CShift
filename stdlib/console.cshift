//! Reading the standard input: the compiler calls [ReadLine] for `Console.ReadLine()`.
namespace ConsoleInput;

using System;

/// The next line of the standard input, without its line break (`\n` or `\r\n`); `null` at the end of the input.
/// What the program wrote to the console before is shown first (`Console.Write("Name: ")` without a line break as a
/// prompt). Bytes that are not valid UTF-8 become `?`.
///
/// ```
/// Console.Write("Name: ");
/// if (Console.ReadLine() is string name)
///     Console.WriteLine("Hello, " + name);
/// ```
Optional<string> ReadLine()
{
    _Os.FlushOutput();
    int b = _Os.ReadInputByte();
    if (b < 0)
        return null;
    var line = new uint8[128];
    int length = 0;
    while (b >= 0 && b != '\n')
    {
        if (length == line.Length)
        {
            var bigger = new uint8[line.Length * 2];
            Array.Copy(line, 0, bigger, 0, length);
            line = bigger;
        }
        line[length] = (uint8)b;
        length += 1;
        b = _Os.ReadInputByte();
    }
    if (length > 0 && line[length - 1] == '\r')
        length -= 1;
    var text = Encoding.UTF8().GetString(line, 0, length);
    if (text is string valid)
        return valid;
    for (var i = 0; i < length; i += 1)
    {
        if (line[i] >= 128)
            line[i] = (uint8)'?';
    }
    return Encoding.UTF8().GetString(line, 0, length) is string ascii ? ascii : "";
}
