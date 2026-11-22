/* The OpenGL 3.3 core functions Black Temple uses, as a struct of function pointers.
 *
 * Constants and types come from the Khronos header GL/glcorearb.h. On Windows, opengl32.dll only exports OpenGL 1.1,
 * so every function is looked up at run time (src/Engine/Gl.cshift, via glfwGetProcAddress). In CShift every field
 * becomes an Action<...>/Func<...>.
 *
 * To use another OpenGL function: add a field here and a Load(...) line in src/Engine/Gl.cshift.
 */
#ifndef BLACK_TEMPLE_GLFUNCS_H
#define BLACK_TEMPLE_GLFUNCS_H

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
    PFNGLGETERRORPROC GetError;
    PFNGLVIEWPORTPROC Viewport;
    PFNGLCLEARCOLORPROC ClearColor;
    PFNGLCLEARPROC Clear;
    PFNGLENABLEPROC Enable;
    PFNGLDISABLEPROC Disable;
    PFNGLDEPTHMASKPROC DepthMask;
    PFNGLCULLFACEPROC CullFace;
    PFNGLDRAWARRAYSPROC DrawArrays;
    PFNGLREADPIXELSPROC ReadPixels;
    PFNGLPIXELSTOREIPROC PixelStorei;

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
    PFNGLUNIFORM1IPROC Uniform1i;
    PFNGLUNIFORM1FPROC Uniform1f;
    PFNGLUNIFORM3FPROC Uniform3f;
    PFNGLUNIFORM1FVPROC Uniform1fv;
    PFNGLUNIFORM3FVPROC Uniform3fv;
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

    /* textures */
    PFNGLGENTEXTURESPROC GenTextures;
    PFNGLDELETETEXTURESPROC DeleteTextures;
    PFNGLBINDTEXTUREPROC BindTexture;
    PFNGLACTIVETEXTUREPROC ActiveTexture;
    PFNGLTEXIMAGE3DPROC TexImage3D;
    PFNGLTEXSUBIMAGE3DPROC TexSubImage3D;
    PFNGLTEXPARAMETERIPROC TexParameteri;
    PFNGLGENERATEMIPMAPPROC GenerateMipmap;
} GlFunctions;

#endif
