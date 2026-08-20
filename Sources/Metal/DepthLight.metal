#include <metal_stdlib>
using namespace metal;

struct LightUniforms {
    float2 lightPosition;
    float3 lightColor;
    float intensity;
    float radius;
    float depthStrength;
    uint width;
    uint height;
};

static inline float readDepth(texture2d<float, access::read> tex, float2 uv) {
    uv = clamp(uv, float2(0.0), float2(0.999999));
    uint2 p = uint2(uv * float2(tex.get_width(), tex.get_height()));
    return tex.read(p).r;
}

kernel void depthLightKernel(
    texture2d<float, access::read> cameraTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant LightUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;

    float4 src = cameraTexture.read(gid);
    float2 size = float2(max(u.width, 1u), max(u.height, 1u));
    float2 uv = (float2(gid) + 0.5) / size;
    float2 lightUV = u.lightPosition / size;

    // Depth Anything V2 returns relative inverse-depth-like values: larger is generally closer.
    // Use relative differences so the effect remains stable even when the raw output scale changes.
    float z = readDepth(depthTexture, uv);
    float2 texel = 1.0 / float2(depthTexture.get_width(), depthTexture.get_height());
    float zx1 = readDepth(depthTexture, uv + float2(texel.x, 0.0));
    float zx0 = readDepth(depthTexture, uv - float2(texel.x, 0.0));
    float zy1 = readDepth(depthTexture, uv + float2(0.0, texel.y));
    float zy0 = readDepth(depthTexture, uv - float2(0.0, texel.y));

    float scale = max(abs(z), 0.08);
    float dzdx = (zx1 - zx0) / scale;
    float dzdy = (zy1 - zy0) / scale;
    float normalGain = mix(3.5, 11.0, clamp(u.depthStrength, 0.0, 1.0));
    float3 N = normalize(float3(-dzdx * normalGain, dzdy * normalGain, 1.0));

    float2 deltaPx = u.lightPosition - float2(gid);
    float distPx = length(deltaPx);
    float spatial = smoothstep(u.radius, 0.0, distPx);

    float lightZ = readDepth(depthTexture, lightUV);
    // Put the virtual lamp slightly toward the camera relative to the surface under the cursor.
    float zLift = max(abs(lightZ), 0.08) * 0.18 + 0.025;
    float virtualLightZ = lightZ + zLift;

    float2 dirScreen = deltaPx / max(max(u.width, u.height), 1u);
    float zDelta = (virtualLightZ - z) / max(scale, 0.08);
    float3 L = normalize(float3(dirScreen.x * 2.5, -dirScreen.y * 2.5, 0.35 + zDelta * 0.55));

    float diffuse = max(dot(N, L), 0.0);
    diffuse = pow(diffuse, 0.72);

    // Screen-space ray marching in the depth field. A closer sample along the ray casts a shadow.
    float occlusion = 0.0;
    const int STEPS = 18;
    float relBias = 0.035;
    for (int i = 1; i < STEPS; ++i) {
        float t = float(i) / float(STEPS);
        float2 suv = mix(uv, lightUV, t);
        float sampleZ = readDepth(depthTexture, suv);
        float expected = mix(z, virtualLightZ, t);
        float localScale = max(max(abs(expected), abs(z)), 0.08);
        float blocker = (sampleZ - expected) / localScale;
        float awayFromReceiver = smoothstep(0.10, 0.28, t);
        float beforeLamp = 1.0 - smoothstep(0.82, 0.98, t);
        occlusion = max(occlusion, smoothstep(relBias, relBias + 0.10, blocker) * awayFromReceiver * beforeLamp);
    }

    // Soften the shadow and preserve a little indirect fill.
    float shadowStrength = mix(0.0, 0.92, clamp(u.depthStrength, 0.0, 1.0));
    float visibility = 1.0 - occlusion * shadowStrength;

    float energy = spatial * diffuse * visibility * u.intensity;
    float3 base = src.rgb;
    float luminance = dot(base, float3(0.2126, 0.7152, 0.0722));

    // Warm/cool point-light contribution with a small specular response.
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float specular = pow(max(dot(N, H), 0.0), 26.0) * spatial * visibility;
    float3 lit = base + u.lightColor * energy * (0.55 + luminance * 0.55);
    lit += u.lightColor * specular * u.intensity * 0.16;

    // Draw the virtual lamp inside the processed frame so real scene geometry can cover it.
    float orbRadius = max(9.0, u.radius * 0.055);
    float orbD = distPx;
    float glow = exp(-pow(orbD / max(orbRadius * 2.6, 1.0), 2.0) * 2.0);
    float core = 1.0 - smoothstep(orbRadius * 0.55, orbRadius, orbD);

    // Pixels substantially closer than the virtual lamp are in front of it (e.g. a hand).
    float frontDelta = (z - virtualLightZ) / max(max(abs(virtualLightZ), abs(z)), 0.08);
    float orbVisible = 1.0 - smoothstep(0.025, 0.10, frontDelta);
    float lamp = clamp(glow * 0.58 + core * 1.15, 0.0, 1.4) * orbVisible;
    lit += u.lightColor * lamp * (0.50 + u.intensity * 0.75);
    lit += float3(1.0) * core * 0.72 * orbVisible;

    // Very subtle contact-darkening where the ray is blocked; this makes hand shadows readable.
    lit *= 1.0 - occlusion * spatial * shadowStrength * 0.18;

    outputTexture.write(float4(clamp(lit, 0.0, 1.0), src.a), gid);
}
