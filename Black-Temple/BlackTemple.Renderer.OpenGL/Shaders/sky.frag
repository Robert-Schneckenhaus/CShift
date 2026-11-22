// Outdoor sky: gradient from horizon to zenith, sun, moon and stars depending on the time of day.
#version 330 core

in vec2 vNdc;

uniform vec3 uForward;
uniform vec3 uRight;
uniform vec3 uUp;
uniform float uTanHalfFov;
uniform float uAspect;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform float uNight;        // 0 = day, 1 = full night (stars)
uniform float uBrightness;

out vec4 fragColor;

float hash(vec3 p)
{
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void main()
{
    vec3 dir = normalize(uForward + uRight * vNdc.x * uTanHalfFov * uAspect + uUp * vNdc.y * uTanHalfFov);
    float h = clamp(dir.y, 0.0, 1.0);
    vec3 color = mix(uHorizon, uZenith, pow(h, 0.55));

    // stars
    if (uNight > 0.0 && dir.y > 0.0)
    {
        vec3 cell = floor(dir * 220.0);
        float s = hash(cell);
        if (s > 0.996)
            color += vec3(0.8, 0.85, 1.0) * uNight * (s - 0.996) * 250.0 * h;
    }

    // sun
    float sunDot = dot(dir, uSunDir);
    color += uSunColor * (smoothstep(0.9985, 0.9992, sunDot) * 1.5 + pow(max(sunDot, 0.0), 64.0) * 0.35);

    // moon (opposite of the sun)
    float moonDot = dot(dir, -uSunDir);
    color += vec3(0.85, 0.88, 1.0) * smoothstep(0.9990, 0.9994, moonDot) * uNight;

    fragColor = vec4(color * uBrightness, 1.0);
}
