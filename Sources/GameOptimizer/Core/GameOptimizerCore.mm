#include "GameOptimizerCore.hpp"
#include "../Public/GameOptimizer.h"
#include "../Utilities/GameOptimizerValidation.hpp"
#include "../Utilities/GameOptimizerLogger.hpp"
#import "../UI/GameOptimizerOverlayController.h"
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <cstring>
#include <cmath>
#include <algorithm>

using namespace GameOptimizer;

static NSString *const kGOConfigDefaultsKey = @"com.gameoptimizer.configuration.v1";

@interface GameOptimizerSaveDebounceBox : NSObject
@property (nonatomic, strong) NSTimer *timer;
@end
@implementation GameOptimizerSaveDebounceBox
@end

namespace GameOptimizer {

GameOptimizerCore &GameOptimizerCore::Shared() {
    static GameOptimizerCore *instance = new GameOptimizerCore();
    return *instance;
}

GameOptimizerCore::GameOptimizerCore() {}

static void GOSaveConfigurationNow(const GameOptimizerConfiguration &config) {
    NSData *data = [NSData dataWithBytes:&config length:sizeof(config)];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kGOConfigDefaultsKey];
}

static GameOptimizerConfiguration GOLoadPersistedOrDefault() {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kGOConfigDefaultsKey];
    if (data == nil || data.length != sizeof(GameOptimizerConfiguration)) {
        return MakeSafeConfiguration();
    }
    GameOptimizerConfiguration loaded{};
    memcpy(&loaded, data.bytes, sizeof(loaded));
    if (loaded.configVersion != GameOptimizerConfigurationCurrentVersion) {
        return MakeSafeConfiguration();
    }
    std::string detail;
    if (ValidateConfiguration(loaded, &detail) != GameOptimizerResultSuccess) {
        Logger::Shared().LogWarning("Persisted configuration failed validation, using Safe defaults: " + detail);
        return MakeSafeConfiguration();
    }
    return loaded;
}

void GameOptimizerCore::ScheduleConfigurationSave() {
    RunOnMainAsync([this]() {
        GameOptimizerSaveDebounceBox *box = (__bridge GameOptimizerSaveDebounceBox *)_saveDebounceBox;
        if (box == nil) {
            box = [[GameOptimizerSaveDebounceBox alloc] init];
            _saveDebounceBox = (__bridge_retained void *)box;
        }
        [box.timer invalidate];
        GameOptimizerConfiguration snapshot = _configStore.Snapshot();
        box.timer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                      repeats:NO
                                                        block:^(NSTimer * _Nonnull timer) {
            GOSaveConfigurationNow(snapshot);
        }];
    });
}

void GameOptimizerCore::PushConfigToSubsystems(const GameOptimizerConfiguration &config) {
    _metricsCollector.SetFPSPacingTarget(config.fpsLimitEnabled && config.masterEnabled ? config.targetFPS : 0);
}

void GameOptimizerCore::RecordError(GameOptimizerResult code, const std::string &detail) {
    _lastErrorCode.store((int)code);
    Logger::Shared().LogError(detail);
}

GameOptimizerResult GameOptimizerCore::Initialize() {
    if (_initialized.load()) return GameOptimizerResultAlreadyInitialized;

    GameOptimizerConfiguration loaded = GOLoadPersistedOrDefault();
    _configStore.Replace(loaded);
    _drc.ResetScale(loaded.manualRenderScaleEnabled ? loaded.manualRenderScale : loaded.maximumRenderScale,
                     ControllerBounds{loaded.minimumRenderScale, loaded.maximumRenderScale, loaded.scaleStep,
                                      loaded.decreaseDelaySeconds, loaded.increaseDelaySeconds,
                                      loaded.gpuFrameTimeMarginMS, loaded.scaleChangeCooldownSeconds});

    _metricsCollector.Start();
    PushConfigToSubsystems(loaded);

    _initialized.store(true);

    RunOnMainAsync([this]() {
        EnsureOverlayCreated();
    });

    return GameOptimizerResultSuccess;
}

void GameOptimizerCore::Shutdown() {
    if (!_initialized.load()) return;
    _initialized.store(false);

    RunOnMainAsync([this]() {
        if (_overlayController) {
            GameOptimizerOverlayController *overlay = (__bridge_transfer GameOptimizerOverlayController *)_overlayController;
            [overlay teardown];
            _overlayController = nullptr;
        }
        if (_saveDebounceBox) {
            GameOptimizerSaveDebounceBox *box = (__bridge_transfer GameOptimizerSaveDebounceBox *)_saveDebounceBox;
            [box.timer invalidate];
            _saveDebounceBox = nullptr;
        }
    });

    _metricsCollector.Stop();
    _renderer.ShutdownAndWaitForGPU();
    Logger::Shared().ClearEvents();
}

void GameOptimizerCore::EnsureOverlayCreated() {
    if (_overlayController != nullptr) return;
    GameOptimizerOverlayController *overlay = [[GameOptimizerOverlayController alloc] init];
    _overlayController = (__bridge_retained void *)overlay;
}

void GameOptimizerCore::ShowMenu() {
    if (!IsInitialized()) return;
    RunOnMainAsync([this]() {
        EnsureOverlayCreated();
        GameOptimizerOverlayController *overlay = (__bridge GameOptimizerOverlayController *)_overlayController;
        [overlay show];
    });
}

void GameOptimizerCore::HideMenu() {
    if (!IsInitialized()) return;
    RunOnMainAsync([this]() {
        if (!_overlayController) return;
        GameOptimizerOverlayController *overlay = (__bridge GameOptimizerOverlayController *)_overlayController;
        [overlay hide];
    });
}

void GameOptimizerCore::ToggleMenu() {
    if (!IsInitialized()) return;
    RunOnMainAsync([this]() {
        EnsureOverlayCreated();
        GameOptimizerOverlayController *overlay = (__bridge GameOptimizerOverlayController *)_overlayController;
        [overlay toggle];
    });
}

bool GameOptimizerCore::IsMenuVisible() const {
    if (_overlayController == nullptr) return false;
    GameOptimizerOverlayController *overlay = (__bridge GameOptimizerOverlayController *)_overlayController;
    return [overlay isVisible];
}

GameOptimizerResult GameOptimizerCore::SetMasterEnabled(bool enabled) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    _configStore.MutateInPlace([enabled](GameOptimizerConfiguration &c) { c.masterEnabled = enabled; });
    if (!enabled) {
        _drc.ResetScale(1.0f, ControllerBounds{});
    }
    PushConfigToSubsystems(_configStore.Snapshot());
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

static GameOptimizerResult GOApplyClampedFloat(ConfigurationStore &store, float rawValue, const GameOptimizerRange &range,
                                                int decimals, void (^apply)(GameOptimizerConfiguration &, float)) {
    RangeCheckResult check = CheckRange(rawValue, range, decimals);
    if (!check.inRange && !check.wasClamped) return GameOptimizerResultInvalidArgument;
    float finalValue = check.clampedValue;
    store.MutateInPlace([&](GameOptimizerConfiguration &c) { apply(c, finalValue); });
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::SetManualRenderScale(float scale) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    GameOptimizerResult r = GOApplyClampedFloat(_configStore, scale, GameOptimizerRangeManualRenderScale, 2,
                                                 ^(GameOptimizerConfiguration &c, float v) { c.manualRenderScale = v; });
    if (r == GameOptimizerResultSuccess) ScheduleConfigurationSave();
    return r;
}

GameOptimizerResult GameOptimizerCore::SetDynamicResolutionEnabled(bool enabled) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    _configStore.MutateInPlace([enabled](GameOptimizerConfiguration &c) { c.dynamicResolutionEnabled = enabled; });
    GameOptimizerConfiguration snap = _configStore.Snapshot();
    _drc.ResetScale(snap.maximumRenderScale,
                     ControllerBounds{snap.minimumRenderScale, snap.maximumRenderScale, snap.scaleStep,
                                      snap.decreaseDelaySeconds, snap.increaseDelaySeconds,
                                      snap.gpuFrameTimeMarginMS, snap.scaleChangeCooldownSeconds});
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::SetMinimumRenderScale(float scale) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    RangeCheckResult check = CheckRange(scale, GameOptimizerRangeMinimumRenderScale, 2);
    if (!check.inRange && !check.wasClamped) return GameOptimizerResultInvalidArgument;
    float finalValue = check.clampedValue;
    GameOptimizerResult outcome = GameOptimizerResultSuccess;
    _configStore.MutateInPlace([&](GameOptimizerConfiguration &c) {
        if (finalValue > c.maximumRenderScale) { outcome = GameOptimizerResultInvalidArgument; return; }
        c.minimumRenderScale = finalValue;
    });
    if (outcome == GameOptimizerResultSuccess) ScheduleConfigurationSave();
    return outcome;
}

GameOptimizerResult GameOptimizerCore::SetMaximumRenderScale(float scale) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    RangeCheckResult check = CheckRange(scale, GameOptimizerRangeMaximumRenderScale, 2);
    if (!check.inRange && !check.wasClamped) return GameOptimizerResultInvalidArgument;
    float finalValue = check.clampedValue;
    GameOptimizerResult outcome = GameOptimizerResultSuccess;
    _configStore.MutateInPlace([&](GameOptimizerConfiguration &c) {
        if (finalValue < c.minimumRenderScale) { outcome = GameOptimizerResultInvalidArgument; return; }
        c.maximumRenderScale = finalValue;
    });
    if (outcome == GameOptimizerResultSuccess) ScheduleConfigurationSave();
    return outcome;
}

GameOptimizerResult GameOptimizerCore::SetScaleStep(float step) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    if (IsFiniteValue(step) && step == 0.0f) return GameOptimizerResultInvalidArgument;
    GameOptimizerResult r = GOApplyClampedFloat(_configStore, step, GameOptimizerRangeScaleStep, 2,
                                                 ^(GameOptimizerConfiguration &c, float v) { c.scaleStep = v; });
    if (r == GameOptimizerResultSuccess) ScheduleConfigurationSave();
    return r;
}

GameOptimizerResult GameOptimizerCore::SetTargetFPS(int fps) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    if (fps < 1 || fps > 1000) return GameOptimizerResultInvalidArgument;

    int maxSupported = _metricsCollector.MaximumSupportedFrameRate();
    int clamped = std::min(fps, maxSupported);
    clamped = std::max(clamped, (int)GameOptimizerRangeTargetFPS.minimum);
    clamped = std::min(clamped, (int)GameOptimizerRangeTargetFPS.maximum);

    GameOptimizerResult result = (clamped != fps) ? GameOptimizerResultUnsupportedFPS : GameOptimizerResultSuccess;

    _configStore.MutateInPlace([clamped](GameOptimizerConfiguration &c) { c.targetFPS = clamped; });
    PushConfigToSubsystems(_configStore.Snapshot());
    ScheduleConfigurationSave();
    return result;
}

GameOptimizerResult GameOptimizerCore::SetFPSLimitEnabled(bool enabled) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    _configStore.MutateInPlace([enabled](GameOptimizerConfiguration &c) { c.fpsLimitEnabled = enabled; });
    PushConfigToSubsystems(_configStore.Snapshot());
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::SetCPUOptimizationEnabled(bool enabled) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    _configStore.MutateInPlace([enabled](GameOptimizerConfiguration &c) { c.cpuOptimizationEnabled = enabled; });
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::SetCPUOptimizationMode(GameOptimizerCPUMode mode) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    if (mode < GameOptimizerCPUModeOff || mode > GameOptimizerCPUModeStrong) return GameOptimizerResultInvalidArgument;
    _configStore.MutateInPlace([mode](GameOptimizerConfiguration &c) { c.cpuOptimizationMode = mode; });
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::SetThermalProtectionEnabled(bool enabled) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    _configStore.MutateInPlace([enabled](GameOptimizerConfiguration &c) { c.thermalProtectionEnabled = enabled; });
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::RestoreSafeDefaults() {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    GameOptimizerConfiguration safe = MakeSafeConfiguration();
    _configStore.Replace(safe);
    _drc.ResetScale(1.0f, ControllerBounds{safe.minimumRenderScale, safe.maximumRenderScale, safe.scaleStep,
                                            safe.decreaseDelaySeconds, safe.increaseDelaySeconds,
                                            safe.gpuFrameTimeMarginMS, safe.scaleChangeCooldownSeconds});
    _lastErrorCode.store(GameOptimizerResultSuccess);
    Logger::Shared().ClearEvents();
    PushConfigToSubsystems(safe);
    GOSaveConfigurationNow(safe);
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::ApplyValidatedConfigurationInternal(const GameOptimizerConfiguration &config) {
    std::string detail;
    GameOptimizerResult validation = ValidateConfiguration(config, &detail);
    if (validation != GameOptimizerResultSuccess) {
        RecordError(validation, "ApplyConfiguration rejected: " + detail);
        return validation;
    }
    _configStore.Replace(config);
    _drc.ResetScale(_drc.CurrentScale(),
                     ControllerBounds{config.minimumRenderScale, config.maximumRenderScale, config.scaleStep,
                                      config.decreaseDelaySeconds, config.increaseDelaySeconds,
                                      config.gpuFrameTimeMarginMS, config.scaleChangeCooldownSeconds});
    PushConfigToSubsystems(config);
    ScheduleConfigurationSave();
    return GameOptimizerResultSuccess;
}

GameOptimizerResult GameOptimizerCore::ApplyConfiguration(const GameOptimizerConfiguration &configuration) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    return ApplyValidatedConfigurationInternal(configuration);
}

GameOptimizerConfiguration GameOptimizerCore::ConfigurationForPreset(GameOptimizerPreset preset) {
    return MakePresetConfiguration(preset, _configStore.Snapshot());
}

GameOptimizerResult GameOptimizerCore::ApplyPreset(GameOptimizerPreset preset) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    GameOptimizerConfiguration target = MakePresetConfiguration(preset, _configStore.Snapshot());
    return ApplyValidatedConfigurationInternal(target);
}

size_t GameOptimizerCore::CopyLastError(char *buffer, size_t bufferSize) {
    std::string msg = Logger::Shared().LastErrorMessage();
    if (buffer == nullptr || bufferSize == 0) return msg.size();
    size_t toCopy = std::min(bufferSize - 1, msg.size());
    memcpy(buffer, msg.data(), toCopy);
    buffer[toCopy] = '\0';
    return toCopy;
}

const char *GameOptimizerCore::GetLastErrorPointer() {
    static thread_local std::string cached;
    cached = Logger::Shared().LastErrorMessage();
    return cached.c_str();
}

GameOptimizerResult GameOptimizerCore::AttachMetalDevice(void *mtlDevice, void *mtlCommandQueue) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;
    GameOptimizerResult r = _renderer.AttachDevice(mtlDevice, mtlCommandQueue);
    if (r != GameOptimizerResultSuccess) RecordError(r, "AttachMetalDevice failed");
    return r;
}

GameOptimizerRenderSize GameOptimizerCore::BeginFrame(uint32_t drawableWidth, uint32_t drawableHeight) {
    GameOptimizerRenderSize result{};
    result.width = drawableWidth;
    result.height = drawableHeight;
    result.appliedScale = 1.0f;
    result.shouldSkipFrame = false;

    if (!IsInitialized() || drawableWidth == 0 || drawableHeight == 0) return result;

    GameOptimizerConfiguration config = _configStore.Snapshot();

    ScopedLock guard(_frameLock);
    _lastDrawableWidth = drawableWidth;
    _lastDrawableHeight = drawableHeight;

    if (config.fpsLimitEnabled) {
        double now = CACurrentMediaTime();
        double minInterval = 1.0 / std::max(1, (int)config.targetFPS);
        if (_lastAcceptedFrameTime > 0 && (now - _lastAcceptedFrameTime) < minInterval * 0.95) {
            result.shouldSkipFrame = true;
        } else {
            _lastAcceptedFrameTime = now;
        }
    }

    float scaleToUse = 1.0f;
    bool needsOffscreen = false;
    if (config.masterEnabled) {
        if (config.dynamicResolutionEnabled) {
            scaleToUse = _drc.CurrentScale();
            needsOffscreen = true;
        } else if (config.manualRenderScaleEnabled && config.manualRenderScale < 0.999f) {
            scaleToUse = config.manualRenderScale;
            needsOffscreen = true;
        }
    }

    _pendingFrameUsesOffscreen = needsOffscreen;
    if (!needsOffscreen) {
        _lastAppliedScale = 1.0f;
        return result;
    }

    RenderTargetSet targets{};
    GameOptimizerResult acquireResult = _renderer.AcquireFrameRenderTargets(drawableWidth, drawableHeight, scaleToUse,
                                                                              true, &targets);
    if (acquireResult != GameOptimizerResultSuccess && acquireResult != GameOptimizerResultOperationDeferred) {
        RecordError(acquireResult, "AcquireFrameRenderTargets failed");
        _consecutiveRenderFailures++;
        if (_consecutiveRenderFailures >= kMaxConsecutiveFailuresBeforeAutoDisable) {
            DisableDynamicResolutionAfterRepeatedFailure();
        }
        _pendingFrameUsesOffscreen = false;
        _lastAppliedScale = 1.0f;
        return result;
    }

    _consecutiveRenderFailures = 0;
    _pendingFrameGeneration = targets.generation;
    _lastRenderTargets = targets;
    _lastAppliedScale = scaleToUse;

    result.width = targets.width;
    result.height = targets.height;
    result.appliedScale = scaleToUse;
    return result;
}

void GameOptimizerCore::DisableDynamicResolutionAfterRepeatedFailure() {
    _configStore.MutateInPlace([](GameOptimizerConfiguration &c) { c.dynamicResolutionEnabled = false; });
    Logger::Shared().LogError("Dynamic Resolution auto-disabled after repeated render target failures");
    ScheduleConfigurationSave();
}

GameOptimizerResult GameOptimizerCore::EncodeUpscale(void *commandBuffer, void *sourceTexture, void *destinationTexture) {
    if (!IsInitialized()) return GameOptimizerResultNotInitialized;

    GameOptimizerConfiguration config = _configStore.Snapshot();
    GameOptimizerResult r = _renderer.EncodeUpscale(commandBuffer, sourceTexture, destinationTexture, config.upscaleMode);
    if (r != GameOptimizerResultSuccess) {
        RecordError(r, "EncodeUpscale failed");
        _consecutiveRenderFailures++;
        if (_consecutiveRenderFailures >= kMaxConsecutiveFailuresBeforeAutoDisable) {
            DisableDynamicResolutionAfterRepeatedFailure();
        }
    }
    return r;
}

void GameOptimizerCore::EndFrame(double cpuFrameTimeMS, double gpuFrameTimeMS) {
    if (!IsInitialized()) return;

    double now = CACurrentMediaTime();
    _metricsCollector.RecordFrame(now);

    GameOptimizerConfiguration config = _configStore.Snapshot();
    FrameMetricsSnapshot metricsSnap = _metricsCollector.Snapshot();

    ScopedLock guard(_frameLock);

    double dt = (_lastUpdateTimestamp > 0.0) ? (now - _lastUpdateTimestamp) : 0.0;
    _lastUpdateTimestamp = now;

    if (_pendingFrameUsesOffscreen) {
        _renderer.RetireGeneration(_pendingFrameGeneration);
    }

    if (config.masterEnabled && config.dynamicResolutionEnabled) {
        FrameSample sample;
        sample.cpuFrameTimeMS = cpuFrameTimeMS;
        sample.gpuTimeValid = gpuFrameTimeMS >= 0.0;
        sample.gpuFrameTimeMS = sample.gpuTimeValid ? gpuFrameTimeMS : 0.0;
        sample.deltaTimeSeconds = dt;
        sample.targetFPS = config.fpsLimitEnabled ? (double)config.targetFPS : 60.0;
        sample.thermalState = metricsSnap.thermalState;
        sample.justForegrounded = _metricsCollector.ConsumeJustForegroundedFlag();
        sample.pipelineRebuilding = false;
        sample.drawableWidth = _lastDrawableWidth;
        sample.drawableHeight = _lastDrawableHeight;

        ControllerBounds bounds{config.minimumRenderScale, config.maximumRenderScale, config.scaleStep,
                                config.decreaseDelaySeconds, config.increaseDelaySeconds,
                                config.gpuFrameTimeMarginMS, config.scaleChangeCooldownSeconds};

        if (config.thermalProtectionEnabled) {
            if (metricsSnap.thermalState == ThermalLevel::Serious) {
                bounds.maximumScale = std::min(bounds.maximumScale, config.seriousMaxScale);
            } else if (metricsSnap.thermalState == ThermalLevel::Critical) {
                bounds.maximumScale = std::min(bounds.maximumScale, config.criticalMaxScale);
            }
        }

        _drc.Update(sample, bounds);
    } else {
        _metricsCollector.ConsumeJustForegroundedFlag();
    }
}

float GameOptimizerCore::GetPreferredFrameRate() {
    GameOptimizerConfiguration config = _configStore.Snapshot();
    FrameMetricsSnapshot metricsSnap = _metricsCollector.Snapshot();

    int fps = config.fpsLimitEnabled ? config.targetFPS : _metricsCollector.MaximumSupportedFrameRate();

    if (config.thermalProtectionEnabled) {
        if (metricsSnap.thermalState == ThermalLevel::Serious) fps = std::min(fps, config.seriousFPS);
        else if (metricsSnap.thermalState == ThermalLevel::Critical) fps = std::min(fps, config.criticalFPS);
    }
    return (float)std::max(1, fps);
}

GameOptimizerMetrics GameOptimizerCore::GetMetrics() {
    GameOptimizerMetrics m{};
    GameOptimizerConfiguration config = _configStore.Snapshot();
    FrameMetricsSnapshot metricsSnap = _metricsCollector.Snapshot();

    m.currentFPS = metricsSnap.currentFPS;
    m.averageFPS = metricsSnap.averageFPS;
    m.minimumFPSLast10Seconds = metricsSnap.minimumFPSLast10Seconds;
    m.droppedFrames = metricsSnap.droppedFrames;
    m.thermalState = (GameOptimizerThermalState)metricsSnap.thermalState;
    m.applicationState = metricsSnap.applicationState;

    {
        ScopedLock guard(_frameLock);
        m.currentRenderScale = _lastAppliedScale;
        m.renderWidth = _lastRenderTargets.width > 0 ? _lastRenderTargets.width : _lastDrawableWidth;
        m.renderHeight = _lastRenderTargets.height > 0 ? _lastRenderTargets.height : _lastDrawableHeight;
        m.drawableWidth = _lastDrawableWidth;
        m.drawableHeight = _lastDrawableHeight;
    }

    m.targetFPS = config.targetFPS;
    m.renderScaleChangeCount = _drc.ScaleChangeCount();
    m.memoryUsageBytes = _renderer.EstimatedMemoryUsageBytes();
    m.pipelineReady = _renderer.PipelinesReady();
    m.dynamicResolutionEnabled = config.dynamicResolutionEnabled;
    m.cpuOptimizationEnabled = config.cpuOptimizationEnabled;
    m.usingCPUFallbackTiming = !_renderer.IsDeviceAttached();
    m.lastErrorCode = (GameOptimizerResult)_lastErrorCode.load();
    m.secondsSinceLastError = Logger::Shared().SecondsSinceLastError(CACurrentMediaTime());

    return m;
}

} // namespace GameOptimizer

#pragma mark - Public C API trampolines

GameOptimizerResult GameOptimizerInitialize(void) { return GameOptimizerCore::Shared().Initialize(); }
void GameOptimizerShutdown(void) { GameOptimizerCore::Shared().Shutdown(); }
bool GameOptimizerIsInitialized(void) { return GameOptimizerCore::Shared().IsInitialized(); }

void GameOptimizerShowMenu(void) { GameOptimizerCore::Shared().ShowMenu(); }
void GameOptimizerHideMenu(void) { GameOptimizerCore::Shared().HideMenu(); }
void GameOptimizerToggleMenu(void) { GameOptimizerCore::Shared().ToggleMenu(); }
bool GameOptimizerIsMenuVisible(void) { return GameOptimizerCore::Shared().IsMenuVisible(); }

GameOptimizerResult GameOptimizerSetMasterEnabled(bool enabled) { return GameOptimizerCore::Shared().SetMasterEnabled(enabled); }
GameOptimizerResult GameOptimizerSetManualRenderScale(float scale) {
    if (!std::isfinite(scale)) return GameOptimizerResultInvalidArgument;
    return GameOptimizerCore::Shared().SetManualRenderScale(scale);
}
GameOptimizerResult GameOptimizerSetDynamicResolutionEnabled(bool enabled) { return GameOptimizerCore::Shared().SetDynamicResolutionEnabled(enabled); }
GameOptimizerResult GameOptimizerSetMinimumRenderScale(float scale) {
    if (!std::isfinite(scale)) return GameOptimizerResultInvalidArgument;
    return GameOptimizerCore::Shared().SetMinimumRenderScale(scale);
}
GameOptimizerResult GameOptimizerSetMaximumRenderScale(float scale) {
    if (!std::isfinite(scale)) return GameOptimizerResultInvalidArgument;
    return GameOptimizerCore::Shared().SetMaximumRenderScale(scale);
}
GameOptimizerResult GameOptimizerSetScaleStep(float step) {
    if (!std::isfinite(step)) return GameOptimizerResultInvalidArgument;
    return GameOptimizerCore::Shared().SetScaleStep(step);
}
GameOptimizerResult GameOptimizerSetTargetFPS(int fps) { return GameOptimizerCore::Shared().SetTargetFPS(fps); }
GameOptimizerResult GameOptimizerSetFPSLimitEnabled(bool enabled) { return GameOptimizerCore::Shared().SetFPSLimitEnabled(enabled); }
GameOptimizerResult GameOptimizerSetCPUOptimizationEnabled(bool enabled) { return GameOptimizerCore::Shared().SetCPUOptimizationEnabled(enabled); }
GameOptimizerResult GameOptimizerSetCPUOptimizationMode(GameOptimizerCPUMode mode) { return GameOptimizerCore::Shared().SetCPUOptimizationMode(mode); }
GameOptimizerResult GameOptimizerSetThermalProtectionEnabled(bool enabled) { return GameOptimizerCore::Shared().SetThermalProtectionEnabled(enabled); }
GameOptimizerResult GameOptimizerRestoreSafeDefaults(void) { return GameOptimizerCore::Shared().RestoreSafeDefaults(); }

GameOptimizerMetrics GameOptimizerGetMetrics(void) { return GameOptimizerCore::Shared().GetMetrics(); }
GameOptimizerConfiguration GameOptimizerGetConfiguration(void) { return GameOptimizerCore::Shared().GetConfiguration(); }
GameOptimizerResult GameOptimizerApplyConfiguration(const GameOptimizerConfiguration *configuration) {
    if (configuration == nullptr) return GameOptimizerResultInvalidArgument;
    return GameOptimizerCore::Shared().ApplyConfiguration(*configuration);
}
GameOptimizerResult GameOptimizerApplyPreset(GameOptimizerPreset preset) { return GameOptimizerCore::Shared().ApplyPreset(preset); }
GameOptimizerConfiguration GameOptimizerConfigurationForPreset(GameOptimizerPreset preset) { return GameOptimizerCore::Shared().ConfigurationForPreset(preset); }

const char *GameOptimizerGetLastError(void) { return GameOptimizerCore::Shared().GetLastErrorPointer(); }
size_t GameOptimizerCopyLastError(char *buffer, size_t bufferSize) { return GameOptimizerCore::Shared().CopyLastError(buffer, bufferSize); }

GameOptimizerResult GameOptimizerAttachMetalDevice(void *mtlDevice, void *mtlCommandQueue) {
    return GameOptimizerCore::Shared().AttachMetalDevice(mtlDevice, mtlCommandQueue);
}
GameOptimizerRenderSize GameOptimizerBeginFrame(uint32_t drawableWidth, uint32_t drawableHeight) {
    return GameOptimizerCore::Shared().BeginFrame(drawableWidth, drawableHeight);
}
GameOptimizerResult GameOptimizerEncodeUpscale(void *commandBuffer, void *sourceTexture, void *destinationTexture) {
    return GameOptimizerCore::Shared().EncodeUpscale(commandBuffer, sourceTexture, destinationTexture);
}
void GameOptimizerEndFrame(double cpuFrameTimeMS, double gpuFrameTimeMS) {
    GameOptimizerCore::Shared().EndFrame(cpuFrameTimeMS, gpuFrameTimeMS);
}
float GameOptimizerGetPreferredFrameRate(void) { return GameOptimizerCore::Shared().GetPreferredFrameRate(); }
