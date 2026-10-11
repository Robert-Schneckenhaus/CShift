// embed("file") as ReadOnlySlice<uint8> gives the bytes of a file of any kind (fonts, images, sounds) unchanged: a byte
// order mark, NUL, bytes that are not UTF-8, quotes, backslashes and \r\n stay as they are. The constant is an ordinary
// constant slice: its length, elements and ranges are constants too, and it spreads into other constant slices.
// expect-exit: 0
// expect-stdout: bytes 239 187 191 0 255 34 92 13 10 65 127 128 195 40 10 32
// expect-stdout: length 16 0 first 239 last 32
// expect-stdout: head 239 187 191 0
// expect-stdout: more 255 34 42
// expect-stdout: local true
// expect-stdout: sum 1618

using System;

const ReadOnlySlice<uint8> Data = embed("embed/data.bin");
const ReadOnlySlice<uint8> Empty = embed("embed/empty.txt");
const int Size = Data.Length;
const uint8 First = Data[0];
const uint8 Last = Data[^1];
const ReadOnlySlice<uint8> Head = Data[..4];
const ReadOnlySlice<uint8> More = [..Data[4..6], 42];

string Text(ReadOnlySlice<uint8> bytes)
{
    var sb = StringBuilder.Create();
    for (var i = 0; i < bytes.Length; i += 1)
    {
        if (i > 0)
            sb.Append(" ");
        sb.Append(((int)bytes[i]).ToString());
    }
    return sb.ToString();
}

int Sum(ReadOnlySlice<uint8> bytes)
{
    int sum = 0;
    foreach (var b in bytes)
        sum += (int)b;
    return sum;
}

int Main()
{
    Console.WriteLine("bytes " + Text(Data));
    Console.WriteLine("length " + Size.ToString() + " " + Empty.Length.ToString() + " first " + ((int)First).ToString() + " last " +
                      ((int)Last).ToString());
    Console.WriteLine("head " + Text(Head));
    Console.WriteLine("more " + Text(More));

    const ReadOnlySlice<uint8> Local = embed("embed/data.bin");
    bool same = Local.Length == Data.Length;
    for (var i = 0; same && i < Local.Length; i += 1)
        same = Local[i] == Data[i];
    Console.WriteLine("local " + same.ToString().ToLower());
    Console.WriteLine("sum " + Sum(Data).ToString());
    return 0;
}
