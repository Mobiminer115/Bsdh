#include "SafeResourcePool.hpp"

#import <Metal/Metal.h>

namespace GameOptimizer {

namespace {
// Deliberately conservative and NOT a runtime device query: Metal does not
// expose a simple "maxTextureDimension2D" property on id<MTLDevice>, and
// this project's rule is to never invent an API that doesn't exist. 8192 is
// safely within the guaranteed 2D texture size limit for every Metal-capable
// iOS device shipped to date; if you have verified your minimum supported
// device supports larger textures you may raise this.
constexpr uint32_t kConservativeMaxTextureDimension = 8192;
} // namespace

SafeResourcePool::SafeResourcePool() {}

SafeResourcePool::~SafeResourcePool() {
    ReleaseAllImmediately();
}

void SafeResourcePool::SetDevice(void *mtlDevice) {
    ScopedLock guard(_lock);
    _device = mtlDevice;
}

GameOptimizerResult SafeResourcePool::AcquireRenderTargets(uint32_t width,
                                                             uint32_t height,
                                                             bool needsDepth,
                                                             uint64_t pixelFormatRawValue,
                                                             RenderTargetSet *outSet) {
    if (outSet == nullptr) return GameOptimizerResultInvalidArgument;
    if (width == 0 || height == 0) return GameOptimizerResultInvalidArgument;

    ScopedLock guard(_lock);

    if (_device == nullptr) return GameOptimizerResultMetalUnavailable;

    uint32_t clampedWidth = std::min(width, kConservativeMaxTextureDimension);
    uint32_t clampedHeight = std::min(height, kConservativeMaxTextureDimension);

    bool unchanged = (_current.colorTexture != nullptr) &&
                      (_current.width == clampedWidth) &&
                      (_current.height == clampedHeight) &&
                      (_hasDepth == needsDepth) &&
                      (_pixelFormat == pixelFormatRawValue);
    if (unchanged) {
        *outSet = _current;
        return GameOptimizerResultSuccess;
    }

    if (_pending.size() >= kMaxPendingGenerations) {
        // Too many old texture sets still awaiting GPU confirmation of
        // completion — do not grow the list further. Hand back whatever we
        // currently have (if anything) so the caller can keep rendering at
        // the previous size this frame instead of stalling.
        if (_current.colorTexture != nullptr) {
            *outSet = _current;
            return GameOptimizerResultOperationDeferred;
        }
        return GameOptimizerResultOperationDeferred;
    }

    id<MTLDevice> device = (__bridge id<MTLDevice>)_device;

    MTLPixelFormat pixelFormat = (MTLPixelFormat)pixelFormatRawValue;
    MTLTextureDescriptor *colorDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                             width:clampedWidth
                                                            height:clampedHeight
                                                         mipmapped:NO];
    colorDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    colorDescriptor.storageMode = MTLStorageModePrivate;
    colorDescriptor.textureType = MTLTextureType2D;

    id<MTLTexture> newColor = [device newTextureWithDescriptor:colorDescriptor];
    if (newColor == nil) {
        return GameOptimizerResultTextureCreationFailed;
    }

    id<MTLTexture> newDepth = nil;
    if (needsDepth) {
        MTLTextureDescriptor *depthDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                 width:clampedWidth
                                                                height:clampedHeight
                                                             mipmapped:NO];
        depthDescriptor.usage = MTLTextureUsageRenderTarget;
        depthDescriptor.storageMode = MTLStorageModePrivate;
        depthDescriptor.textureType = MTLTextureType2D;

        newDepth = [device newTextureWithDescriptor:depthDescriptor];
        if (newDepth == nil) {
            // Depth is a nice-to-have for the offscreen pass; if it fails we
            // still proceed with color-only rather than failing the whole
            // frame, since a 3D scene renderer that truly requires depth
            // will surface its own, more specific error when it tries to
            // bind a null depth attachment.
            newDepth = nil;
        }
    }

    // Retire the previous generation into the pending list (deferred release
    // — the GPU may still be reading it via a command buffer already in
    // flight) rather than releasing it here.
    if (_current.colorTexture != nullptr) {
        PendingRelease pending;
        pending.generation = _current.generation;
        pending.colorTexture = (__bridge_retained void *)((__bridge id<MTLTexture>)_current.colorTexture);
        pending.depthTexture = _current.depthTexture
                                    ? (__bridge_retained void *)((__bridge id<MTLTexture>)_current.depthTexture)
                                    : nullptr;
        pending.approximateBytes = _currentApproximateBytes;
        _pending.push_back(pending);
    }

    _current.colorTexture = (__bridge_retained void *)newColor;
    _current.depthTexture = newDepth ? (__bridge_retained void *)newDepth : nullptr;
    _current.width = clampedWidth;
    _current.height = clampedHeight;
    _current.generation = _nextGeneration++;
    _hasDepth = (newDepth != nil);
    _pixelFormat = pixelFormatRawValue;

    uint64_t bytesPerPixelColor = 4; // true for BGRA8Unorm/RGBA8Unorm; documented estimate for other formats
    uint64_t bytesPerPixelDepth = 4; // true for Depth32Float
    _currentApproximateBytes = (uint64_t)clampedWidth * (uint64_t)clampedHeight * bytesPerPixelColor;
    if (_hasDepth) {
        _currentApproximateBytes += (uint64_t)clampedWidth * (uint64_t)clampedHeight * bytesPerPixelDepth;
    }

    *outSet = _current;
    return GameOptimizerResultSuccess;
}

void SafeResourcePool::RetireGeneration(uint64_t generation) {
    ScopedLock guard(_lock);

    std::vector<PendingRelease> stillPending;
    stillPending.reserve(_pending.size());

    for (auto &entry : _pending) {
        if (entry.generation <= generation) {
            // __bridge_transfer hands the retain we took when enqueuing back
            // to ARC, which releases it as these locals go out of scope.
            if (entry.colorTexture) {
                id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)entry.colorTexture;
                (void)t;
            }
            if (entry.depthTexture) {
                id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)entry.depthTexture;
                (void)t;
            }
        } else {
            stillPending.push_back(entry);
        }
    }

    _pending.swap(stillPending);
}

bool SafeResourcePool::IsAtPendingReleaseLimit() const {
    ScopedLock guard(_lock);
    return _pending.size() >= kMaxPendingGenerations;
}

uint64_t SafeResourcePool::EstimatedMemoryUsageBytes() const {
    ScopedLock guard(_lock);
    uint64_t total = _currentApproximateBytes;
    for (const auto &entry : _pending) {
        total += entry.approximateBytes;
    }
    return total;
}

void SafeResourcePool::ReleaseAllImmediately() {
    ScopedLock guard(_lock);

    if (_current.colorTexture) {
        id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)_current.colorTexture;
        (void)t;
    }
    if (_current.depthTexture) {
        id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)_current.depthTexture;
        (void)t;
    }
    _current = RenderTargetSet{};
    _currentApproximateBytes = 0;

    for (auto &entry : _pending) {
        if (entry.colorTexture) {
            id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)entry.colorTexture;
            (void)t;
        }
        if (entry.depthTexture) {
            id<MTLTexture> t = (__bridge_transfer id<MTLTexture>)entry.depthTexture;
            (void)t;
        }
    }
    _pending.clear();
}

} // namespace GameOptimizer
