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

struct V6Uniforms {
    float2 lightPosition;
    float lightDepth;
    float radius;
    float4 colorIntensity;
    float4 params;       // x=shadow strength, y=subject depth, z=max lit depth
    uint2 dimensions;
    uint2 padding;
};

static inline float readDepth(texture2d<float, access::read> tex, float2 uv) {
    uv = clamp(uv, float2(0.0), float2(0.999999));
    uint2 p = uint2(uv * float2(tex.get_width(), tex.get_height()));
    return tex.read(p).r;
}

static inline float validMetric(float z, float fallback) {
    return (isfinite(z) && z > 0.12 && z < 4.5) ? z : fallback;
}

static inline float smoothMetricDepth(texture2d<float, access::read> tex, float2 uv) {
    float2 texel = 1.0 / float2(tex.get_width(), tex.get_height());
    float c = readDepth(tex, uv);
    c = validMetric(c, 1.0);
    float l = validMetric(readDepth(tex, uv - float2(texel.x, 0.0)), c);
    float r = validMetric(readDepth(tex, uv + float2(texel.x, 0.0)), c);
    float u = validMetric(readDepth(tex, uv - float2(0.0, texel.y)), c);
    float d = validMetric(readDepth(tex, uv + float2(0.0, texel.y)), c);

    float threshold = max(0.018, c * 0.045);
    float sum = c * 2.0;
    float weight = 2.0;
    if (abs(l - c) < threshold) { sum += l; weight += 1.0; }
    if (abs(r - c) < threshold) { sum += r; weight += 1.0; }
    if (abs(u - c) < threshold) { sum += u; weight += 1.0; }
    if (abs(d - c) < threshold) { sum += d; weight += 1.0; }
    return sum / weight;
}

kernel void trueDepthRelightKernel(
    texture2d<float, access::read> cameraTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant V6Uniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.dimensions.x || gid.y >= u.dimensions.y) return;

    float2 size = float2(max(u.dimensions.x, 1u), max(u.dimensions.y, 1u));
    float2 uv = (float2(gid) + 0.5) / size;
    float4 src = cameraTexture.read(gid);

    float z = smoothMetricDepth(depthTexture, uv);
    if (!isfinite(z) || z < 0.12 || z > 4.5) {
        outputTexture.write(src, gid);
        return;
    }

    float2 dtexel = 1.0 / float2(depthTexture.get_width(), depthTexture.get_height());
    float zl = smoothMetricDepth(depthTexture, uv - float2(dtexel.x, 0.0));
    float zr = smoothMetricDepth(depthTexture, uv + float2(dtexel.x, 0.0));
    float zu = smoothMetricDepth(depthTexture, uv - float2(0.0, dtexel.y));
    float zd = smoothMetricDepth(depthTexture, uv + float2(0.0, dtexel.y));

    float edgeClamp = max(0.025, z * 0.08);
    zl = abs(zl - z) < edgeClamp ? zl : z;
    zr = abs(zr - z) < edgeClamp ? zr : z;
    zu = abs(zu - z) < edgeClamp ? zu : z;
    zd = abs(zd - z) < edgeClamp ? zd : z;

    float aspect = size.x / max(size.y, 1.0);
    float3 receiver = float3((uv.x - 0.5) * z * aspect * 0.92,
                             (0.5 - uv.y) * z * 0.92,
                             z);
    float2 lightUV = clamp(u.lightPosition, float2(0.02), float2(0.98));
    float3 lamp = float3((lightUV.x - 0.5) * u.lightDepth * aspect * 0.92,
                         (0.5 - lightUV.y) * u.lightDepth * 0.92,
                         u.lightDepth);

    float3 Lvec = lamp - receiver;
    float lampDistance = max(length(Lvec), 0.001);
    float3 L = Lvec / lampDistance;

    float dzdx = (zr - zl) / max(z * 0.12, 0.025);
    float dzdy = (zd - zu) / max(z * 0.12, 0.025);
    float3 N = normalize(float3(-dzdx * 1.15, dzdy * 1.15, -1.0));
    if (dot(N, float3(0,0,-1)) < 0.0) N = -N;

    float diffuse = max(dot(N, L), 0.0);
    diffuse = pow(diffuse, 0.72);

    float2 screenDelta = uv - lightUV;
    screenDelta.x *= aspect;
    float radial = length(screenDelta);
    float radius = max(u.radius, 0.08);
    float spatial = 1.0 - smoothstep(radius * 0.32, radius, radial);
    float metricFalloff = 1.0 / (1.0 + lampDistance * lampDistance * 3.2);

    // Keep the background clean. The strongest relighting follows the near subject volume.
    float subjectDepth = u.params.y;
    float maxLitDepth = u.params.z;
    float subjectGate = 1.0 - smoothstep(subjectDepth + 0.38, maxLitDepth, z);
    subjectGate = clamp(subjectGate, 0.0, 1.0);

    // Metric screen-space ray march. Any depth sample closer to the camera than the
    // expected receiver->lamp ray blocks the lamp, which makes a hand cast a shadow.
    float occlusion = 0.0;
    const int STEPS = 12;
    for (int i = 1; i < STEPS; ++i) {
        float t = float(i) / float(STEPS);
        float2 suv = mix(uv, lightUV, t);
        float sampleZ = smoothMetricDepth(depthTexture, suv);
        float expectedZ = mix(z, u.lightDepth, t);
        float bias = max(0.012, expectedZ * 0.025);
        float blocker = expectedZ - sampleZ - bias;
        float body = smoothstep(0.008, 0.055, blocker);
        float endFade = smoothstep(0.06, 0.18, t) * (1.0 - smoothstep(0.80, 0.97, t));
        occlusion = max(occlusion, body * endFade);
    }

    float shadowStrength = clamp(u.params.x, 0.0, 1.0);
    float visibility = 1.0 - occlusion * mix(0.35, 0.96, shadowStrength);

    float3 lightColor = u.colorIntensity.rgb;
    float intensity = u.colorIntensity.a;
    float energy = spatial * metricFalloff * diffuse * visibility * subjectGate * intensity * 2.55;

    float3 base = src.rgb;
    float luminance = dot(base, float3(0.2126, 0.7152, 0.0722));
    float3 lit = base + lightColor * energy * (0.54 + luminance * 0.52);

    float3 V = normalize(-receiver);
    float3 H = normalize(L + V);
    float spec = pow(max(dot(N, H), 0.0), 34.0) * spatial * visibility * subjectGate;
    lit += lightColor * spec * intensity * 0.20;

    // Slight contact darkening makes cast shadows legible without painting the whole image black.
    lit *= 1.0 - occlusion * spatial * subjectGate * shadowStrength * 0.20;

    // Lamp is part of the 3D composite. Geometry closer than the virtual lamp hides it.
    float orbRadius = mix(0.012, 0.026, clamp(radius, 0.08, 0.72));
    float orbDist = length(screenDelta);
    float glow = exp(-pow(orbDist / max(orbRadius * 3.0, 0.001), 2.0) * 1.7);
    float core = 1.0 - smoothstep(orbRadius * 0.45, orbRadius, orbDist);
    float frontOfLamp = u.lightDepth - z;
    float orbVisible = 1.0 - smoothstep(0.018, 0.065, frontOfLamp);
    float lampEnergy = (glow * 0.75 + core * 1.15) * orbVisible;
    lit += lightColor * lampEnergy * (0.48 + intensity * 0.82);
    lit += float3(1.0) * core * orbVisible * 0.78;

    outputTexture.write(float4(clamp(lit, 0.0, 1.0), src.a), gid);
}

// AI fallback kernel for devices/cameras without synchronized hardware depth.
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
    float z = readDepth(depthTexture, uv);
    float2 texel = 1.0 / float2(depthTexture.get_width(), depthTexture.get_height());
    float zx1 = readDepth(depthTexture, uv + float2(texel.x, 0.0));
    float zx0 = readDepth(depthTexture, uv - float2(texel.x, 0.0));
    float zy1 = readDepth(depthTexture, uv + float2(0.0, texel.y));
    float zy0 = readDepth(depthTexture, uv - float2(0.0, texel.y));

    float scale = max(abs(z), 0.08);
    float dzdx = (zx1 - zx0) / scale;
    float dzdy = (zy1 - zy0) / scale;
    float3 N = normalize(float3(-dzdx * 6.0, dzdy * 6.0, 1.0));
    float2 deltaPx = u.lightPosition - float2(gid);
    float distPx = length(deltaPx);
    float spatial = smoothstep(u.radius, 0.0, distPx);
    float lightZ = readDepth(depthTexture, lightUV);
    float virtualLightZ = lightZ + max(abs(lightZ), 0.08) * 0.16 + 0.02;
    float2 dirScreen = deltaPx / max(max(u.width, u.height), 1u);
    float3 L = normalize(float3(dirScreen.x * 2.5, -dirScreen.y * 2.5, 0.35 + (virtualLightZ - z) * 0.8));
    float diffuse = pow(max(dot(N, L), 0.0), 0.75);

    float occlusion = 0.0;
    const int STEPS = 12;
    for (int i = 1; i < STEPS; ++i) {
        float t = float(i) / float(STEPS);
        float sampleZ = readDepth(depthTexture, mix(uv, lightUV, t));
        float expected = mix(z, virtualLightZ, t);
        float blocker = (sampleZ - expected) / max(max(abs(expected), abs(z)), 0.08);
        occlusion = max(occlusion, smoothstep(0.04, 0.13, blocker) * smoothstep(0.10, 0.25, t) * (1.0 - smoothstep(0.82, 0.98, t)));
    }

    float visibility = 1.0 - occlusion * mix(0.25, 0.90, clamp(u.depthStrength, 0.0, 1.0));
    float energy = spatial * diffuse * visibility * u.intensity;
    float3 lit = src.rgb + u.lightColor * energy * (0.55 + dot(src.rgb, float3(0.2126,0.7152,0.0722)) * 0.5);

    float orbRadius = max(9.0, u.radius * 0.055);
    float glow = exp(-pow(distPx / max(orbRadius * 2.6, 1.0), 2.0) * 2.0);
    float core = 1.0 - smoothstep(orbRadius * 0.55, orbRadius, distPx);
    float frontDelta = (z - virtualLightZ) / max(max(abs(virtualLightZ), abs(z)), 0.08);
    float orbVisible = 1.0 - smoothstep(0.025, 0.10, frontDelta);
    lit += u.lightColor * (glow * 0.55 + core) * orbVisible * (0.55 + u.intensity * 0.65);
    lit += float3(1.0) * core * orbVisible * 0.65;

    outputTexture.write(float4(clamp(lit, 0.0, 1.0), src.a), gid);
}
