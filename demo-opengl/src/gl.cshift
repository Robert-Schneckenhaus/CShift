// Loads the OpenGL functions listed in include/gl33.h.
//
// gl33.h declares the struct GlFunctions: one Action<...>/Func<...> field per OpenGL function, with the signatures
// taken from the Khronos header GL/glcorearb.h. Once a context is current, LoadGl() asks GLFW for each function's
// address and stores it in the global `gl`, so the rest of the program calls gl.Clear(...), gl.CreateShader(...), ...

using Glfw from "GLFW/glfw3.h";
using Gl from "gl33.h";

Gl.GlFunctions gl;

bool loadOk = true;

// Looks up one function and stores it in `slot`. The type argument (Action<...>/Func<...>) is inferred from the
// field, so every Load(...) call below stays a one-liner.
void Load<T>(ref T slot, string name)
{
    unsafe
    {
        void* address = (void*)Glfw.glfwGetProcAddress(name);
        if (address == null)
        {
            Console.WriteLine("OpenGL function not found: " + name);
            loadOk = false;
        }
        slot = (T)address;
    }
}

// Needs a current OpenGL context (glfwMakeContextCurrent). Returns false if a function is missing.
bool LoadGl()
{
    Load(ref gl.GetString, "glGetString");
    Load(ref gl.Viewport, "glViewport");
    Load(ref gl.ClearColor, "glClearColor");
    Load(ref gl.Clear, "glClear");
    Load(ref gl.Enable, "glEnable");
    Load(ref gl.DrawElements, "glDrawElements");

    Load(ref gl.CreateShader, "glCreateShader");
    Load(ref gl.ShaderSource, "glShaderSource");
    Load(ref gl.CompileShader, "glCompileShader");
    Load(ref gl.GetShaderiv, "glGetShaderiv");
    Load(ref gl.GetShaderInfoLog, "glGetShaderInfoLog");
    Load(ref gl.DeleteShader, "glDeleteShader");
    Load(ref gl.CreateProgram, "glCreateProgram");
    Load(ref gl.AttachShader, "glAttachShader");
    Load(ref gl.LinkProgram, "glLinkProgram");
    Load(ref gl.GetProgramiv, "glGetProgramiv");
    Load(ref gl.GetProgramInfoLog, "glGetProgramInfoLog");
    Load(ref gl.UseProgram, "glUseProgram");
    Load(ref gl.DeleteProgram, "glDeleteProgram");
    Load(ref gl.GetUniformLocation, "glGetUniformLocation");
    Load(ref gl.UniformMatrix4fv, "glUniformMatrix4fv");

    Load(ref gl.GenVertexArrays, "glGenVertexArrays");
    Load(ref gl.BindVertexArray, "glBindVertexArray");
    Load(ref gl.DeleteVertexArrays, "glDeleteVertexArrays");
    Load(ref gl.GenBuffers, "glGenBuffers");
    Load(ref gl.BindBuffer, "glBindBuffer");
    Load(ref gl.BufferData, "glBufferData");
    Load(ref gl.DeleteBuffers, "glDeleteBuffers");
    Load(ref gl.VertexAttribPointer, "glVertexAttribPointer");
    Load(ref gl.EnableVertexAttribArray, "glEnableVertexAttribArray");
    return loadOk;
}

// glGetString returns a C string (as uint8*); copies it into a string.
string GlString(uint32 name)
{
    unsafe
    {
        uint8* text = gl.GetString(name);
        if (text == null)
            return "?";
        return string.FromCStr((char*)text);
    }
}
