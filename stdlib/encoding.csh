// Text encodings: conversion between strings (always UTF-8 in memory) and raw bytes.
//
//     var bytes = Encoding.UTF8().GetBytes("héllo");
//     if (Encoding.ASCII().GetString(bytes) is string text) { ... }

namespace System;

enum EncodingKind : uint8
{
    UTF8,
    ASCII
}

struct Encoding
{
    EncodingKind _kind;

    static Encoding UTF8()
    {
        return Encoding { _kind = EncodingKind.UTF8 };
    }

    static Encoding ASCII()
    {
        return Encoding { _kind = EncodingKind.ASCII };
    }

    string Name()
    {
        if (_kind == EncodingKind.ASCII)
            return "ASCII";
        return "UTF-8";
    }

    // UTF-8: the bytes of the string. ASCII: one byte per character, characters above 127 become '?'.
    uint8[] GetBytes(string s)
    {
        if (_kind == EncodingKind.UTF8)
        {
            var bytes = new uint8[s.Length];
            for (var i = 0; i < s.Length; i += 1)
                bytes[i] = s[i];
            return bytes;
        }

        // Count the characters: every byte below 0x80 or every lead byte (>= 0xC0) starts a character.
        int count = 0;
        for (var i = 0; i < s.Length; i += 1)
        {
            if (s[i] < 0x80 || s[i] >= 0xC0)
                count += 1;
        }
        var result = new uint8[count];
        int position = 0;
        for (var i = 0; i < s.Length; i += 1)
        {
            uint8 b = s[i];
            if (b < 0x80)
            {
                result[position] = b;
                position += 1;
            }
            else if (b >= 0xC0)
            {
                result[position] = '?';
                position += 1;
            }
        }
        return result;
    }

    int GetByteCount(string s)
    {
        if (_kind == EncodingKind.UTF8)
            return s.Length;
        return GetBytes(s).Length;
    }

    EncodingError<string> GetString(uint8[] bytes)
    {
        return GetString(bytes, 0, bytes.Length);
    }

    // Decodes count bytes starting at start. Invalid input (malformed UTF-8, bytes above 127 for ASCII) is an error.
    EncodingError<string> GetString(uint8[] bytes, int start, int count)
    {
        if (start < 0 || count < 0 || start + count > bytes.Length)
            return error("byte range is out of bounds", EncodingError.OutOfBounds);
        int end = start + count;

        if (_kind == EncodingKind.ASCII)
        {
            for (var i = start; i < end; i += 1)
            {
                if (bytes[i] >= 0x80)
                    return error("byte at index " + i + " is not ASCII", EncodingError.NotAscii);
            }
            return string.FromBytes(bytes, start, count);
        }

        // Validate UTF-8: lead byte, continuation bytes, no overlong forms, no surrogates, at most U+10FFFF.
        int position = start;
        while (position < end)
        {
            int lead = bytes[position];
            if (lead < 0x80)
            {
                position += 1;
                continue;
            }

            int extra = 0;
            int codePoint = 0;
            if (lead >= 0xC2 && lead <= 0xDF)
            {
                extra = 1;
                codePoint = lead & 0x1F;
            }
            else if (lead >= 0xE0 && lead <= 0xEF)
            {
                extra = 2;
                codePoint = lead & 0x0F;
            }
            else if (lead >= 0xF0 && lead <= 0xF4)
            {
                extra = 3;
                codePoint = lead & 0x07;
            }
            else
            {
                return error("invalid UTF-8 byte at index " + position, EncodingError.InvalidUtf8);
            }

            if (position + extra >= end)
                return error("truncated UTF-8 sequence at index " + position, EncodingError.InvalidUtf8);
            for (var k = 1; k <= extra; k += 1)
            {
                int next = bytes[position + k];
                if ((next & 0xC0) != 0x80)
                    return error("invalid UTF-8 continuation byte at index " + (position + k), EncodingError.InvalidUtf8);
                codePoint = (codePoint << 6) | (next & 0x3F);
            }
            if ((extra == 2 && codePoint < 0x800) || (extra == 3 && (codePoint < 0x10000 || codePoint > 0x10FFFF)))
                return error("overlong or out-of-range UTF-8 sequence at index " + position, EncodingError.InvalidUtf8);
            if (codePoint >= 0xD800 && codePoint <= 0xDFFF)
                return error("UTF-8 sequence encodes a surrogate at index " + position, EncodingError.InvalidUtf8);
            position += extra + 1;
        }
        return string.FromBytes(bytes, start, count);
    }
}
