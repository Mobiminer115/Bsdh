//
//  SafeResourcePool.hpp
//  GameOptimizer
//
//  Owns the offscreen color (+ optional depth) render targets used by the
//  upscale pipeline. Never creates a new texture unless the requested size,
//  pixel format, or depth requirement actually changed since the last call —
//  and even then, the texture(s) being replaced are not deallocated until the
//  GPU work that might still be reading them has been confirmed complete via
//  RetireGeneration(), called from a command buffer completion handler.
//

#ifndef GAME_OPTIMIZER_SAFE_RESOURCE_POOL_HPP
#define GAME_OPTIMIZER_SAFE_RESOURCE_POOL_HPP

#include "../Public/GameOptimizerTypes.h"
#include "../Utilities/GameOptimizerThreading.hpp"
#include <cstdint>
#include <vector>

namespace GameOptimizer {

struct RenderTargetSet {
    void *colorTexture = nullptr; // bridged id<MTLTexture>, non-owning to the caller (pool retains it)
    void *depthTexture = nullptr; // bridged id<MTLTexture>, nullptr if depth was not requested
    uint32_t width = 0;
    uint32_t height = 0;
    uint64_t generation = 0;
};

class SafeResourcePool {
public:
    SafeResourcePool();
    ~SafeResourcePool();

    SafeResourcePool(const SafeResourcePool &) = delete;
    SafeResourcePool &operator=(const SafeResourcePool &) = delete;

    /// Bridged id<MTLDevice>, non-owning — the caller (GameOptimizerMetalRenderer)
    /// keeps the device alive for as long as this pool is used.
    void SetDevice(void *mtlDevice);

    /// Returns the current (possibly freshly reallocated) render target set
    /// for the given parameters. If nothing changed since the last call, this
    /// is just a fast pointer return — no allocation, no generation bump.
    /// pixelFormatRawValue is an MTLPixelFormat value; pass 80 (BGRA8Unorm)
    /// unless the integrator has a specific reason to change it.
    GameOptimizerResult AcquireRenderTargets(uint32_t width,
                                              uint32_t height,
                                              bool needsDepth,
                                              uint64_t pixelFormatRawValue,
                                              RenderTargetSet *outSet);

    /// Call from a command buffer completion handler once you know every
    /// command buffer that might reference `generation` has finished
    /// executing (in practice: the generation that GameOptimizerBeginFrame
    /// handed out for that particular frame). Thread-safe — completion
    /// handlers do not run on the render thread.
    void RetireGeneration(uint64_t generation);

    /// True when the pending-release list is full; callers should skip
    /// resizing this frame (keep using the current target set) rather than
    /// grow the list further.
    bool IsAtPendingReleaseLimit() const;

    uint64_t EstimatedMemoryUsageBytes() const;

    /// Drops every retained texture immediately, WITHOUT waiting for GPU
    /// completion. Only safe to call once you have already confirmed the GPU
    /// is idle (e.g. after waiting on the command queue during shutdown) —
    /// this is intentionally the one place in the codebase allowed to skip
    /// deferred release, precisely because normal frame-to-frame resizing
    /// must never take this shortcut.
    void ReleaseAllImmediately();

private:
    static constexpr size_t kMaxPendingGenerations = 3;

    void *_device = nullptr; // bridged id<MTLDevice>, non-owning

    mutable UnfairLock _lock;

    RenderTargetSet _current;
    uint64_t _currentApproximateBytes = 0;
    bool _hasDepth = false;
    uint64_t _pixelFormat = 80; // MTLPixelFormatBGRA8Unorm
    uint64_t _nextGeneration = 1;

    struct PendingRelease {
        uint64_t generation = 0;
        void *colorTexture = nullptr; // bridged, owning (+1 retain taken when enqueued)
        void *depthTexture = nullptr; // bridged, owning
        uint64_t approximateBytes = 0;
    };
    std::vector<PendingRelease> _pending;
    uint64_t _currentBytes = 0;
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_SAFE_RESOURCE_POOL_HPP */
