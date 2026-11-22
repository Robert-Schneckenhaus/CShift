// Shared fragment shader of walls, floors, ceilings and billboards.
// Lighting = ambient (+ sun outdoors) + up to 32 point lights, then linear distance fog.
#version 330 core

in vec3 vWorld;
in vec3 vUv;          // u, v, texture array layer
in vec3 vNormal;
in float vFullbright;

uniform sampler2DArray uTexture;
uniform vec3 uCameraPos;
uniform vec3 uAmbient;
uniform float uFaceShade;     // darkens walls facing east/west a little (depth cue)
uniform vec3 uSunDir;
uniform vec3 uSunColor;       // black indoors

#define MAX_LIGHTS 32
uniform int uLightCount;
uniform vec3 uLightPos[MAX_LIGHTS];
uniform vec3 uLightColor[MAX_LIGHTS];   // color * intensity
uniform float uLightRadius[MAX_LIGHTS];

uniform vec3 uFogColor;
uniform float uFogStart;
uniform float uFogEnd;
uniform float uBrightness;    // fades to black (map changes)

out vec4 fragColor;

void main()
{
    vec4 albedo = texture(uTexture, vUv);
    if (albedo.a < 0.5)
        discard;

    vec3 n = normalize(vNormal);
    vec3 light = uAmbient * (1.0 - uFaceShade * abs(n.x));
    light += uSunColor * max(dot(n, uSunDir), 0.0) * 0.35;

    for (int i = 0; i < uLightCount; i++)
    {
        vec3 toLight = uLightPos[i] - vWorld;
        float dist = length(toLight);
        // falls off like 1 / (1 + 6 x^2), windowed so that it reaches 0 exactly at the radius
        float x = dist / uLightRadius[i];
        float window = clamp(1.0 - x * x, 0.0, 1.0);
        float att = window * window / (1.0 + 6.0 * x * x);
        float ndl = max(dot(n, toLight / max(dist, 0.0001)), 0.0) * 0.65 + 0.35;
        light += uLightColor[i] * att * ndl;
    }

    light = mix(light, vec3(1.0), vFullbright);
    vec3 color = albedo.rgb * light;

    float dist = length(vWorld - uCameraPos);
    float fog = clamp((dist - uFogStart) / max(uFogEnd - uFogStart, 0.0001), 0.0, 1.0);
    color = mix(color, uFogColor, fog);
    fragColor = vec4(color * uBrightness, 1.0);
}
