namespace System.Image;

using System;

//! Images in memory and the file formats PNG, BMP and PPM: [Image] holds the pixels as 32-bit ARGB values, [Color]
//! is one of them.
//!
//! ```
//! using System.Image;
//!
//! var image = try Image.Load("sprite.png");          // PNG, BMP or PPM, found by the content
//! var c = image.GetPixel(0, 0);
//! image.SetPixel(1, 0, Color.FromArgb(255, c.R, 0, 0));
//! try image.Save("sprite.bmp");                      // the format from the extension
//! ```

/// The errors of loading, decoding and saving images ([Image.Load], [Image.Decode], [Image.Save]).
error ImageError
{
    /// The file does not exist or cannot be read.
    CannotOpen = 1,
    /// The file cannot be created or written.
    CannotWrite = 2,
    /// The data is not a valid image (a damaged or truncated file).
    InvalidData = 3,
    /// The format, or a variant of it, is not supported (an unknown file type or extension, a JPEG inside a BMP, ...).
    Unsupported = 4
}

/// The file formats of images.
enum ImageFormat : uint8
{
    /// PNG: all color types and bit depths, interlaced or not; written with the fewest colors that keep the image
    /// (a palette for up to 256 colors).
    Png = 0,
    /// BMP (Windows bitmap): 1, 4, 8, 16, 24 and 32 bits per pixel, RLE, bit fields; written with 24 bits per pixel, or
    /// 32 with alpha.
    Bmp = 1,
    /// PPM, PGM and PBM (Netpbm, `P1` to `P6`); written as a binary PPM (`P6`) without the alpha channel.
    Ppm = 2
}

/// A color: alpha, red, green and blue, from 0 to 255 each (an alpha of 0 is transparent, 255 opaque).
///
/// ```
/// var red = Color.FromRgb(255, 0, 0);
/// uint32 argb = red.ToArgb();                 // 0xFFFF0000
/// var same = Color.FromArgb(argb);
/// ```
struct Color : IEquatable<Color>, IHashable
{
    /// Alpha: 0 is transparent, 255 opaque.
    uint8 A;
    /// Red.
    uint8 R;
    /// Green.
    uint8 G;
    /// Blue.
    uint8 B;

    /// A color from its four components (0 to 255 each).
    /// @panics when a component is not 0 to 255.
    static Color FromArgb(int alpha, int red, int green, int blue)
    {
        if (alpha < 0 || alpha > 255 || red < 0 || red > 255 || green < 0 || green > 255 || blue < 0 || blue > 255)
            Environment.Panic("Color.FromArgb: the components must be 0 to 255 (" + alpha.ToString() + ", " + red.ToString() + ", " +
                              green.ToString() + ", " + blue.ToString() + ")");
        return Color { A = (uint8)alpha, R = (uint8)red, G = (uint8)green, B = (uint8)blue };
    }

    /// An opaque color from red, green and blue (0 to 255 each).
    /// @panics when a component is not 0 to 255.
    static Color FromRgb(int red, int green, int blue)
    {
        return FromArgb(255, red, green, blue);
    }

    /// A color from a 32-bit value `0xAARRGGBB` (the value of [Color.ToArgb] and of [Image.Pixels]).
    static Color FromArgb(uint32 argb)
    {
        return Color { A = (uint8)(argb >> 24), R = (uint8)(argb >> 16), G = (uint8)(argb >> 8), B = (uint8)argb };
    }

    /// The color as a 32-bit value `0xAARRGGBB`.
    uint32 ToArgb()
    {
        return ((uint32)A << 24) | ((uint32)R << 16) | ((uint32)G << 8) | B;
    }

    /// Transparent white, `0x00FFFFFF` (like `Color.Transparent` of .NET; [Image.Create] fills with transparent
    /// black, 0).
    static Color Transparent() { return FromArgb(0x00FFFFFFu); }
    /// Opaque black.
    static Color Black() { return FromArgb(0xFF000000u); }
    /// Opaque white.
    static Color White() { return FromArgb(0xFFFFFFFFu); }

    /// Whether all four components are the same.
    bool Equals(Color other)
    {
        return A == other.A && R == other.R && G == other.G && B == other.B;
    }

    /// A hash code (the ARGB value).
    int GetHashCode()
    {
        return (int)ToArgb();
    }

    /// The color as text: `#AARRGGBB`.
    string ToString()
    {
        return "#" + ToArgb().ToString("X8");
    }
}

/// An image: `Width` times `Height` pixels, stored row by row from the top left as 32-bit ARGB values (`0xAARRGGBB`,
/// not premultiplied) in `Pixels`.
///
/// ```
/// var image = Image.Create(16, 16);                  // transparent black
/// image.SetPixel(3, 4, Color.White());
/// uint32 argb = image.Pixels[4 * image.Width + 3];  // the same pixel, directly
/// try image.Save("glyph.png");
/// ```
///
/// Like a [List], an image is a small struct that points at its pixels: copies share them; [Image.Clone] copies
/// them. Images are decoded into this one format, whatever the file had (a palette, grayscale, 16 bits per channel:
/// those keep the 8 highest bits); saving chooses the format of the file ([ImageFormat]).
struct Image
{
    /// The width in pixels.
    int Width;
    /// The height in pixels.
    int Height;
    /// The pixels, row by row from the top left: `Pixels[y * Width + x]` is `0xAARRGGBB`.
    uint32[] Pixels;

    /// A new image of `width` times `height` transparent black pixels (0).
    /// @panics when a size is negative.
    static Image Create(int width, int height)
    {
        if (width < 0 || height < 0)
            Environment.Panic("Image.Create: the size must not be negative (" + width.ToString() + " x " + height.ToString() + ")");
        return Image { Width = width, Height = height, Pixels = new uint32[width * height] };
    }

    /// A new image of `width` times `height` pixels of the color `fill`.
    /// @panics when a size is negative.
    static Image Create(int width, int height, Color fill)
    {
        var image = Create(width, height);
        image.Clear(fill);
        return image;
    }

    /// Reads an image file: PNG, BMP or PPM/PGM/PBM, recognized by its content (not the extension).
    /// @error ImageError.CannotOpen the file does not exist or cannot be read.
    /// @error ImageError.InvalidData the file is damaged.
    /// @error ImageError.Unsupported the file has another format.
    static ImageError<Image> Load(StringSlice path)
    {
        var read = File.ReadAllBytes(path);
        if (read is not uint8[] bytes)
            return error("cannot open the image file '" + path + "'", ImageError.CannotOpen);
        var decoded = Decode(bytes);
        if (decoded is not Image image)
            return error(decoded.Message + " in '" + path + "'", decoded.Code);
        return image;
    }

    /// Decodes an image from the bytes of a PNG, BMP or PPM/PGM/PBM file.
    /// @error ImageError.InvalidData the data is damaged.
    /// @error ImageError.Unsupported the data has another format.
    static ImageError<Image> Decode(ReadOnlySlice<uint8> data)
    {
        var format = DetectFormat(data);
        if (format is not ImageFormat f)
            return error("unknown image format", ImageError.Unsupported);
        switch (f)
        {
            case ImageFormat.Png: return _DecodePng(data);
            case ImageFormat.Bmp: return _DecodeBmp(data);
            default: return _DecodePpm(data);
        }
    }

    /// The format of the bytes of an image file, recognized by its first bytes; `null` for none of PNG, BMP and
    /// PPM/PGM/PBM.
    static Optional<ImageFormat> DetectFormat(ReadOnlySlice<uint8> data)
    {
        if (data.Length >= 8 && data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G' &&
            data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A)
            return ImageFormat.Png;
        if (data.Length >= 2 && data[0] == 'B' && data[1] == 'M')
            return ImageFormat.Bmp;
        if (data.Length >= 2 && data[0] == 'P' && data[1] >= '1' && data[1] <= '6')
            return ImageFormat.Ppm;
        return null;
    }

    /// The format that belongs to the extension of `path` (`.png`, `.bmp`/`.dib`, `.ppm`/`.pnm`; any case), or
    /// `null`.
    static Optional<ImageFormat> FormatOfPath(StringSlice path)
    {
        var extension = Path.GetExtension(path).ToLower();
        if (extension == ".png")
            return ImageFormat.Png;
        if (extension == ".bmp" || extension == ".dib")
            return ImageFormat.Bmp;
        if (extension == ".ppm" || extension == ".pnm")
            return ImageFormat.Ppm;
        return null;
    }

    /// Writes the image to a file in the format of its extension ([Image.FormatOfPath]).
    /// @error ImageError.Unsupported the extension is none of the formats.
    /// @error ImageError.CannotWrite the file cannot be created or written.
    ImageError<void> Save(StringSlice path)
    {
        var format = FormatOfPath(path);
        if (format is not ImageFormat f)
            return error("unknown image file extension in '" + path + "' (.png, .bmp or .ppm)", ImageError.Unsupported);
        return Save(path, f);
    }

    /// Writes the image to a file in `format`, whatever the extension.
    /// @error ImageError.CannotWrite the file cannot be created or written.
    ImageError<void> Save(StringSlice path, ImageFormat format)
    {
        var written = File.WriteAllBytes(path, Encode(format));
        if (written is error e)
            return error(e.Message, ImageError.CannotWrite);
        return;
    }

    /// The bytes of the image as a file in `format`.
    uint8[] Encode(ImageFormat format)
    {
        switch (format)
        {
            case ImageFormat.Png: return _EncodePng(this);
            case ImageFormat.Bmp: return _EncodeBmp(this);
            default: return _EncodePpm(this);
        }
    }

    /// The color of the pixel at `x`, `y` (0, 0 is the top left).
    /// @panics when the position is outside of the image.
    Color GetPixel(int x, int y)
    {
        return Color.FromArgb(Pixels[_Index(x, y)]);
    }

    /// Sets the pixel at `x`, `y` to `color`.
    /// @panics when the position is outside of the image.
    void SetPixel(int x, int y, Color color)
    {
        Pixels[_Index(x, y)] = color.ToArgb();
    }

    /// The pixel at `x`, `y` as `0xAARRGGBB`.
    /// @panics when the position is outside of the image.
    uint32 GetArgb(int x, int y)
    {
        return Pixels[_Index(x, y)];
    }

    /// Sets the pixel at `x`, `y` to `0xAARRGGBB`.
    /// @panics when the position is outside of the image.
    void SetArgb(int x, int y, uint32 argb)
    {
        Pixels[_Index(x, y)] = argb;
    }

    /// Sets all pixels to `color`.
    void Clear(Color color)
    {
        uint32 argb = color.ToArgb();
        for (var i = 0; i < Pixels.Length; i += 1)
            Pixels[i] = argb;
    }

    /// A copy with its own pixels.
    Image Clone()
    {
        return Image { Width = Width, Height = Height, Pixels = Pixels.Clone() };
    }

    /// A new image of the part `width` times `height` from `x`, `y`.
    /// @panics when the part is not inside of the image.
    Image Crop(int x, int y, int width, int height)
    {
        if (x < 0 || y < 0 || width < 0 || height < 0 || x + width > Width || y + height > Height)
            Environment.Panic("Image.Crop: the part (" + x.ToString() + ", " + y.ToString() + ", " + width.ToString() + " x " +
                              height.ToString() + ") is not inside of the image (" + Width.ToString() + " x " + Height.ToString() + ")");
        var result = Create(width, height);
        for (var row = 0; row < height; row += 1)
            Array.Copy(Pixels, (y + row) * Width + x, result.Pixels, row * width, width);
        return result;
    }

    /// Copies the pixels of `source` to `x`, `y` (they replace the pixels there, alpha included: no blending). Parts
    /// outside of this image are left out.
    void Copy(const ref Image source, int x, int y)
    {
        Copy(source, 0, 0, source.Width, source.Height, x, y);
    }

    /// Copies the part `width` times `height` from `sourceX`, `sourceY` of `source` to `x`, `y` (the pixels replace the
    /// ones there: no blending). Parts outside of either image are left out; `source` may be this image, and the parts
    /// may overlap.
    void Copy(const ref Image source, int sourceX, int sourceY, int width, int height, int x, int y)
    {
        // clip against the source and the target
        if (sourceX < 0) { width += sourceX; x -= sourceX; sourceX = 0; }
        if (sourceY < 0) { height += sourceY; y -= sourceY; sourceY = 0; }
        if (x < 0) { width += x; sourceX -= x; x = 0; }
        if (y < 0) { height += y; sourceY -= y; y = 0; }
        width = Math.Min(width, Math.Min(source.Width - sourceX, Width - x));
        height = Math.Min(height, Math.Min(source.Height - sourceY, Height - y));
        if (width <= 0 || height <= 0)
            return;
        // rows go through a buffer, from the bottom up when the target is lower: overlapping parts stay right
        var row = new uint32[width];
        bool up = y > sourceY;
        for (var i = 0; i < height; i += 1)
        {
            int r = up ? height - 1 - i : i;
            Array.Copy(source.Pixels, (sourceY + r) * source.Width + sourceX, row, 0, width);
            Array.Copy(row, 0, Pixels, (y + r) * Width + x, width);
        }
    }

    int _Index(int x, int y)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height)
            Environment.Panic("pixel (" + x.ToString() + ", " + y.ToString() + ") is outside of the image (" + Width.ToString() + " x " +
                              Height.ToString() + ")");
        return y * Width + x;
    }
}

// Reads big-endian and little-endian numbers of the decoders.
uint32 _ImageBig32(ReadOnlySlice<uint8> d, int pos)
{
    return ((uint32)d[pos] << 24) | ((uint32)d[pos + 1] << 16) | ((uint32)d[pos + 2] << 8) | d[pos + 3];
}

uint32 _ImageLittle32(ReadOnlySlice<uint8> d, int pos)
{
    return (uint32)d[pos] | ((uint32)d[pos + 1] << 8) | ((uint32)d[pos + 2] << 16) | ((uint32)d[pos + 3] << 24);
}

int _ImageLittle16(ReadOnlySlice<uint8> d, int pos)
{
    return d[pos] | (d[pos + 1] << 8);
}

// A growable byte buffer of the encoders.
struct _ImageBytes
{
    uint8[] Data;
    int Count;

    static _ImageBytes Create(int capacity)
    {
        return _ImageBytes { Data = new uint8[capacity < 64 ? 64 : capacity] };
    }

    void Add(uint8 value)
    {
        if (Count == Data.Length)
            _Room(1);
        Data[Count] = value;
        Count += 1;
    }

    void AddRange(ReadOnlySlice<uint8> bytes)
    {
        _Room(bytes.Length);
        for (var i = 0; i < bytes.Length; i += 1)
            Data[Count + i] = bytes[i];
        Count += bytes.Length;
    }

    void AddText(StringSlice text)
    {
        AddRange(text.AsBytes());
    }

    void AddBig32(uint32 value)
    {
        Add((uint8)(value >> 24));
        Add((uint8)(value >> 16));
        Add((uint8)(value >> 8));
        Add((uint8)value);
    }

    void AddLittle16(int value)
    {
        Add((uint8)value);
        Add((uint8)(value >> 8));
    }

    void AddLittle32(uint32 value)
    {
        Add((uint8)value);
        Add((uint8)(value >> 8));
        Add((uint8)(value >> 16));
        Add((uint8)(value >> 24));
    }

    uint8[] ToArray()
    {
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
