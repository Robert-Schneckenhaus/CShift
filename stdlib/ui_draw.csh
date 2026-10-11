namespace System.Ui;

using System;
using System.Image;

//! Drawing for System.Ui: [Canvas] draws rectangles, rounded rectangles, circles, lines, text and images into an
//! [Image] (with clipping, transparency and smooth edges); [Font] is a bitmap font for its text.

/// A rectangle in pixels: X and Y are its top left corner.
struct Rect : IEquatable<Rect>
{
    /// The left edge.
    int X;
    /// The top edge.
    int Y;
    /// The width in pixels.
    int Width;
    /// The height in pixels.
    int Height;

    /// A rectangle with its top left corner at (x, y).
    static Rect Create(int x, int y, int width, int height)
    {
        return Rect { X = x, Y = y, Width = width, Height = height };
    }

    /// The first column to the right of the rectangle.
    int Right() { return X + Width; }

    /// The first row below the rectangle.
    int Bottom() { return Y + Height; }

    /// True if the point lies inside (the right and bottom edges are outside).
    bool Contains(int x, int y)
    {
        return x >= X && y >= Y && x < X + Width && y < Y + Height;
    }

    /// The rectangle made smaller by `amount` on every side (larger for a negative amount).
    Rect Shrink(int amount)
    {
        return Rect { X = X + amount, Y = Y + amount, Width = Math.Max(0, Width - 2 * amount), Height = Math.Max(0, Height - 2 * amount) };
    }

    /// The part that both rectangles cover (empty if they do not overlap).
    Rect Intersect(Rect other)
    {
        int left = Math.Max(X, other.X);
        int top = Math.Max(Y, other.Y);
        int right = Math.Min(X + Width, other.X + other.Width);
        int bottom = Math.Min(Y + Height, other.Y + other.Height);
        return Rect { X = left, Y = top, Width = Math.Max(0, right - left), Height = Math.Max(0, bottom - top) };
    }

    /// True if it covers no pixel.
    bool IsEmpty() { return Width <= 0 || Height <= 0; }

    /// True if both have the same position and size.
    bool Equals(Rect other)
    {
        return X == other.X && Y == other.Y && Width == other.Width && Height == other.Height;
    }

    /// "(x, y, width x height)".
    string ToString()
    {
        return $"({X}, {Y}, {Width} x {Height})";
    }
}

/// A bitmap font: every character is a cell of the same size. The two built-in fonts are the "fixed" fonts of X11,
/// with ASCII, Latin-1 and a few typographic marks and arrows; other characters are drawn as `?`. `Zoom` draws every
/// pixel of a glyph as a square of that many pixels.
struct Font
{
    /// The width of a character cell in pixels (without the zoom).
    int Width;
    /// The height of a character cell in pixels (without the zoom).
    int Height;
    /// How far the baseline is below the top of a cell.
    int Ascent;
    /// Every font pixel becomes Zoom x Zoom pixels.
    int Zoom;
    int[] _Codes;    // the characters, sorted
    uint16[] _Rows;  // Height rows per character, bit 15 = leftmost pixel
    int _Fallback;   // the glyph for characters that the font does not have

    /// 7 x 13 pixels: for a scale of 1 (96 dpi).
    static Font Fixed7x13()
    {
        return _Make(_Font7x13Width, _Font7x13Height, _Font7x13Ascent, _Font7x13Codes, _Font7x13Bits);
    }

    /// 10 x 20 pixels: for a scale of about 1.5.
    static Font Fixed10x20()
    {
        return _Make(_Font10x20Width, _Font10x20Height, _Font10x20Ascent, _Font10x20Codes, _Font10x20Bits);
    }

    /// The built-in font that suits a scale (1 = 96 dpi): 7x13, 10x20, and both zoomed for higher scales.
    static Font ForScale(double scale)
    {
        if (scale < 1.375)
            return Fixed7x13();
        if (scale < 2.25)
            return Fixed10x20();
        if (scale < 3.0)
            return Fixed7x13().Zoomed(2);
        return Fixed10x20().Zoomed(2);
    }

    static Font _Make(int width, int height, int ascent, ReadOnlySlice<int> codes, string bits)
    {
        int rowBytes = (width + 7) / 8;
        var rows = new uint16[codes.Length * height];
        int pos = 0;
        for (var i = 0; i < rows.Length; i += 1)
        {
            int value = 0;
            for (var b = 0; b < rowBytes * 2; b += 1)
            {
                value = value * 16 + Char.HexValue(bits[pos]);
                pos += 1;
            }
            rows[i] = (uint16)(rowBytes == 1 ? value << 8 : value);
        }
        var font = Font { Width = width, Height = height, Ascent = ascent, Zoom = 1, _Codes = codes.ToArray(), _Rows = rows };
        font._Fallback = font._Find('?');
        return font;
    }

    /// The same font with every pixel drawn `zoom` x `zoom` times.
    Font Zoomed(int zoom)
    {
        var font = Font { Width = Width, Height = Height, Ascent = Ascent, Zoom = Math.Max(1, zoom), _Codes = _Codes, _Rows = _Rows, _Fallback = _Fallback };
        return font;
    }

    /// The width of one character on the screen.
    int CharWidth() { return Width * Zoom; }

    /// The height of a line on the screen.
    int LineHeight() { return Height * Zoom; }

    /// The width of a text on the screen (every character has the same width).
    int Measure(StringSlice text)
    {
        return _CountChars(text) * Width * Zoom;
    }

    /// Draws text into a canvas with its top left corner at (x, y) and returns its width (see [Canvas.Text]).
    int Draw(ref Canvas canvas, int x, int y, StringSlice text, Color color)
    {
        int cw = Width * Zoom;
        int start = x;
        int i = 0;
        while (i < text.Length)
        {
            int length = 1;
            int code = _DecodeChar(text, i, ref length);
            i += length;
            if (x + cw > canvas.Clip.X && x < canvas.Clip.X + canvas.Clip.Width && code != 0x20)
                _DrawGlyph(ref canvas, _Glyph(code), x, y, color);
            x += cw;
        }
        return x - start;
    }

    void _DrawGlyph(ref Canvas canvas, int glyph, int x, int y, Color color)
    {
        if (glyph < 0)
            return;
        uint32 argb = color.ToArgb();
        bool opaque = color.A == 255;
        var clip = canvas.Clip;
        var pixels = canvas.Target.Pixels;
        int stride = canvas.Target.Width;
        int baseRow = glyph * Height;
        for (var row = 0; row < Height; row += 1)
        {
            int bits = (int)_Rows[baseRow + row];
            if (bits == 0)
                continue;
            for (var col = 0; col < Width; col += 1)
            {
                if ((bits & (0x8000 >> col)) == 0)
                    continue;
                for (var zy = 0; zy < Zoom; zy += 1)
                {
                    int py = y + row * Zoom + zy;
                    for (var zx = 0; zx < Zoom; zx += 1)
                    {
                        int px = x + col * Zoom + zx;
                        if (!clip.Contains(px, py))
                            continue;
                        if (opaque)
                            pixels[py * stride + px] = argb;
                        else
                            canvas.Blend(px, py, color, 255);
                    }
                }
            }
        }
    }

    /// The index of a character's glyph, or -1.
    int _Find(int code)
    {
        if (code >= 0x20 && code < 0x7F && _Codes.Length > 0x5E && _Codes[code - 0x20] == code)
            return code - 0x20;
        int low = 0;
        int high = _Codes.Length - 1;
        while (low <= high)
        {
            int middle = (low + high) / 2;
            int c = _Codes[middle];
            if (c == code)
                return middle;
            if (c < code)
                low = middle + 1;
            else
                high = middle - 1;
        }
        return -1;
    }

    int _Glyph(int code)
    {
        int index = _Find(code);
        return index >= 0 ? index : _Fallback;
    }
}

/// The number of characters (code points) of UTF-8 text.
int _CountChars(StringSlice text)
{
    int count = 0;
    for (var i = 0; i < text.Length; i += 1)
    {
        if (((int)text[i] & 0xC0) != 0x80)
            count += 1;
    }
    return count;
}

/// The code point that starts at byte `index` of UTF-8 text, and in `length` how many bytes it has. Broken sequences
/// give 0xFFFD and a length of 1.
int _DecodeChar(StringSlice text, int index, ref int length)
{
    int b = (int)text[index];
    length = 1;
    if (b < 0x80)
        return b;
    int count = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 0;
    if (count == 0 || index + count > text.Length)
        return 0xFFFD;
    int code = b & (0x7F >> count);
    for (var k = 1; k < count; k += 1)
    {
        int c = (int)text[index + k];
        if ((c & 0xC0) != 0x80)
            return 0xFFFD;
        code = (code << 6) | (c & 0x3F);
    }
    length = count;
    return code;
}

/// Draws into an [Image]: everything is clipped to `Clip`, colors with an alpha below 255 are blended with what is
/// already there, and the edges of rounded rectangles, circles and lines are smooth. A canvas shares the pixels of its
/// image (an Image holds them by reference), so drawing changes the image.
///
/// ```
/// var image = Image.Create(200, 100);
/// var canvas = Canvas.Create(image);
/// canvas.Clear(Color.White());
/// canvas.FillRoundRect(Rect.Create(10, 10, 120, 30), 6, Color.FromRgb(40, 110, 220));
/// canvas.Text(Font.Fixed7x13(), 20, 18, "Hello", Color.White());
/// ```
struct Canvas
{
    /// The image that is drawn into.
    Image Target;
    /// Only pixels inside this rectangle are changed.
    Rect Clip;

    /// A canvas for the whole image.
    static Canvas Create(Image target)
    {
        return Canvas { Target = target, Clip = Rect.Create(0, 0, target.Width, target.Height) };
    }

    /// Restricts drawing to a rectangle (within the image).
    void SetClip(Rect clip)
    {
        Clip = clip.Intersect(Rect.Create(0, 0, Target.Width, Target.Height));
    }

    /// Fills the whole image (ignoring the clip rectangle) with one color.
    void Clear(Color color)
    {
        uint32 argb = color.ToArgb();
        var pixels = Target.Pixels;
        for (var i = 0; i < pixels.Length; i += 1)
            pixels[i] = argb;
    }

    /// Blends one pixel: `coverage` 0 (nothing) to 255 (the color with its own alpha).
    void Blend(int x, int y, Color color, int coverage)
    {
        if (!Clip.Contains(x, y))
            return;
        int alpha = (int)color.A * coverage / 255;
        if (alpha <= 0)
            return;
        int index = y * Target.Width + x;
        if (alpha >= 255)
        {
            Target.Pixels[index] = color.ToArgb() | 0xFF000000u;
            return;
        }
        uint32 dst = Target.Pixels[index];
        int dr = (int)((dst >> 16) & 0xFFu);
        int dg = (int)((dst >> 8) & 0xFFu);
        int db = (int)(dst & 0xFFu);
        int r = dr + ((int)color.R - dr) * alpha / 255;
        int g = dg + ((int)color.G - dg) * alpha / 255;
        int b = db + ((int)color.B - db) * alpha / 255;
        Target.Pixels[index] = 0xFF000000u | ((uint32)r << 16) | ((uint32)g << 8) | (uint32)b;
    }

    /// Fills a rectangle.
    void FillRect(Rect rect, Color color)
    {
        var area = rect.Intersect(Clip);
        if (area.IsEmpty() || color.A == 0)
            return;
        if (color.A < 255)
        {
            for (var y = area.Y; y < area.Y + area.Height; y += 1)
            {
                for (var x = area.X; x < area.X + area.Width; x += 1)
                    Blend(x, y, color, 255);
            }
            return;
        }
        uint32 argb = color.ToArgb();
        var pixels = Target.Pixels;
        for (var y = area.Y; y < area.Y + area.Height; y += 1)
        {
            int row = y * Target.Width;
            for (var x = area.X; x < area.X + area.Width; x += 1)
                pixels[row + x] = argb;
        }
    }

    /// Draws the outline of a rectangle, `width` pixels thick, inside the rectangle.
    void StrokeRect(Rect rect, int width, Color color)
    {
        int w = Math.Min(width, Math.Min(rect.Width, rect.Height) / 2);
        FillRect(Rect.Create(rect.X, rect.Y, rect.Width, w), color);
        FillRect(Rect.Create(rect.X, rect.Y + rect.Height - w, rect.Width, w), color);
        FillRect(Rect.Create(rect.X, rect.Y + w, w, rect.Height - 2 * w), color);
        FillRect(Rect.Create(rect.X + rect.Width - w, rect.Y + w, w, rect.Height - 2 * w), color);
    }

    /// Fills a rectangle with rounded corners of the given radius (smooth edges).
    void FillRoundRect(Rect rect, int radius, Color color)
    {
        _RoundRect(rect, radius, -1.0, color);
    }

    /// Draws the outline of a rounded rectangle, `width` pixels thick, inside the rectangle.
    void StrokeRoundRect(Rect rect, int radius, int width, Color color)
    {
        _RoundRect(rect, radius, (double)width, color);
    }

    // A rounded rectangle, filled (width < 0) or its outline. Every pixel gets the part of it that the shape covers:
    // in the corners from the distance of its center to the corner's circle, elsewhere it is inside or outside.
    void _RoundRect(Rect rect, int radius, double width, Color color)
    {
        var area = rect.Intersect(Clip);
        if (area.IsEmpty())
            return;
        int r = Math.Clamp(radius, 0, Math.Min(rect.Width, rect.Height) / 2);
        if (r == 0 && width < 0)
        {
            FillRect(rect, color);
            return;
        }
        if (r == 0)
        {
            StrokeRect(rect, (int)width, color);
            return;
        }
        double inner = width < 0 ? -1.0 : (double)r - width; // the radius of the inner edge of an outline
        int w = width < 0 ? 0 : (int)width;
        for (var y = area.Y; y < area.Y + area.Height; y += 1)
        {
            int dy = y - rect.Y;
            bool cornerRow = dy < r || dy >= rect.Height - r;
            if (!cornerRow && width < 0)
            {
                FillRect(Rect.Create(area.X, y, area.Width, 1), color);
                continue;
            }
            if (!cornerRow)
            {
                // the straight sides of an outline
                FillRect(Rect.Create(rect.X, y, w, 1), color);
                FillRect(Rect.Create(rect.X + rect.Width - w, y, w, 1), color);
                continue;
            }
            double cy = dy < r ? (double)(rect.Y + r) : (double)(rect.Y + rect.Height - r);
            for (var x = area.X; x < area.X + area.Width; x += 1)
            {
                int dx = x - rect.X;
                double cx;
                if (dx < r)
                    cx = (double)(rect.X + r);
                else if (dx >= rect.Width - r)
                    cx = (double)(rect.X + rect.Width - r);
                else
                {
                    // the straight top and bottom edges
                    bool edge = width < 0 || dy < w || dy >= rect.Height - w;
                    if (edge)
                        Blend(x, y, color, 255);
                    continue;
                }
                double px = (double)x + 0.5 - cx;
                double py = (double)y + 0.5 - cy;
                double d = Math.Sqrt(px * px + py * py);
                double cover = Math.Clamp((double)r - d + 0.5, 0.0, 1.0);
                if (inner >= 0)
                    cover -= Math.Clamp(inner - d + 0.5, 0.0, 1.0);
                if (cover > 0)
                    Blend(x, y, color, (int)(cover * 255.0 + 0.5));
            }
        }
    }

    /// Fills a circle (smooth edge); the center may lie between pixels.
    void FillCircle(double cx, double cy, double radius, Color color)
    {
        int left = (int)Math.Floor(cx - radius);
        int top = (int)Math.Floor(cy - radius);
        int right = (int)Math.Ceiling(cx + radius);
        int bottom = (int)Math.Ceiling(cy + radius);
        for (var y = top; y <= bottom; y += 1)
        {
            for (var x = left; x <= right; x += 1)
            {
                double px = (double)x + 0.5 - cx;
                double py = (double)y + 0.5 - cy;
                double cover = Math.Clamp(radius - Math.Sqrt(px * px + py * py) + 0.5, 0.0, 1.0);
                if (cover > 0)
                    Blend(x, y, color, (int)(cover * 255.0 + 0.5));
            }
        }
    }

    /// Draws a line `width` pixels thick with round ends (smooth edges); coordinates may lie between pixels.
    void Line(double x0, double y0, double x1, double y1, double width, Color color)
    {
        double half = width / 2.0;
        int left = (int)Math.Floor(Math.Min(x0, x1) - half - 1.0);
        int top = (int)Math.Floor(Math.Min(y0, y1) - half - 1.0);
        int right = (int)Math.Ceiling(Math.Max(x0, x1) + half + 1.0);
        int bottom = (int)Math.Ceiling(Math.Max(y0, y1) + half + 1.0);
        double vx = x1 - x0;
        double vy = y1 - y0;
        double length2 = vx * vx + vy * vy;
        for (var y = top; y <= bottom; y += 1)
        {
            for (var x = left; x <= right; x += 1)
            {
                double px = (double)x + 0.5 - x0;
                double py = (double)y + 0.5 - y0;
                double t = length2 > 0 ? Math.Clamp((px * vx + py * vy) / length2, 0.0, 1.0) : 0.0;
                double ex = px - t * vx;
                double ey = py - t * vy;
                double cover = Math.Clamp(half - Math.Sqrt(ex * ex + ey * ey) + 0.5, 0.0, 1.0);
                if (cover > 0)
                    Blend(x, y, color, (int)(cover * 255.0 + 0.5));
            }
        }
    }

    /// Draws text with its top left corner at (x, y) and returns its width. Line ends are not interpreted.
    int Text(Font font, int x, int y, StringSlice text, Color color)
    {
        return font.Draw(ref this, x, y, text, color);
    }

    /// Draws an image with its top left corner at (x, y), blended by the alpha of its pixels.
    void DrawImage(Image image, int x, int y)
    {
        var area = Rect.Create(x, y, image.Width, image.Height).Intersect(Clip);
        for (var py = area.Y; py < area.Y + area.Height; py += 1)
        {
            int srcRow = (py - y) * image.Width;
            for (var px = area.X; px < area.X + area.Width; px += 1)
            {
                uint32 p = image.Pixels[srcRow + px - x];
                uint32 a = p >> 24;
                if (a == 255u)
                    Target.Pixels[py * Target.Width + px] = p;
                else if (a > 0u)
                    Blend(px, py, Color.FromArgb(p), 255);
            }
        }
    }
}
