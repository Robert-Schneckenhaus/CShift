/* The part of OpenGL 3.3 (core profile) that the demo uses.
 *
 * Constants and types come from the official Khronos header GL/glcorearb.h. On Windows, opengl32.dll only exports
 * OpenGL 1.1; everything newer has to be looked up at run time (wglGetProcAddress, here via glfwGetProcAddress).
 * So instead of prototypes, this header declares a struct of function pointers - one field per OpenGL function,
 * typed with glcorearb.h's PFNGL...PROC typedefs. In CShift every field is an Action<...>/Func<...>, and
 * src/gl.csh fills them in (gl.Clear = glClear, gl.CreateShader = glCreateShader, ...).
 *
 * To use another OpenGL function: add a field here and a Load(...) line in src/gl.csh.
 */
#ifndef CSHIFT_DEMO_GL33_H
#define CSHIFT_DEMO_GL33_H

/* Without APIENTRY, glcorearb.h would pull in all of <windows.h> on Windows. */
#ifndef APIENTRY
#ifdef _WIN32
#define APIENTRY __stdcall
#else
#define APIENTRY
#endif
#endif

#include <GL/glcorearb.h>

typedef struct GlFunctions
{
    /* state, drawing */
    PFNGLGETSTRINGPROC GetString;
    PFNGLVIEWPORTPROC Viewport;
    PFNGLCLEARCOLORPROC ClearColor;
    PFNGLCLEARPROC Clear;
    PFNGLENABLEPROC Enable;
    PFNGLDRAWELEMENTSPROC DrawElements;

    /* shaders and programs */
    PFNGLCREATESHADERPROC CreateShader;
    PFNGLSHADERSOURCEPROC ShaderSource;
    PFNGLCOMPILESHADERPROC CompileShader;
    PFNGLGETSHADERIVPROC GetShaderiv;
    PFNGLGETSHADERINFOLOGPROC GetShaderInfoLog;
    PFNGLDELETESHADERPROC DeleteShader;
    PFNGLCREATEPROGRAMPROC CreateProgram;
    PFNGLATTACHSHADERPROC AttachShader;
    PFNGLLINKPROGRAMPROC LinkProgram;
    PFNGLGETPROGRAMIVPROC GetProgramiv;
    PFNGLGETPROGRAMINFOLOGPROC GetProgramInfoLog;
    PFNGLUSEPROGRAMPROC UseProgram;
    PFNGLDELETEPROGRAMPROC DeleteProgram;
    PFNGLGETUNIFORMLOCATIONPROC GetUniformLocation;
    PFNGLUNIFORMMATRIX4FVPROC UniformMatrix4fv;

    /* vertex arrays and buffers */
    PFNGLGENVERTEXARRAYSPROC GenVertexArrays;
    PFNGLBINDVERTEXARRAYPROC BindVertexArray;
    PFNGLDELETEVERTEXARRAYSPROC DeleteVertexArrays;
    PFNGLGENBUFFERSPROC GenBuffers;
    PFNGLBINDBUFFERPROC BindBuffer;
    PFNGLBUFFERDATAPROC BufferData;
    PFNGLDELETEBUFFERSPROC DeleteBuffers;
    PFNGLVERTEXATTRIBPOINTERPROC VertexAttribPointer;
    PFNGLENABLEVERTEXATTRIBARRAYPROC EnableVertexAttribArray;
} GlFunctions;

#endif
