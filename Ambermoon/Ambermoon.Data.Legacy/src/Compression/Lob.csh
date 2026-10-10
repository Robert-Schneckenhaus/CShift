namespace Ambermoon.Data.Legacy.Compression;

using System;
using Ambermoon.Data.Legacy.Serialization;

/// The LOB compression of the original game (Lothar Becks): a header byte for every 8 entries, each a literal byte
/// (bit 1) or a match of 3 to 18 bytes up to 4095 bytes back (bit 0, 2 bytes).
struct Lob
{
    /// `data` compressed (the result has an even length if `data` has).
    static Error<uint8[]> CompressData(uint8[] data)
    {
        if (data.Length == 0)
            return error(_OutOfBounds);
        var w = _LobWriter { Out = ByteList.Create(data.Length), HeaderBitMask = 0x80 >> 1, Header = 0x80 };
        w.Out.Add(0); // the first header, written later
        var trie = MatchTrie.Create();
        int length = data.Length;

        // the first byte cannot be a match
        trie.Add(data, 0, _LobMaxMatchLength);
        w.Out.Add(data[0]);
        int i = 1;

        while (i <= length - _LobMaxMatchLength)
        {
            var match = trie.GetLongestMatch(data, i, _LobMaxMatchLength);
            trie.Add(data, i, _LobMaxMatchLength);
            if (match.Length > 2)
            {
                w.AddMatch(i - match.Offset, match.Length, i + match.Length == length);
                for (var j = 1; j < match.Length; j += 1)
                    trie.Add(data, i + j, Math.Min(_LobMaxMatchLength, length - i - j));
                i += match.Length;
            }
            else
            {
                w.AddByte(data[i], false);
                i += 1;
            }
        }

        while (i <= length - _LobMinMatchLength)
        {
            int rest = length - i;
            var match = trie.GetLongestMatch(data, i, rest);
            trie.Add(data, i, rest);
            if (match.Length > 2)
            {
                w.AddMatch(i - match.Offset, match.Length, i + match.Length == length);
                for (var j = 1; j < match.Length; j += 1)
                    trie.Add(data, i + j, rest - j);
                i += match.Length;
            }
            else
            {
                w.AddByte(data[i], false);
                i += 1;
            }
        }

        while (i < length)
        {
            w.AddByte(data[i], i == length - 1);
            i += 1;
        }

        if (w.HeaderBitMask != 0x80)
            w.Out[w.HeaderPosition] = (uint8)w.Header;
        if (trie.Error().Length > 0)
            return error(trie.Error());
        return w.Out.ToArray();
    }

    /// Decompresses `decodedSize` bytes from the reader's position on.
    static Error<DataReader> Decompress(ref DataReader reader, uint32 decodedSize)
    {
        int size = (int)decodedSize;
        var decoded = new uint8[size];
        var src = reader.ToArray();
        int decodeIndex = 0;

        while (decodeIndex < size)
        {
            int p = reader.Position;
            if (p < 0 || p > src.Length - 17)
            {
                // the last groups: through the reader, which reads zeros past the end and remembers that
                decodeIndex = _DecompressGroup(ref reader, decoded, decodeIndex);
                if (decodeIndex < 0 || reader.Overrun())
                    return error(_OutOfBounds);
                continue;
            }
            // a whole group (a header and 8 entries: at most 17 bytes) is there: straight from the bytes
            int header = src[p];
            p += 1;
            for (var i = 0; i < 8; i += 1)
            {
                if ((header & 0x80) == 0) // a match
                {
                    int first = src[p];
                    int matchLength = (first & 0x0f) + 3;
                    int from = decodeIndex - (((first << 4) & 0xff00) | src[p + 1]);
                    p += 2;
                    int to = decodeIndex;
                    int stop = to + matchLength;
                    if (from < 0 || stop > size)
                    {
                        reader.Position = p;
                        return error(_OutOfBounds);
                    }
                    while (to < stop)
                    {
                        decoded[to] = decoded[from];
                        to += 1;
                        from += 1;
                    }
                    decodeIndex = stop;
                }
                else // a literal byte
                {
                    decoded[decodeIndex] = src[p];
                    p += 1;
                    decodeIndex += 1;
                }
                if (decodeIndex == size)
                    break;
                header <<= 1;
            }
            reader.Position = p;
        }

        return DataReader.FromData(decoded);
    }

    // one group (a header and up to 8 entries) through the reader: the new decode index, -1 if a match is out of bounds
    static int _DecompressGroup(ref DataReader reader, uint8[] decoded, int decodeIndex)
    {
        int size = decoded.Length;
        int header = reader.ReadByte();
        for (var i = 0; i < 8; i += 1)
        {
            if ((header & 0x80) == 0) // a match
            {
                int first = reader.ReadByte();
                int matchLength = (first & 0x0f) + 3;
                int matchOffset = ((first << 4) & 0xff00) | reader.ReadByte();
                int matchIndex = decodeIndex - matchOffset;
                if (matchIndex < 0 || decodeIndex + matchLength > size)
                    return -1;
                for (var n = 0; n < matchLength; n += 1)
                    decoded[decodeIndex + n] = decoded[matchIndex + n];
                decodeIndex += matchLength;
            }
            else // a literal byte
            {
                decoded[decodeIndex] = reader.ReadByte();
                decodeIndex += 1;
            }
            if (decodeIndex == size)
                break;
            header <<= 1;
        }
        return decodeIndex;
    }
}

// the state of Lob.CompressData: the output and the header byte that is being filled
struct _LobWriter
{
    ByteList Out;
    int HeaderPosition;
    int HeaderBitMask;
    int Header;

    void AddByte(uint8 b, bool last)
    {
        Header |= HeaderBitMask;
        Out.Add(b);
        _PostAdd(last);
    }

    void AddMatch(int offset, int length, bool last)
    {
        Out.Add((uint8)(((offset >> 4) & 0xf0) | ((length - 3) & 0x0f)));
        Out.Add((uint8)(offset & 0xff));
        _PostAdd(last);
    }

    void _PostAdd(bool last)
    {
        HeaderBitMask >>= 1;
        if (HeaderBitMask == 0)
        {
            Out[HeaderPosition] = (uint8)Header;
            HeaderBitMask = 0x80;
            Header = 0;
            if (!last)
            {
                HeaderPosition = Out.Count();
                Out.Add(0); // the next header
            }
            else if (Out.Count() % 2 == 1)
            {
                Out.Add(0xc0); // a header, then 2 padding bytes
                Out.Add(0);
                Out.Add(0);
            }
        }
        else if (last && Out.Count() % 2 == 1)
        {
            Out.Add(0); // padding
        }
    }
}

const int _LobMinMatchLength = 3;
const int _LobMaxMatchLength = 18;
