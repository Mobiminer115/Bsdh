//
//  UpscaleShaders.metal
//  GameOptimizer
//
//  Full-screen-triangle upscale pass: one vertex shader that needs no vertex
//  buffer, and two fragment shaders — a hardware-sampled one (used for both
//  Nearest and Bilinear, which differ only by the MTLSamplerState bound at
//  draw time) and a manual 16-tap Catmull-Rom convolution for "Bicubic Lite".
//
//  NOTE: GameOptimizerMetalRenderer.mm does NOT load this file via
//  -newDefaultLibrary. It compiles an embedded copy of this exact source from
//  a string at first use via -newLibraryWithSource:options:error:, so the
//  library builds identically whether Xcode's Metal compiler processes this
//  file or not (relevant for Swift Package Manager, whose handling of .metal
//  build inputs is less predictable than a native Xcode target's). Keep the
//  two copies in sync if you edit the shader; the embedded copy is the one
//  actually used at runtime.
//

#include <metal_stdlib>
using namespace metal;

struct UpscaleVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex UpscaleVertexOut upscale_vertex_main(uint vertexID [[vertex_id]]) {
    // Single oversized triangle covering the full screen; avoids the
    // diagonal seam a two-triangle quad would need to hide.
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 texCoords[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    UpscaleVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 upscale_fragment_sampled(UpscaleVertexOut in [[stage_in]],
                                          texture2d<float> sourceTexture [[texture(0)]],
                                          sampler upscaleSampler [[sampler(0)]]) {
    // Used for BOTH Nearest and Bilinear — the two tiers differ only by the
    // min/mag filter configured on `upscaleSampler` at draw time, not by
    // shader code, so there is exactly one hardware-sampled pipeline state
    // instead of two near-identical ones.
    return sourceTexture.sample(upscaleSampler, in.texCoord);
}

inline float gameOptimizerCatmullRomWeight0(float t) { return -0.5 * t * t * t + t * t - 0.5 * t; }
inline float gameOptimizerCatmullRomWeight1(float t) { return  1.5 * t * t * t - 2.5 * t * t + 1.0; }
inline float gameOptimizerCatmullRomWeight2(float t) { return -1.5 * t * t * t + 2.0 * t * t + 0.5 * t; }
inline float gameOptimizerCatmullRomWeight3(float t) { return  0.5 * t * t * t - 0.5 * t * t; }

fragment float4 upscale_fragment_bicubic(UpscaleVertexOut in [[stage_in]],
                                          texture2d<float> sourceTexture [[texture(0)]]) {
    float texWidth = sourceTexture.get_width();
    float texHeight = sourceTexture.get_height();
    float2 texSize = float2(texWidth, texHeight);

    float2 samplePos = in.texCoord * texSize - 0.5;
    float2 texelIndex = floor(samplePos);
    float2 t = samplePos - texelIndex;

    float wx[4] = {
        gameOptimizerCatmullRomWeight0(t.x),
        gameOptimizerCatmullRomWeight1(t.x),
        gameOptimizerCatmullRomWeight2(t.x),
        gameOptimizerCatmullRomWeight3(t.x)
    };
    float wy[4] = {
        gameOptimizerCatmullRomWeight0(t.y),
        gameOptimizerCatmullRomWeight1(t.y),
        gameOptimizerCatmullRomWeight2(t.y),
        gameOptimizerCatmullRomWeight3(t.y)
    };

    float4 colorSum = float4(0.0);
    int maxX = int(texWidth) - 1;
    int maxY = int(texHeight) - 1;

    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            int2 coord = int2(texelIndex) + int2(i - 1, j - 1);
            coord.x = clamp(coord.x, 0, maxX);
            coord.y = clamp(coord.y, 0, maxY);
            float4 texel = sourceTexture.read(uint2(coord));
            colorSum += texel * (wx[i] * wy[j]);
        }
    }

    return colorSum;
}
