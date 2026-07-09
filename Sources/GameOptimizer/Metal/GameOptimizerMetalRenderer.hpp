//
//  GameOptimizerMetalRenderer.hpp
//  GameOptimizer
//
//  Owns everything Metal-specific: the (non-owning) device/queue references
//  handed to us via GameOptimizerAttachMetalDevice, the lazily-created and
//  cached upscale pipeline states + samplers, and the SafeResourcePool that
//  backs the offscreen render target. GameOptimizerCore.mm is the only
//  caller; nothing here ever touches UIKit or the public C API directly.
//

#ifndef GAME_OPTIMIZER_METAL_RENDERER_HPP
#define GAME_OPTIMIZER_METAL_RENDERER_HPP

#include "../Public/GameOptimizerTypes.h"
#include "../Utilities/GameOptimizerThreading.hpp"
#include "../Core/SafeResourcePool.hpp"
#include <cstdint>

namespace GameOptimizer {

class GameOptimizerMetalRenderer {
public:
    GameOptimizerMetalRenderer();
    ~GameOptimizerMetalRenderer();

    GameOptimizerMetalRenderer(const GameOptimizerMetalRenderer &) = delete;
    GameOptimizerMetalRenderer &operator=(const GameOptimizerMetalRenderer &) = delete;

    /// Bridged id<MTLDevice> / id<MTLCommandQueue>, both non-owning — caller
    /// keeps them alive. Safe to call again later to re-attach (e.g. if the
    /// app recreates its device, which is rare but not impossible).
    GameOptimizerResult AttachDevice(void *mtlDevice, void *mtlCommandQueue);
    bool IsDeviceAttached() const;

    /// Pure arithmetic (no Metal calls): rounds drawableSize * scale to a
    /// positive even width/height, per the spec's texture-sizing rules.
    /// Does NOT apply the device texture-size ceiling — that clamp happens
    /// inside SafeResourcePool, which is the single source of truth for the
    /// size actually allocated (read it back from RenderTargetSet).
    static void ComputeRenderSize(uint32_t drawableWidth, uint32_t drawableHeight, float scale,
                                   uint32_t *outWidth, uint32_t *outHeight);

    /// Acquires this frame's offscreen render target (creating/resizing only
    /// if needed). GameOptimizerResultOperationDeferred means the
    /// pending-release limit was hit; outSet is still populated with the
    /// previous (still valid) target so the caller can keep rendering at the
    /// old size for this one frame rather than stalling.
    GameOptimizerResult AcquireFrameRenderTargets(uint32_t drawableWidth,
                                                   uint32_t drawableHeight,
                                                   float scale,
                                                   bool needsDepth,
                                                   RenderTargetSet *outSet);

    /// Encodes the full-screen upscale blit. See GameOptimizer.h for the
    /// exact contract (bridged pointers, ownership, threading).
    GameOptimizerResult EncodeUpscale(void *commandBuffer,
                                       void *sourceTexture,
                                       void *destinationTexture,
                                       GameOptimizerUpscaleMode mode);

    void RetireGeneration(uint64_t generation) { _resourcePool.RetireGeneration(generation); }
    bool IsAtPendingReleaseLimit() const { return _resourcePool.IsAtPendingReleaseLimit(); }
    uint64_t EstimatedMemoryUsageBytes() const { return _resourcePool.EstimatedMemoryUsageBytes(); }
    bool PipelinesReady() const { return _pipelinesReady; }

    /// Shutdown-only: submits an empty command buffer and blocks until it
    /// completes (guaranteeing every previously-submitted frame has too,
    /// since a queue's command buffers complete in commit order), then
    /// releases every cached Metal object immediately. Never call this from
    /// the regular per-frame path.
    void ShutdownAndWaitForGPU();

private:
    GameOptimizerResult EnsurePipelinesReady();

    void *_device = nullptr;
    void *_commandQueue = nullptr;
    void *_library = nullptr;
    void *_sampledPipelineState = nullptr;  // used for both Nearest and Bilinear (sampler differs)
    void *_bicubicPipelineState = nullptr;
    void *_nearestSampler = nullptr;
    void *_linearSampler = nullptr;
    bool  _pipelinesReady = false;

    uint64_t _pixelFormat = 80; // MTLPixelFormatBGRA8Unorm

    SafeResourcePool _resourcePool;
    mutable UnfairLock _lock; // guards lazy pipeline creation only
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_METAL_RENDERER_HPP */
