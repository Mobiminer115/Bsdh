#ifndef GAME_OPTIMIZER_CORE_HPP
#define GAME_OPTIMIZER_CORE_HPP

#include "../Public/GameOptimizerTypes.h"
#include "../Utilities/GameOptimizerThreading.hpp"
#include "GameOptimizerConfiguration.hpp"
#include "DynamicResolutionController.hpp"
#include "FrameMetricsCollector.hpp"
#include "../Metal/GameOptimizerMetalRenderer.hpp"
#include <atomic>
#include <string>

namespace GameOptimizer {

class GameOptimizerCore {
public:
    static GameOptimizerCore &Shared();

    GameOptimizerResult Initialize();
    void Shutdown();
    bool IsInitialized() const { return _initialized.load(); }

    void ShowMenu();
    void HideMenu();
    void ToggleMenu();
    bool IsMenuVisible() const;

    GameOptimizerResult SetMasterEnabled(bool enabled);
    GameOptimizerResult SetManualRenderScale(float scale);
    GameOptimizerResult SetDynamicResolutionEnabled(bool enabled);
    GameOptimizerResult SetMinimumRenderScale(float scale);
    GameOptimizerResult SetMaximumRenderScale(float scale);
    GameOptimizerResult SetScaleStep(float step);
    GameOptimizerResult SetTargetFPS(int fps);
    GameOptimizerResult SetFPSLimitEnabled(bool enabled);
    GameOptimizerResult SetCPUOptimizationEnabled(bool enabled);
    GameOptimizerResult SetCPUOptimizationMode(GameOptimizerCPUMode mode);
    GameOptimizerResult SetThermalProtectionEnabled(bool enabled);
    GameOptimizerResult RestoreSafeDefaults();

    GameOptimizerMetrics GetMetrics();
    GameOptimizerConfiguration GetConfiguration() { return _configStore.Snapshot(); }
    GameOptimizerResult ApplyConfiguration(const GameOptimizerConfiguration &configuration);
    GameOptimizerResult ApplyPreset(GameOptimizerPreset preset);
    GameOptimizerConfiguration ConfigurationForPreset(GameOptimizerPreset preset);

    size_t CopyLastError(char *buffer, size_t bufferSize);
    const char *GetLastErrorPointer();

    GameOptimizerResult AttachMetalDevice(void *mtlDevice, void *mtlCommandQueue);
    GameOptimizerRenderSize BeginFrame(uint32_t drawableWidth, uint32_t drawableHeight);
    GameOptimizerResult EncodeUpscale(void *commandBuffer, void *sourceTexture, void *destinationTexture);
    void EndFrame(double cpuFrameTimeMS, double gpuFrameTimeMS);
    float GetPreferredFrameRate();

    ConfigurationStore &Configuration() { return _configStore; }
    FrameMetricsCollector &MetricsCollector() { return _metricsCollector; }

private:
    GameOptimizerCore();
    GameOptimizerCore(const GameOptimizerCore &) = delete;
    GameOptimizerCore &operator=(const GameOptimizerCore &) = delete;

    void RecordError(GameOptimizerResult code, const std::string &detail);
    GameOptimizerResult ApplyValidatedConfigurationInternal(const GameOptimizerConfiguration &config);
    void PushConfigToSubsystems(const GameOptimizerConfiguration &config);
    void DisableDynamicResolutionAfterRepeatedFailure();
    void ScheduleConfigurationSave();
    void EnsureOverlayCreated();

    static constexpr int kMaxConsecutiveFailuresBeforeAutoDisable = 5;

    std::atomic<bool> _initialized{false};
    std::atomic<int> _lastErrorCode{GameOptimizerResultSuccess};

    ConfigurationStore _configStore;
    DynamicResolutionController _drc;
    FrameMetricsCollector _metricsCollector;
    GameOptimizerMetalRenderer _renderer;

    mutable UnfairLock _frameLock;
    double _lastUpdateTimestamp = -1.0;
    uint32_t _lastDrawableWidth = 0;
    uint32_t _lastDrawableHeight = 0;
    uint64_t _pendingFrameGeneration = 0;
    bool _pendingFrameUsesOffscreen = false;
    int _consecutiveRenderFailures = 0;
    double _lastAcceptedFrameTime = -1.0;
    RenderTargetSet _lastRenderTargets;
    float _lastAppliedScale = 1.0f;

    void *_overlayController = nullptr;
    void *_saveDebounceBox = nullptr;
};

} // namespace GameOptimizer

#endif
