namespace System.Image;

using System;

// Netpbm: decoding of PBM, PGM and PPM (P1 to P6, text and binary, up to 16 bits per sample); encoding as a binary PPM
// (P6) with 8 bits per sample.

// The reader of the header and of the text formats: numbers between white space and comments.
struct _PnmReader
{
    ReadOnlySlice<uint8> Data;
    int Pos;

    void SkipSpace()
    {
        while (Pos < Data.Length)
        {
            uint8 c = Data[Pos];
            if (c == '#')
            {
                while (Pos < Data.Length && Data[Pos] != '\n' && Data[Pos] != '\r')
                    Pos += 1;
            }
            else if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x0B || c == 0x0C)
                Pos += 1;
            else
                break;
        }
    }

    // The next number, or -1 if there is none.
    int Number()
    {
        SkipSpace();
        if (Pos >= Data.Length || Data[Pos] < '0' || Data[Pos] > '9')
            return -1;
        int64 value = 0;
        while (Pos < Data.Length && Data[Pos] >= '0' && Data[Pos] <= '9')
        {
            value = value * 10 + (Data[Pos] - '0');
            if (value > 0x7FFFFFFF)
                return -1;
            Pos += 1;
        }
        return (int)value;
    }

    // The next bit of a P1 image (digits may follow each other without space), or -1.
    int Bit()
    {
        SkipSpace();
        if (Pos >= Data.Length || (Data[Pos] != '0' && Data[Pos] != '1'))
            return -1;
        int bit = Data[Pos] - '0';
        Pos += 1;
        return bit;
    }
}

ImageError<Image> _DecodePpm(ReadOnlySlice<uint8> data)
{
    int kind = data[1] - '0';
    var r = _PnmReader { Data = data, Pos = 2 };
    int width = r.Number();
    int height = r.Number();
    int max = kind == 1 || kind == 4 ? 1 : r.Number();
    if (width <= 0 || height <= 0 || (int64)width * height > 0x10000000)
        return error("invalid PPM image size", ImageError.InvalidData);
    if (max <= 0 || max > 65535)
        return error("invalid PPM maximum value", ImageError.InvalidData);
    if (kind >= 4)
    {
        // exactly one white space character before the binary data
        if (r.Pos >= data.Length)
            return error("the PPM file is truncated", ImageError.InvalidData);
        r.Pos += 1;
    }
    var image = Image.Create(width, height);
    int channels = kind == 3 || kind == 6 ? 3 : 1;
    int sampleBytes = max > 255 ? 2 : 1;
    int count = width * height;

    if (kind == 4)
    {
        int rowBytes = (width + 7) / 8;
        if (r.Pos + (int64)rowBytes * height > data.Length)
            return error("the PPM file is truncated", ImageError.InvalidData);
        for (var y = 0; y < height; y += 1)
        {
            for (var x = 0; x < width; x += 1)
            {
                int bit = (data[r.Pos + y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1;
                image.Pixels[y * width + x] = bit == 1 ? 0xFF000000u : 0xFFFFFFFFu;
            }
        }
        return image;
    }
    if (kind >= 5 && r.Pos + (int64)count * channels * sampleBytes > data.Length)
        return error("the PPM file is truncated", ImageError.InvalidData);

    var samples = new int[channels];
    for (var i = 0; i < count; i += 1)
    {
        for (var c = 0; c < channels; c += 1)
        {
            int v;
            if (kind == 1)
                v = r.Bit();
            else if (kind <= 3)
                v = r.Number();
            else if (sampleBytes == 2)
            {
                v = (data[r.Pos] << 8) | data[r.Pos + 1];
                r.Pos += 2;
            }
            else
            {
                v = data[r.Pos];
                r.Pos += 1;
            }
            if (v < 0)
                return error("the PPM file is truncated", ImageError.InvalidData);
            if (v > max)
                return error("a PPM sample is larger than the maximum value", ImageError.InvalidData);
            samples[c] = kind == 1 ? (v == 1 ? 0 : 255) : (int)(((int64)v * 255 + max / 2) / max);
        }
        uint32 red = (uint32)samples[0];
        uint32 green = channels == 3 ? (uint32)samples[1] : red;
        uint32 blue = channels == 3 ? (uint32)samples[2] : red;
        image.Pixels[i] = 0xFF000000u | (red << 16) | (green << 8) | blue;
    }
    return image;
}

uint8[] _EncodePpm(const ref Image image)
{
    var o = _ImageBytes.Create(image.Pixels.Length * 3 + 32);
    o.AddText("P6\n" + image.Width.ToString() + " " + image.Height.ToString() + "\n255\n");
    for (var i = 0; i < image.Pixels.Length; i += 1)
    {
        uint32 p = image.Pixels[i];
        o.Add((uint8)(p >> 16));
        o.Add((uint8)(p >> 8));
        o.Add((uint8)p);
    }
    return o.ToArray();
}
