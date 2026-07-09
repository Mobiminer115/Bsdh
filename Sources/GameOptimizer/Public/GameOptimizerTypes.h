//
//  GameOptimizerTypes.h
//  GameOptimizer
//
//  Public, pure-C type definitions for the GameOptimizer library.
//  This header intentionally avoids any Objective-C or C++ types so it can be
//  imported from plain C, Objective-C, Objective-C++, C++ or bridged into Swift
//  without requiring the Objective-C runtime.
//
//  Do not edit generated bridging; this file is hand-written and is the single
//  source of truth for every struct/enum shared between Core, Metal, UI and the
//  public API.
//

#ifndef GAME_OPTIMIZER_TYPES_H
#define GAME_OPTIMIZER_TYPES_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Current on-disk configuration schema version. Bump this whenever
/// GameOptimizerConfiguration's binary/serialized layout changes in a way that
/// requires migration or invalidation of previously saved user defaults.
static const uint32_t GameOptimizerConfigurationCurrentVersion = 1;

#pragma mark - Result codes

/// Every public API call returns one of these instead of throwing, aborting or
/// crashing. Callers should treat any non-Success value as "the requested
/// change was not applied; existing safe state is unchanged."
typedef enum GameOptimizerResult {
    GameOptimizerResultSuccess = 0,
    GameOptimizerResultAlreadyInitialized = 1,
    GameOptimizerResultNotInitialized = 2,
    GameOptimizerResultInvalidArgument = 3,
    GameOptimizerResultInvalidState = 4,
    GameOptimizerResultMetalUnavailable = 5,
    GameOptimizerResultPipelineCreationFailed = 6,
    GameOptimizerResultTextureCreationFailed = 7,
    GameOptimizerResultUnsupportedFPS = 8,
    GameOptimizerResultOperationDeferred = 9,
    GameOptimizerResultInternalError = 10,
} GameOptimizerResult;

#pragma mark - CPU optimization mode

typedef enum GameOptimizerCPUMode {
    GameOptimizerCPUModeOff = 0,
    GameOptimizerCPUModeLight = 1,      // "Nhẹ"
    GameOptimizerCPUModeBalanced = 2,   // "Cân bằng"
    GameOptimizerCPUModeStrong = 3,     // "Mạnh"
} GameOptimizerCPUMode;

#pragma mark - Upscale mode

typedef enum GameOptimizerUpscaleMode {
    GameOptimizerUpscaleModeNearest = 0,
    GameOptimizerUpscaleModeBilinear = 1,     // default
    GameOptimizerUpscaleModeBicubicLite = 2,
} GameOptimizerUpscaleMode;

#pragma mark - Thermal state

/// Deliberately mirrors Foundation's ProcessInfo.ThermalState (Nominal / Fair /
/// Serious / Critical) 1:1 so mapping in FrameMetricsCollector is a straight
/// cast, not a lookup table that can drift out of sync.
typedef enum GameOptimizerThermalState {
    GameOptimizerThermalStateNominal = 0,
    GameOptimizerThermalStateFair = 1,
    GameOptimizerThermalStateSerious = 2,
    GameOptimizerThermalStateCritical = 3,
} GameOptimizerThermalState;

#pragma mark - Application lifecycle state

typedef enum GameOptimizerApplicationState {
    GameOptimizerApplicationStateActive = 0,
    GameOptimizerApplicationStateInactive = 1,
    GameOptimizerApplicationStateBackground = 2,
} GameOptimizerApplicationState;

#pragma mark - Valid ranges (shared by validation layer AND the UI, so the two can never disagree)

typedef struct GameOptimizerRange {
    float minimum;
    float maximum;
    float defaultValue;
} GameOptimizerRange;

/* Render scale */
static const GameOptimizerRange GameOptimizerRangeManualRenderScale        = { 0.50f, 1.00f, 0.80f };
static const GameOptimizerRange GameOptimizerRangeMinimumRenderScale       = { 0.50f, 1.00f, 0.65f };
static const GameOptimizerRange GameOptimizerRangeMaximumRenderScale       = { 0.50f, 1.00f, 1.00f };
static const GameOptimizerRange GameOptimizerRangeScaleStep                = { 0.01f, 0.10f, 0.05f };
static const GameOptimizerRange GameOptimizerRangeDecreaseDelaySeconds     = { 0.25f, 10.0f, 2.00f };
static const GameOptimizerRange GameOptimizerRangeIncreaseDelaySeconds     = { 0.50f, 20.0f, 5.00f };
static const GameOptimizerRange GameOptimizerRangeGPUFrameTimeMarginMS     = { 0.10f, 10.0f, 1.50f };
static const GameOptimizerRange GameOptimizerRangeScaleChangeCooldownSec   = { 0.25f, 10.0f, 1.00f };

/* FPS */
static const GameOptimizerRange GameOptimizerRangeTargetFPS                = { 15.0f, 120.0f, 60.0f };
static const GameOptimizerRange GameOptimizerRangeSeriousFPS               = { 15.0f, 120.0f, 45.0f };
static const GameOptimizerRange GameOptimizerRangeCriticalFPS              = { 15.0f, 120.0f, 30.0f };

/* Thermal max-scale ceilings */
static const GameOptimizerRange GameOptimizerRangeSeriousMaxScale          = { 0.50f, 1.00f, 0.75f };
static const GameOptimizerRange GameOptimizerRangeCriticalMaxScale         = { 0.50f, 1.00f, 0.60f };

/* CPU optimization */
static const GameOptimizerRange GameOptimizerRangeUIMetricsUpdateRateHz    = { 0.50f, 10.0f, 2.00f };
static const GameOptimizerRange GameOptimizerRangeBackgroundTaskIntervalS  = { 0.10f, 60.0f, 1.00f };
/* Maximum worker count is integer, 0 == "auto"; upper bound is resolved at
   runtime from the device's active processor count, see GameOptimizerValidation. */
static const int32_t GameOptimizerMaximumWorkerCountAuto = 0;

#pragma mark - Configuration

/// A fully self-contained, POD, trivially-copyable snapshot of every tunable
/// parameter in the library. Copies of this struct are what cross thread
/// boundaries — never a pointer into live, mutable state.
typedef struct GameOptimizerConfiguration {
    uint32_t configVersion;

    bool masterEnabled;

    bool  manualRenderScaleEnabled;
    float manualRenderScale;

    bool  dynamicResolutionEnabled;
    float minimumRenderScale;
    float maximumRenderScale;
    float scaleStep;
    float decreaseDelaySeconds;
    float increaseDelaySeconds;
    float gpuFrameTimeMarginMS;
    float scaleChangeCooldownSeconds;

    bool    fpsLimitEnabled;
    int32_t targetFPS;

    bool                  cpuOptimizationEnabled;
    GameOptimizerCPUMode  cpuOptimizationMode;
    float                 uiMetricsUpdateRateHz;
    float                 backgroundTaskIntervalSeconds;
    int32_t               maximumWorkerCount; /* 0 = auto */

    bool    thermalProtectionEnabled;
    int32_t seriousFPS;
    float   seriousMaxScale;
    int32_t criticalFPS;
    float   criticalMaxScale;

    GameOptimizerUpscaleMode upscaleMode;

    /* UI-only, not render-critical, but part of the persisted+applied config */
    bool floatingButtonHidden;
    bool restoreGestureEnabled;
} GameOptimizerConfiguration;

#pragma mark - Metrics (read-only snapshot, written by the render/metrics thread, read by anyone)

typedef struct GameOptimizerMetrics {
    double currentFPS;
    double averageFPS;
    double minimumFPSLast10Seconds;

    double cpuFrameTimeMS;
    double gpuFrameTimeMS;
    double totalFrameTimeMS;

    float    currentRenderScale;
    uint32_t renderWidth;
    uint32_t renderHeight;
    uint32_t drawableWidth;
    uint32_t drawableHeight;

    int32_t  targetFPS;
    uint64_t droppedFrames;
    uint64_t renderScaleChangeCount;

    GameOptimizerThermalState thermalState;
    uint64_t                  memoryUsageBytes;

    bool pipelineReady;
    bool dynamicResolutionEnabled;
    bool cpuOptimizationEnabled;
    bool usingCPUFallbackTiming; /* true when GPU timing was unavailable this frame */

    GameOptimizerApplicationState applicationState;
    GameOptimizerResult           lastErrorCode;
    double                        secondsSinceLastError;
} GameOptimizerMetrics;

#pragma mark - Render size hint (Metal integration helper, see GameOptimizerBeginFrame)

typedef struct GameOptimizerRenderSize {
    uint32_t width;
    uint32_t height;
    float    appliedScale;
    bool     shouldSkipFrame; /* true only for the app's own optional FPS-cap cooperation */
} GameOptimizerRenderSize;

#pragma mark - Presets

typedef enum GameOptimizerPreset {
    GameOptimizerPresetSafe = 0,
    GameOptimizerPresetQuality = 1,
    GameOptimizerPresetBalanced = 2,
    GameOptimizerPresetSmooth = 3,
    GameOptimizerPresetThermalSafe = 4,
    GameOptimizerPresetCustom = 5,
} GameOptimizerPreset;

#ifdef __cplusplus
}
#endif

#endif /* GAME_OPTIMIZER_TYPES_H */
