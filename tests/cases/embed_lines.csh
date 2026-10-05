// embed_lines("file") gives the lines of a file as a constant ReadOnlySlice<string>: without their line ends (\n and
// \r\n), without the byte order mark; a line end at the end of the file does not start an empty line, an empty file
// has no lines. The constant works like any constant slice (Length, indexing, foreach, spreading).
// expect-exit: 0
// expect-stdout: lines 6: [pear] [apple] [] [  fig  ] [] [ü€]
// expect-stdout: open 2: [first] [last]
// expect-stdout: empty 0
// expect-stdout: local 2 last
// expect-stdout: spread 3 more

using System;

const ReadOnlySlice<string> Lines = embed_lines("embed/lines.txt");
const ReadOnlySlice<string> Open = embed_lines("embed/lines_open.txt");
const ReadOnlySlice<string> Empty = embed_lines("embed/empty.txt");
const ReadOnlySlice<string> More = [..Open, "more"];

string Show(ReadOnlySlice<string> lines)
{
    string text = lines.Length.ToString() + ":";
    foreach (var line in lines)
        text += " [" + line + "]";
    return text;
}

int Main()
{
    Console.WriteLine("lines " + Show(Lines));
    Console.WriteLine("open " + Show(Open));
    Console.WriteLine("empty " + Empty.Length.ToString());
    const ReadOnlySlice<string> Local = embed_lines("embed/lines_open.txt");
    Console.WriteLine("local " + Local.Length.ToString() + " " + Local[1]);
    Console.WriteLine("spread " + More.Length.ToString() + " " + More[2]);
    return 0;
}
