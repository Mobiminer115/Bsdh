#include "DynamicResolutionController.hpp"

#include <algorithm>
#include <cmath>

namespace GameOptimizer {

DynamicResolutionController::DynamicResolutionController() {}

void DynamicResolutionController::ResetSmoothing() {
    _emaInitialized = false;
    _emaFrameTimeMS = 0.0;
    _overBudgetAccumSeconds = 0.0;
    _underBudgetAccumSeconds = 0.0;
    _secondsSinceLastChange = 1e9;
}

void DynamicResolutionController::ResetScale(float scale, const ControllerBounds &bounds) {
    float lo = std::min(bounds.minimumScale, bounds.maximumScale);
    float hi = std::max(bounds.minimumScale, bounds.maximumScale);
    if (!std::isfinite(scale)) scale = hi;
    _currentScale = std::min(std::max(scale, lo), hi);
    _scaleChangeCount = 0;
    ResetSmoothing();
}

ControllerDecision DynamicResolutionController::Update(const FrameSample &sample, const ControllerBounds &bounds) {
    ControllerDecision decision;
    decision.currentScale = _currentScale;

    float minScale = std::min(bounds.minimumScale, bounds.maximumScale);
    float maxScale = std::max(bounds.minimumScale, bounds.maximumScale);

    // Bounds can change out from under us at any time via a live config
    // update; always re-clamp the current value into them first so we never
    // hand out a scale the renderer would have to clamp again downstream.
    if (_currentScale < minScale || _currentScale > maxScale) {
        _currentScale = std::min(std::max(_currentScale, minScale), maxScale);
        decision.currentScale = _currentScale;
        decision.changedThisUpdate = true;
        decision.reason = ScaleChangeReason::ClampedToBounds;
        _scaleChangeCount++;
        _secondsSinceLastChange = 0.0;
    }

    double dt = sample.deltaTimeSeconds;
    if (!std::isfinite(dt) || dt < 0.0) dt = 0.0;
    if (dt > 0.5) dt = 0.5; // clamp pathological stalls/debugger pauses
    _secondsSinceLastChange += dt;

    if (sample.drawableWidth == 0 || sample.drawableHeight == 0) {
        decision.reason = ScaleChangeReason::HeldForInvalidDrawable;
        decision.currentScale = _currentScale;
        return decision;
    }
    if (sample.pipelineRebuilding) {
        decision.reason = ScaleChangeReason::HeldForPipelineRebuild;
        decision.currentScale = _currentScale;
        return decision;
    }
    if (sample.justForegrounded) {
        // Deliberately do NOT fold this sample into the EMA at all — the
        // first frame back from background is routinely a huge outlier.
        decision.reason = ScaleChangeReason::HeldForForeground;
        decision.currentScale = _currentScale;
        return decision;
    }

    double rawEffectiveMS = sample.gpuTimeValid ? sample.gpuFrameTimeMS : sample.cpuFrameTimeMS;
    if (!std::isfinite(rawEffectiveMS) || rawEffectiveMS < 0.0) rawEffectiveMS = 0.0;
    decision.usingFallbackTiming = !sample.gpuTimeValid;

    double emaInput = rawEffectiveMS;
    if (_emaInitialized && _emaFrameTimeMS > 0.0) {
        double spikeCap = _emaFrameTimeMS * kSpikeClampMultiplier;
        if (emaInput > spikeCap) emaInput = spikeCap; // one huge stall can't dominate the average
    }
    if (!_emaInitialized) {
        _emaFrameTimeMS = emaInput;
        _emaInitialized = true;
    } else {
        _emaFrameTimeMS = _emaFrameTimeMS * (1.0 - kEMAAlpha) + emaInput * kEMAAlpha;
    }
    decision.smoothedFrameTimeMS = _emaFrameTimeMS;

    decision.isCPUBound = sample.gpuTimeValid && sample.cpuFrameTimeMS > sample.gpuFrameTimeMS * kCPUBoundRatio;

    double targetFPS = sample.targetFPS;
    if (!std::isfinite(targetFPS) || targetFPS < 1.0) targetFPS = 1.0;
    double frameBudgetMS = 1000.0 / targetFPS;

    double upperBand = frameBudgetMS + bounds.gpuFrameTimeMarginMS;
    double lowerBand = std::max(0.0, frameBudgetMS - bounds.gpuFrameTimeMarginMS);

    if (_emaFrameTimeMS > upperBand) {
        _overBudgetAccumSeconds += dt;
        _underBudgetAccumSeconds = 0.0;
    } else if (_emaFrameTimeMS < lowerBand) {
        _underBudgetAccumSeconds += dt;
        _overBudgetAccumSeconds = 0.0;
    } else {
        // Inside the hysteresis dead-zone: decay rather than hard-reset so a
        // brief dip through the band doesn't erase sustained pressure that
        // was about to cross the decrease/increase threshold.
        _overBudgetAccumSeconds = std::max(0.0, _overBudgetAccumSeconds - dt);
        _underBudgetAccumSeconds = std::max(0.0, _underBudgetAccumSeconds - dt);
    }

    bool cooldownElapsed = _secondsSinceLastChange >= bounds.cooldownSeconds;
    if (!cooldownElapsed) {
        decision.reason = ScaleChangeReason::HeldForCooldown;
        decision.currentScale = _currentScale;
        return decision;
    }

    if (_overBudgetAccumSeconds >= bounds.decreaseDelaySeconds && _currentScale > minScale) {
        float newScale = std::max(minScale, _currentScale - bounds.step);
        if (newScale != _currentScale) {
            _currentScale = newScale;
            decision.currentScale = _currentScale;
            decision.changedThisUpdate = true;
            decision.reason = ScaleChangeReason::DecreasedOverBudget;
            _scaleChangeCount++;
            _secondsSinceLastChange = 0.0;
            _overBudgetAccumSeconds = 0.0;
            return decision;
        }
    }

    bool thermalAllowsIncrease = (sample.thermalState == ThermalLevel::Nominal ||
                                   sample.thermalState == ThermalLevel::Fair);
    if (!thermalAllowsIncrease) {
        decision.reason = ScaleChangeReason::HeldForThermal;
        decision.currentScale = _currentScale;
        return decision;
    }

    if (_underBudgetAccumSeconds >= bounds.increaseDelaySeconds && _currentScale < maxScale) {
        float newScale = std::min(maxScale, _currentScale + bounds.step);
        if (newScale != _currentScale) {
            _currentScale = newScale;
            decision.currentScale = _currentScale;
            decision.changedThisUpdate = true;
            decision.reason = ScaleChangeReason::IncreasedUnderBudget;
            _scaleChangeCount++;
            _secondsSinceLastChange = 0.0;
            _underBudgetAccumSeconds = 0.0;
            return decision;
        }
    }

    decision.currentScale = _currentScale;
    return decision;
}

} // namespace GameOptimizer
