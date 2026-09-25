// CShift + MiniFB: a window with an animated plasma.
//
// MiniFB.h is imported as the namespace Mfb (see includePaths in cshift.json). C functions, structs, enums and
// constants can be used directly; the callbacks below are ordinary CShift functions that C calls.
//
//   Esc  closes the window

using Mfb from "MiniFB.h";

const int Width = 320;
const int Height = 200;

// Called by MiniFB for every key event. Action<...> is the type of a function pointer without a result.
void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed && key == Mfb.mfb_key.KB_KEY_ESCAPE)
        Mfb.mfb_close(window);
}

// Func<mfb_window*, bool>: return true to let the window close.
bool OnClose(Mfb.mfb_window* window)
{
    Console.WriteLine("window closed");
    return true;
}

uint32 Rgb(int r, int g, int b)
{
    return ((uint32)r << 16) | ((uint32)g << 8) | (uint32)b;
}

int Channel(double value)
{
    return (int)(127.5 + 127.5 * Math.Sin(value));
}

int Main()
{
    Mfb.mfb_window* window = Mfb.mfb_open_ex("CShift + MiniFB", (uint32)(Width * 2), (uint32)(Height * 2), (uint32)Mfb.MFB_WF_RESIZABLE);
    if (window == null)
    {
        Console.WriteLine("cannot open the window");
        return 1;
    }
    Mfb.mfb_set_keyboard_callback(window, OnKey);
    Mfb.mfb_set_close_callback(window, OnClose);
    Mfb.mfb_set_target_fps(60);

    unsafe
    {
        uint32* pixels = (uint32*)Memory.Allocate(Width * Height * sizeof(uint32));
        int frame = 0;
        while (true)
        {
            double t = frame * 0.05;
            for (var y = 0; y < Height; y += 1)
            {
                for (var x = 0; x < Width; x += 1)
                {
                    double v = Math.Sin(x * 0.05 + t) + Math.Sin(y * 0.07 - t) + Math.Sin((x + y) * 0.03 + t * 0.5);
                    pixels[y * Width + x] = Rgb(Channel(v), Channel(v + 2.0), Channel(v + 4.0));
                }
            }
            if (Mfb.mfb_update_ex(window, pixels, (uint32)Width, (uint32)Height) != Mfb.mfb_update_state.MFB_STATE_OK)
                break;
            frame += 1;
            if (frame % 60 == 0)
                Mfb.mfb_set_title(window, "CShift + MiniFB - frame " + frame.ToString());
        }
        Memory.Free(pixels);
        Console.WriteLine("frames: " + frame.ToString());
    }
    return 0;
}
