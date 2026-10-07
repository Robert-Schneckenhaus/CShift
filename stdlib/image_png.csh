namespace System.Image;

using System;
using System.Compression;

// PNG (ISO/IEC 15948): decoding of all color types, bit depths and interlacing; encoding with a palette for up to 256
// colors, else RGB or RGBA with 8 bits per channel.

// The passes of Adam7 interlacing: the first column and row, and the steps.
const ReadOnlySlice<int> _Adam7X = [0, 4, 0, 2, 0, 1, 0];
const ReadOnlySlice<int> _Adam7Y = [0, 0, 4, 0, 2, 0, 1];
const ReadOnlySlice<int> _Adam7DX = [8, 8, 4, 4, 2, 2, 1];
const ReadOnlySlice<int> _Adam7DY = [8, 8, 8, 4, 4, 2, 2];

// The 16-bit gray values at which GDI+ steps to the next 8-bit value (measured: its conversion is not linear).
const ReadOnlySlice<int> _Gray16Steps = [
    127, 379, 632, 884, 1137, 1389, 1641, 1894, 2146, 2399, 2649, 2892, 3122, 3551, 3752, 3946,
    4315, 4490, 4827, 4988, 5298, 5595, 5737, 6015, 6281, 6538, 6786, 7026, 7373, 7596, 7812, 8127,
    8330, 8626, 8913, 9099, 9371, 9635, 9893, 10143, 10387, 10704, 10935, 11161, 11456, 11671, 11952, 12226,
    12493, 12690, 12947, 13261, 13506, 13746, 13982, 14270, 14497, 14774, 15046, 15312, 15573, 15829, 16081, 16328,
    16571, 16810, 17091, 17368, 17594, 17862, 18124, 18383, 18637, 18887, 19133, 19416, 19655, 19929, 20160, 20426,
    20688, 20946, 21201, 21452, 21734, 21977, 22218, 22489, 22755, 22986, 23246, 23503, 23787, 24037, 24283, 24557,
    24797, 25064, 25328, 25559, 25816, 26098, 26349, 26597, 26869, 27111, 27377, 27640, 27874, 28131, 28410, 28661,
    28909, 29179, 29422, 29687, 29948, 30207, 30462, 30716, 30966, 31237, 31482, 31747, 31988, 32248, 32505, 32759,
    33032, 33282, 33529, 33795, 34057, 34317, 34575, 34830, 35083, 35334, 35601, 35847, 36110, 36370, 36627, 36883,
    37136, 37387, 37654, 37901, 38163, 38422, 38680, 38935, 39189, 39456, 39705, 39969, 40214, 40473, 40730, 40985,
    41254, 41505, 41769, 42016, 42276, 42534, 42791, 43045, 43312, 43562, 43825, 44072, 44331, 44588, 44844, 45097,
    45363, 45612, 45874, 46134, 46392, 46648, 46902, 47154, 47418, 47680, 47927, 48185, 48442, 48697, 48962, 49214,
    49476, 49724, 49982, 50239, 50506, 50760, 51011, 51273, 51534, 51781, 52037, 52304, 52558, 52810, 53072, 53332,
    53590, 53847, 54102, 54356, 54608, 54870, 55129, 55388, 55644, 55899, 56153, 56416, 56666, 56926, 57183, 57440,
    57695, 57958, 58210, 58471, 58729, 58977, 59243, 59497, 59751, 60012, 60262, 60520, 60777, 61042, 61297, 61549,
    61810, 62069, 62327, 62583, 62838, 63092, 63353, 63604, 63862, 64119, 64375, 64638, 64891, 65152, 65411
];

// The header and the transparency of a PNG image while it is decoded.
struct _PngInfo
{
    int Width;
    int Height;
    int BitDepth;
    int ColorType;
    int Channels;
    uint32[] Palette;     // ARGB, alpha from tRNS
    int PaletteCount;
    bool HasKey;          // tRNS of gray and RGB images: this color is transparent
    int KeyR;
    int KeyG;
    int KeyB;
}

ImageError<Image> _DecodePng(ReadOnlySlice<uint8> data)
{
    var info = _PngInfo { Palette = new uint32[256] };
    var idat = _ImageBytes.Create(data.Length);
    bool header = false;
    bool ended = false;
    int pos = 8;
    while (pos + 12 <= data.Length)
    {
        uint32 length32 = _ImageBig32(data, pos);
        if (length32 > 0x7FFFFFFFu || pos + 12 + (int64)length32 > data.Length)
            return error("a PNG chunk is truncated", ImageError.InvalidData);
        int length = (int)length32;
        var type = data[pos + 4..pos + 8];
        var body = data[pos + 8..pos + 8 + length];
        uint32 crc = _ImageBig32(data, pos + 8 + length);
        bool critical = (type[0] & 0x20) == 0;
        if (Crc32.Compute(data[pos + 4..pos + 8 + length]) != crc)
        {
            if (critical)
                return error("a PNG chunk has a wrong CRC", ImageError.InvalidData);
            pos += 12 + length;
            continue;
        }
        pos += 12 + length;

        if (_IsChunk(type, "IHDR"))
        {
            if (length != 13)
                return error("invalid PNG header", ImageError.InvalidData);
            uint32 w = _ImageBig32(body, 0);
            uint32 h = _ImageBig32(body, 4);
            info.BitDepth = body[8];
            info.ColorType = body[9];
            if (w == 0 || h == 0 || w > 0x7FFFFFFFu || h > 0x7FFFFFFFu || (int64)w * h > 0x10000000)
                return error("invalid PNG image size", ImageError.InvalidData);
            info.Width = (int)w;
            info.Height = (int)h;
            int d = info.BitDepth;
            switch (info.ColorType)
            {
                case 0: info.Channels = 1; if (d != 1 && d != 2 && d != 4 && d != 8 && d != 16) return error("invalid PNG bit depth", ImageError.InvalidData); break;
                case 3: info.Channels = 1; if (d != 1 && d != 2 && d != 4 && d != 8) return error("invalid PNG bit depth", ImageError.InvalidData); break;
                case 2: info.Channels = 3; if (d != 8 && d != 16) return error("invalid PNG bit depth", ImageError.InvalidData); break;
                case 4: info.Channels = 2; if (d != 8 && d != 16) return error("invalid PNG bit depth", ImageError.InvalidData); break;
                case 6: info.Channels = 4; if (d != 8 && d != 16) return error("invalid PNG bit depth", ImageError.InvalidData); break;
                default: return error("invalid PNG color type", ImageError.InvalidData);
            }
            if (body[10] != 0 || body[11] != 0 || body[12] > 1)
                return error("unknown PNG compression, filter or interlace method", ImageError.InvalidData);
            header = true;
        }
        else if (!header)
            return error("the PNG header is missing", ImageError.InvalidData);
        else if (_IsChunk(type, "PLTE"))
        {
            if (length % 3 != 0 || length / 3 > 256)
                return error("invalid PNG palette", ImageError.InvalidData);
            info.PaletteCount = length / 3;
            for (var i = 0; i < info.PaletteCount; i += 1)
                info.Palette[i] = 0xFF000000u | ((uint32)body[i * 3] << 16) | ((uint32)body[i * 3 + 1] << 8) | body[i * 3 + 2];
        }
        else if (_IsChunk(type, "tRNS"))
        {
            if (info.ColorType == 3)
            {
                for (var i = 0; i < length && i < 256; i += 1)
                    info.Palette[i] = (info.Palette[i] & 0x00FFFFFFu) | ((uint32)body[i] << 24);
            }
            else if (info.ColorType == 0 && length >= 2)
            {
                info.HasKey = true;
                info.KeyR = (body[0] << 8) | body[1];
                info.KeyG = info.KeyR;
                info.KeyB = info.KeyR;
            }
            else if (info.ColorType == 2 && length >= 6)
            {
                info.HasKey = true;
                info.KeyR = (body[0] << 8) | body[1];
                info.KeyG = (body[2] << 8) | body[3];
                info.KeyB = (body[4] << 8) | body[5];
            }
        }
        else if (_IsChunk(type, "IDAT"))
            idat.AddRange(body);
        else if (_IsChunk(type, "IEND"))
        {
            ended = true;
            break;
        }
        else if (critical)
            return error("unknown critical PNG chunk '" + string.FromBytes(type.ToArray()) + "'", ImageError.Unsupported);
    }
    if (!header)
        return error("the PNG header is missing", ImageError.InvalidData);
    if (!ended && idat.Count == 0)
        return error("the PNG data is truncated", ImageError.InvalidData);
    if (info.ColorType == 3 && info.PaletteCount == 0)
        return error("the PNG palette is missing", ImageError.InvalidData);

    var inflated = Zlib.Decompress(idat.Data[0..idat.Count]);
    if (inflated is not uint8[] raw)
        return error("invalid PNG pixel data: " + inflated.Message, ImageError.InvalidData);

    var image = Image.Create(info.Width, info.Height);
    int bitsPerPixel = info.Channels * info.BitDepth;
    int filterStep = Math.Max(1, bitsPerPixel / 8);
    int offset = 0;
    bool interlaced = data.Length > 0 && _PngInterlaced(data);
    int passes = interlaced ? 7 : 1;
    for (var pass = 0; pass < passes; pass += 1)
    {
        int x0 = interlaced ? _Adam7X[pass] : 0;
        int y0 = interlaced ? _Adam7Y[pass] : 0;
        int dx = interlaced ? _Adam7DX[pass] : 1;
        int dy = interlaced ? _Adam7DY[pass] : 1;
        if (x0 >= info.Width || y0 >= info.Height)
            continue;
        int columns = (info.Width - x0 + dx - 1) / dx;
        int rows = (info.Height - y0 + dy - 1) / dy;
        int rowBytes = (int)(((int64)columns * bitsPerPixel + 7) / 8);
        var previous = new uint8[rowBytes];
        var current = new uint8[rowBytes];
        for (var row = 0; row < rows; row += 1)
        {
            if (offset + 1 + rowBytes > raw.Length)
                return error("the PNG pixel data is truncated", ImageError.InvalidData);
            int filter = raw[offset];
            Array.Copy(raw, offset + 1, current, 0, rowBytes);
            offset += 1 + rowBytes;
            if (!_Unfilter(filter, current, previous, filterStep))
                return error("invalid PNG filter type", ImageError.InvalidData);
            _PngRow(ref info, current, ref image, x0, y0 + row * dy, dx, columns);
            var swap = previous;
            previous = current;
            current = swap;
        }
    }
    return image;
}

bool _PngInterlaced(ReadOnlySlice<uint8> data)
{
    // IHDR is the first chunk; its interlace method is its last byte
    return data.Length > 28 && data[28] == 1;
}

bool _IsChunk(ReadOnlySlice<uint8> type, StringSlice name)
{
    return type[0] == name[0] && type[1] == name[1] && type[2] == name[2] && type[3] == name[3];
}

bool _Unfilter(int filter, uint8[] row, uint8[] prior, int step)
{
    int n = row.Length;
    switch (filter)
    {
        case 0:
            break;
        case 1:
            for (var i = step; i < n; i += 1)
                row[i] = unchecked(row[i] + row[i - step]);
            break;
        case 2:
            for (var i = 0; i < n; i += 1)
                row[i] = unchecked(row[i] + prior[i]);
            break;
        case 3:
            for (var i = 0; i < n; i += 1)
            {
                int left = i >= step ? row[i - step] : 0;
                row[i] = unchecked(row[i] + (uint8)((left + prior[i]) >> 1));
            }
            break;
        case 4:
            for (var i = 0; i < n; i += 1)
            {
                int a = i >= step ? row[i - step] : 0;
                int b = prior[i];
                int c = i >= step ? prior[i - step] : 0;
                row[i] = unchecked(row[i] + (uint8)_Paeth(a, b, c));
            }
            break;
        default:
            return false;
    }
    return true;
}

int _Paeth(int a, int b, int c)
{
    int p = a + b - c;
    int pa = Math.Abs(p - a);
    int pb = Math.Abs(p - b);
    int pc = Math.Abs(p - c);
    if (pa <= pb && pa <= pc)
        return a;
    return pb <= pc ? b : c;
}

// Converts an unfiltered row into pixels: `columns` pixels from x0, y, every dx-th.
void _PngRow(ref _PngInfo info, uint8[] row, ref Image image, int x0, int y, int dx, int columns)
{
    int depth = info.BitDepth;
    int baseIndex = y * image.Width;
    for (var i = 0; i < columns; i += 1)
    {
        uint32 argb;
        switch (info.ColorType)
        {
            case 3:
                argb = info.Palette[_PngSample(row, i, depth)];
                break;
            case 0:
            {
                int v = _PngSample(row, i, depth);
                // 16 bits: scaled down, not cut (like GDI+)
                int g = depth == 16 ? _Gray16(v) : _PngScale(v, depth);
                argb = 0xFF000000u | ((uint32)g << 16) | ((uint32)g << 8) | (uint32)g;
                if (info.HasKey && v == info.KeyR)
                    argb = 0;   // transparent black (like GDI+)
                break;
            }
            case 2:
            {
                int r = _PngSample(row, i * 3, depth);
                int g = _PngSample(row, i * 3 + 1, depth);
                int b = _PngSample(row, i * 3 + 2, depth);
                argb = 0xFF000000u | ((uint32)_PngScale(r, depth) << 16) | ((uint32)_PngScale(g, depth) << 8) | (uint32)_PngScale(b, depth);
                if (info.HasKey && r == info.KeyR && g == info.KeyG && b == info.KeyB)
                    argb &= 0x00FFFFFFu;
                break;
            }
            case 4:
            {
                int g = _PngScale(_PngSample(row, i * 2, depth), depth);
                int a = _PngScale(_PngSample(row, i * 2 + 1, depth), depth);
                argb = ((uint32)a << 24) | ((uint32)g << 16) | ((uint32)g << 8) | (uint32)g;
                break;
            }
            default:
            {
                int r = _PngScale(_PngSample(row, i * 4, depth), depth);
                int g = _PngScale(_PngSample(row, i * 4 + 1, depth), depth);
                int b = _PngScale(_PngSample(row, i * 4 + 2, depth), depth);
                int a = _PngScale(_PngSample(row, i * 4 + 3, depth), depth);
                argb = ((uint32)a << 24) | ((uint32)r << 16) | ((uint32)g << 8) | (uint32)b;
                break;
            }
        }
        image.Pixels[baseIndex + x0 + i * dx] = argb;
    }
}

// The index-th sample of a row of samples with `depth` bits.
int _PngSample(uint8[] row, int index, int depth)
{
    switch (depth)
    {
        case 8: return row[index];
        case 16: return (row[index * 2] << 8) | row[index * 2 + 1];
        case 4: return (row[index >> 1] >> (4 - (index & 1) * 4)) & 15;
        case 2: return (row[index >> 2] >> (6 - (index & 3) * 2)) & 3;
        default: return (row[index >> 3] >> (7 - (index & 7))) & 1;
    }
}

// A 16-bit gray value as 0 to 255, like GDI+.
int _Gray16(int value)
{
    int low = 0;
    int high = _Gray16Steps.Length;
    while (low < high)
    {
        int middle = (low + high) / 2;
        if (_Gray16Steps[middle] <= value)
            low = middle + 1;
        else
            high = middle;
    }
    return low;
}

// A sample with `depth` bits as 0 to 255.
int _PngScale(int value, int depth)
{
    switch (depth)
    {
        case 8: return value;
        case 16: return value >> 8;
        case 4: return value * 17;
        case 2: return value * 85;
        default: return value * 255;
    }
}

uint8[] _EncodePng(const ref Image image)
{
    int width = image.Width;
    int height = image.Height;
    var pixels = image.Pixels;

    // up to 256 colors: a palette (transparent colors first, so that tRNS is short)
    bool opaque = true;
    for (var i = 0; i < pixels.Length; i += 1)
    {
        if ((pixels[i] >> 24) != 255)
        {
            opaque = false;
            break;
        }
    }
    var indices = Dictionary<uint32, int>.Create();
    var palette = List<uint32>.Create();
    for (var i = 0; i < pixels.Length && palette.Count() <= 256; i += 1)
    {
        if (!indices.ContainsKey(pixels[i]))
        {
            indices[pixels[i]] = palette.Count();
            palette.Add(pixels[i]);
        }
    }
    bool indexed = palette.Count() <= 256 && pixels.Length > 0;
    int transparentCount = 0;
    if (indexed)
    {
        var sorted = List<uint32>.Create();
        foreach (var c in palette)
        {
            if ((c >> 24) != 255)
                sorted.Add(c);
        }
        transparentCount = sorted.Count();
        foreach (var c in palette)
        {
            if ((c >> 24) == 255)
                sorted.Add(c);
        }
        palette = sorted;
        for (var i = 0; i < palette.Count(); i += 1)
            indices[palette[i]] = i;
    }

    int colorType;
    int depth = 8;
    int channels;
    if (indexed)
    {
        colorType = 3;
        channels = 1;
        int count = palette.Count();
        depth = count <= 2 ? 1 : count <= 4 ? 2 : count <= 16 ? 4 : 8;
    }
    else if (opaque)
    {
        colorType = 2;
        channels = 3;
    }
    else
    {
        colorType = 6;
        channels = 4;
    }

    // the filtered rows: no filter for palettes, else the one with the smallest sum of the absolute values per row
    int rowBytes = (width * channels * depth + 7) / 8;
    int step = Math.Max(1, channels * depth / 8);
    var raw = new uint8[(rowBytes + 1) * height];
    var prior = new uint8[rowBytes];
    var row = new uint8[rowBytes];
    var candidate = new uint8[rowBytes];
    var best = new uint8[rowBytes];
    for (var y = 0; y < height; y += 1)
    {
        for (var i = 0; i < rowBytes; i += 1)
            row[i] = 0;
        int baseIndex = y * width;
        for (var x = 0; x < width; x += 1)
        {
            uint32 p = pixels[baseIndex + x];
            if (indexed)
            {
                int index = indices[p];
                int bit = x * depth;
                row[bit >> 3] |= (uint8)(index << (8 - depth - (bit & 7)));
            }
            else
            {
                int o = x * channels;
                row[o] = (uint8)(p >> 16);
                row[o + 1] = (uint8)(p >> 8);
                row[o + 2] = (uint8)p;
                if (channels == 4)
                    row[o + 3] = (uint8)(p >> 24);
            }
        }
        int start = y * (rowBytes + 1);
        if (indexed)
        {
            raw[start] = 0;
            Array.Copy(row, 0, raw, start + 1, rowBytes);
        }
        else
        {
            int bestFilter = 0;
            int64 bestSum = -1;
            for (var filter = 0; filter < 5; filter += 1)
            {
                _Filter(filter, row, prior, candidate, step);
                int64 sum = 0;
                for (var i = 0; i < rowBytes; i += 1)
                {
                    int v = candidate[i];
                    sum += v < 128 ? v : 256 - v;
                }
                if (bestSum < 0 || sum < bestSum)
                {
                    bestSum = sum;
                    bestFilter = filter;
                    Array.Copy(candidate, 0, best, 0, rowBytes);
                }
            }
            raw[start] = (uint8)bestFilter;
            Array.Copy(best, 0, raw, start + 1, rowBytes);
        }
        var swap = prior;
        prior = row;
        row = swap;
    }

    var o = _ImageBytes.Create(raw.Length / 2 + 1024);
    o.AddRange([0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    var ihdr = _ImageBytes.Create(13);
    ihdr.AddBig32((uint32)width);
    ihdr.AddBig32((uint32)height);
    ihdr.Add((uint8)depth);
    ihdr.Add((uint8)colorType);
    ihdr.Add(0);
    ihdr.Add(0);
    ihdr.Add(0);
    _PngChunk(ref o, "IHDR", ihdr.Data[0..ihdr.Count]);
    if (indexed)
    {
        var plte = new uint8[palette.Count() * 3];
        for (var i = 0; i < palette.Count(); i += 1)
        {
            plte[i * 3] = (uint8)(palette[i] >> 16);
            plte[i * 3 + 1] = (uint8)(palette[i] >> 8);
            plte[i * 3 + 2] = (uint8)palette[i];
        }
        _PngChunk(ref o, "PLTE", plte);
        if (transparentCount > 0)
        {
            var trns = new uint8[transparentCount];
            for (var i = 0; i < transparentCount; i += 1)
                trns[i] = (uint8)(palette[i] >> 24);
            _PngChunk(ref o, "tRNS", trns);
        }
    }
    _PngChunk(ref o, "IDAT", Zlib.Compress(raw, 9));
    _PngChunk(ref o, "IEND", new uint8[0]);
    return o.ToArray();
}

void _Filter(int filter, uint8[] row, uint8[] prior, uint8[] result, int step)
{
    int n = row.Length;
    for (var i = 0; i < n; i += 1)
    {
        int a = i >= step ? row[i - step] : 0;
        int b = prior[i];
        int c = i >= step ? prior[i - step] : 0;
        int predicted;
        switch (filter)
        {
            case 0: predicted = 0; break;
            case 1: predicted = a; break;
            case 2: predicted = b; break;
            case 3: predicted = (a + b) >> 1; break;
            default: predicted = _Paeth(a, b, c); break;
        }
        result[i] = (uint8)(row[i] - predicted);
    }
}

void _PngChunk(ref _ImageBytes o, StringSlice type, ReadOnlySlice<uint8> body)
{
    o.AddBig32((uint32)body.Length);
    int start = o.Count;
    o.AddText(type);
    o.AddRange(body);
    o.AddBig32(Crc32.Compute(o.Data[start..o.Count]));
}
