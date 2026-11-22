// A full screen triangle behind everything; the fragment shader computes the view direction per pixel.
#version 330 core

out vec2 vNdc;

void main()
{
    vec2 p = vec2((gl_VertexID == 1) ? 3.0 : -1.0, (gl_VertexID == 2) ? 3.0 : -1.0);
    vNdc = p;
    gl_Position = vec4(p, 0.999, 1.0);
}
