#import "ExampleMetalRenderer.h"
#include "../Public/GameOptimizer.h"

// This file shows the CALL SEQUENCE integrators need. It intentionally does
// not implement a full offscreen-texture pool for the "scene target" (that's
// what SafeResourcePool already does inside the library) — wherever you see
// "YOUR OFFSCREEN TEXTURE" below, substitute your own reused MTLTexture sized
// exactly renderSize.width x renderSize.height, recreated only when that size
// actually changes.

@interface ExampleMetalRenderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation ExampleMetalRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _commandQueue = [device newCommandQueue];

        GameOptimizerInitialize();
        GameOptimizerAttachMetalDevice((__bridge void *)device, (__bridge void *)_commandQueue);

        // Optional: tune a couple of defaults for this app.
        GameOptimizerSetFPSLimitEnabled(true);
        GameOptimizerSetTargetFPS(60);
        GameOptimizerSetDynamicResolutionEnabled(true);
    }
    return self;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Nothing required here — GameOptimizerBeginFrame re-derives the correct
    // render size from the drawable size you pass it every frame.
}

- (void)drawInMTKView:(MTKView *)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    id<MTLTexture> drawableTexture = view.currentRenderPassDescriptor.colorAttachments[0].texture;
    if (!drawable || !drawableTexture) return;

    uint32_t drawableW = (uint32_t)view.drawableSize.width;
    uint32_t drawableH = (uint32_t)view.drawableSize.height;
    if (drawableW == 0 || drawableH == 0) return;

    GameOptimizerRenderSize renderSize = GameOptimizerBeginFrame(drawableW, drawableH);
    if (renderSize.shouldSkipFrame) return;

    CFTimeInterval cpuStart = CACurrentMediaTime();
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    BOOL usingOffscreen = (renderSize.width != drawableW || renderSize.height != drawableH);
    id<MTLTexture> sceneTarget = usingOffscreen ? nil /* YOUR OFFSCREEN TEXTURE, sized renderSize.width x renderSize.height */
                                                  : drawableTexture;
    if (usingOffscreen && sceneTarget == nil) {
        // Fallback for this trivial example only, since it has no real scene
        // or texture pool: render straight to the drawable at full size.
        sceneTarget = drawableTexture;
        usingOffscreen = NO;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = sceneTarget;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.05, 0.08, 1.0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    // ... your real scene draw calls go here ...
    [encoder endEncoding];

    if (usingOffscreen) {
        GameOptimizerEncodeUpscale((__bridge void *)commandBuffer,
                                    (__bridge void *)sceneTarget,
                                    (__bridge void *)drawableTexture);
    }

    double cpuMS = (CACurrentMediaTime() - cpuStart) * 1000.0;

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        double gpuMS = -1.0;
        if (buffer.GPUEndTime > buffer.GPUStartTime) {
            gpuMS = (buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0;
        }
        // Called from Metal's internal completion queue, not the main
        // thread — this is intentional, see GameOptimizer.h.
        GameOptimizerEndFrame(cpuMS, gpuMS);
    }];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

// Toggling the menu, e.g. from a debug button or shake gesture in your app:
//   GameOptimizerToggleMenu();
//
// Tearing down, e.g. in applicationWillTerminate:
//   GameOptimizerShutdown();
