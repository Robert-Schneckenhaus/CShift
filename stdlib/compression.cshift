namespace System.Compression;

using System;

//! Compression and checksums: [Deflate] (RFC 1951, the compression of zip files and PNG images), the containers
//! [Zlib] (RFC 1950) and [Gzip] (RFC 1952), and the checksums [Crc32] and [Adler32].

/// The errors of decompressing ([Deflate.Decompress], [Zlib.Decompress], [Gzip.Decompress]).
error CompressionError
{
    /// The data is not valid in the format: a wrong header, an invalid block or code, a distance before the start.
    InvalidData = 1,
    /// The data ends before the end of the compressed stream.
    Truncated = 2,
    /// The data was decompressed, but its checksum or length does not match the one that was stored.
    ChecksumMismatch = 3
}

/// The CRC-32 checksum of zip, gzip and PNG (the polynomial 0xEDB88320, reflected).
///
/// ```
/// uint32 crc = Crc32.Compute(bytes);
/// uint32 same = Crc32.Update(Crc32.Update(0, first), second);   // in parts
/// ```
struct Crc32
{
    /// The checksum of `data`.
    static uint32 Compute(ReadOnlySlice<uint8> data)
    {
        return Update(0, data);
    }

    /// Continues the checksum `crc` of the bytes before `data` (0 at the start).
    static uint32 Update(uint32 crc, ReadOnlySlice<uint8> data)
    {
        uint32 c = ~crc;
        for (var i = 0; i < data.Length; i += 1)
            c = _Crc32Table[(int)((c ^ data[i]) & 0xFF)] ^ (c >> 8);
        return ~c;
    }
}

/// The Adler-32 checksum of zlib.
struct Adler32
{
    /// The checksum of `data`.
    static uint32 Compute(ReadOnlySlice<uint8> data)
    {
        return Update(1, data);
    }

    /// Continues the checksum `adler` of the bytes before `data` (1 at the start).
    static uint32 Update(uint32 adler, ReadOnlySlice<uint8> data)
    {
        uint32 a = adler & 0xFFFF;
        uint32 b = adler >> 16;
        int i = 0;
        while (i < data.Length)
        {
            // 5552 bytes are the most that cannot overflow b before the modulo
            int end = i + Math.Min(5552, data.Length - i);
            while (i < end)
            {
                a += data[i];
                b += a;
                i += 1;
            }
            a %= 65521;
            b %= 65521;
        }
        return (b << 16) | a;
    }
}

/// Raw deflate data (RFC 1951) without a container: the format of the entries of zip files. [Zlib] and [Gzip] wrap
/// it with a header and a checksum.
///
/// ```
/// uint8[] packed = Deflate.Compress(bytes);         // level 6
/// uint8[] smallest = Deflate.Compress(bytes, 9);
/// uint8[] unpacked = try Deflate.Decompress(packed);
/// ```
struct Deflate
{
    /// `data` compressed with level 6 (the default of zlib).
    static uint8[] Compress(ReadOnlySlice<uint8> data)
    {
        return Compress(data, 6);
    }

    /// `data` compressed with `level`: 0 stores it (no compression), 1 is the fastest, 9 the smallest (like zlib's
    /// levels). Each block is written in the smallest of the three block types.
    /// @panics when `level` is not 0 to 9.
    static uint8[] Compress(ReadOnlySlice<uint8> data, int level)
    {
        if (level < 0 || level > 9)
            Environment.Panic("Deflate.Compress: level must be 0 to 9, not " + level.ToString());
        var w = _BitOut.Create(data.Length / 2 + 64);
        _DeflateData(ref w, data, level);
        return w.ToArray();
    }

    /// The bytes of the compressed data `data`. Bytes after the end of the stream are ignored.
    /// @error CompressionError.InvalidData `data` is not valid deflate data.
    /// @error CompressionError.Truncated `data` ends before the end of the stream.
    static CompressionError<uint8[]> Decompress(ReadOnlySlice<uint8> data)
    {
        var result = try _Inflate(data, 0);
        return result.Data;
    }
}

/// Deflate data in the zlib container (RFC 1950): a 2-byte header, the data and the Adler-32 checksum. PNG images
/// keep their pixels like this.
struct Zlib
{
    /// `data` compressed with level 6.
    static uint8[] Compress(ReadOnlySlice<uint8> data)
    {
        return Compress(data, 6);
    }

    /// `data` compressed with `level` (0 to 9, see [Deflate.Compress]).
    /// @panics when `level` is not 0 to 9.
    static uint8[] Compress(ReadOnlySlice<uint8> data, int level)
    {
        if (level < 0 || level > 9)
            Environment.Panic("Zlib.Compress: level must be 0 to 9, not " + level.ToString());
        var w = _BitOut.Create(data.Length / 2 + 64);
        // CMF: deflate with a 32 KB window; FLG: the level class, and FCHECK makes the header a multiple of 31
        int levelClass = level <= 1 ? 0 : level <= 5 ? 1 : level == 6 ? 2 : 3;
        int header = 0x7800 | (levelClass << 6);
        header += 31 - header % 31;
        w.PutByte((uint8)(header >> 8));
        w.PutByte((uint8)header);
        _DeflateData(ref w, data, level);
        uint32 adler = Adler32.Compute(data);
        w.PutByte((uint8)(adler >> 24));
        w.PutByte((uint8)(adler >> 16));
        w.PutByte((uint8)(adler >> 8));
        w.PutByte((uint8)adler);
        return w.ToArray();
    }

    /// The bytes of the zlib data `data`; the checksum is checked. Bytes after the checksum are ignored.
    /// @error CompressionError.InvalidData the header is not one of zlib (or asks for a preset dictionary), or the
    /// deflate data is not valid.
    /// @error CompressionError.Truncated `data` ends before the end of the stream or its checksum.
    /// @error CompressionError.ChecksumMismatch the Adler-32 checksum does not match.
    static CompressionError<uint8[]> Decompress(ReadOnlySlice<uint8> data)
    {
        if (data.Length < 2)
            return error("the zlib data is too short", CompressionError.Truncated);
        int cmf = data[0];
        int flg = data[1];
        if ((cmf & 0x0F) != 8 || (cmf >> 4) > 7 || (cmf * 256 + flg) % 31 != 0)
            return error("not a zlib header", CompressionError.InvalidData);
        if ((flg & 0x20) != 0)
            return error("zlib data with a preset dictionary is not supported", CompressionError.InvalidData);
        var result = try _Inflate(data, 2);
        int end = result.End;
        if (end + 4 > data.Length)
            return error("the zlib data ends before its checksum", CompressionError.Truncated);
        uint32 stored = ((uint32)data[end] << 24) | ((uint32)data[end + 1] << 16) | ((uint32)data[end + 2] << 8) | data[end + 3];
        if (stored != Adler32.Compute(result.Data))
            return error("the Adler-32 checksum of the zlib data does not match", CompressionError.ChecksumMismatch);
        return result.Data;
    }
}

/// Deflate data in the gzip container (RFC 1952, `.gz` files): a header, the data, its CRC-32 and its length.
struct Gzip
{
    /// `data` compressed with level 6.
    static uint8[] Compress(ReadOnlySlice<uint8> data)
    {
        return Compress(data, 6);
    }

    /// `data` compressed with `level` (0 to 9, see [Deflate.Compress]). The header has no file name and no time.
    /// @panics when `level` is not 0 to 9.
    static uint8[] Compress(ReadOnlySlice<uint8> data, int level)
    {
        if (level < 0 || level > 9)
            Environment.Panic("Gzip.Compress: level must be 0 to 9, not " + level.ToString());
        var w = _BitOut.Create(data.Length / 2 + 64);
        w.PutByte(0x1F);
        w.PutByte(0x8B);
        w.PutByte(8);   // deflate
        w.PutByte(0);   // no flags
        for (var i = 0; i < 4; i += 1)
            w.PutByte(0);   // no modification time
        w.PutByte((uint8)(level == 9 ? 2 : level == 1 ? 4 : 0));
        w.PutByte(255); // unknown operating system
        _DeflateData(ref w, data, level);
        _PutLittle32(ref w, Crc32.Compute(data));
        _PutLittle32(ref w, (uint32)data.Length);
        return w.ToArray();
    }

    /// The bytes of the gzip data `data` (the first member); the CRC-32 and the length are checked.
    /// @error CompressionError.InvalidData the header is not one of gzip, or the deflate data is not valid.
    /// @error CompressionError.Truncated `data` ends before the end of the stream or its trailer.
    /// @error CompressionError.ChecksumMismatch the CRC-32 or the length does not match.
    static CompressionError<uint8[]> Decompress(ReadOnlySlice<uint8> data)
    {
        if (data.Length < 18)
            return error("the gzip data is too short", CompressionError.Truncated);
        if (data[0] != 0x1F || data[1] != 0x8B || data[2] != 8)
            return error("not a gzip header", CompressionError.InvalidData);
        int flags = data[3];
        int pos = 10;
        if ((flags & 4) != 0)       // FEXTRA
        {
            if (pos + 2 > data.Length)
                return error("the gzip header is truncated", CompressionError.Truncated);
            pos += 2 + (data[pos] | (data[pos + 1] << 8));
        }
        for (var bit = 8; bit <= 16; bit *= 2)   // FNAME, FCOMMENT: zero-terminated
        {
            if ((flags & bit) == 0)
                continue;
            while (pos < data.Length && data[pos] != 0)
                pos += 1;
            pos += 1;
        }
        if ((flags & 2) != 0)       // FHCRC
            pos += 2;
        if (pos > data.Length)
            return error("the gzip header is truncated", CompressionError.Truncated);
        var result = try _Inflate(data, pos);
        int end = result.End;
        if (end + 8 > data.Length)
            return error("the gzip data ends before its trailer", CompressionError.Truncated);
        uint32 crc = (uint32)data[end] | ((uint32)data[end + 1] << 8) | ((uint32)data[end + 2] << 16) | ((uint32)data[end + 3] << 24);
        uint32 size = (uint32)data[end + 4] | ((uint32)data[end + 5] << 8) | ((uint32)data[end + 6] << 16) | ((uint32)data[end + 7] << 24);
        if (crc != Crc32.Compute(result.Data) || size != (uint32)result.Data.Length)
            return error("the CRC-32 or the length of the gzip data does not match", CompressionError.ChecksumMismatch);
        return result.Data;
    }
}

void _PutLittle32(ref _BitOut w, uint32 value)
{
    w.PutByte((uint8)value);
    w.PutByte((uint8)(value >> 8));
    w.PutByte((uint8)(value >> 16));
    w.PutByte((uint8)(value >> 24));
}

// ---------------------------------------------------------------------------------------------------------------
// The tables of the format

const ReadOnlySlice<int> _LengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
    115, 131, 163, 195, 227, 258];
const ReadOnlySlice<int> _LengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const ReadOnlySlice<int> _DistBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
    1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const ReadOnlySlice<int> _DistExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
    12, 13, 13];
// The order in which the lengths of the code length code are stored.
const ReadOnlySlice<int> _CodeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

// The parameters of the levels 1 to 9 (zlib's): a match this long or longer is not followed by a lazy search
// (MaxLazy), one this long searches a quarter of the chain only (Good), a match this long ends the search (Nice), the
// most positions searched (Chain).
const ReadOnlySlice<int> _LevelMaxLazy = [0, 4, 5, 6, 4, 16, 16, 32, 128, 258];
const ReadOnlySlice<int> _LevelGood = [0, 4, 4, 4, 4, 8, 8, 8, 32, 32];
const ReadOnlySlice<int> _LevelNice = [0, 8, 16, 32, 16, 32, 128, 128, 258, 258];
const ReadOnlySlice<int> _LevelChain = [0, 4, 8, 32, 16, 32, 128, 256, 1024, 4096];

const ReadOnlySlice<uint32> _Crc32Table = [
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
    0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
    0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
    0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
    0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
    0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
    0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
    0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
    0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
    0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
    0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
    0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
    0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
    0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
    0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
    0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
    0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
    0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
];

// ---------------------------------------------------------------------------------------------------------------
// Compression

// The output: bytes, and bits from the lowest on (the bit order of deflate).
struct _BitOut
{
    uint8[] Data;
    int Count;
    uint64 Bits;
    int BitCount;

    static _BitOut Create(int capacity)
    {
        return _BitOut { Data = new uint8[capacity < 64 ? 64 : capacity] };
    }

    void PutBits(uint32 value, int count)
    {
        Bits |= (uint64)value << BitCount;
        BitCount += count;
        if (BitCount >= 32)
        {
            _Room(4);
            Data[Count] = (uint8)Bits;
            Data[Count + 1] = (uint8)(Bits >> 8);
            Data[Count + 2] = (uint8)(Bits >> 16);
            Data[Count + 3] = (uint8)(Bits >> 24);
            Count += 4;
            Bits >>= 32;
            BitCount -= 32;
        }
    }

    // Writes the bits that are left, filled up to a whole byte.
    void Align()
    {
        while (BitCount > 0)
        {
            _Room(1);
            Data[Count] = (uint8)Bits;
            Count += 1;
            Bits >>= 8;
            BitCount = BitCount > 8 ? BitCount - 8 : 0;
        }
        Bits = 0;
    }

    // A byte at a byte boundary (after Align).
    void PutByte(uint8 value)
    {
        _Room(1);
        Data[Count] = value;
        Count += 1;
    }

    void PutBytes(ReadOnlySlice<uint8> data, int start, int count)
    {
        _Room(count);
        for (var i = 0; i < count; i += 1)
            Data[Count + i] = data[start + i];
        Count += count;
    }

    uint8[] ToArray()
    {
        Align();
        var result = new uint8[Count];
        Array.Copy(Data, 0, result, 0, Count);
        return result;
    }

    void _Room(int count)
    {
        if (Count + count <= Data.Length)
            return;
        int size = Data.Length * 2;
        if (size < Count + count)
            size = Count + count;
        var bigger = new uint8[size];
        Array.Copy(Data, 0, bigger, 0, Count);
        Data = bigger;
    }
}

// The symbols of a block before they are written: literals (Dist 0) and matches (Value = length, Dist = distance).
struct _Symbols
{
    uint16[] Value;
    uint16[] Dist;
    int Count;
    int[] LitFreq;     // 286 literal/length codes
    int[] DistFreq;    // 30 distance codes
}

const int _MaxSymbols = 16384;
const int _HashBits = 15;
const int _WindowSize = 32768;

// The code of each length 3..258 (index length - 3) and of each distance (index: distance - 1 up to 256, else
// 256 + (distance - 1) >> 7).
struct _CodeTables
{
    uint8[] LengthCode;
    uint8[] DistCode;

    static _CodeTables Create()
    {
        var t = _CodeTables { LengthCode = new uint8[256], DistCode = new uint8[512] };
        for (var code = 0; code < 29; code += 1)
        {
            int count = 1 << _LengthExtra[code];
            for (var i = 0; i < count; i += 1)
            {
                int length = _LengthBase[code] + i;
                if (length <= 258)
                    t.LengthCode[length - 3] = (uint8)code;
            }
        }
        t.LengthCode[255] = 28;   // 258 has a code of its own
        for (var code = 0; code < 30; code += 1)
        {
            int count = 1 << _DistExtra[code];
            for (var i = 0; i < count; i += 1)
            {
                int d = _DistBase[code] + i - 1;
                if (d < 256)
                    t.DistCode[d] = (uint8)code;
                else
                    t.DistCode[256 + (d >> 7)] = (uint8)code;
            }
        }
        return t;
    }

    int Dist(int distance)
    {
        int d = distance - 1;
        return d < 256 ? DistCode[d] : DistCode[256 + (d >> 7)];
    }
}

void _DeflateData(ref _BitOut w, ReadOnlySlice<uint8> data, int level)
{
    int n = data.Length;
    if (level == 0)
    {
        _WriteStored(ref w, data, 0, n, true);
        return;
    }

    var tables = _CodeTables.Create();
    var syms = _Symbols { Value = new uint16[_MaxSymbols], Dist = new uint16[_MaxSymbols], LitFreq = new int[286], DistFreq = new int[30] };
    var head = new int[1 << _HashBits];
    for (var i = 0; i < head.Length; i += 1)
        head[i] = -1;
    var prev = new int[_WindowSize];
    int maxLazy = _LevelMaxLazy[level];
    int good = _LevelGood[level];
    int nice = _LevelNice[level];
    int chain = _LevelChain[level];

    int blockStart = 0;
    int pos = 0;
    bool pending = false;   // a literal or a match at pos - 1 waits for the lazy decision
    int prevLength = 0;
    int prevDist = 0;
    while (pos < n)
    {
        int length = 0;
        int dist = 0;
        int candidate = _Insert(data, pos, head, prev);
        if (candidate >= 0 && (!pending || prevLength < maxLazy))
        {
            int maxChain = pending && prevLength >= good ? chain >> 2 : chain;
            int found = _LongestMatch(data, pos, candidate, prev, maxChain, nice, pending ? prevLength : 2);
            length = found >> 16;
            dist = found & 0xFFFF;
            // a short match far away costs more than its literals
            if (length < 3 || (length == 3 && dist > 4096))
                length = 0;
        }

        if (pending && prevLength >= 3 && length <= prevLength)
        {
            _AddMatch(ref syms, ref tables, prevLength, prevDist);
            int end = pos - 1 + prevLength;
            for (var p = pos + 1; p < end; p += 1)
                _Insert(data, p, head, prev);
            pos = end;
            pending = false;
        }
        else
        {
            if (pending)
                _AddLiteral(ref syms, data[pos - 1]);
            pending = true;
            prevLength = length;
            prevDist = dist;
            pos += 1;
        }

        if (syms.Count >= _MaxSymbols - 1)
        {
            int blockEnd = pending ? pos - 1 : pos;
            _WriteBlock(ref w, ref syms, data, blockStart, blockEnd, false);
            blockStart = blockEnd;
        }
    }
    if (pending)
    {
        if (prevLength >= 3)
            _AddMatch(ref syms, ref tables, prevLength, prevDist);
        else
            _AddLiteral(ref syms, data[pos - 1]);
    }
    _WriteBlock(ref w, ref syms, data, blockStart, n, true);
    w.Align();
}

// Enters the 3 bytes at pos into the hash chains; the previous position with the same hash, or -1.
int _Insert(ReadOnlySlice<uint8> data, int pos, int[] head, int[] prev)
{
    if (pos + 3 > data.Length)
        return -1;
    int h = (((int)data[pos] << 10) ^ ((int)data[pos + 1] << 5) ^ data[pos + 2]) & ((1 << _HashBits) - 1);
    int candidate = head[h];
    prev[pos & (_WindowSize - 1)] = candidate;
    head[h] = pos;
    return candidate;
}

// The longest match for pos among the positions of the chain from candidate, longer than `better`:
// length << 16 | distance, or 0.
int _LongestMatch(ReadOnlySlice<uint8> data, int pos, int candidate, int[] prev, int chain, int nice, int better)
{
    int maxLength = Math.Min(258, data.Length - pos);
    if (maxLength < 3)
        return 0;
    int best = better < 2 ? 2 : better;
    if (best >= maxLength)
        return 0;
    int bestDist = 0;
    int limit = pos - _WindowSize;
    int cur = candidate;
    while (cur >= 0 && cur >= limit && chain > 0)
    {
        if (data[cur + best] == data[pos + best] && data[cur] == data[pos] && data[cur + 1] == data[pos + 1])
        {
            int length = 2;
            while (length < maxLength && data[cur + length] == data[pos + length])
                length += 1;
            if (length > best)
            {
                best = length;
                bestDist = pos - cur;
                if (length >= nice || length >= maxLength)
                    break;
            }
        }
        chain -= 1;
        int next = prev[cur & (_WindowSize - 1)];
        if (next >= cur)
            break;   // the slot belongs to a newer position already
        cur = next;
    }
    if (bestDist == 0)
        return 0;
    return (best << 16) | bestDist;
}

void _AddLiteral(ref _Symbols s, uint8 value)
{
    s.Value[s.Count] = value;
    s.Dist[s.Count] = 0;
    s.Count += 1;
    s.LitFreq[value] += 1;
}

void _AddMatch(ref _Symbols s, ref _CodeTables t, int length, int dist)
{
    s.Value[s.Count] = (uint16)length;
    s.Dist[s.Count] = (uint16)dist;
    s.Count += 1;
    s.LitFreq[257 + t.LengthCode[length - 3]] += 1;
    s.DistFreq[t.Dist(dist)] += 1;
}

// Writes data[start..end) as stored blocks (at most 65535 bytes each).
void _WriteStored(ref _BitOut w, ReadOnlySlice<uint8> data, int start, int end, bool final)
{
    int pos = start;
    while (true)
    {
        int count = Math.Min(65535, end - pos);
        bool last = pos + count == end;
        w.PutBits(final && last ? 1u : 0u, 3);
        w.Align();
        w.PutByte((uint8)count);
        w.PutByte((uint8)(count >> 8));
        w.PutByte((uint8)~count);
        w.PutByte((uint8)(~count >> 8));
        w.PutBytes(data, pos, count);
        pos += count;
        if (last)
            break;
    }
}

// Writes the symbols as one block (the smallest of stored, fixed and dynamic codes) and empties them.
void _WriteBlock(ref _BitOut w, ref _Symbols s, ReadOnlySlice<uint8> data, int start, int end, bool final)
{
    s.LitFreq[256] += 1;   // the end of the block
    var litLengths = new uint8[286];
    var distLengths = new uint8[30];
    _HuffmanLengths(s.LitFreq, litLengths, 15);
    // two distance codes at least: some old inflaters cannot handle one or none
    int usedDists = 0;
    for (var i = 0; i < 30; i += 1)
    {
        if (s.DistFreq[i] > 0)
            usedDists += 1;
    }
    var distFreq = s.DistFreq.Clone();
    if (usedDists < 2)
    {
        if (distFreq[0] == 0)
            distFreq[0] = 1;
        else
            distFreq[1] = 1;
    }
    _HuffmanLengths(distFreq, distLengths, 15);

    int litCount = 286;
    while (litCount > 257 && litLengths[litCount - 1] == 0)
        litCount -= 1;
    int distCount = 30;
    while (distCount > 1 && distLengths[distCount - 1] == 0)
        distCount -= 1;

    // the code lengths, run-length coded (symbols 0-18 with their extra bits)
    var all = new uint8[litCount + distCount];
    for (var i = 0; i < litCount; i += 1)
        all[i] = litLengths[i];
    for (var i = 0; i < distCount; i += 1)
        all[litCount + i] = distLengths[i];
    var rle = new uint8[all.Length];
    var rleExtra = new uint8[all.Length];
    int rleCount = 0;
    var clFreq = new int[19];
    int i2 = 0;
    while (i2 < all.Length)
    {
        int value = all[i2];
        int run = 1;
        while (i2 + run < all.Length && all[i2 + run] == value)
            run += 1;
        i2 += run;
        if (value == 0)
        {
            while (run >= 11)
            {
                int k = Math.Min(run, 138);
                rle[rleCount] = 18;
                rleExtra[rleCount] = (uint8)(k - 11);
                rleCount += 1;
                run -= k;
            }
            if (run >= 3)
            {
                rle[rleCount] = 17;
                rleExtra[rleCount] = (uint8)(run - 3);
                rleCount += 1;
                run = 0;
            }
        }
        else
        {
            rle[rleCount] = (uint8)value;
            rleCount += 1;
            run -= 1;
            while (run >= 3)
            {
                int k = Math.Min(run, 6);
                rle[rleCount] = 16;
                rleExtra[rleCount] = (uint8)(k - 3);
                rleCount += 1;
                run -= k;
            }
        }
        while (run > 0)
        {
            rle[rleCount] = (uint8)value;
            rleCount += 1;
            run -= 1;
        }
    }
    for (var i = 0; i < rleCount; i += 1)
        clFreq[rle[i]] += 1;
    var clLengths = new uint8[19];
    _HuffmanLengths(clFreq, clLengths, 7);
    int clCount = 19;
    while (clCount > 4 && clLengths[_CodeLengthOrder[clCount - 1]] == 0)
        clCount -= 1;

    // the sizes in bits of the three kinds of blocks
    int64 dynamicBits = 3 + 5 + 5 + 4 + 3 * clCount;
    for (var i = 0; i < 19; i += 1)
        dynamicBits += (int64)clFreq[i] * clLengths[i];
    dynamicBits += 2 * (int64)clFreq[16] + 3 * (int64)clFreq[17] + 7 * (int64)clFreq[18];
    int64 fixedBits = 3;
    for (var i = 0; i < 286; i += 1)
    {
        int extra = i >= 265 && i < 285 ? (i - 261) / 4 : 0;
        dynamicBits += (int64)s.LitFreq[i] * (litLengths[i] + extra);
        fixedBits += (int64)s.LitFreq[i] * (_FixedLitLength(i) + extra);
    }
    for (var i = 0; i < 30; i += 1)
    {
        dynamicBits += (int64)s.DistFreq[i] * (distLengths[i] + _DistExtra[i]);
        fixedBits += (int64)s.DistFreq[i] * (5 + _DistExtra[i]);
    }
    int raw = end - start;
    int64 storedBits = (int64)(raw / 65535 + 1) * 40 + 8 * (int64)raw;

    if (storedBits <= dynamicBits && storedBits <= fixedBits)
        _WriteStored(ref w, data, start, end, final);
    else if (fixedBits <= dynamicBits)
    {
        var fixedLit = new uint8[288];
        for (var i = 0; i < 288; i += 1)
            fixedLit[i] = (uint8)_FixedLitLength(i);
        var fixedDist = new uint8[30];
        for (var i = 0; i < 30; i += 1)
            fixedDist[i] = 5;
        w.PutBits(final ? 3u : 2u, 3);
        _WriteSymbols(ref w, ref s, fixedLit, fixedDist);
    }
    else
    {
        w.PutBits(final ? 5u : 4u, 3);
        w.PutBits((uint32)(litCount - 257), 5);
        w.PutBits((uint32)(distCount - 1), 5);
        w.PutBits((uint32)(clCount - 4), 4);
        for (var i = 0; i < clCount; i += 1)
            w.PutBits(clLengths[_CodeLengthOrder[i]], 3);
        var clCodes = _CanonicalCodes(clLengths);
        for (var i = 0; i < rleCount; i += 1)
        {
            int sym = rle[i];
            w.PutBits(clCodes[sym], clLengths[sym]);
            if (sym == 16)
                w.PutBits(rleExtra[i], 2);
            else if (sym == 17)
                w.PutBits(rleExtra[i], 3);
            else if (sym == 18)
                w.PutBits(rleExtra[i], 7);
        }
        _WriteSymbols(ref w, ref s, litLengths, distLengths);
    }

    s.Count = 0;
    for (var i = 0; i < 286; i += 1)
        s.LitFreq[i] = 0;
    for (var i = 0; i < 30; i += 1)
        s.DistFreq[i] = 0;
}

int _FixedLitLength(int symbol)
{
    return symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8;
}

void _WriteSymbols(ref _BitOut w, ref _Symbols s, uint8[] litLengths, uint8[] distLengths)
{
    var litCodes = _CanonicalCodes(litLengths);
    var distCodes = _CanonicalCodes(distLengths);
    var tables = _CodeTables.Create();
    for (var i = 0; i < s.Count; i += 1)
    {
        int dist = s.Dist[i];
        int value = s.Value[i];
        if (dist == 0)
        {
            w.PutBits(litCodes[value], litLengths[value]);
            continue;
        }
        int lc = tables.LengthCode[value - 3];
        w.PutBits(litCodes[257 + lc], litLengths[257 + lc]);
        if (_LengthExtra[lc] > 0)
            w.PutBits((uint32)(value - _LengthBase[lc]), _LengthExtra[lc]);
        int dc = tables.Dist(dist);
        w.PutBits(distCodes[dc], distLengths[dc]);
        if (_DistExtra[dc] > 0)
            w.PutBits((uint32)(dist - _DistBase[dc]), _DistExtra[dc]);
    }
    w.PutBits(litCodes[256], litLengths[256]);
}

// The canonical codes of the code lengths, bit-reversed (deflate writes them from the highest bit on).
uint32[] _CanonicalCodes(uint8[] lengths)
{
    var count = new int[16];
    for (var i = 0; i < lengths.Length; i += 1)
        count[lengths[i]] += 1;
    count[0] = 0;
    var next = new int[16];
    int code = 0;
    for (var bits = 1; bits < 16; bits += 1)
    {
        code = (code + count[bits - 1]) << 1;
        next[bits] = code;
    }
    var codes = new uint32[lengths.Length];
    for (var i = 0; i < lengths.Length; i += 1)
    {
        int len = lengths[i];
        if (len == 0)
            continue;
        int c = next[len];
        next[len] += 1;
        int reversed = 0;
        for (var b = 0; b < len; b += 1)
        {
            reversed = (reversed << 1) | (c & 1);
            c >>= 1;
        }
        codes[i] = (uint32)reversed;
    }
    return codes;
}

// The Huffman code lengths (at most maxBits) for the frequencies (Moffat's in-place algorithm on the sorted
// frequencies, then the lengths are limited like in miniz).
void _HuffmanLengths(int[] freq, uint8[] lengths, int maxBits)
{
    int n = freq.Length;
    for (var i = 0; i < n; i += 1)
        lengths[i] = 0;
    // the used symbols, sorted by frequency (insertion sort: at most 286 of them)
    var syms = new int[n];
    int used = 0;
    for (var i = 0; i < n; i += 1)
    {
        if (freq[i] == 0)
            continue;
        int j = used;
        while (j > 0 && freq[syms[j - 1]] > freq[i])
        {
            syms[j] = syms[j - 1];
            j -= 1;
        }
        syms[j] = i;
        used += 1;
    }
    if (used == 0)
        return;
    if (used == 1)
    {
        lengths[syms[0]] = 1;
        return;
    }

    var a = new int[used];
    for (var i = 0; i < used; i += 1)
        a[i] = freq[syms[i]];
    // Moffat & Katajainen: a[i] becomes the code length of the i-th least frequent symbol
    a[0] += a[1];
    int root = 0;
    int leaf = 2;
    for (var next = 1; next < used - 1; next += 1)
    {
        if (leaf >= used || a[root] < a[leaf])
        {
            a[next] = a[root];
            a[root] = next;
            root += 1;
        }
        else
        {
            a[next] = a[leaf];
            leaf += 1;
        }
        if (leaf >= used || (root < next && a[root] < a[leaf]))
        {
            a[next] += a[root];
            a[root] = next;
            root += 1;
        }
        else
        {
            a[next] += a[leaf];
            leaf += 1;
        }
    }
    a[used - 2] = 0;
    for (var next = used - 3; next >= 0; next -= 1)
        a[next] = a[a[next]] + 1;
    int avail = 1;
    int usedNodes = 0;
    int depth = 0;
    root = used - 2;
    int nextLeaf = used - 1;
    while (avail > 0)
    {
        while (root >= 0 && a[root] == depth)
        {
            usedNodes += 1;
            root -= 1;
        }
        while (avail > usedNodes)
        {
            a[nextLeaf] = depth;
            nextLeaf -= 1;
            avail -= 1;
        }
        avail = 2 * usedNodes;
        depth += 1;
        usedNodes = 0;
    }

    // the number of codes of each length, limited to maxBits
    var count = new int[used + 2];
    for (var i = 0; i < used; i += 1)
        count[a[i]] += 1;
    var limited = new int[maxBits + 1];
    for (var len = 1; len < count.Length; len += 1)
        limited[Math.Min(len, maxBits)] += count[len];
    uint32 total = 0;
    for (var len = maxBits; len > 0; len -= 1)
        total += (uint32)limited[len] << (maxBits - len);
    while (total != 1u << maxBits)
    {
        limited[maxBits] -= 1;
        for (var len = maxBits - 1; len > 0; len -= 1)
        {
            if (limited[len] > 0)
            {
                limited[len] -= 1;
                limited[len + 1] += 2;
                break;
            }
        }
        total -= 1;
    }

    // the longest codes for the least frequent symbols
    int k = 0;
    for (var len = maxBits; len > 0; len -= 1)
    {
        for (var c = limited[len]; c > 0; c -= 1)
        {
            lengths[syms[k]] = (uint8)len;
            k += 1;
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Decompression

// The input: bits from the lowest on.
struct _BitIn
{
    ReadOnlySlice<uint8> Data;
    int Pos;          // the next byte to load into Bits
    uint64 Bits;
    int BitCount;
    int Overrun;      // the bytes that were loaded behind the end (as zeros)

    void Fill()
    {
        while (BitCount <= 56)
        {
            uint64 b = 0;
            if (Pos < Data.Length)
                b = Data[Pos];
            else
                Overrun += 1;
            Pos += 1;
            Bits |= b << BitCount;
            BitCount += 8;
        }
    }

    uint32 Take(int count)
    {
        if (BitCount < count)
            Fill();
        uint32 value = (uint32)(Bits & ((1ul << count) - 1));
        Bits >>= count;
        BitCount -= count;
        return value;
    }

    // Drops the bits up to the next byte boundary.
    void AlignToByte()
    {
        int drop = BitCount % 8;
        Bits >>= drop;
        BitCount -= drop;
    }

    // The position of the next byte that has not been read (bits that were loaded but not used are given back).
    int BytePos()
    {
        return Pos - BitCount / 8;
    }

    bool PastEnd()
    {
        return BytePos() > Data.Length;
    }
}

// A decoding table: indexed by the next `Bits` bits of the input (lowest first), symbol << 4 | code length;
// 0 is an invalid code.
struct _Decoder
{
    int[] Table;
    int Bits;
}

// The decoder of the code lengths, or an empty one (Table null) if the lengths are not a valid code. Incomplete codes
// are accepted when they have a single code (allowed by the format for distances), as zlib does.
_Decoder _BuildDecoder(uint8[] lengths, int count)
{
    int maxLen = 0;
    var blCount = new int[16];
    for (var i = 0; i < count; i += 1)
    {
        blCount[lengths[i]] += 1;
        maxLen = Math.Max(maxLen, (int)lengths[i]);
    }
    if (maxLen == 0)
        return _Decoder { Table = new int[2], Bits = 1 };   // no codes: everything is invalid
    blCount[0] = 0;
    int left = 1;
    for (var len = 1; len <= 15; len += 1)
    {
        left = left * 2 - blCount[len];
        if (left < 0)
            return _Decoder { };   // over-subscribed
    }
    int codes = 0;
    for (var len = 1; len <= 15; len += 1)
        codes += blCount[len];
    if (left > 0 && codes != 1)
        return _Decoder { };       // incomplete
    var next = new int[16];
    int code = 0;
    for (var len = 1; len <= 15; len += 1)
    {
        code = (code + blCount[len - 1]) << 1;
        next[len] = code;
    }
    var table = new int[1 << maxLen];
    for (var sym = 0; sym < count; sym += 1)
    {
        int len = lengths[sym];
        if (len == 0)
            continue;
        int c = next[len];
        next[len] += 1;
        int reversed = 0;
        for (var b = 0; b < len; b += 1)
        {
            reversed = (reversed << 1) | (c & 1);
            c >>= 1;
        }
        int entry = (sym << 4) | len;
        for (var i = reversed; i < table.Length; i += 1 << len)
            table[i] = entry;
    }
    return _Decoder { Table = table, Bits = maxLen };
}

// The next symbol, or -1 for an invalid code.
int _Decode(ref _BitIn r, const ref _Decoder d)
{
    if (r.BitCount < d.Bits)
        r.Fill();
    int entry = d.Table[(int)(r.Bits & (uint64)((1 << d.Bits) - 1))];
    if (entry == 0)
        return -1;
    int len = entry & 15;
    r.Bits >>= len;
    r.BitCount -= len;
    return entry >> 4;
}

// The output of the decompression: the bytes, and the position after the deflate stream.
struct _Inflated
{
    uint8[] Data;
    int End;
}

struct _ByteOut
{
    uint8[] Data;
    int Count;

    void Room(int count)
    {
        if (Count + count <= Data.Length)
            return;
        int size = Data.Length * 2;
        if (size < Count + count)
            size = Count + count;
        var bigger = new uint8[size];
        Array.Copy(Data, 0, bigger, 0, Count);
        Data = bigger;
    }
}

CompressionError<_Inflated> _Inflate(ReadOnlySlice<uint8> data, int start)
{
    var r = _BitIn { Data = data, Pos = start };
    var o = _ByteOut { Data = new uint8[data.Length * 4 + 1024] };
    var fixedLit = new uint8[288];
    for (var i = 0; i < 288; i += 1)
        fixedLit[i] = (uint8)_FixedLitLength(i);
    // the fixed distance code has 32 codes; 30 and 31 must not occur
    var fixedDist = new uint8[32];
    for (var i = 0; i < 32; i += 1)
        fixedDist[i] = 5;
    var fixedLitDecoder = _BuildDecoder(fixedLit, 288);
    var fixedDistDecoder = _BuildDecoder(fixedDist, 32);

    while (true)
    {
        uint32 final = r.Take(1);
        uint32 type = r.Take(2);
        if (type == 0)
        {
            r.AlignToByte();
            int len = (int)r.Take(16);
            int nlen = (int)r.Take(16);
            if (r.PastEnd())
                return error("the deflate data is truncated", CompressionError.Truncated);
            if ((len ^ 0xFFFF) != nlen)
                return error("invalid stored block length in the deflate data", CompressionError.InvalidData);
            // the bytes are read directly: give back the bits that were loaded already
            int pos = r.BytePos();
            if (pos + len > data.Length)
                return error("the deflate data is truncated", CompressionError.Truncated);
            o.Room(len);
            for (var i = 0; i < len; i += 1)
                o.Data[o.Count + i] = data[pos + i];
            o.Count += len;
            r.Pos = pos + len;
            r.Bits = 0;
            r.BitCount = 0;
        }
        else if (type == 3)
            return error("invalid block type in the deflate data", CompressionError.InvalidData);
        else
        {
            _Decoder lit;
            _Decoder dist;
            if (type == 1)
            {
                lit = fixedLitDecoder;
                dist = fixedDistDecoder;
            }
            else
            {
                int hlit = (int)r.Take(5) + 257;
                int hdist = (int)r.Take(5) + 1;
                int hclen = (int)r.Take(4) + 4;
                if (hlit > 286 || hdist > 30)
                    return error("invalid code counts in the deflate data", CompressionError.InvalidData);
                var clLengths = new uint8[19];
                for (var i = 0; i < hclen; i += 1)
                    clLengths[_CodeLengthOrder[i]] = (uint8)r.Take(3);
                var cl = _BuildDecoder(clLengths, 19);
                if (cl.Table == null)
                    return error("invalid code length code in the deflate data", CompressionError.InvalidData);
                var lengths = new uint8[hlit + hdist];
                int k = 0;
                while (k < lengths.Length)
                {
                    int sym = _Decode(ref r, cl);
                    if (sym < 0)
                        return error("invalid code length in the deflate data", CompressionError.InvalidData);
                    if (sym < 16)
                    {
                        lengths[k] = (uint8)sym;
                        k += 1;
                        continue;
                    }
                    int repeat;
                    uint8 value = 0;
                    if (sym == 16)
                    {
                        if (k == 0)
                            return error("a repeated code length without a previous one in the deflate data", CompressionError.InvalidData);
                        value = lengths[k - 1];
                        repeat = 3 + (int)r.Take(2);
                    }
                    else if (sym == 17)
                        repeat = 3 + (int)r.Take(3);
                    else
                        repeat = 11 + (int)r.Take(7);
                    if (k + repeat > lengths.Length)
                        return error("too many code lengths in the deflate data", CompressionError.InvalidData);
                    for (var i = 0; i < repeat; i += 1)
                        lengths[k + i] = value;
                    k += repeat;
                    if (r.PastEnd())
                        return error("the deflate data is truncated", CompressionError.Truncated);
                }
                if (lengths[256] == 0)
                    return error("the deflate data has no end-of-block code", CompressionError.InvalidData);
                var distLengths = new uint8[hdist];
                for (var i = 0; i < hdist; i += 1)
                    distLengths[i] = lengths[hlit + i];
                lit = _BuildDecoder(lengths, hlit);
                dist = _BuildDecoder(distLengths, hdist);
                if (lit.Table == null || dist.Table == null)
                    return error("invalid Huffman code in the deflate data", CompressionError.InvalidData);
            }

            while (true)
            {
                int sym = _Decode(ref r, lit);
                if (sym < 256)
                {
                    if (sym < 0)
                    {
                        if (r.PastEnd())
                            return error("the deflate data is truncated", CompressionError.Truncated);
                        return error("invalid literal/length code in the deflate data", CompressionError.InvalidData);
                    }
                    if (o.Count == o.Data.Length)
                        o.Room(1);
                    o.Data[o.Count] = (uint8)sym;
                    o.Count += 1;
                    continue;
                }
                if (sym == 256)
                    break;
                sym -= 257;
                if (sym >= 29)
                    return error("invalid length code in the deflate data", CompressionError.InvalidData);
                int length = _LengthBase[sym] + (int)r.Take(_LengthExtra[sym]);
                int dsym = _Decode(ref r, dist);
                if (dsym < 0 || dsym >= 30)
                    return error("invalid distance code in the deflate data", CompressionError.InvalidData);
                int distance = _DistBase[dsym] + (int)r.Take(_DistExtra[dsym]);
                if (r.PastEnd())
                    return error("the deflate data is truncated", CompressionError.Truncated);
                if (distance > o.Count)
                    return error("a distance before the start of the deflate data", CompressionError.InvalidData);
                o.Room(length);
                int from = o.Count - distance;
                for (var i = 0; i < length; i += 1)
                    o.Data[o.Count + i] = o.Data[from + i];
                o.Count += length;
            }
        }
        if (r.PastEnd())
            return error("the deflate data is truncated", CompressionError.Truncated);
        if (final == 1)
            break;
    }

    var result = new uint8[o.Count];
    Array.Copy(o.Data, 0, result, 0, o.Count);
    return _Inflated { Data = result, End = r.BytePos() };
}
