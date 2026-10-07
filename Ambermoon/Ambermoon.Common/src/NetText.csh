namespace Ambermoon;

using System;

/// Whether a code point is white space for .NET (`char.IsWhiteSpace`): tab to carriage return, space, U+0085, U+00A0,
/// U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000.
bool IsWhiteSpaceNet(int codePoint)
{
    return codePoint == ' ' || (codePoint >= '\t' && codePoint <= '\r') || codePoint == 0x85 || codePoint == 0xA0 ||
           codePoint == 0x1680 || (codePoint >= 0x2000 && codePoint <= 0x200A) || codePoint == 0x2028 ||
           codePoint == 0x2029 || codePoint == 0x202F || codePoint == 0x205F || codePoint == 0x3000;
}

/// `text.Trim()` of .NET: without the white space ([IsWhiteSpaceNet]) at the start and the end.
StringSlice TrimNet(StringSlice text)
{
    int start = 0;
    while (start < text.Length)
    {
        int length = _CodePointLength(text, start);
        if (!IsWhiteSpaceNet(_CodePointAt(text, start, length)))
            break;
        start += length;
    }
    int end = text.Length;
    while (end > start)
    {
        // the start of the last character
        int first = end - 1;
        while (first > start && (text[first] & 0xC0) == 0x80)
            first -= 1;
        if (!IsWhiteSpaceNet(_CodePointAt(text, first, end - first)))
            break;
        end = first;
    }
    return text[start..end];
}

/// Whether the text is empty or only white space (`string.IsNullOrWhiteSpace` of .NET).
bool IsWhiteSpaceOnlyNet(StringSlice text)
{
    return TrimNet(text).Length == 0;
}

// the number of bytes of the UTF-8 character at 'i'
int _CodePointLength(StringSlice text, int i)
{
    int b = text[i];
    int length = b < 0x80 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;
    return i + length <= text.Length ? length : text.Length - i;
}

// the code point of the UTF-8 character of 'length' bytes at 'i'
int _CodePointAt(StringSlice text, int i, int length)
{
    int b = text[i];
    if (length == 1)
        return b;
    int value = b & (0xFF >> (length + 1));
    for (var k = 1; k < length; k += 1)
        value = (value << 6) | (text[i + k] & 0x3F);
    return value;
}

/// The lines of a text like `File.ReadAllLines` of .NET: split at "\r\n", "\n" and "\r"; a line break at the end does
/// not start another line.
List<string> SplitLinesNet(StringSlice text)
{
    var lines = List<string>.Create();
    int start = 0;
    int i = 0;
    while (i < text.Length)
    {
        if (text[i] == '\n' || text[i] == '\r')
        {
            lines.Add(text[start..i].ToString());
            if (text[i] == '\r' && i + 1 < text.Length && text[i + 1] == '\n')
                i += 1;
            i += 1;
            start = i;
        }
        else
            i += 1;
    }
    if (start < text.Length)
        lines.Add(text[start..].ToString());
    return lines;
}
