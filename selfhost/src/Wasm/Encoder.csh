// The binary format of WebAssembly: a growing byte buffer with the encodings of the format (LEB128 numbers, IEEE
// floats, names, sections). See https://webassembly.github.io/spec/core/binary/.

namespace CShift.Wasm;

using System;

struct Bytes
{
    List<uint8> Data;

    static Bytes Create()
    {
        return Bytes { Data = List<uint8>.Create() };
    }

    int Count() { return Data.Count(); }

    void Byte(int b)
    {
        Data.Add(unchecked((uint8)b));
    }

    // an unsigned LEB128 number
    void U32(int64 value)
    {
        uint64 v = unchecked((uint64)value);
        while (true)
        {
            int b = unchecked((int)(v & 127ul));
            v = v >> 7;
            if (v == 0ul)
            {
                Byte(b);
                return;
            }
            Byte(b | 128);
        }
    }

    // a signed LEB128 number (i32 and i64 constants)
    void S64(int64 value)
    {
        int64 v = value;
        while (true)
        {
            int b = unchecked((int)(v & 127));
            v = v >> 7; // arithmetic
            bool done = (v == 0 && (b & 64) == 0) || (v == -1 && (b & 64) != 0);
            if (done)
            {
                Byte(b);
                return;
            }
            Byte(b | 128);
        }
    }

    // a fixed-width little-endian number
    void Fixed(int64 value, int bytes)
    {
        uint64 v = unchecked((uint64)value);
        for (var i = 0; i < bytes; i += 1)
        {
            Byte(unchecked((int)(v & 255ul)));
            v = v >> 8;
        }
    }

    // zero bytes up to a length
    void PadTo(int length)
    {
        while (Data.Count() < length)
            Data.Add(0);
    }

    void Name(string text)
    {
        U32(text.Length);
        for (var i = 0; i < text.Length; i += 1)
            Byte((int)text[i]);
    }

    void Append(Bytes other)
    {
        for (var i = 0; i < other.Data.Count(); i += 1)
            Data.Add(other.Data.Get(i));
    }

    // a section: its id, its size, its contents
    void Section(int id, Bytes contents)
    {
        if (contents.Count() == 0)
            return;
        Byte(id);
        U32(contents.Count());
        Append(contents);
    }

    uint8[] ToArray() { return Data.ToArray(); }
}

// The value types
const int I32 = 127;  // 0x7F
const int I64 = 126;  // 0x7E
const int F32 = 125;  // 0x7D
const int F64 = 124;  // 0x7C

// The section ids
const int SecType = 1;
const int SecImport = 2;
const int SecFunction = 3;
const int SecTable = 4;
const int SecMemory = 5;
const int SecGlobal = 6;
const int SecExport = 7;
const int SecElement = 9;
const int SecCode = 10;
const int SecData = 11;
