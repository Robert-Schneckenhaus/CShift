// CShift + OpenGL 3.3: a rotating, rainbow colored cube.
//
// GLFW opens the window and creates an OpenGL 3.3 core profile context; the OpenGL functions are loaded at run time
// (src/gl.csh, include/gl33.h). The cube's 8 corners each get a color of the rainbow, the vertex shader transforms
// them with a model-view-projection matrix (src/matrix.csh), and the rasterizer blends the colors across the faces.
//
//   Esc  closes the window

using Glfw from "GLFW/glfw3.h";
using Gl from "gl33.h";

const string VertexShaderSource =
    "#version 330 core\n" +
    "layout(location = 0) in vec3 aPosition;\n" +
    "layout(location = 1) in vec3 aColor;\n" +
    "uniform mat4 uMvp;\n" +
    "out vec3 vColor;\n" +
    "void main()\n" +
    "{\n" +
    "    vColor = aColor;\n" +
    "    gl_Position = uMvp * vec4(aPosition, 1.0);\n" +
    "}\n";

const string FragmentShaderSource =
    "#version 330 core\n" +
    "in vec3 vColor;\n" +
    "out vec4 fragColor;\n" +
    "void main()\n" +
    "{\n" +
    "    fragColor = vec4(vColor, 1.0);\n" +
    "}\n";

void OnError(int code, char* description)
{
    unsafe
    {
        Console.WriteLine("GLFW error " + code.ToString() + ": " + string.FromCStr(description));
    }
}

void OnKey(Glfw.GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (key == Glfw.GLFW_KEY_ESCAPE && action == Glfw.GLFW_PRESS)
        Glfw.glfwSetWindowShouldClose(window, 1);
}

// Compiles one shader; prints the compiler's log and returns 0 if it fails.
uint32 CompileShader(uint32 kind, string source)
{
    uint32 shader = gl.CreateShader(kind);
    unsafe
    {
        char* text = source.CStr();
        gl.ShaderSource(shader, 1, &text, null);
        gl.CompileShader(shader);
        int ok = 0;
        gl.GetShaderiv(shader, Gl.GL_COMPILE_STATUS, &ok);
        if (ok == 0)
        {
            char* log = (char*)Memory.Allocate(1024);
            gl.GetShaderInfoLog(shader, 1024, null, log);
            Console.WriteLine("shader error: " + string.FromCStr(log));
            Memory.Free(log);
            gl.DeleteShader(shader);
            return 0;
        }
    }
    return shader;
}

// Compiles and links the vertex and fragment shader; returns 0 on errors.
uint32 CreateProgram()
{
    uint32 vertex = CompileShader(Gl.GL_VERTEX_SHADER, VertexShaderSource);
    uint32 fragment = CompileShader(Gl.GL_FRAGMENT_SHADER, FragmentShaderSource);
    if (vertex == 0 || fragment == 0)
        return 0;
    uint32 program = gl.CreateProgram();
    gl.AttachShader(program, vertex);
    gl.AttachShader(program, fragment);
    gl.LinkProgram(program);
    gl.DeleteShader(vertex);
    gl.DeleteShader(fragment);
    unsafe
    {
        int ok = 0;
        gl.GetProgramiv(program, Gl.GL_LINK_STATUS, &ok);
        if (ok == 0)
        {
            char* log = (char*)Memory.Allocate(1024);
            gl.GetProgramInfoLog(program, 1024, null, log);
            Console.WriteLine("link error: " + string.FromCStr(log));
            Memory.Free(log);
            gl.DeleteProgram(program);
            return 0;
        }
    }
    return program;
}

// A fully saturated color on the color wheel: hue 0 = red, 1/6 = yellow, 1/3 = green, ... 1 = red again.
float Hue(double hue, int channel)
{
    // channel 0 (red) peaks at hue 0, green at 1/3, blue at 2/3
    double h = hue * 6 - channel * 2;
    while (h < 0)
        h += 6;
    while (h >= 6)
        h -= 6;
    double d = h < 3 ? h : 6 - h;   // distance from the peak, 0..3
    if (d <= 1)
        return 1;
    if (d >= 2)
        return 0;
    return (float)(2 - d);
}

int Main()
{
    Glfw.glfwSetErrorCallback(OnError);
    if (Glfw.glfwInit() == 0)
        return 1;

    Glfw.glfwWindowHint(Glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    Glfw.glfwWindowHint(Glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    Glfw.glfwWindowHint(Glfw.GLFW_OPENGL_PROFILE, Glfw.GLFW_OPENGL_CORE_PROFILE);
    Glfw.glfwWindowHint(Glfw.GLFW_OPENGL_FORWARD_COMPAT, 1);   // needed on macOS, harmless elsewhere
    Glfw.glfwWindowHint(Glfw.GLFW_SAMPLES, 4);

    Glfw.GLFWwindow* window = Glfw.glfwCreateWindow(800, 600, "CShift + OpenGL", null, null);
    if (window == null)
    {
        Console.WriteLine("cannot create a window with OpenGL 3.3");
        Glfw.glfwTerminate();
        return 1;
    }
    Glfw.glfwMakeContextCurrent(window);
    Glfw.glfwSwapInterval(1);
    Glfw.glfwSetKeyCallback(window, OnKey);

    if (!LoadGl())
    {
        Glfw.glfwTerminate();
        return 1;
    }
    Console.WriteLine("OpenGL " + GlString(Gl.GL_VERSION) + " (" + GlString(Gl.GL_RENDERER) + ")");

    uint32 program = CreateProgram();
    if (program == 0)
    {
        Glfw.glfwTerminate();
        return 1;
    }
    int mvpLocation = 0;
    unsafe
    {
        mvpLocation = gl.GetUniformLocation(program, "uMvp".CStr());
    }

    // The 8 corners: position (x, y, z), then color (r, g, b), one hue of the rainbow each.
    var vertices = new float[8 * 6];
    for (var i = 0; i < 8; i += 1)
    {
        vertices[i * 6 + 0] = (i & 1) != 0 ? 0.5f : -0.5f;
        vertices[i * 6 + 1] = (i & 2) != 0 ? 0.5f : -0.5f;
        vertices[i * 6 + 2] = (i & 4) != 0 ? 0.5f : -0.5f;
        double hue = i / 8.0;
        vertices[i * 6 + 3] = Hue(hue, 0);
        vertices[i * 6 + 4] = Hue(hue, 1);
        vertices[i * 6 + 5] = Hue(hue, 2);
    }
    // 6 faces x 2 triangles, as indices into the corners (bit 0 = x, bit 1 = y, bit 2 = z)
    var indices = new uint32[] {
        0, 2, 3,  0, 3, 1,   // back   (z = -0.5)
        4, 5, 7,  4, 7, 6,   // front  (z = +0.5)
        0, 4, 6,  0, 6, 2,   // left   (x = -0.5)
        1, 3, 7,  1, 7, 5,   // right  (x = +0.5)
        0, 1, 5,  0, 5, 4,   // bottom (y = -0.5)
        2, 6, 7,  2, 7, 3    // top    (y = +0.5)
    };

    uint32 vao = 0;
    uint32 vbo = 0;
    uint32 ebo = 0;
    unsafe
    {
        gl.GenVertexArrays(1, &vao);
        gl.BindVertexArray(vao);

        gl.GenBuffers(1, &vbo);
        gl.BindBuffer(Gl.GL_ARRAY_BUFFER, vbo);
        gl.BufferData(Gl.GL_ARRAY_BUFFER, 8 * 6 * sizeof(float), &vertices[0], Gl.GL_STATIC_DRAW);

        gl.GenBuffers(1, &ebo);
        gl.BindBuffer(Gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(Gl.GL_ELEMENT_ARRAY_BUFFER, 36 * sizeof(uint32), &indices[0], Gl.GL_STATIC_DRAW);

        int stride = 6 * sizeof(float);
        gl.VertexAttribPointer(0, 3, Gl.GL_FLOAT, (uint8)Gl.GL_FALSE, stride, (void*)0);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(1, 3, Gl.GL_FLOAT, (uint8)Gl.GL_FALSE, stride, (void*)(3 * sizeof(float)));
        gl.EnableVertexAttribArray(1);
    }

    gl.Enable(Gl.GL_DEPTH_TEST);
    gl.Enable(Gl.GL_MULTISAMPLE);
    gl.ClearColor(0.08f, 0.08f, 0.1f, 1.0f);

    int frames = 0;
    while (Glfw.glfwWindowShouldClose(window) == 0)
    {
        int width = 0;
        int height = 0;
        Glfw.glfwGetFramebufferSize(window, ref width, ref height);
        if (height < 1)
            height = 1;
        gl.Viewport(0, 0, width, height);
        gl.Clear((uint32)(Gl.GL_COLOR_BUFFER_BIT | Gl.GL_DEPTH_BUFFER_BIT));

        double t = Glfw.glfwGetTime();
        Mat4 projection = Mat4.Perspective(Math.PI / 4, (double)width / height, 0.1, 100.0);
        Mat4 view = Mat4.Translation(0, 0, -3);
        Mat4 model = Mat4.RotationY(t).Multiply(Mat4.RotationX(t * 0.7));
        Mat4 mvp = projection.Multiply(view).Multiply(model);

        gl.UseProgram(program);
        unsafe
        {
            gl.UniformMatrix4fv(mvpLocation, 1, (uint8)Gl.GL_FALSE, &mvp.M[0]);
        }
        gl.BindVertexArray(vao);
        gl.DrawElements(Gl.GL_TRIANGLES, 36, Gl.GL_UNSIGNED_INT, null);

        Glfw.glfwSwapBuffers(window);
        Glfw.glfwPollEvents();
        frames += 1;
    }

    unsafe
    {
        gl.DeleteBuffers(1, &ebo);
        gl.DeleteBuffers(1, &vbo);
        gl.DeleteVertexArrays(1, &vao);
    }
    gl.DeleteProgram(program);
    Glfw.glfwDestroyWindow(window);
    Glfw.glfwTerminate();
    Console.WriteLine("frames: " + frames.ToString());
    return 0;
}
