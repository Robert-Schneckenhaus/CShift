//! Reading and writing the data of the Amiga game Ambermoon: big-endian readers and writers, the container formats
//! (JH, LOB, VOL1, AMNC, AMNP, AMBR, AMPC) and their compressions. A port of Ambermoon.Data.Legacy
//! (https://github.com/Pyrdacor/Ambermoon.net).
namespace Ambermoon.Data.Legacy.Serialization;

using System;

/// Reads big-endian values (the byte order of the Amiga) from bytes.
///
/// A reader is a value: a copy has a position of its own (pass a reader as `ref` to read on with it). Reading past the
/// end does not stop the program: it gives zeros and sets [DataReader.Overrun], which the readers of the formats check
/// to report damaged data as an error.
struct DataReader
{
    uint8[] _data;
    /// Where the next value is read.
    int Position;
    bool _overrun;

    /// A reader of `data` itself (no copy).
    static DataReader FromData(uint8[] data)
    {
        return DataReader { _data = data };
    }

    /// A reader of a copy of `data`.
    static DataReader Create(uint8[] data)
    {
        return FromData(data.Clone());
    }

    /// A reader of a copy of `length` bytes of `data`, from `offset` on.
    static DataReader Create(ReadOnlySlice<uint8> data, int offset, int length)
    {
        return FromData(data[offset..offset + length].ToArray());
    }

    /// The number of bytes.
    int Size()
    {
        return _data == null ? 0 : _data.Length;
    }

    /// The number of bytes from the position to the end (0 if the position is behind the end).
    int Remaining()
    {
        int left = Size() - Position;
        return left < 0 ? 0 : left;
    }

    /// Whether a read went past the end of the data (it gave zeros).
    bool Overrun()
    {
        return _overrun;
    }

    /// The byte at `index` (also `reader[index]`).
    uint8 Get(int index)
    {
        return _data[index];
    }

    /// Moves the position to the next multiple of 2.
    void AlignToWord()
    {
        Position = (Position + 1) & ~1;
    }

    /// Moves the position to the next multiple of 4.
    void AlignToDword()
    {
        Position = (Position + 3) & ~3;
    }

    /// The byte at the position, without moving on.
    uint8 PeekByte()
    {
        return _At(Position);
    }

    /// The word (16 bits) at the position, without moving on.
    uint16 PeekWord()
    {
        return (uint16)((_At(Position) << 8) | _At(Position + 1));
    }

    /// The dword (32 bits) at the position, without moving on.
    uint32 PeekDword()
    {
        return ((uint32)_At(Position) << 24) | ((uint32)_At(Position + 1) << 16) | ((uint32)_At(Position + 2) << 8) |
               (uint32)_At(Position + 3);
    }

    /// Reads a byte and tells whether it is not 0.
    bool ReadBool()
    {
        return ReadByte() != 0;
    }

    /// Reads a byte.
    uint8 ReadByte()
    {
        int p = Position;
        Position = p + 1;
        if (p >= 0 && p < Size())
            return _data[p];
        _overrun = true;
        return 0;
    }

    /// Reads a word (16 bits, big-endian).
    uint16 ReadWord()
    {
        uint16 value = PeekWord();
        Position += 2;
        return value;
    }

    /// Reads a dword (32 bits, big-endian).
    uint32 ReadDword()
    {
        uint32 value = PeekDword();
        Position += 4;
        return value;
    }

    /// Reads a qword (64 bits, big-endian).
    uint64 ReadQword()
    {
        uint64 high = ReadDword();
        return (high << 32) | ReadDword();
    }

    /// Reads `amount` bytes (a new array).
    uint8[] ReadBytes(int amount)
    {
        var bytes = new uint8[amount];
        int available = Remaining();
        int n = amount < available ? amount : available;
        if (n > 0)
            Array.Copy(_data, Position, bytes, 0, n);
        if (n < amount)
            _overrun = true;
        Position += amount;
        return bytes;
    }

    /// The bytes from the position to the end (a new array); the position is the end afterwards.
    uint8[] ReadToEnd()
    {
        var bytes = new uint8[Remaining()];
        if (bytes.Length > 0)
            Array.Copy(_data, Position, bytes, 0, bytes.Length);
        Position = Size();
        return bytes;
    }

    /// The bytes of the reader (not a copy).
    uint8[] ToArray()
    {
        return _data == null ? new uint8[0] : _data;
    }

    uint8 _At(int index)
    {
        if (index >= 0 && index < Size())
            return _data[index];
        _overrun = true;
        return 0;
    }
}
