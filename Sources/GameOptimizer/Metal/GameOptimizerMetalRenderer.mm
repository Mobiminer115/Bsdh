#include "GameOptimizerMetalRenderer.hpp"
#include "../Utilities/GameOptimizerLogger.hpp"
#import <Metal/Metal.h>
#include <cmath>
#include <algorithm>

namespace GameOptimizer {

static const char *kUpscaleShaderSource = R"METAL(
#include <metal_stdlib>
using namespace metal;

struct UpscaleVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex UpscaleVertexOut upscale_vertex_main(uint vertexID [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0,-1.0), float2(3.0,-1.0), float2(-1.0,3.0) };
    float2 texCoords[3] = { float2(0.0,1.0), float2(2.0,1.0), float2(0.0,-1.0) };
    UpscaleVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 upscale_fragment_sampled(UpscaleVertexOut in [[stage_in]],
                                          texture2d<float> sourceTexture [[texture(0)]],
                                          sampler upscaleSampler [[sampler(0)]]) {
    return sourceTexture.sample(upscaleSampler, in.texCoord);
}

inline float goCRW0(float t) { return -0.5*t*t*t + t*t - 0.5*t; }
inline float goCRW1(float t) { return  1.5*t*t*t - 2.5*t*t + 1.0; }
inline float goCRW2(float t) { return -1.5*t*t*t + 2.0*t*t + 0.5*t; }
inline float goCRW3(float t) { return  0.5*t*t*t - 0.5*t*t; }

fragment float4 upscale_fragment_bicubic(UpscaleVertexOut in [[stage_in]],
                                          texture2d<float> sourceTexture [[texture(0)]]) {
    float texW = sourceTexture.get_width();
    float texH = sourceTexture.get_height();
    float2 samplePos = in.texCoord * float2(texW, texH) - 0.5;
    float2 texelIndex = floor(samplePos);
    float2 t = samplePos - texelIndex;
    float wx[4] = { goCRW0(t.x), goCRW1(t.x), goCRW2(t.x), goCRW3(t.x) };
    float wy[4] = { goCRW0(t.y), goCRW1(t.y), goCRW2(t.y), goCRW3(t.y) };
    float4 sum = float4(0.0);
    int maxX = int(texW) - 1;
    int maxY = int(texH) - 1;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            int2 coord = int2(texelIndex) + int2(i - 1, j - 1);
            coord.x = clamp(coord.x, 0, maxX);
            coord.y = clamp(coord.y, 0, maxY);
            sum += sourceTexture.read(uint2(coord)) * (wx[i] * wy[j]);
        }
    }
    return sum;
}
)METAL";

GameOptimizerMetalRenderer::GameOptimizerMetalRenderer() {}

GameOptimizerMetalRenderer::~GameOptimizerMetalRenderer() {
    ShutdownAndWaitForGPU();
}

GameOptimizerResult GameOptimizerMetalRenderer::AttachDevice(void *mtlDevice, void *mtlCommandQueue) {
    if (mtlDevice == nullptr || mtlCommandQueue == nullptr) return GameOptimizerResultInvalidArgument;
    _device = mtlDevice;
    _commandQueue = mtlCommandQueue;
    _resourcePool.SetDevice(mtlDevice);
    return GameOptimizerResultSuccess;
}

bool GameOptimizerMetalRenderer::IsDeviceAttached() const {
    return _device != nullptr;
}

void GameOptimizerMetalRenderer::ComputeRenderSize(uint32_t drawableWidth, uint32_t drawableHeight, float scale,
                                                     uint32_t *outWidth, uint32_t *outHeight) {
    if (!std::isfinite(scale) || scale <= 0.0f) scale = 1.0f;
    long w = std::lround((double)drawableWidth * (double)scale);
    long h = std::lround((double)drawableHeight * (double)scale);
    if (w < 2) w = 2;
    if (h < 2) h = 2;
    if (w % 2 != 0) w += 1;
    if (h % 2 != 0) h += 1;
    *outWidth = (uint32_t)w;
    *outHeight = (uint32_t)h;
}

GameOptimizerResult GameOptimizerMetalRenderer::AcquireFrameRenderTargets(uint32_t drawableWidth,
                                                                           uint32_t drawableHeight,
                                                                           float scale,
                                                                           bool needsDepth,
                                                                           RenderTargetSet *outSet) {
    if (outSet == nullptr || drawableWidth == 0 || drawableHeight == 0) return GameOptimizerResultInvalidArgument;
    uint32_t renderW = 0, renderH = 0;
    ComputeRenderSize(drawableWidth, drawableHeight, scale, &renderW, &renderH);
    return _resourcePool.AcquireRenderTargets(renderW, renderH, needsDepth, _pixelFormat, outSet);
}

GameOptimizerResult GameOptimizerMetalRenderer::EnsurePipelinesReady() {
    ScopedLock guard(_lock);
    if (_pipelinesReady) return GameOptimizerResultSuccess;
    if (_device == nullptr) return GameOptimizerResultMetalUnavailable;

    id<MTLDevice> device = (__bridge id<MTLDevice>)_device;
    NSError *error = nil;

    NSString *source = [NSString stringWithUTF8String:kUpscaleShaderSource];
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        Logger::Shared().LogError(std::string("Metal shader compile failed: ") +
                                   (error ? error.localizedDescription.UTF8String : "unknown"));
        return GameOptimizerResultPipelineCreationFailed;
    }

    id<MTLFunction> vertexFn = [library newFunctionWithName:@"upscale_vertex_main"];
    id<MTLFunction> sampledFragmentFn = [library newFunctionWithName:@"upscale_fragment_sampled"];
    id<MTLFunction> bicubicFragmentFn = [library newFunctionWithName:@"upscale_fragment_bicubic"];
    if (!vertexFn || !sampledFragmentFn || !bicubicFragmentFn) {
        Logger::Shared().LogError("Metal shader functions missing from compiled library");
        return GameOptimizerResultPipelineCreationFailed;
    }

    MTLRenderPipelineDescriptor *sampledDesc = [[MTLRenderPipelineDescriptor alloc] init];
    sampledDesc.vertexFunction = vertexFn;
    sampledDesc.fragmentFunction = sampledFragmentFn;
    sampledDesc.colorAttachments[0].pixelFormat = (MTLPixelFormat)_pixelFormat;
    id<MTLRenderPipelineState> sampledPipeline = [device newRenderPipelineStateWithDescriptor:sampledDesc error:&error];
    if (sampledPipeline == nil) {
        Logger::Shared().LogError(std::string("Sampled pipeline creation failed: ") +
                                   (error ? error.localizedDescription.UTF8String : "unknown"));
        return GameOptimizerResultPipelineCreationFailed;
    }

    MTLRenderPipelineDescriptor *bicubicDesc = [[MTLRenderPipelineDescriptor alloc] init];
    bicubicDesc.vertexFunction = vertexFn;
    bicubicDesc.fragmentFunction = bicubicFragmentFn;
    bicubicDesc.colorAttachments[0].pixelFormat = (MTLPixelFormat)_pixelFormat;
    id<MTLRenderPipelineState> bicubicPipeline = [device newRenderPipelineStateWithDescriptor:bicubicDesc error:&error];
    if (bicubicPipeline == nil) {
        Logger::Shared().LogError(std::string("Bicubic pipeline creation failed: ") +
                                   (error ? error.localizedDescription.UTF8String : "unknown"));
        return GameOptimizerResultPipelineCreationFailed;
    }

    MTLSamplerDescriptor *nearestDesc = [[MTLSamplerDescriptor alloc] init];
    nearestDesc.minFilter = MTLSamplerMinMagFilterNearest;
    nearestDesc.magFilter = MTLSamplerMinMagFilterNearest;
    nearestDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    nearestDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> nearestSampler = [device newSamplerStateWithDescriptor:nearestDesc];

    MTLSamplerDescriptor *linearDesc = [[MTLSamplerDescriptor alloc] init];
    linearDesc.minFilter = MTLSamplerMinMagFilterLinear;
    linearDesc.magFilter = MTLSamplerMinMagFilterLinear;
    linearDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    linearDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> linearSampler = [device newSamplerStateWithDescriptor:linearDesc];

    if (nearestSampler == nil || linearSampler == nil) {
        Logger::Shared().LogError("Sampler state creation failed");
        return GameOptimizerResultPipelineCreationFailed;
    }

    _library = (__bridge_retained void *)library;
    _sampledPipelineState = (__bridge_retained void *)sampledPipeline;
    _bicubicPipelineState = (__bridge_retained void *)bicubicPipeline;
    _nearestSampler = (__bridge_retained void *)nearestSampler;
    _linearSampler = (__bridge_retained void *)linearSampler;
    _pipelinesReady = true;
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerMetalRenderer::EncodeUpscale(void *commandBufferPtr,
                                                                void *sourceTexturePtr,
                                                                void *destinationTexturePtr,
                                                                GameOptimizerUpscaleMode mode) {
    if (!commandBufferPtr || !sourceTexturePtr || !destinationTexturePtr) return GameOptimizerResultInvalidArgument;

    GameOptimizerResult ready = EnsurePipelinesReady();
    if (ready != GameOptimizerResultSuccess) return ready;

    id<MTLCommandBuffer> commandBuffer = (__bridge id<MTLCommandBuffer>)commandBufferPtr;
    id<MTLTexture> source = (__bridge id<MTLTexture>)sourceTexturePtr;
    id<MTLTexture> destination = (__bridge id<MTLTexture>)destinationTexturePtr;

    id<MTLRenderPipelineState> pipeline = nil;
    id<MTLSamplerState> sampler = nil;
    bool useBicubic = false;

    switch (mode) {
        case GameOptimizerUpscaleModeNearest:
            pipeline = (__bridge id<MTLRenderPipelineState>)_sampledPipelineState;
            sampler = (__bridge id<MTLSamplerState>)_nearestSampler;
            break;
        case GameOptimizerUpscaleModeBicubicLite:
            pipeline = (__bridge id<MTLRenderPipelineState>)_bicubicPipelineState;
            useBicubic = true;
            break;
        case GameOptimizerUpscaleModeBilinear:
        default:
            pipeline = (__bridge id<MTLRenderPipelineState>)_sampledPipelineState;
            sampler = (__bridge id<MTLSamplerState>)_linearSampler;
            break;
    }
    if (pipeline == nil) return GameOptimizerResultPipelineCreationFailed;

    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = destination;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    if (encoder == nil) return GameOptimizerResultInternalError;

    encoder.label = @"GameOptimizer.Upscale";
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:source atIndex:0];
    if (!useBicubic) [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];

    return GameOptimizerResultSuccess;
}

void GameOptimizerMetalRenderer::ShutdownAndWaitForGPU() {
    if (_commandQueue != nullptr) {
        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)_commandQueue;
        id<MTLCommandBuffer> fence = [queue commandBuffer];
        [fence commit];
        [fence waitUntilCompleted];
    }
    _resourcePool.ReleaseAllImmediately();

    ScopedLock guard(_lock);
    if (_sampledPipelineState) { id<MTLRenderPipelineState> p = (__bridge_transfer id<MTLRenderPipelineState>)_sampledPipelineState; (void)p; }
    if (_bicubicPipelineState) { id<MTLRenderPipelineState> p = (__bridge_transfer id<MTLRenderPipelineState>)_bicubicPipelineState; (void)p; }
    if (_nearestSampler) { id<MTLSamplerState> s = (__bridge_transfer id<MTLSamplerState>)_nearestSampler; (void)s; }
    if (_linearSampler) { id<MTLSamplerState> s = (__bridge_transfer id<MTLSamplerState>)_linearSampler; (void)s; }
    if (_library) { id<MTLLibrary> l = (__bridge_transfer id<MTLLibrary>)_library; (void)l; }
    _sampledPipelineState = _bicubicPipelineState = _nearestSampler = _linearSampler = _library = nullptr;
    _pipelinesReady = false;
    _device = nullptr;
    _commandQueue = nullptr;
}

} // namespace GameOptimizer
