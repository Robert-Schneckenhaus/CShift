// Static map geometry: walls, floors, ceilings.
#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in float aLayer;
layout(location = 3) in vec3 aNormal;

uniform mat4 uViewProj;

out vec3 vWorld;
out vec3 vUv;
out vec3 vNormal;
out float vFullbright;

void main()
{
    vWorld = aPos;
    vUv = vec3(aUv, aLayer);
    vNormal = aNormal;
    vFullbright = 0.0;
    gl_Position = uViewProj * vec4(aPos, 1.0);
}
