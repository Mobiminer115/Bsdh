//
//  GameOptimizer.h
//  GameOptimizer
//
//  Public API. Every function here:
//    - is safe to call from any thread unless documented otherwise,
//    - validates its own arguments (range, NaN/Infinity, null pointers),
//    - never throws a C++ exception across this boundary,
//    - never aborts/crashes on bad input — it returns a GameOptimizerResult
//      and leaves the active configuration untouched.
//
//  Sections 1-3 below are the exact API surface requested in the project spec.
//  Section 4 ("Metal render integration") is an additive, optional extension
//  for apps that want GameOptimizer to also perform the offscreen-render +
//  upscale-blit itself; you can ignore it entirely and only use Sections 1-3
//  if you'd rather drive your own Metal pipeline using GameOptimizerGetMetrics()
//  for the render scale to use.
//

#ifndef GAME_OPTIMIZER_H
#define GAME_OPTIMIZER_H

#include "GameOptimizerTypes.h"

#if defined(__cplusplus)
    #define GAMEOPTIMIZER_EXTERN extern "C"
#else
    #define GAMEOPTIMIZER_EXTERN extern
#endif

#if defined(GAMEOPTIMIZER_BUILDING_LIBRARY)
    #define GAMEOPTIMIZER_API GAMEOPTIMIZER_EXTERN __attribute__((visibility("default")))
#else
    #define GAMEOPTIMIZER_API GAMEOPTIMIZER_EXTERN
#endif

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 1. Lifecycle

/// Initializes the library: allocates internal state, registers lifecycle
/// notification observers, prepares (but does not force-create) Metal
/// resources. Safe to call more than once; a second call while already
/// initialized returns GameOptimizerResultAlreadyInitialized and does nothing.
/// Must be called from the main thread.
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerInitialize(void);

/// Tears everything down: hides the UI, invalidates timers/display links,
/// releases Metal resources once the GPU is done with them, unregisters
/// notifications. Safe to call multiple times, including when never
/// initialized. Must be called from the main thread.
GAMEOPTIMIZER_API void GameOptimizerShutdown(void);

/// Thread-safe.
GAMEOPTIMIZER_API bool GameOptimizerIsInitialized(void);

#pragma mark - 2. Menu / overlay UI

/// These four are safe to call from any thread; UIKit work is always
/// dispatched to the main thread internally (async, never sync).
GAMEOPTIMIZER_API void GameOptimizerShowMenu(void);
GAMEOPTIMIZER_API void GameOptimizerHideMenu(void);
GAMEOPTIMIZER_API void GameOptimizerToggleMenu(void);
GAMEOPTIMIZER_API bool GameOptimizerIsMenuVisible(void);

#pragma mark - 3. Configuration, metrics, presets

GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetMasterEnabled(bool enabled);

GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetManualRenderScale(float scale);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetDynamicResolutionEnabled(bool enabled);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetMinimumRenderScale(float scale);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetMaximumRenderScale(float scale);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetScaleStep(float step);

GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetTargetFPS(int fps);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetFPSLimitEnabled(bool enabled);

GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetCPUOptimizationEnabled(bool enabled);
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetCPUOptimizationMode(GameOptimizerCPUMode mode);

GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerSetThermalProtectionEnabled(bool enabled);

/// Immediately resets every tunable to the built-in "Safe" configuration
/// (see README §Presets). Never fails except if not initialized.
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerRestoreSafeDefaults(void);

/// Thread-safe snapshot reads. Cheap (lock + struct copy, no Metal/UIKit touched).
GAMEOPTIMIZER_API GameOptimizerMetrics GameOptimizerGetMetrics(void);
GAMEOPTIMIZER_API GameOptimizerConfiguration GameOptimizerGetConfiguration(void);

/// Validates the entire struct as one transaction: if any field is invalid,
/// NOTHING is applied and the previous configuration remains active.
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerApplyConfiguration(const GameOptimizerConfiguration *configuration);

/// Loads a built-in preset (validated, applied transactionally, then saved).
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerApplyPreset(GameOptimizerPreset preset);

/// Returns a populated GameOptimizerConfiguration for the given preset without
/// applying it, so UI can show "what will change" before commit.
GAMEOPTIMIZER_API GameOptimizerConfiguration GameOptimizerConfigurationForPreset(GameOptimizerPreset preset);

#pragma mark - Errors

/// Returns a pointer to an internally-owned, static-lifetime UTF-8 buffer
/// that is only ever updated from within library calls (never freed by the
/// caller). It is valid until the next call to any GameOptimizer function on
/// any thread, which is why GameOptimizerCopyLastError below is the
/// recommended, fully-safe alternative for anything beyond quick debug prints.
GAMEOPTIMIZER_API const char *GameOptimizerGetLastError(void);

/// Safe alternative: copies up to bufferSize-1 bytes of the last error message
/// (plus NUL terminator) into a caller-owned buffer. Returns the number of
/// bytes written, excluding the terminator. Passing a null buffer or zero size
/// is safe and returns the required length (like snprintf).
GAMEOPTIMIZER_API size_t GameOptimizerCopyLastError(char *buffer, size_t bufferSize);

#pragma mark - 4. Metal render integration (additive, optional)

/// Hands GameOptimizer non-owning references to your already-created Metal
/// device and command queue (bridged as void* via (__bridge void*)). The
/// library does not retain, release, or take ownership of these — your app
/// keeps managing their lifetime exactly as before. Call once, after you
/// create your device/queue and before your first frame.
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerAttachMetalDevice(void *mtlDevice, void *mtlCommandQueue);

/// Call at the start of your frame, after you know the drawable size. Returns
/// the render width/height you should render your 3D scene into this frame
/// (already resolution-scaled, rounded, and clamped) plus the scale actually
/// in effect. `shouldSkipFrame` is only ever true when FPS limiting is on AND
/// you have opted into library-driven pacing instead of using
/// GameOptimizerGetPreferredFrameRate() with your own CADisplayLink/MTKView —
/// most integrations can safely ignore it.
GAMEOPTIMIZER_API GameOptimizerRenderSize GameOptimizerBeginFrame(uint32_t drawableWidth, uint32_t drawableHeight);

/// Encodes a full-screen upscale blit from `sourceTexture` (your rendered
/// scene, sized per GameOptimizerBeginFrame) into `destinationTexture`
/// (typically the CAMetalDrawable's texture) using the currently-selected
/// upscale filter, on the given command buffer. All three pointers are
/// bridged Metal object references (id<MTLCommandBuffer>, id<MTLTexture>,
/// id<MTLTexture>); ownership stays with the caller. Never calls
/// waitUntilCompleted, never commits or presents the buffer for you.
GAMEOPTIMIZER_API GameOptimizerResult GameOptimizerEncodeUpscale(void *commandBuffer,
                                                                   void *sourceTexture,
                                                                   void *destinationTexture);

/// Reports this frame's measured timings back to the dynamic resolution
/// controller. Call once per frame, after you've submitted your command
/// buffer (GPU time is usually only known inside its completion handler —
/// see IntegrationExample.mm). Safe to call with gpuFrameTimeMS < 0 to mean
/// "unavailable"; the library will fall back to CPU timing and mark
/// usingCPUFallbackTiming in the metrics.
GAMEOPTIMIZER_API void GameOptimizerEndFrame(double cpuFrameTimeMS, double gpuFrameTimeMS);

/// If you drive your own CADisplayLink/MTKView instead of using the
/// shouldSkipFrame flag above, read this each time your target frame rate
/// might have changed (e.g. after a thermal state change) and assign it to
/// preferredFramesPerSecond / preferredFrameRateRange.
GAMEOPTIMIZER_API float GameOptimizerGetPreferredFrameRate(void);

#ifdef __cplusplus
}
#endif

#endif /* GAME_OPTIMIZER_H */
