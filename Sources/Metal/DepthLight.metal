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

struct V7Uniforms {
    float2 lightPosition;
    float lightDepth;
    float radius;
    float4 colorIntensity;
    float4 params;      // x shadow, y subjectDepth, z maxLitDepth, w reserved
    float4 mapping;     // x cameraAspect, y effectiveDepthAspect, z rotateDepth
    uint2 dimensions;
    uint2 padding;
};

constant float3 LUMA = float3(0.2126, 0.7152, 0.0722);
constant float WHITE_POINT = 2.6;
constant float AMBIENT_STRENGTH = 0.18;
constant float SPECULAR_POWER = 36.0;
constant float SPECULAR_F0 = 0.06;
constant int SHADOW_STEPS = 32;
constant float SHADOW_BIAS = 0.014;
constant float SHADOW_SOFTNESS = 0.085;
constant float SHADOW_GAIN = 2.35;

static inline float readDepth(texture2d<float, access::read> tex, float2 uv) {
    uv = clamp(uv, float2(0.0), float2(0.999999));
    uint2 p = uint2(uv * float2(tex.get_width(), tex.get_height()));
    return tex.read(p).r;
}

static inline bool validMetric(float z) {
    return isfinite(z) && z > 0.14 && z < 3.0;
}

static inline float2 mapDepthUV(float2 uv, constant V7Uniforms &u) {
    float2 p = uv;
    if (u.mapping.z > 0.5) p = float2(uv.y, 1.0 - uv.x);
    float camAspect = max(u.mapping.x, 0.001);
    float depthAspect = max(u.mapping.y, 0.001);
    if (depthAspect > camAspect) {
        float s = camAspect / depthAspect;
        p.x = 0.5 + (p.x - 0.5) * s;
    } else {
        float s = depthAspect / camAspect;
        p.y = 0.5 + (p.y - 0.5) * s;
    }
    return clamp(p, float2(0.002), float2(0.998));
}

static inline float rawMetric(texture2d<float, access::read> tex, float2 screenUV, constant V7Uniforms &u) {
    return readDepth(tex, mapDepthUV(screenUV, u));
}

// Edge-preserving 3x3 depth filter. Invalid values are ignored instead of turning into black blobs.
static inline float filteredMetric(texture2d<float, access::read> tex, float2 screenUV, constant V7Uniforms &u) {
    float2 duv = mapDepthUV(screenUV, u);
    float2 t = 1.0 / float2(tex.get_width(), tex.get_height());
    float c = readDepth(tex, duv);
    if (!validMetric(c)) return -1.0;
    float threshold = max(0.012, c * 0.035);
    float sum = c * 4.0;
    float weight = 4.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            float z = readDepth(tex, duv + float2(x, y) * t);
            if (validMetric(z)) {
                float delta = abs(z - c);
                float w = 1.0 - smoothstep(threshold * 0.35, threshold, delta);
                sum += z * w;
                weight += w;
            }
        }
    }
    return sum / max(weight, 0.001);
}

static inline float gentleDelta(float backward, float forward) {
    float b = abs(backward);
    float f = abs(forward);
    return (backward * f + forward * b) / max(b + f, 1e-7);
}

static inline float2 surfaceSlope(texture2d<float, access::read> depthTexture,
                                  float2 uv,
                                  float z,
                                  constant V7Uniforms &u) {
    float2 stepUV = float2(7.0 / max(float(u.dimensions.x), 1.0),
                           7.0 / max(float(u.dimensions.y), 1.0));
    float l = filteredMetric(depthTexture, uv - float2(stepUV.x, 0), u);
    float r = filteredMetric(depthTexture, uv + float2(stepUV.x, 0), u);
    float up = filteredMetric(depthTexture, uv - float2(0, stepUV.y), u);
    float d = filteredMetric(depthTexture, uv + float2(0, stepUV.y), u);
    l = validMetric(l) ? l : z;
    r = validMetric(r) ? r : z;
    up = validMetric(up) ? up : z;
    d = validMetric(d) ? d : z;

    float gx = gentleDelta(z - l, r - z) / 7.0;
    float gy = gentleDelta(z - up, d - z) / 7.0;
    float2 g = float2(gx, gy);
    float steep = max(length(g), 1e-7);
    float noise = 0.0003;
    float shrunk = sqrt(max(steep * steep - noise * noise, 0.0));
    float ceiling = 0.009 * tanh(shrunk / 0.009);
    return g * (ceiling / steep);
}

static inline float localOcclusion(texture2d<float, access::read> depthTexture,
                                   float2 uv,
                                   float center,
                                   constant V7Uniforms &u) {
    float2 px = 1.0 / float2(max(u.dimensions.x, 1u), max(u.dimensions.y, 1u));
    int radii[2] = {3, 9};
    float occ = 0.0;
    float taps = 0.0;
    for (int ri = 0; ri < 2; ++ri) {
        int r = radii[ri];
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                if (x == 0 && y == 0) continue;
                float n = filteredMetric(depthTexture, uv + float2(x * r, y * r) * px, u);
                if (!validMetric(n)) continue;
                // Smaller metric depth = closer to camera. Nearby protrusions darken creases/contact zones.
                float difference = center - n;
                float contact = 1.0 - clamp(abs(difference) / 0.25, 0.0, 1.0);
                float cleared = max(difference - 0.012, 0.0);
                occ += clamp(cleared / 0.07, 0.0, 1.0) * contact;
                taps += 1.0;
            }
        }
    }
    return taps > 0.0 ? clamp(occ / taps, 0.0, 1.0) : 0.0;
}

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float shadowFactor(texture2d<float, access::read> depthTexture,
                                 float2 receiverUV,
                                 float receiverZ,
                                 float2 lightUV,
                                 float lightZ,
                                 constant V7Uniforms &u) {
    float jitter = hash12(receiverUV * float2(u.dimensions));
    float occlusion = 0.0;
    float validCount = 0.0;
    for (int i = 1; i < SHADOW_STEPS; ++i) {
        float t = (float(i) + jitter * 0.7) / float(SHADOW_STEPS);
        float2 probeUV = mix(receiverUV, lightUV, t);
        float sampleZ = filteredMetric(depthTexture, probeUV, u);
        if (!validMetric(sampleZ)) continue;
        float expected = mix(receiverZ, lightZ, t);
        float travel = t;
        float bias = SHADOW_BIAS + travel * 0.020;
        float blocker = expected - sampleZ - bias;
        float thickness = 0.08 + travel * 0.18;
        float hit = smoothstep(0.0, SHADOW_SOFTNESS, blocker) * (1.0 - smoothstep(thickness, thickness + 0.08, blocker));
        // Ignore geometry well in front of the light plane so the lamp is not shadowed by unrelated foreground noise.
        float frontFade = 1.0 - smoothstep(0.0, 0.20, lightZ - sampleZ);
        occlusion += hit * frontFade;
        validCount += 1.0;
    }
    if (validCount < 4.0) return 1.0;
    float avg = occlusion / validCount;
    return 1.0 - clamp(avg * SHADOW_GAIN, 0.0, 1.0);
}

static inline float3 filmicToneMap(float3 x) {
    // Soft white point similar to the public TypeGPU demo; prevents the giant burned halo.
    x = max(x, float3(0.0));
    float3 mapped = x / (1.0 + x);
    float wp = WHITE_POINT / (1.0 + WHITE_POINT);
    return clamp(mapped / wp, 0.0, 1.0);
}

kernel void trueDepthRelightKernel(
    texture2d<float, access::read> cameraTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant V7Uniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.dimensions.x || gid.y >= u.dimensions.y) return;

    float2 size = float2(max(u.dimensions.x,1u), max(u.dimensions.y,1u));
    float2 uv = (float2(gid)+0.5)/size;
    float4 src = cameraTexture.read(gid);
    float z = filteredMetric(depthTexture, uv, u);
    if (!validMetric(z)) { outputTexture.write(src, gid); return; }

    float subjectDepth = u.params.y;
    float maxLitDepth = max(u.params.z, subjectDepth + 0.25);
    float subjectGate = 1.0 - smoothstep(subjectDepth + 0.32, maxLitDepth, z);
    subjectGate = clamp(subjectGate, 0.0, 1.0);

    float2 slope = surfaceSlope(depthTexture, uv, z, u);
    float relief = 185.0;
    float slopeCompression = 0.55;
    float2 compressed = slope / (1.0 + length(slope) * relief * slopeCompression);
    float3 N = normalize(float3(-compressed.x * relief, compressed.y * relief, -1.0));
    if (N.z > 0.0) N = -N;

    float aspect = size.x / max(size.y, 1.0);
    float2 lightUV = clamp(u.lightPosition, float2(0.025), float2(0.975));
    float3 receiver = float3((uv.x-0.5)*z*aspect*0.86, (0.5-uv.y)*z*0.86, z);
    float3 lamp = float3((lightUV.x-0.5)*u.lightDepth*aspect*0.86,
                         (0.5-lightUV.y)*u.lightDepth*0.86,
                         u.lightDepth);
    float3 Lvec = lamp - receiver;
    float dist = max(length(Lvec), 0.001);
    float3 L = Lvec / dist;

    float ndotl = dot(N, L);
    float wrap = 0.25;
    float diffuse = clamp((ndotl + wrap) / (1.0 + wrap), 0.0, 1.0);
    diffuse = pow(diffuse, 0.86);

    float2 screenDelta = uv - lightUV;
    screenDelta.x *= aspect;
    float radial = length(screenDelta);
    float radius = max(u.radius, 0.08);
    float spatial = 1.0 - smoothstep(radius * 0.20, radius, radial);
    float falloff = 1.0 / (1.0 + dist * dist * 4.2);

    float shadow = shadowFactor(depthTexture, uv, z, lightUV, u.lightDepth, u);
    float shadowStrength = clamp(u.params.x, 0.0, 1.0);
    float visibility = mix(1.0, shadow, shadowStrength);

    float ao = localOcclusion(depthTexture, uv, z, u);
    float ambientOcclusion = 1.0 - ao * 0.35 * subjectGate;

    float intensity = clamp(u.colorIntensity.a, 0.0, 1.0);
    float3 lightColor = u.colorIntensity.rgb;
    float3 base = clamp(src.rgb, 0.0, 1.0);
    float luminance = dot(base, LUMA);

    float energy = spatial * falloff * diffuse * visibility * subjectGate * intensity * 2.05;
    float3 ambientFill = float3(0.78, 0.86, 1.0) * AMBIENT_STRENGTH * (1.0 - subjectGate * 0.15);
    float3 linearish = base * ambientOcclusion + ambientFill * base * 0.10;
    linearish += lightColor * energy * (0.50 + luminance * 0.38);

    float3 V = normalize(-receiver);
    float3 H = normalize(L + V);
    float spec = pow(max(dot(N,H),0.0), SPECULAR_POWER) * SPECULAR_F0;
    linearish += lightColor * spec * spatial * visibility * subjectGate * intensity * 1.5;

    // Filmic highlight handling, preserving skin texture instead of clipping to flat white.
    float3 lit = filmicToneMap(linearish * 1.18);
    lit = mix(base, lit, clamp(0.88 * subjectGate + 0.12, 0.0, 1.0));

    // 3x3 soft-source bulb visibility: a hand passing in front can partially cover it.
    float bulbWorld = 0.014 + radius * 0.008;
    float bulbDist = length(screenDelta);
    float open = 0.0;
    float2 sourceStep = float2(0.012 / max(aspect,0.1), 0.012);
    for (int sy=-1; sy<=1; ++sy) {
        for (int sx=-1; sx<=1; ++sx) {
            float2 probe = clamp(lightUV + float2(sx,sy)*sourceStep*0.60, float2(0.01), float2(0.99));
            float pz = filteredMetric(depthTexture, probe, u);
            float vis = !validMetric(pz) ? 1.0 : smoothstep(-0.025, 0.055, pz - u.lightDepth);
            open += vis;
        }
    }
    float bulbExposure = open / 9.0;
    float core = 1.0 - smoothstep(bulbWorld * 0.45, bulbWorld, bulbDist);
    float halo = exp(-pow(bulbDist / max(bulbWorld * 3.0, 0.001), 2.0) * 1.7);
    float lampEnergy = (core * 0.62 + halo * 0.20) * bulbExposure;
    lit = filmicToneMap(lit + lightColor * lampEnergy * (0.45 + intensity * 0.55) + float3(1.0) * core * bulbExposure * 0.22);

    // Tiny dither prevents visible banding in soft shadows.
    float dither = (hash12(float2(gid)) - 0.5) / 255.0;
    lit = clamp(lit + dither, 0.0, 1.0);
    outputTexture.write(float4(lit, src.a), gid);
}

// Monocular Core ML fallback. Kept deliberately conservative; V8's best path is synchronized TrueDepth.
kernel void depthLightKernel(
    texture2d<float, access::read> cameraTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant LightUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    float4 src = cameraTexture.read(gid);
    float2 size = float2(max(u.width,1u),max(u.height,1u));
    float2 uv=(float2(gid)+0.5)/size;
    float2 lightUV=u.lightPosition/size;
    float z=readDepth(depthTexture,uv);
    float2 t=1.0/float2(depthTexture.get_width(),depthTexture.get_height());
    float zx1=readDepth(depthTexture,uv+float2(t.x*5.0,0));
    float zx0=readDepth(depthTexture,uv-float2(t.x*5.0,0));
    float zy1=readDepth(depthTexture,uv+float2(0,t.y*5.0));
    float zy0=readDepth(depthTexture,uv-float2(0,t.y*5.0));
    float scale=max(abs(z),0.08);
    float3 N=normalize(float3(-(zx1-zx0)/scale*2.7,(zy1-zy0)/scale*2.7,1.0));
    float2 deltaPx=u.lightPosition-float2(gid);
    float spatial=smoothstep(u.radius,0.0,length(deltaPx));
    float lightZ=readDepth(depthTexture,lightUV);
    float virtualLightZ=lightZ+max(abs(lightZ),0.08)*0.10+0.018;
    float2 dirScreen=deltaPx/max(max(u.width,u.height),1u);
    float3 L=normalize(float3(dirScreen.x*2.0,-dirScreen.y*2.0,0.42+(virtualLightZ-z)*0.5));
    float diffuse=max(dot(N,L),0.0);
    float energy=spatial*diffuse*min(u.intensity,0.65);
    float3 lit=src.rgb + u.lightColor*energy*(0.40+dot(src.rgb,LUMA)*0.30);
    outputTexture.write(float4(filmicToneMap(lit*1.10),src.a),gid);
}
