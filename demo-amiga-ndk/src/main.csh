// demo-amiga-ndk: a rotating wireframe cube in an Intuition window, written against the AmigaOS NDK 3.2.
//
// The library functions come from the NDK's SFD files ("using Intui from "intuition_lib.sfd";": the compiler calls
// them with their register arguments, and the libraries are opened when the program starts), the structures, flags and
// tags from its C headers ("using I from "intuition/intuition.h";"). The rotation uses FastTrig (tables and fixed
// point: no floating point on a 68000 without an FPU). Close the window to end it (or give a number of frames:
// "demo-amiga-ndk 300").
//
// Build it with the NDK: "ndk" in cshift.json, --ndk <dir> or the environment variable CSHIFT_NDK.

using System;
using Exec from "exec_lib.sfd";
using Intui from "intuition_lib.sfd";
using Gfx from "graphics_lib.sfd";
using I from "intuition/intuition.h";

const int Size = 60;         // half the edge of the cube
const int Distance = 260;    // how far the viewer is away
const int Zoom = 220;

// the corners and the edges of a cube
const ReadOnlySlice<int> CornerX = [-1, 1, 1, -1, -1, 1, 1, -1];
const ReadOnlySlice<int> CornerY = [-1, -1, 1, 1, -1, -1, 1, 1];
const ReadOnlySlice<int> CornerZ = [-1, -1, -1, -1, 1, 1, 1, 1];
const ReadOnlySlice<int> EdgeFrom = [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3];
const ReadOnlySlice<int> EdgeTo = [1, 2, 3, 0, 5, 6, 7, 4, 4, 5, 6, 7];

struct Projected
{
    Fixed<int, 8> X;
    Fixed<int, 8> Y;
}

// The corners rotated about the y and the x axis and projected onto the window (centered at cx, cy); aspect: the
// height of a pixel in relation to its width, in 1/256 (a hires screen without interlace has pixels twice as high).
Projected Project(int angleY, int angleX, int cx, int cy, int aspect)
{
    var p = Projected { };
    int sy = FastTrig.Sin(angleY);
    int cyA = FastTrig.Cos(angleY);
    int sx = FastTrig.Sin(angleX);
    int cxA = FastTrig.Cos(angleX);
    for (var i = 0; i < 8; i += 1)
    {
        int x = CornerX[i] * Size;
        int y = CornerY[i] * Size;
        int z = CornerZ[i] * Size;
        // about the y axis
        int x1 = (x * cyA - z * sy) >> 14;
        int z1 = (x * sy + z * cyA) >> 14;
        // about the x axis
        int y2 = (y * cxA - z1 * sx) >> 14;
        int z2 = (y * sx + z1 * cxA) >> 14;
        int depth = z2 + Distance;
        p.X[i] = cx + x1 * Zoom / depth;
        p.Y[i] = cy + y2 * Zoom * 256 / aspect / depth;
    }
    return p;
}

void DrawCube(void* rp, Projected p, int pen)
{
    Gfx.SetAPen(rp, (uint8)pen);
    for (var e = 0; e < 12; e += 1)
    {
        Gfx.Move(rp, (int16)p.X[EdgeFrom[e]], (int16)p.Y[EdgeFrom[e]]);
        Gfx.Draw(rp, (int16)p.X[EdgeTo[e]], (int16)p.Y[EdgeTo[e]]);
    }
}

int Main(string[] args)
{
    int frames = -1;
    if (args.Length > 0 && args[0].ParseInt() is int n)
        frames = n;

    unsafe
    {
        var window = (I.Window*)Intui.OpenWindowTags(null,
            I.WA_Left, 40, I.WA_Top, 30, I.WA_Width, 320, I.WA_Height, 200,
            I.WA_Title, "CShift on AmigaOS".CStr(),
            I.WA_Flags, I.WFLG_CLOSEGADGET | I.WFLG_DRAGBAR | I.WFLG_DEPTHGADGET | I.WFLG_ACTIVATE | I.WFLG_SMART_REFRESH,
            I.WA_IDCMP, I.IDCMP_CLOSEWINDOW,
            I.TAG_DONE);
        if (window == null)
        {
            Console.WriteLine("cannot open the window");
            return 20;
        }
        void* rp = window->RPort;
        int left = window->BorderLeft;
        int top = window->BorderTop;
        int right = window->Width - window->BorderRight - 1;
        int bottom = window->Height - window->BorderBottom - 1;
        // a hires screen without interlace (640 x 256): pixels are twice as high as wide
        I.Screen* screen = window->WScreen;
        int aspect = screen->Width >= 640 && screen->Height < 400 ? 512 : 256;
        int cx = (left + right) / 2;
        int cy = (top + bottom) / 2 + 6;

        Gfx.SetAPen(rp, (uint8)1);
        Gfx.Move(rp, (int16)(left + 6), (int16)(top + 10));
        string caption = "NDK 3.2 + SFD + FastTrig";
        Gfx.Text(rp, caption, (uint16)caption.Length);

        int angle = 0;
        var last = Project(0, 0, cx, cy, aspect);
        bool running = true;
        while (running && frames != 0)
        {
            // the messages of the window: the close gadget ends the program
            while (true)
            {
                var message = (I.IntuiMessage*)Exec.GetMsg(window->UserPort);
                if (message == null)
                    break;
                if (message->Class == I.IDCMP_CLOSEWINDOW)
                    running = false;
                Exec.ReplyMsg(message);
            }
            var next = Project(angle, angle / 2 + 40, cx, cy, aspect);
            Gfx.WaitTOF();
            DrawCube(rp, last, 0);  // erase the last one
            DrawCube(rp, next, 2);
            last = next;
            angle += 8;
            if (frames > 0)
                frames -= 1;
        }
        Intui.CloseWindow(window);
    }
    Console.WriteLine("bye");
    return 0;
}
