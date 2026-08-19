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

kernel void depthLightKernel(
    texture2d<float, access::read> cameraTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant LightUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;

    float4 src = cameraTexture.read(gid);

    uint2 dgid = uint2(
        min((uint)((float)gid.x / max((float)u.width, 1.0) * depthTexture.get_width()), depthTexture.get_width() - 1),
        min((uint)((float)gid.y / max((float)u.height, 1.0) * depthTexture.get_height()), depthTexture.get_height() - 1)
    );

    float depth = clamp(depthTexture.read(dgid).r, 0.0, 1.0);
    float2 p = float2(gid);
    float dist = distance(p, u.lightPosition);
    float spatial = smoothstep(u.radius, 0.0, dist);
    float depthGate = mix(0.35, 1.0, pow(depth, 0.85));
    float energy = spatial * mix(1.0, depthGate, clamp(u.depthStrength, 0.0, 1.0)) * u.intensity;

    float3 lit = src.rgb + u.lightColor * energy;
    lit += u.lightColor * energy * max(max(src.r, src.g), src.b) * 0.2;
    outputTexture.write(float4(clamp(lit, 0.0, 1.0), src.a), gid);
}
