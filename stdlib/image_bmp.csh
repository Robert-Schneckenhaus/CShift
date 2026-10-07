namespace System.Image;

using System;

// BMP (Windows bitmap): decoding of the OS/2 and Windows headers (12 to 124 bytes), 1, 4, 8, 16, 24 and 32 bits per
// pixel, RLE4/RLE8 and bit fields; encoding with 24 bits per pixel, or 32 bits with an alpha mask (BITMAPV4HEADER) when
// the image has transparent pixels.

// A mask of bit fields: where its bits are and how many there are.
struct _BmpMask
{
    uint32 Mask;
    int Shift;
    int Bits;

    static _BmpMask Create(uint32 mask)
    {
        var m = _BmpMask { Mask = mask };
        if (mask == 0)
            return m;
        while (((mask >> m.Shift) & 1) == 0)
            m.Shift += 1;
        uint32 rest = mask >> m.Shift;
        while (m.Bits < 32 && (rest & 1) != 0)
        {
            m.Bits += 1;
            rest >>= 1;
        }
        return m;
    }

    // The field of the pixel as 0 to 255.
    int Get(uint32 pixel)
    {
        if (Bits == 0)
            return 0;
        uint32 value = (pixel & Mask) >> Shift;
        if (Bits >= 8)
            return (int)(value >> (Bits - 8));
        // the bits are repeated to fill 8 (like GDI+: 5 bits abcde become abcdeabc)
        int result = 0;
        int shift = 8 - Bits;
        while (shift > -Bits)
        {
            result |= shift >= 0 ? (int)(value << shift) : (int)(value >> -shift);
            shift -= Bits;
        }
        return result & 255;
    }
}

ImageError<Image> _DecodeBmp(ReadOnlySlice<uint8> d)
{
    if (d.Length < 26)
        return error("the BMP file is truncated", ImageError.InvalidData);
    int64 pixelOffset = _ImageLittle32(d, 10);
    int headerSize = (int)_ImageLittle32(d, 14);
    int width;
    int height;
    int bpp;
    int compression = 0;
    int colorsUsed = 0;
    int paletteEntry = 4;
    int masksAfterHeader = 0;
    if (headerSize == 12)
    {
        width = _ImageLittle16(d, 18);
        height = _ImageLittle16(d, 20);
        bpp = _ImageLittle16(d, 24);
        paletteEntry = 3;
    }
    else if (headerSize >= 40 && headerSize <= 124 && 14 + headerSize <= d.Length)
    {
        width = (int)_ImageLittle32(d, 18);
        height = (int)_ImageLittle32(d, 22);
        bpp = _ImageLittle16(d, 28);
        compression = (int)_ImageLittle32(d, 30);
        colorsUsed = (int)_ImageLittle32(d, 46);
        if (headerSize == 40 && compression == 3)
            masksAfterHeader = 12;
        else if (headerSize == 40 && compression == 6)
            masksAfterHeader = 16;
    }
    else
        return error("unknown BMP header (" + headerSize.ToString() + " bytes)", ImageError.Unsupported);

    bool topDown = height < 0;
    if (topDown)
        height = -height;
    if (width <= 0 || height <= 0 || (int64)width * height > 0x10000000)
        return error("invalid BMP image size", ImageError.InvalidData);
    if (compression == 4 || compression == 5)
        return error("BMP files with JPEG or PNG data are not supported", ImageError.Unsupported);
    if (compression != 0 && compression != 1 && compression != 2 && compression != 3 && compression != 6)
        return error("unknown BMP compression " + compression.ToString(), ImageError.Unsupported);
    if (bpp != 1 && bpp != 4 && bpp != 8 && bpp != 16 && bpp != 24 && bpp != 32)
        return error("BMP files with " + bpp.ToString() + " bits per pixel are not supported", ImageError.Unsupported);
    if ((compression == 1 && bpp != 8) || (compression == 2 && bpp != 4) || ((compression == 3 || compression == 6) && bpp != 16 && bpp != 32))
        return error("invalid BMP compression for " + bpp.ToString() + " bits per pixel", ImageError.InvalidData);

    // the masks: bit fields, or the defaults (5-5-5 for 16 bits; 32 bits have no alpha without bit fields)
    var red = _BmpMask.Create(0x00FF0000u);
    var green = _BmpMask.Create(0x0000FF00u);
    var blue = _BmpMask.Create(0x000000FFu);
    var alpha = _BmpMask.Create(0);
    if (bpp == 16)
    {
        red = _BmpMask.Create(0x7C00u);
        green = _BmpMask.Create(0x03E0u);
        blue = _BmpMask.Create(0x001Fu);
    }
    if (compression == 3 || compression == 6)
    {
        int at = headerSize == 40 ? 54 : 54;
        if (at + 12 > d.Length)
            return error("the BMP file is truncated", ImageError.InvalidData);
        red = _BmpMask.Create(_ImageLittle32(d, at));
        green = _BmpMask.Create(_ImageLittle32(d, at + 4));
        blue = _BmpMask.Create(_ImageLittle32(d, at + 8));
        if ((headerSize >= 56 || compression == 6) && at + 16 <= d.Length)
            alpha = _BmpMask.Create(_ImageLittle32(d, at + 12));
    }

    // the palette
    var palette = new uint32[256];
    if (bpp <= 8)
    {
        int count = colorsUsed > 0 && colorsUsed <= 256 ? colorsUsed : 1 << bpp;
        int start = 14 + headerSize + masksAfterHeader;
        for (var i = 0; i < count; i += 1)
        {
            int p = start + i * paletteEntry;
            if (p + 3 > d.Length || (pixelOffset > start && p + 3 > pixelOffset))
                break;
            palette[i] = 0xFF000000u | ((uint32)d[p + 2] << 16) | ((uint32)d[p + 1] << 8) | d[p];
        }
    }

    var image = Image.Create(width, height);
    if (compression == 1 || compression == 2)
    {
        if (pixelOffset >= d.Length)
            return error("the BMP file is truncated", ImageError.InvalidData);
        _DecodeBmpRle(d, (int)pixelOffset, compression == 2, palette, topDown, ref image);
        return image;
    }

    int64 stride = ((int64)width * bpp + 31) / 32 * 4;
    if (pixelOffset + stride * (height - 1) + ((int64)width * bpp + 7) / 8 > d.Length)
        return error("the BMP file is truncated", ImageError.InvalidData);
    for (var row = 0; row < height; row += 1)
    {
        int y = topDown ? row : height - 1 - row;
        int p = (int)(pixelOffset + stride * row);
        int target = y * width;
        for (var x = 0; x < width; x += 1)
        {
            uint32 argb;
            switch (bpp)
            {
                case 1: argb = palette[(d[p + (x >> 3)] >> (7 - (x & 7))) & 1]; break;
                case 4: argb = palette[(d[p + (x >> 1)] >> (4 - (x & 1) * 4)) & 15]; break;
                case 8: argb = palette[d[p + x]]; break;
                case 24:
                {
                    int q = p + x * 3;
                    argb = 0xFF000000u | ((uint32)d[q + 2] << 16) | ((uint32)d[q + 1] << 8) | d[q];
                    break;
                }
                default:
                {
                    uint32 pixel = bpp == 16 ? (uint32)_ImageLittle16(d, p + x * 2) : _ImageLittle32(d, p + x * 4);
                    int a = alpha.Bits > 0 ? alpha.Get(pixel) : 255;
                    argb = ((uint32)a << 24) | ((uint32)red.Get(pixel) << 16) | ((uint32)green.Get(pixel) << 8) | (uint32)blue.Get(pixel);
                    break;
                }
            }
            image.Pixels[target + x] = argb;
        }
    }
    return image;
}

// RLE8 and RLE4: runs and absolute parts from the bottom row on; skipped pixels stay transparent.
void _DecodeBmpRle(ReadOnlySlice<uint8> d, int pos, bool four, uint32[] palette, bool topDown, ref Image image)
{
    int x = 0;
    int y = 0;
    int width = image.Width;
    int height = image.Height;
    while (pos + 1 < d.Length && y < height)
    {
        int n = d[pos];
        int c = d[pos + 1];
        pos += 2;
        if (n > 0)
        {
            for (var i = 0; i < n; i += 1)
            {
                int index = four ? ((i & 1) == 0 ? c >> 4 : c & 15) : c;
                _BmpRlePixel(ref image, x, y, palette[index], topDown);
                x += 1;
            }
            continue;
        }
        if (c == 0)
        {
            x = 0;
            y += 1;
        }
        else if (c == 1)
            break;
        else if (c == 2)
        {
            if (pos + 1 >= d.Length)
                break;
            x += d[pos];
            y += d[pos + 1];
            pos += 2;
        }
        else
        {
            int bytes = four ? (c + 1) / 2 : c;
            for (var i = 0; i < c; i += 1)
            {
                int p = pos + (four ? i >> 1 : i);
                if (p >= d.Length)
                    break;
                int index = four ? ((i & 1) == 0 ? d[p] >> 4 : d[p] & 15) : d[p];
                _BmpRlePixel(ref image, x, y, palette[index], topDown);
                x += 1;
            }
            pos += (bytes + 1) & ~1;
        }
    }
}

void _BmpRlePixel(ref Image image, int x, int y, uint32 argb, bool topDown)
{
    if (x >= image.Width || y >= image.Height)
        return;
    int row = topDown ? y : image.Height - 1 - y;
    image.Pixels[row * image.Width + x] = argb;
}

uint8[] _EncodeBmp(const ref Image image)
{
    int width = image.Width;
    int height = image.Height;
    bool opaque = true;
    for (var i = 0; i < image.Pixels.Length; i += 1)
    {
        if ((image.Pixels[i] >> 24) != 255)
        {
            opaque = false;
            break;
        }
    }
    int bpp = opaque ? 24 : 32;
    int headerSize = opaque ? 40 : 108;
    int stride = (width * bpp + 31) / 32 * 4;
    int offset = 14 + headerSize;
    int size = offset + stride * height;

    var o = _ImageBytes.Create(size);
    o.Add('B');
    o.Add('M');
    o.AddLittle32((uint32)size);
    o.AddLittle32(0);
    o.AddLittle32((uint32)offset);
    o.AddLittle32((uint32)headerSize);
    o.AddLittle32((uint32)width);
    o.AddLittle32((uint32)height);    // bottom-up
    o.AddLittle16(1);
    o.AddLittle16(bpp);
    o.AddLittle32(opaque ? 0u : 3u);  // BI_RGB or BI_BITFIELDS
    o.AddLittle32((uint32)(stride * height));
    o.AddLittle32(3780);              // 96 dots per inch
    o.AddLittle32(3780);
    o.AddLittle32(0);
    o.AddLittle32(0);
    if (!opaque)
    {
        o.AddLittle32(0x00FF0000u);
        o.AddLittle32(0x0000FF00u);
        o.AddLittle32(0x000000FFu);
        o.AddLittle32(0xFF000000u);
        o.AddLittle32(0x73524742u);   // 'sRGB'
        for (var i = 0; i < 12; i += 1)
            o.AddLittle32(0);         // end points and gamma (unused with sRGB)
    }
    for (var row = height - 1; row >= 0; row -= 1)
    {
        int start = o.Count;
        int source = row * width;
        for (var x = 0; x < width; x += 1)
        {
            uint32 p = image.Pixels[source + x];
            o.Add((uint8)p);
            o.Add((uint8)(p >> 8));
            o.Add((uint8)(p >> 16));
            if (!opaque)
                o.Add((uint8)(p >> 24));
        }
        while (o.Count - start < stride)
            o.Add(0);
    }
    return o.ToArray();
}
