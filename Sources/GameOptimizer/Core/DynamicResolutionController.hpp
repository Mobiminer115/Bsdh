//
//  DynamicResolutionController.hpp
//  GameOptimizer
//
//  Pure C++, zero Apple-framework dependency, zero Metal/UIKit types — this
//  is deliberate so the core decision logic (when to raise/lower render
//  scale) is trivially unit-testable on its own and cannot accidentally touch
//  a GPU object from the wrong thread. GameOptimizerMetalRenderer.mm is the
//  only thing that turns its output into an actual texture resize.
//

#ifndef GAME_OPTIMIZER_DYNAMIC_RESOLUTION_CONTROLLER_HPP
#define GAME_OPTIMIZER_DYNAMIC_RESOLUTION_CONTROLLER_HPP

#include <cstdint>

namespace GameOptimizer {

enum class ThermalLevel : int { Nominal = 0, Fair = 1, Serious = 2, Critical = 3 };

/// Everything the controller needs to make one decision, gathered by the
/// caller (GameOptimizerCore) into one struct so Update() has no hidden
/// inputs and is easy to reason about / unit test.
struct FrameSample {
    double cpuFrameTimeMS = 0.0;
    double gpuFrameTimeMS = 0.0;
    bool   gpuTimeValid = false;
    double deltaTimeSeconds = 0.0;     // wall-clock time since the previous Update() call
    double targetFPS = 60.0;
    ThermalLevel thermalState = ThermalLevel::Nominal;
    bool   justForegrounded = false;    // true only for the first frame after entering foreground
    bool   pipelineRebuilding = false;  // true while the renderer is mid-resize
    uint32_t drawableWidth = 0;
    uint32_t drawableHeight = 0;
};

/// Tunable bounds, taken directly from a validated GameOptimizerConfiguration
/// snapshot (already clamped/ordered by the time it reaches here).
struct ControllerBounds {
    float minimumScale = 0.65f;
    float maximumScale = 1.00f;
    float step = 0.05f;
    float decreaseDelaySeconds = 2.0f;
    float increaseDelaySeconds = 5.0f;
    float gpuFrameTimeMarginMS = 1.5f;
    float cooldownSeconds = 1.0f;
};

enum class ScaleChangeReason : int {
    None = 0,
    DecreasedOverBudget = 1,
    IncreasedUnderBudget = 2,
    ClampedToBounds = 3,
    HeldForCooldown = 4,
    HeldForThermal = 5,
    HeldForForeground = 6,
    HeldForPipelineRebuild = 7,
    HeldForInvalidDrawable = 8,
    HeldCPUBound = 9,
};

struct ControllerDecision {
    float currentScale = 1.0f;
    bool  changedThisUpdate = false;
    ScaleChangeReason reason = ScaleChangeReason::None;
    bool  isCPUBound = false;
    bool  usingFallbackTiming = false;
    double smoothedFrameTimeMS = 0.0;
};

class DynamicResolutionController {
public:
    DynamicResolutionController();

    /// Resets internal smoothing/hysteresis state (but not the current scale)
    /// — call when returning from background or after a long stall so old
    /// EMA history doesn't influence the first few post-resume decisions.
    void ResetSmoothing();

    /// Fully resets, including current scale, back to `scale` (clamped into
    /// [bounds.minimumScale, bounds.maximumScale]). Used on
    /// GameOptimizerRestoreSafeDefaults and on first enable.
    void ResetScale(float scale, const ControllerBounds &bounds);

    /// Advances the controller by one frame/sample and returns the decision.
    /// Never allocates, never touches a lock, never calls into Metal/UIKit —
    /// pure arithmetic, safe to call every frame from the render thread.
    ControllerDecision Update(const FrameSample &sample, const ControllerBounds &bounds);

    float CurrentScale() const { return _currentScale; }
    uint64_t ScaleChangeCount() const { return _scaleChangeCount; }

private:
    float _currentScale = 1.0f;
    double _emaFrameTimeMS = 0.0;
    bool   _emaInitialized = false;

    double _overBudgetAccumSeconds = 0.0;
    double _underBudgetAccumSeconds = 0.0;
    double _secondsSinceLastChange = 1e9; // large so the very first change isn't blocked by cooldown

    uint64_t _scaleChangeCount = 0;

    static constexpr double kEMAAlpha = 0.15;
    static constexpr double kSpikeClampMultiplier = 3.0; // a single huge stall can move the EMA at most this much
    static constexpr double kCPUBoundRatio = 1.3;        // cpu > gpu * ratio => treat as CPU-bound this frame
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_DYNAMIC_RESOLUTION_CONTROLLER_HPP */
