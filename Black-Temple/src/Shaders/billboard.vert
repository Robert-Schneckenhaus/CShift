// Billboards: objects are flat sprites that always turn towards the camera (around the vertical axis only).
#version 330 core

layout(location = 0) in vec3 aCenter;    // bottom center of the sprite in the world
layout(location = 1) in vec2 aCorner;    // x: offset along the camera's right vector, y: height above aCenter
layout(location = 2) in vec2 aUv;
layout(location = 3) in float aLayer;
layout(location = 4) in float aFullbright;

uniform mat4 uViewProj;
uniform vec3 uCameraRight;
uniform vec3 uCameraPos;

out vec3 vWorld;
out vec3 vUv;
out vec3 vNormal;
out float vFullbright;

void main()
{
    vec3 world = aCenter + uCameraRight * aCorner.x + vec3(0.0, aCorner.y, 0.0);
    vec3 toCamera = uCameraPos - aCenter;
    toCamera.y = 0.0;
    vNormal = length(toCamera) > 0.001 ? normalize(toCamera) : vec3(0.0, 0.0, 1.0);
    vWorld = world;
    vUv = vec3(aUv, aLayer);
    vFullbright = aFullbright;
    gl_Position = uViewProj * vec4(world, 1.0);
}
