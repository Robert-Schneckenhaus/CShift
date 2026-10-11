// CShift + GLFW: Snake, drawn by a tiny software renderer into a 160 x 120 picture that OpenGL 1.1 shows scaled up
// (glDrawPixels with glPixelZoom). The same program runs natively and in the browser (cshiftc --backend wasm, see
// docs/wasm.md): the game loop stays a plain loop.
//
//   arrow keys or WASD   steer
//   Space                start again after a crash
//   Esc                  quit

using System;

// GLFW and OpenGL, declared by hand (no C headers needed)
extern "C" int glfwInit();
extern "C" void glfwTerminate();
extern "C" void glfwWindowHint(int hint, int value);
extern "C" void* glfwCreateWindow(int width, int height, char* title, void* monitor, void* share);
extern "C" void glfwMakeContextCurrent(void* window);
extern "C" void glfwSwapInterval(int interval);
extern "C" int glfwWindowShouldClose(void* window);
extern "C" void glfwSetWindowShouldClose(void* window, int value);
extern "C" void glfwPollEvents();
extern "C" void glfwSwapBuffers(void* window);
extern "C" double glfwGetTime();
extern "C" void glfwGetFramebufferSize(void* window, ref int width, ref int height);
extern "C" Action<void*, int, int, int, int> glfwSetKeyCallback(void* window, Action<void*, int, int, int, int> callback);

extern "C" void glViewport(int x, int y, int width, int height);
extern "C" void glClearColor(float red, float green, float blue, float alpha);
extern "C" void glClear(uint32 mask);
extern "C" void glRasterPos2f(float x, float y);
extern "C" void glPixelZoom(float x, float y);
extern "C" void glDrawPixels(int width, int height, uint32 format, uint32 type, void* pixels);

const int GlfwResizable = 0x00020003;
const int GlfwPress = 1;
const int GlfwRepeat = 2;
const int KeySpace = 32;
const int KeyEscape = 256;
const int KeyRight = 262;
const int KeyLeft = 263;
const int KeyDown = 264;
const int KeyUp = 265;
const int KeyA = 65;
const int KeyD = 68;
const int KeyS = 83;
const int KeyW = 87;
const uint32 GlColorBufferBit = 0x4000;
const uint32 GlRgba = 0x1908;
const uint32 GlUnsignedByte = 0x1401;

const int ScreenWidth = 160;
const int ScreenHeight = 120;
const int Scale = 4;
const int Cell = 8;
const int Columns = 20;
const int Rows = 14;          // the top row of the screen shows the score
const double TickSeconds = 0.11;

struct Point
{
    int X;
    int Y;
}

// ---------------------------------------------------------------------------------------------------------------
// The picture: RGBA bytes, row 0 at the top
// ---------------------------------------------------------------------------------------------------------------

uint8[] pixels = new uint8[ScreenWidth * ScreenHeight * 4];

void FillRect(int x, int y, int width, int height, uint32 color)
{
    for (var row = y; row < y + height; row += 1)
    {
        if (row < 0 || row >= ScreenHeight)
            continue;
        for (var column = x; column < x + width; column += 1)
        {
            if (column < 0 || column >= ScreenWidth)
                continue;
            int at = (row * ScreenWidth + column) * 4;
            pixels[at] = (uint8)((color >> 16) & 255);
            pixels[at + 1] = (uint8)((color >> 8) & 255);
            pixels[at + 2] = (uint8)(color & 255);
            pixels[at + 3] = 255;
        }
    }
}

// A 3 x 5 font for digits and a few letters: 15 bits per glyph, the top row first.
int Glyph(char c)
{
    switch (c)
    {
    case '0': return 0x7B6F;
    case '1': return 0x2C97;
    case '2': return 0x73E7;
    case '3': return 0x73CF;
    case '4': return 0x5BC9;
    case '5': return 0x79CF;
    case '6': return 0x79EF;
    case '7': return 0x7292;
    case '8': return 0x7BEF;
    case '9': return 0x7BCF;
    case 'A': return 0x2BED;
    case 'C': return 0x7927;
    case 'E': return 0x79E7;
    case 'G': return 0x796F;
    case 'M': return 0x5FED;
    case 'O': return 0x7B6F;
    case 'P': return 0x7BE4;
    case 'R': return 0x7BF5;
    case 'S': return 0x79CF;
    case 'V': return 0x5B6A;
    default: return 0;
    }
}

void DrawText(string text, int x, int y, uint32 color)
{
    foreach (var c in text)
    {
        int glyph = Glyph(c);
        for (var bit = 0; bit < 15; bit += 1)
        {
            if ((glyph & (1 << (14 - bit))) != 0)
                FillRect(x + bit % 3, y + bit / 3, 1, 1, color);
        }
        x += 4;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// The game
// ---------------------------------------------------------------------------------------------------------------

List<Point> snake = List<Point>.Create();
Point direction = Point { X = 1, Y = 0 };
Point nextDirection = Point { X = 1, Y = 0 };
Point food = Point { X = 0, Y = 0 };
Random random = Random.Create(42);
int score = 0;
int best = 0;
bool over = false;

void Restart()
{
    snake.Clear();
    for (var i = 0; i < 4; i += 1)
        snake.Add(Point { X = 6 - i, Y = Rows / 2 });
    direction = Point { X = 1, Y = 0 };
    nextDirection = direction;
    score = 0;
    over = false;
    PlaceFood();
}

bool OnSnake(int x, int y)
{
    foreach (var p in snake)
    {
        if (p.X == x && p.Y == y)
            return true;
    }
    return false;
}

void PlaceFood()
{
    while (true)
    {
        int x = random.Next(Columns);
        int y = random.Next(Rows);
        if (!OnSnake(x, y))
        {
            food = Point { X = x, Y = y };
            return;
        }
    }
}

void Steer(int x, int y)
{
    // no turning back into the snake's own neck
    if (x == -direction.X && y == -direction.Y)
        return;
    nextDirection = Point { X = x, Y = y };
}

void OnKey(void* window, int key, int scancode, int action, int mods)
{
    if (action != GlfwPress && action != GlfwRepeat)
        return;
    if (key == KeyEscape)
        glfwSetWindowShouldClose(window, 1);
    else if (key == KeyUp || key == KeyW)
        Steer(0, -1);
    else if (key == KeyDown || key == KeyS)
        Steer(0, 1);
    else if (key == KeyLeft || key == KeyA)
        Steer(-1, 0);
    else if (key == KeyRight || key == KeyD)
        Steer(1, 0);
    else if (key == KeySpace && over)
        Restart();
}

void Tick()
{
    if (over)
        return;
    direction = nextDirection;
    Point head = snake.Get(0);
    int x = (head.X + direction.X + Columns) % Columns;
    int y = (head.Y + direction.Y + Rows) % Rows;
    bool eats = x == food.X && y == food.Y;
    if (!eats)
        snake.RemoveAt(snake.Count() - 1);
    if (OnSnake(x, y))
    {
        over = true;
        if (score > best)
            best = score;
        return;
    }
    snake.Insert(0, Point { X = x, Y = y });
    if (eats)
    {
        score += 1;
        PlaceFood();
    }
}

void Draw(double time)
{
    FillRect(0, 0, ScreenWidth, ScreenHeight, 0x10141C);
    FillRect(0, 0, ScreenWidth, 8, 0x232A38);
    DrawText("SCORE " + score.ToString(), 2, 2, 0xE8E8E8);
    DrawText(best.ToString(), ScreenWidth - 4 * best.ToString().Length - 2, 2, 0x8A93A6);
    int top = 8;
    // the food blinks
    if ((int)(time * 4) % 2 == 0)
        FillRect(food.X * Cell + 2, top + food.Y * Cell + 2, Cell - 4, Cell - 4, 0xFF5050);
    else
        FillRect(food.X * Cell + 1, top + food.Y * Cell + 1, Cell - 2, Cell - 2, 0xFF7070);
    for (var i = 0; i < snake.Count(); i += 1)
    {
        Point p = snake.Get(i);
        uint32 color = i == 0 ? 0xB8FF6Au : (i % 2 == 0 ? 0x5CC85Cu : 0x4CB04Cu);
        FillRect(p.X * Cell + 1, top + p.Y * Cell + 1, Cell - 2, Cell - 2, color);
    }
    if (over)
    {
        FillRect(40, 48, 80, 22, 0x000000);
        DrawText("GAME OVER", 62, 52, 0xFF7070);
        DrawText("SPACE", 70, 61, 0xE8E8E8);
    }
}

int Main()
{
    if (glfwInit() == 0)
        return 1;
    glfwWindowHint(GlfwResizable, 0);
    void* window;
    unsafe
    {
        window = glfwCreateWindow(ScreenWidth * Scale, ScreenHeight * Scale, "CShift Snake".CStr(), null, null);
    }
    if (window == null)
    {
        Console.WriteLine("cannot open a window");
        glfwTerminate();
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);
    glfwSetKeyCallback(window, OnKey);
    Restart();

    double last = glfwGetTime();
    double pending = 0;
    while (glfwWindowShouldClose(window) == 0)
    {
        glfwPollEvents();
        double now = glfwGetTime();
        pending += now - last;
        last = now;
        // a fixed step: the snake moves at the same speed at any frame rate
        while (pending >= TickSeconds)
        {
            Tick();
            pending -= TickSeconds;
        }
        Draw(now);

        int width = 0;
        int height = 0;
        glfwGetFramebufferSize(window, ref width, ref height);
        glViewport(0, 0, width, height);
        glClearColor(0, 0, 0, 1);
        glClear(GlColorBufferBit);
        // row 0 of the picture at the top left corner, drawn downwards
        glRasterPos2f(-1, 1);
        glPixelZoom((float)width / ScreenWidth, -(float)height / ScreenHeight);
        unsafe
        {
            glDrawPixels(ScreenWidth, ScreenHeight, GlRgba, GlUnsignedByte, &pixels[0]);
        }
        glfwSwapBuffers(window);
    }
    glfwTerminate();
    Console.WriteLine("best score: " + (score > best ? score : best).ToString());
    return 0;
}
