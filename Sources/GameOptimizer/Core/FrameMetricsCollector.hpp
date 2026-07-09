//
//  FrameMetricsCollector.hpp
//  GameOptimizer
//
//  Owns the library's one and only CADisplayLink (used solely to realize the
//  FPS-limit feature via preferredFramesPerSecond / preferredFrameRateRange),
//  tracks rolling FPS statistics from actual reported frame timings, and
//  mirrors ProcessInfo's thermal state + the app's foreground/background
//  state. A plain C++ class; the CADisplayLink/thermal-notification plumbing
//  is a private implementation detail hidden inside the .mm file behind a
//  tiny Objective-C proxy object so this header stays easy to reason about.
//

#ifndef GAME_OPTIMIZER_FRAME_METRICS_COLLECTOR_HPP
#define GAME_OPTIMIZER_FRAME_METRICS_COLLECTOR_HPP

#include "../Public/GameOptimizerTypes.h"
#include "../Utilities/GameOptimizerThreading.hpp"
#include "DynamicResolutionController.hpp" // for ThermalLevel
#include <deque>
#include <cstdint>

namespace GameOptimizer {

struct FrameMetricsSnapshot {
    double currentFPS = 0.0;
    double averageFPS = 0.0;
    double minimumFPSLast10Seconds = 0.0;
    uint64_t droppedFrames = 0;
    ThermalLevel thermalState = ThermalLevel::Nominal;
    GameOptimizerApplicationState applicationState = GameOptimizerApplicationStateActive;
};

class FrameMetricsCollector {
public:
    FrameMetricsCollector();
    ~FrameMetricsCollector();

    FrameMetricsCollector(const FrameMetricsCollector &) = delete;
    FrameMetricsCollector &operator=(const FrameMetricsCollector &) = delete;

    /// Registers UIApplication/ProcessInfo notification observers. Safe to
    /// call once; a second call is a no-op. Must be called from the main
    /// thread (mirrors GameOptimizerInitialize's threading contract).
    void Start();

    /// Invalidates the display link and unregisters every observer. Safe to
    /// call multiple times, including without a matching Start(). Must be
    /// called from the main thread.
    void Stop();

    /// Call once per reported app frame (from GameOptimizerEndFrame), with a
    /// monotonic timestamp such as CACurrentMediaTime(). Thread-safe.
    void RecordFrame(double wallClockNowSeconds);

    /// When FPS limiting is enabled, call to start/refresh the pacing display
    /// link at the given target. Passing fps <= 0 stops pacing. Safe from any
    /// thread (hops to main internally).
    void SetFPSPacingTarget(int fps);

    /// Thread-safe read of everything this collector currently knows.
    FrameMetricsSnapshot Snapshot();

    /// One-shot flag consumed exactly once by the frame-decision path
    /// (GameOptimizerEndFrame), never by general UI polling — reading it via
    /// Snapshot() above would otherwise risk a UI refresh silently eating the
    /// signal before the render thread sees it. Returns true at most once
    /// per resume-from-background.
    bool ConsumeJustForegroundedFlag();

    /// The maximum refresh rate this device's main screen supports, used to
    /// clamp a user-requested target FPS. Falls back to 60 if it cannot be
    /// determined. Safe from any thread.
    int MaximumSupportedFrameRate() const;

private:
    void *_displayLinkProxy = nullptr; // bridged GameOptimizerDisplayLinkProxy*, owns the CADisplayLink
    bool  _started = false;

    mutable UnfairLock _lock;
    std::deque<std::pair<double, double>> _recentFrames; // (timestamp, instantFPS), trailing ~10s
    double _lastFrameTimestamp = -1.0;
    double _averageFPS_EMA = 0.0;
    bool   _averageFPSInitialized = false;
    uint64_t _droppedFrames = 0;

    ThermalLevel _thermalState = ThermalLevel::Nominal;
    GameOptimizerApplicationState _applicationState = GameOptimizerApplicationStateActive;
    bool _pendingJustForegrounded = false;

    void PruneOldSamples(double nowSeconds);

    // Called from the Objective-C proxy; kept public-to-the-translation-unit
    // via friendship would be overkill, so these are invoked through a small
    // internal function-pointer trampoline set up in the .mm instead.
public:
    void HandleThermalStateChanged(int processInfoThermalStateRawValue);
    void HandleDidEnterBackground();
    void HandleWillEnterForeground();
    void HandleDidBecomeActive();
    void HandleWillResignActive();
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_FRAME_METRICS_COLLECTOR_HPP */
