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
    float4 params;      // x shadow, y subjectDepth, z maxLitDepth
    float4 mapping;     // x cameraAspect, y effectiveDepthAspect, z rotateDepth
    uint2 dimensions;
    uint2 padding;
};

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
    if (u.mapping.z > 0.5) {
        p = float2(uv.y, 1.0 - uv.x);
    }
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

static inline float robustMetricDepth(texture2d<float, access::read> tex,
                                      float2 screenUV,
                                      constant V7Uniforms &u) {
    float2 uv = mapDepthUV(screenUV, u);
    float2 t = 1.0 / float2(tex.get_width(), tex.get_height());
    float c = readDepth(tex, uv);
    if (!validMetric(c)) return -1.0;
    float threshold = max(0.018, c * 0.04);
    float sum = c * 3.0;
    float w = 3.0;
    float2 offs[8] = {
        float2(t.x,0), float2(-t.x,0), float2(0,t.y), float2(0,-t.y),
        float2(t.x,t.y), float2(-t.x,t.y), float2(t.x,-t.y), float2(-t.x,-t.y)
    };
    for (uint i=0; i<8; ++i) {
        float z = readDepth(tex, uv + offs[i]);
        if (validMetric(z) && abs(z-c) < threshold) { sum += z; w += 1.0; }
    }
    return sum / w;
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
    float z = robustMetricDepth(depthTexture, uv, u);
    if (!validMetric(z)) { outputTexture.write(src, gid); return; }

    float subjectDepth = u.params.y;
    float maxLitDepth = u.params.z;
    float subjectGate = 1.0 - smoothstep(subjectDepth + 0.28, maxLitDepth, z);
    subjectGate = clamp(subjectGate, 0.0, 1.0);

    float2 px = float2(1.4/size.x, 1.4/size.y);
    float zl = robustMetricDepth(depthTexture, uv-float2(px.x,0), u);
    float zr = robustMetricDepth(depthTexture, uv+float2(px.x,0), u);
    float zu = robustMetricDepth(depthTexture, uv-float2(0,px.y), u);
    float zd = robustMetricDepth(depthTexture, uv+float2(0,px.y), u);
    zl = validMetric(zl) && abs(zl-z) < 0.06 ? zl : z;
    zr = validMetric(zr) && abs(zr-z) < 0.06 ? zr : z;
    zu = validMetric(zu) && abs(zu-z) < 0.06 ? zu : z;
    zd = validMetric(zd) && abs(zd-z) < 0.06 ? zd : z;

    float aspect = size.x/max(size.y,1.0);
    float dzdx = (zr-zl)/max(z*0.16,0.03);
    float dzdy = (zd-zu)/max(z*0.16,0.03);
    float3 N = normalize(float3(-dzdx*0.72, dzdy*0.72, -1.0));
    if (N.z > 0.0) N = -N;

    float2 lightUV = clamp(u.lightPosition,float2(0.03),float2(0.97));
    float3 receiver = float3((uv.x-0.5)*z*aspect*0.82, (0.5-uv.y)*z*0.82, z);
    float3 lamp = float3((lightUV.x-0.5)*u.lightDepth*aspect*0.82,
                         (0.5-lightUV.y)*u.lightDepth*0.82,
                         u.lightDepth);
    float3 Lvec = lamp-receiver;
    float d = max(length(Lvec),0.001);
    float3 L = Lvec/d;
    float diffuse = pow(max(dot(N,L),0.0),0.82);

    float2 sd = uv-lightUV;
    sd.x *= aspect;
    float radial = length(sd);
    float radius = max(u.radius,0.08);
    float spatial = 1.0-smoothstep(radius*0.18,radius,radial);
    float falloff = 1.0/(1.0+d*d*4.8);

    float occAccum = 0.0;
    float occCount = 0.0;
    const int STEPS = 10;
    for (int i=2; i<STEPS-1; ++i) {
        float t = float(i)/float(STEPS);
        float2 suv = mix(uv,lightUV,t);
        float sampleZ = robustMetricDepth(depthTexture,suv,u);
        if (!validMetric(sampleZ)) continue;
        float expected = mix(z,u.lightDepth,t);
        float bias = max(0.018,expected*0.03);
        float blocker = expected-sampleZ-bias;
        float hit = smoothstep(0.015,0.065,blocker);
        occAccum += hit;
        occCount += 1.0;
    }
    float occlusion = occCount > 0.0 ? clamp(occAccum/max(occCount,1.0)*2.2,0.0,1.0) : 0.0;
    float shadowStrength = clamp(u.params.x,0.0,1.0);
    float visibility = 1.0-occlusion*(0.18+0.42*shadowStrength);

    float intensity = min(u.colorIntensity.a,1.0);
    float3 lightColor = u.colorIntensity.rgb;
    float energy = spatial*falloff*diffuse*visibility*subjectGate*intensity*1.25;

    float3 base = src.rgb;
    float3 add = lightColor*energy*(0.48+dot(base,float3(0.2126,0.7152,0.0722))*0.38);
    float3 lit = 1.0-(1.0-base)*exp(-add*1.15);

    float3 V = normalize(-receiver);
    float3 H = normalize(L+V);
    float spec = pow(max(dot(N,H),0.0),28.0)*spatial*visibility*subjectGate;
    lit = min(lit + lightColor*spec*intensity*0.07, float3(1.0));

    // Shadows never crush the original camera image to black.
    float shadowMul = 1.0-occlusion*spatial*subjectGate*shadowStrength*0.10;
    lit *= shadowMul;

    // Compact lamp core; keep it bright but prevent the giant blown-out halo seen in V6.
    float orbRadius = 0.010 + radius*0.010;
    float orbDist = length(sd);
    float glow = exp(-pow(orbDist/max(orbRadius*2.3,0.001),2.0)*2.2);
    float core = 1.0-smoothstep(orbRadius*0.45,orbRadius,orbDist);
    float lightSurfaceDepth = robustMetricDepth(depthTexture,lightUV,u);
    float blockerDepth = validMetric(lightSurfaceDepth) ? lightSurfaceDepth : z;
    float orbVisible = 1.0-smoothstep(0.018,0.07,u.lightDepth-blockerDepth);
    float lampEnergy = (glow*0.26+core*0.58)*orbVisible;
    lit = min(lit + lightColor*lampEnergy*(0.35+0.35*intensity) + float3(1.0)*core*orbVisible*0.35,
              float3(1.0));

    outputTexture.write(float4(lit,src.a),gid);
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
    float2 size = float2(max(u.width,1u),max(u.height,1u));
    float2 uv=(float2(gid)+0.5)/size;
    float2 lightUV=u.lightPosition/size;
    float z=readDepth(depthTexture,uv);
    float2 t=1.0/float2(depthTexture.get_width(),depthTexture.get_height());
    float zx1=readDepth(depthTexture,uv+float2(t.x,0));
    float zx0=readDepth(depthTexture,uv-float2(t.x,0));
    float zy1=readDepth(depthTexture,uv+float2(0,t.y));
    float zy0=readDepth(depthTexture,uv-float2(0,t.y));
    float scale=max(abs(z),0.08);
    float3 N=normalize(float3(-(zx1-zx0)/scale*4.0,(zy1-zy0)/scale*4.0,1.0));
    float2 deltaPx=u.lightPosition-float2(gid);
    float spatial=smoothstep(u.radius,0.0,length(deltaPx));
    float lightZ=readDepth(depthTexture,lightUV);
    float virtualLightZ=lightZ+max(abs(lightZ),0.08)*0.12+0.02;
    float2 dirScreen=deltaPx/max(max(u.width,u.height),1u);
    float3 L=normalize(float3(dirScreen.x*2.0,-dirScreen.y*2.0,0.4+(virtualLightZ-z)*0.6));
    float diffuse=max(dot(N,L),0.0);
    float energy=spatial*diffuse*min(u.intensity,0.72);
    float3 add=u.lightColor*energy*(0.45+dot(src.rgb,float3(0.2126,0.7152,0.0722))*0.35);
    float3 lit=1.0-(1.0-src.rgb)*exp(-add);
    outputTexture.write(float4(clamp(lit,0.0,1.0),src.a),gid);
}
