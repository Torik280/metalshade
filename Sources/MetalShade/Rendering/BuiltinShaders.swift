let builtinShaderSource = """
#include <metal_stdlib>
using namespace metal;

kernel void fx_sharpen(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c = inTex.read(gid);
    float4 l = inTex.read(uint2(gid.x > 0u ? gid.x-1u : 0u, gid.y));
    float4 r = inTex.read(uint2(min(gid.x+1u, w-1u), gid.y));
    float4 t = inTex.read(uint2(gid.x, gid.y > 0u ? gid.y-1u : 0u));
    float4 b = inTex.read(uint2(gid.x, min(gid.y+1u, h-1u)));

    float4 lap = 4.0*c - l - r - t - b;
    float3 sharpened = clamp((c + lap * intensity * 0.8).rgb, 0.0, 1.0);
    outTex.write(float4(sharpened, c.a), gid);
}

kernel void fx_vibrance(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c    = inTex.read(gid);
    float maxC  = max(c.r, max(c.g, c.b));
    float minC  = min(c.r, min(c.g, c.b));
    float sat   = maxC - minC;
    float luma  = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));
    float boost = (intensity * 1.2) * (1.0 - sat);
    float3 rgb  = clamp(mix(float3(luma), c.rgb, 1.0 + boost), 0.0, 1.0);
    outTex.write(float4(rgb, c.a), gid);
}

kernel void fx_bloom(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 original = inTex.read(gid);
    const int   R          = 4;
    const float weights[5] = {0.2270, 0.1945, 0.1216, 0.0540, 0.0162};

    float4 glow   = float4(0.0);
    float  wTotal = 0.0;

    for (int dy = -R; dy <= R; dy++) {
        for (int dx = -R; dx <= R; dx++) {
            uint2  sp    = uint2(clamp(int(gid.x)+dx, 0, int(w)-1), clamp(int(gid.y)+dy, 0, int(h)-1));
            float4 s     = inTex.read(sp);
            float  luma  = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
            float  bright = max(0.0, luma - 0.55);
            float  w_xy  = weights[abs(dx)] * weights[abs(dy)];
            glow   += s * bright * w_xy;
            wTotal += w_xy;
        }
    }
    glow = (wTotal > 0.0) ? (glow / wTotal) : float4(0.0);
    float3 bloomed = clamp((original + glow * intensity * 1.5).rgb, 0.0, 1.0);
    outTex.write(float4(bloomed, original.a), gid);
}

kernel void fx_vignette(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c  = inTex.read(gid);
    float2 uv = float2(gid) / float2(w, h) - 0.5;
    uv.x *= float(w) / float(h);
    float v = 1.0 - smoothstep(0.25, 0.75, length(uv) * intensity * 2.2);
    outTex.write(float4(c.rgb * v, c.a), gid);
}

kernel void fx_contrast(
    texture2d<float, access::read>  inTex     [[texture(0)]],
    texture2d<float, access::write> outTex    [[texture(1)]],
    constant float&                 intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width(), h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c      = inTex.read(gid);
    float  amount = (intensity - 0.5) * 2.0;
    float3 s      = c.rgb;
    float3 curve  = s * s * (3.0 - 2.0 * s);
    float3 rgb    = clamp(mix(s, curve, amount), 0.0, 1.0);
    outTex.write(float4(rgb, c.a), gid);
}

struct DisplayVert {
    float4 pos [[position]];
    float2 uv;
};

vertex DisplayVert displayVertex(uint vid [[vertex_id]]) {
    float4 positions[3] = { float4(-1,-1,0,1), float4(3,-1,0,1), float4(-1,3,0,1) };
    float2 uvs[3]       = { float2(0,1),       float2(2,1),      float2(0,-1)     };
    DisplayVert out;
    out.pos = positions[vid];
    out.uv  = uvs[vid];
    return out;
}

fragment float4 displayFragment(DisplayVert in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    return tex.sample(s, in.uv);
}
"""
