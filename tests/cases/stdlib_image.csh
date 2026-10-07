// Standard library: System.Image - Color, Image (pixels, Crop, Copy with overlap, Clone), PNG/BMP/PPM encoding and
// decoding (palette and true color, with and without alpha), format detection, the errors. The program runs in a
// temporary directory. Main returns the number of failed checks.
// expect-stdout: color #80FF0000 #00FFFFFF
// expect-stdout: png 7 x 5 indexed 3
// expect-stdout: ppm P6
// expect-stdout: missing: CannotOpen
// expect-stdout: unknown: Unsupported
// expect-stdout: damaged: InvalidData
// expect-stdout: extension: Unsupported
// expect-exit: 0

using System;
using System.Image;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

bool SamePixels(const ref Image a, const ref Image b)
{
    if (a.Width != b.Width || a.Height != b.Height)
        return false;
    for (var i = 0; i < a.Pixels.Length; i += 1)
    {
        if (a.Pixels[i] != b.Pixels[i])
            return false;
    }
    return true;
}

// Encodes and decodes the image in a format; the pixels must stay the same (PPM: without alpha).
int RoundTrip(string name, const ref Image image, ImageFormat format)
{
    var bytes = image.Encode(format);
    if (Image.DetectFormat(bytes) is not ImageFormat detected)
        return Check(name + " detect", false);
    if (detected != format)
        return Check(name + " detect", false);
    var decoded = Image.Decode(bytes);
    if (decoded is not Image back)
    {
        Console.WriteLine("FAIL: " + name + ": " + decoded.Message);
        return 1;
    }
    var expected = image.Clone();
    if (format == ImageFormat.Ppm)
    {
        for (var i = 0; i < expected.Pixels.Length; i += 1)
            expected.Pixels[i] |= 0xFF000000u;
    }
    return Check(name, SamePixels(back, expected));
}

int Main()
{
    int f = 0;
    var c = Color.FromArgb(128, 255, 0, 0);
    Console.WriteLine("color " + c.ToString() + " " + Color.Transparent().ToString());
    f += Check("argb", Color.FromArgb(c.ToArgb()).Equals(c) && c.ToArgb() == 0x80FF0000u);
    f += Check("rgb", Color.FromRgb(1, 2, 3).A == 255);

    // a palette image: 3 colors, one of them transparent
    var small = Image.Create(7, 5);
    f += Check("created transparent", small.GetArgb(6, 4) == 0);
    small.Clear(Color.White());
    small.SetPixel(1, 1, Color.FromRgb(10, 20, 30));
    small.SetArgb(6, 4, 0x40102030u);
    f += Check("get", small.GetPixel(1, 1).G == 20 && small.Pixels[4 * 7 + 6] == 0x40102030u);
    var png = small.Encode(ImageFormat.Png);
    f += Check("indexed png", png[25] == 3);   // the color type in IHDR
    if (Image.Decode(png) is Image p)
        Console.WriteLine("png " + p.Width.ToString() + " x " + p.Height.ToString() + " indexed " + png[25].ToString());
    f += RoundTrip("small png", small, ImageFormat.Png);
    f += RoundTrip("small bmp", small, ImageFormat.Bmp);
    f += RoundTrip("small ppm", small, ImageFormat.Ppm);

    // true color: more than 256 colors, opaque and with alpha
    var random = Random.Create(3);
    var big = Image.Create(61, 43);
    for (var i = 0; i < big.Pixels.Length; i += 1)
        big.Pixels[i] = 0xFF000000u | (uint32)random.Next(0x1000000);
    f += RoundTrip("rgb png", big, ImageFormat.Png);
    f += RoundTrip("rgb bmp", big, ImageFormat.Bmp);
    f += RoundTrip("rgb ppm", big, ImageFormat.Ppm);
    var alpha = big.Clone();
    for (var i = 0; i < alpha.Pixels.Length; i += 3)
        alpha.Pixels[i] &= 0x7FFFFFFFu;
    f += Check("clone is a copy", big.Pixels[0] != alpha.Pixels[0]);
    f += RoundTrip("rgba png", alpha, ImageFormat.Png);
    f += RoundTrip("rgba bmp", alpha, ImageFormat.Bmp);
    var empty = Image.Create(0, 0);
    f += Check("empty png", Image.Decode(empty.Encode(ImageFormat.Png)) is error);

    // crop and copy (also within the same image, overlapping)
    var part = big.Crop(10, 5, 4, 3);
    f += Check("crop", part.Width == 4 && part.GetArgb(3, 2) == big.GetArgb(13, 7));
    var target = Image.Create(5, 5, Color.Black());
    target.Copy(part, 3, -1);   // clipped: 2 x 2 pixels land at 3, 0
    f += Check("copy clipped", target.GetArgb(3, 0) == part.GetArgb(0, 1) && target.GetArgb(4, 1) == part.GetArgb(1, 2) &&
                               target.GetArgb(2, 0) == 0xFF000000u);
    var shifted = big.Clone();
    shifted.Copy(shifted, 0, 0, 20, 20, 2, 3);
    f += Check("copy overlapping", shifted.GetArgb(2, 3) == big.GetArgb(0, 0) && shifted.GetArgb(21, 22) == big.GetArgb(19, 19));

    // files
    string path = "cshift_image_test.png";
    f += Check("save", big.Save(path) is not error);
    f += Check("load", Image.Load(path) is Image loaded && SamePixels(loaded, big));
    f += Check("save as bmp", big.Save(path, ImageFormat.Bmp) is not error);
    f += Check("load bmp", Image.Load(path) is Image loadedBmp && SamePixels(loadedBmp, big));
    File.Delete(path);
    var ppm = big.Encode(ImageFormat.Ppm);
    Console.WriteLine("ppm " + string.FromBytes(ppm, 0, 2));
    f += Check("text ppm", Image.Decode("P3\n# c\n2 1\n100\n100 0 50  0 0 0\n".AsBytes()) is Image t &&
                           t.GetArgb(0, 0) == 0xFFFF0080u && t.GetArgb(1, 0) == 0xFF000000u);

    // errors
    if (Image.Load("cshift_no_such_image.png") is error e1)
        Console.WriteLine("missing: " + e1.Code.ToString());
    if (Image.Decode("GIF89a".AsBytes()) is error e2)
        Console.WriteLine("unknown: " + e2.Code.ToString());
    var damaged = png.Clone();
    damaged[40] ^= 0xFF;
    if (Image.Decode(damaged) is error e3)
        Console.WriteLine("damaged: " + e3.Code.ToString());
    if (big.Save("cshift_image_test.gif") is error e4)
        Console.WriteLine("extension: " + e4.Code.ToString());
    for (var i = 0; i < 300; i += 1)
    {
        var bad = png.Clone();
        bad[8 + random.Next(bad.Length - 8)] = (uint8)random.Next(256);
        Image.Decode(bad[0..random.Next(bad.Length) + 1]);
    }
    return f;
}
