// demo-amiga-gfx: bouncing balls on the Amiga's custom chips, with Amiga.Screen and the blitter (runs on every Amiga,
// from the A500 with a 68000 on).
//
// A 16-color screen with double buffering: the background (lines, rectangles, text in the system font) is drawn once
// into a bitmap of its own. Per frame the blitter puts the background back where the balls were two frames ago and
// draws the balls (bobs, with a mask) at their new places; then the screen swaps its bitmaps. The copper colors the
// sky line by line, a hardware sprite flies along a sine curve. The left mouse button ends it (or the number of
// frames given as the argument: "demo-amiga-gfx 500").

using System;
using Amiga;

const int Width = 320;
const int Height = 256;
const int BallCount = 8;
const int BallSize = 16;
const int Ground = 200;              // the first line of the floor

// a ball in the colors 8..11 (dark .. bright)
const ReadOnlySlice<string> BallPattern = embed_lines("ball.txt");

// a small ship for the sprite (colors 1..3 of the sprite: 17..19)
const ReadOnlySlice<string> ShipPattern = embed_lines("ship.txt");

// the background: a sky (color 0, colored by the copper), a floor of tiles, a frame and the title
void DrawBackground(Bitmap b)
{
    b.Clear();
    for (var x = 0; x < Width; x += 32)
    {
        b.FillRect(x, Ground, 16, Height - Ground, 4);
        b.FillRect(x + 16, Ground, 16, Height - Ground, 5);
    }
    for (var x = -160; x <= Width + 160; x += 40)
        b.DrawLine(Width / 2, Ground, x, Height - 1, 6);
    b.FillRect(0, Ground, Width, 2, 7);
    b.DrawRect(8, 8, Width - 16, 34, 7);
    string title = "CShift on the Amiga";
    int x0 = (Width - SystemFont.TextWidth(title)) / 2;
    b.DrawText(x0 + 1, 13, title, 3);   // a shadow
    b.DrawText(x0, 12, title, 1);
    string line = "Amiga.Screen: blitter, copper, sprites";
    b.DrawText((Width - SystemFont.TextWidth(line)) / 2, 26, line, 2);
}

int Main(string[] args)
{
    int frames = -1;
    if (args.Length > 0 && args[0].ParseInt() is int n)
        frames = n;
    Console.WriteLine("CShift graphics - press the left mouse button to quit");

    if (!Hardware.TakeOver())
    {
        Console.WriteLine("cannot open graphics.library");
        return 20;
    }
    if (Screen.Open(Width, Height, 4, true) is Screen screen)
    {
        if (Bitmap.Create(Width, Height, 4) is Bitmap background)
        {
            if (Bitmap.Create(BallSize, BallSize, 4) is Bitmap ball)
            {
                Run(screen, background, ball, frames);
                ball.Free();
            }
            background.Free();
        }
        Hardware.Restore();
        screen.Close();
    }
    else
        Hardware.Restore();
    Console.WriteLine("bye");
    return 0;
}

void Run(Screen screen, Bitmap background, Bitmap ball, int frames)
{
    // the palette: 1-3 text, 4-7 the floor, 8-11 the balls, 17-19 the sprite
    screen.SetColor(1, 0xFFF);
    screen.SetColor(2, 0xFC4);
    screen.SetColor(3, 0x225);
    screen.SetColor(4, 0x363);
    screen.SetColor(5, 0x252);
    screen.SetColor(6, 0x5A5);
    screen.SetColor(7, 0x8D8);
    screen.SetColor(8, 0x600);
    screen.SetColor(9, 0xB20);
    screen.SetColor(10, 0xF73);
    screen.SetColor(11, 0xFFB);
    screen.SetColor(17, 0x444);
    screen.SetColor(18, 0x0AF);
    screen.SetColor(19, 0xEEE);

    // the sky: the copper changes color 0 every 8 lines (dark blue to light blue above the floor)
    for (var y = 0; y < Ground; y += 8)
    {
        screen.Copper.Wait(y);
        int b = 3 + y * 12 / Ground;
        screen.Copper.Color(0, ((b / 3) << 8) | ((b / 2) << 4) | b);
    }
    screen.Copper.Wait(Ground);
    screen.Copper.Color(0, 0x000);

    DrawBackground(background);
    screen.Front.Copy(background, 0, 0, 0, 0, Width, Height);
    screen.Back.Copy(background, 0, 0, 0, 0, Width, Height);
    
    ball.DrawPattern(0, 0, BallPattern);   

    if (ball.MakeMask() is Bitmap mask)
    {
        if (Sprite.Create(ShipPattern) is Sprite ship)
        {
            screen.ShowSprite(0, ship);
            screen.Show();
            Animate(screen, background, ball, mask, ship, frames);
            screen.HideSprite(0);
            Hardware.WaitVBlank();
            ship.Free();
        }
        mask.Free();
    }
}

void Animate(Screen screen, Bitmap background, Bitmap ball, Bitmap mask, Sprite ship, int frames)
{
    // the balls: position and speed in 1/16 pixels; where they were drawn into each of the two bitmaps
    var x = new int[BallCount];
    var y = new int[BallCount];
    var vx = new int[BallCount];
    var vy = new int[BallCount];
    var oldX = new int[BallCount * 2];
    var oldY = new int[BallCount * 2];
    for (var i = 0; i < BallCount; i += 1)
    {
        x[i] = (20 + i * 36) * 16;
        y[i] = (50 + (i * 37) % 100) * 16;
        vx[i] = (i % 2 == 0 ? 1 : -1) * (12 + i * 5);
        vy[i] = 0;
        oldX[i] = -1;
        oldX[BallCount + i] = -1;
    }
    int buffer = 0;
    int phase = 0;
    while (!Hardware.LeftMouseButton() && frames != 0)
    {
        Bitmap back = screen.Back;
        // the background back where the balls were in this bitmap (two frames ago)
        for (var i = 0; i < BallCount; i += 1)
        {
            int ox = oldX[buffer * BallCount + i];
            if (ox >= 0)
            {
                int oy = oldY[buffer * BallCount + i];
                int wx = ox & ~15;  // whole words are faster for the blitter
                back.Copy(background, wx, oy, wx, oy, 32, BallSize);
            }
        }
        // move and draw the balls
        for (var i = 0; i < BallCount; i += 1)
        {
            vy[i] += 6; // gravity
            x[i] += vx[i];
            y[i] += vy[i];
            if (x[i] < 0 || x[i] > (Width - BallSize) * 16)
            {
                vx[i] = -vx[i];
                x[i] += 2 * vx[i];
            }
            if (y[i] > (Ground - BallSize) * 16)
            {
                y[i] = (Ground - BallSize) * 16;
                vy[i] = -vy[i] * 15 / 16;
                if (vy[i] > -150)
                    vy[i] = -260 - i * 8; // a new jump
            }
            int bx = x[i] >> 4;
            int by = y[i] >> 4;
            back.DrawMasked(ball, mask, 0, 0, bx, by, BallSize, BallSize);
            oldX[buffer * BallCount + i] = bx;
            oldY[buffer * BallCount + i] = by;
        }
        ship.MoveTo(Width / 2 - 8 + ((140 * FastTrig.Sin(phase)) >> 14), 60 + ((20 * FastTrig.Sin(phase * 3)) >> 14));
        phase += 4;
        screen.Swap();
        buffer = 1 - buffer;
        if (frames > 0)
            frames -= 1;
    }
}
