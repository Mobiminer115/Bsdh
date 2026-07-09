#include "GameOptimizerValidation.hpp"

#include <cstdlib>
#include <cmath>
#include <cctype>
#include <algorithm>

namespace GameOptimizer {

namespace {

std::string Trim(const std::string &s) {
    size_t start = 0;
    size_t end = s.size();
    while (start < end && std::isspace(static_cast<unsigned char>(s[start]))) start++;
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) end--;
    return s.substr(start, end - start);
}

/// Normalizes a decimal-separator comma to a dot. Returns false (leaving
/// `out` untouched) if the string mixes '.' and ',' or contains more than one
/// separator of either kind, which we treat as ambiguous/invalid input rather
/// than guessing.
bool NormalizeSeparator(const std::string &trimmed, std::string *out) {
    size_t dotCount = std::count(trimmed.begin(), trimmed.end(), '.');
    size_t commaCount = std::count(trimmed.begin(), trimmed.end(), ',');

    if (dotCount > 1 || commaCount > 1) return false;
    if (dotCount > 0 && commaCount > 0) return false;

    if (commaCount == 1) {
        std::string replaced = trimmed;
        std::replace(replaced.begin(), replaced.end(), ',', '.');
        *out = replaced;
    } else {
        *out = trimmed;
    }
    return true;
}

ParseResult ParseStrict(const std::string &text) {
    ParseResult result;

    std::string trimmed = Trim(text);
    if (trimmed.empty()) {
        result.ok = false;
        result.errorMessage = "Giá trị đang trống.";
        return result;
    }

    std::string normalized;
    if (!NormalizeSeparator(trimmed, &normalized)) {
        result.ok = false;
        result.errorMessage = "Định dạng số không hợp lệ (chỉ dùng một dấu chấm hoặc dấu phẩy).";
        return result;
    }

    // Reject anything that isn't [+-]?digits(.digits)? up front. strtod is
    // technically permissive enough to accept hex floats ("0x1p3"), "nan" and
    // "inf" textual forms — we don't want any of those from a user-facing
    // numeric field even though the isfinite() check below would also catch
    // nan/inf. A whitelist scan is cheap and makes the intent explicit.
    for (char c : normalized) {
        bool isDigit = std::isdigit(static_cast<unsigned char>(c)) != 0;
        bool isDot = (c == '.');
        bool isSign = (c == '+' || c == '-');
        if (!isDigit && !isDot && !isSign) {
            result.ok = false;
            result.errorMessage = "Giá trị chứa ký tự không hợp lệ.";
            return result;
        }
    }

    const char *cstr = normalized.c_str();
    char *endPtr = nullptr;
    errno = 0;
    double parsed = std::strtod(cstr, &endPtr);

    bool consumedSomething = (endPtr != cstr);
    bool consumedEverything = (endPtr != nullptr && *endPtr == '\0');

    if (!consumedSomething || !consumedEverything) {
        result.ok = false;
        result.errorMessage = "Không thể đọc được số từ giá trị đã nhập.";
        return result;
    }

    if (!IsFiniteValue(parsed)) {
        result.ok = false;
        result.errorMessage = "Giá trị không hợp lệ (NaN hoặc vô cực).";
        return result;
    }

    result.ok = true;
    result.value = parsed;
    return result;
}

} // namespace

bool IsFiniteValue(double value) {
    return std::isfinite(value);
}

ParseResult ParseDecimal(const std::string &text) {
    return ParseStrict(text);
}

ParseResult ParseInteger(const std::string &text) {
    ParseResult result = ParseStrict(text);
    if (!result.ok) return result;

    double truncated = std::trunc(result.value);
    if (std::abs(result.value - truncated) > 1e-9) {
        ParseResult failure;
        failure.ok = false;
        failure.errorMessage = "Giá trị phải là số nguyên.";
        return failure;
    }
    result.value = truncated;
    return result;
}

float RoundToDecimalPlaces(float value, int decimalPlaces) {
    if (decimalPlaces < 0) decimalPlaces = 0;
    if (decimalPlaces > 6) decimalPlaces = 6;
    double factor = std::pow(10.0, decimalPlaces);
    return static_cast<float>(std::round(static_cast<double>(value) * factor) / factor);
}

bool IsOrderedPairValid(float minimumValue, float maximumValue) {
    return IsFiniteValue(minimumValue) && IsFiniteValue(maximumValue) && minimumValue <= maximumValue;
}

RangeCheckResult CheckRange(double value, const GameOptimizerRange &range, int decimalPlacesForMessage) {
    RangeCheckResult result;

    if (!IsFiniteValue(value)) {
        result.inRange = false;
        result.clampedValue = range.defaultValue;
        result.wasClamped = false; // not "clamped", it was outright invalid
        return result;
    }

    float v = static_cast<float>(value);

    if (v >= range.minimum && v <= range.maximum) {
        result.inRange = true;
        result.clampedValue = RoundToDecimalPlaces(v, decimalPlacesForMessage);
        result.wasClamped = false;
        return result;
    }

    float clamped = std::min(std::max(v, range.minimum), range.maximum);
    clamped = RoundToDecimalPlaces(clamped, decimalPlacesForMessage);

    result.inRange = false;
    result.clampedValue = clamped;
    result.wasClamped = true;

    char buffer[128];
    std::snprintf(buffer, sizeof(buffer), "Giá trị nằm ngoài giới hạn cho phép. Đã điều chỉnh về %.*f.",
                  decimalPlacesForMessage, static_cast<double>(clamped));
    result.noticeMessage = buffer;
    return result;
}

int32_t ResolveWorkerCount(int32_t requested, int32_t activeProcessorCount) {
    if (activeProcessorCount < 1) activeProcessorCount = 1;

    if (requested == GameOptimizerMaximumWorkerCountAuto) {
        int32_t autoValue = activeProcessorCount / 2;
        if (autoValue < 1) autoValue = 1;
        return autoValue;
    }

    if (requested < 1) requested = 1;
    if (requested > activeProcessorCount) requested = activeProcessorCount;
    return requested;
}

GameOptimizerResult ValidateConfiguration(const GameOptimizerConfiguration &c, std::string *outErrorDetail) {
    auto fail = [&](const char *msg) -> GameOptimizerResult {
        if (outErrorDetail) *outErrorDetail = msg;
        return GameOptimizerResultInvalidArgument;
    };

    if (!IsFiniteValue(c.manualRenderScale) ||
        c.manualRenderScale < GameOptimizerRangeManualRenderScale.minimum ||
        c.manualRenderScale > GameOptimizerRangeManualRenderScale.maximum) {
        return fail("manualRenderScale ngoài phạm vi 0.50 - 1.00.");
    }

    if (!IsOrderedPairValid(c.minimumRenderScale, c.maximumRenderScale)) {
        return fail("minimumRenderScale không được lớn hơn maximumRenderScale.");
    }
    if (c.minimumRenderScale < GameOptimizerRangeMinimumRenderScale.minimum ||
        c.maximumRenderScale > GameOptimizerRangeMaximumRenderScale.maximum) {
        return fail("minimumRenderScale/maximumRenderScale ngoài phạm vi 0.50 - 1.00.");
    }

    if (!IsFiniteValue(c.scaleStep) || c.scaleStep < GameOptimizerRangeScaleStep.minimum ||
        c.scaleStep > GameOptimizerRangeScaleStep.maximum || c.scaleStep == 0.0f) {
        return fail("scaleStep phải khác 0 và trong phạm vi 0.01 - 0.10.");
    }

    if (!IsFiniteValue(c.decreaseDelaySeconds) ||
        c.decreaseDelaySeconds < GameOptimizerRangeDecreaseDelaySeconds.minimum ||
        c.decreaseDelaySeconds > GameOptimizerRangeDecreaseDelaySeconds.maximum) {
        return fail("decreaseDelaySeconds ngoài phạm vi 0.25 - 10 giây.");
    }
    if (!IsFiniteValue(c.increaseDelaySeconds) ||
        c.increaseDelaySeconds < GameOptimizerRangeIncreaseDelaySeconds.minimum ||
        c.increaseDelaySeconds > GameOptimizerRangeIncreaseDelaySeconds.maximum) {
        return fail("increaseDelaySeconds ngoài phạm vi 0.5 - 20 giây.");
    }
    if (!IsFiniteValue(c.gpuFrameTimeMarginMS) ||
        c.gpuFrameTimeMarginMS < GameOptimizerRangeGPUFrameTimeMarginMS.minimum ||
        c.gpuFrameTimeMarginMS > GameOptimizerRangeGPUFrameTimeMarginMS.maximum) {
        return fail("gpuFrameTimeMarginMS ngoài phạm vi 0.1 - 10 ms.");
    }
    if (!IsFiniteValue(c.scaleChangeCooldownSeconds) ||
        c.scaleChangeCooldownSeconds < GameOptimizerRangeScaleChangeCooldownSec.minimum ||
        c.scaleChangeCooldownSeconds > GameOptimizerRangeScaleChangeCooldownSec.maximum) {
        return fail("scaleChangeCooldownSeconds ngoài phạm vi 0.25 - 10 giây.");
    }

    if (c.targetFPS < static_cast<int32_t>(GameOptimizerRangeTargetFPS.minimum) ||
        c.targetFPS > static_cast<int32_t>(GameOptimizerRangeTargetFPS.maximum)) {
        return fail("targetFPS ngoài phạm vi 15 - 120.");
    }

    if (!IsFiniteValue(c.uiMetricsUpdateRateHz) ||
        c.uiMetricsUpdateRateHz < GameOptimizerRangeUIMetricsUpdateRateHz.minimum ||
        c.uiMetricsUpdateRateHz > GameOptimizerRangeUIMetricsUpdateRateHz.maximum) {
        return fail("uiMetricsUpdateRateHz ngoài phạm vi 0.5 - 10 Hz.");
    }
    if (!IsFiniteValue(c.backgroundTaskIntervalSeconds) ||
        c.backgroundTaskIntervalSeconds < GameOptimizerRangeBackgroundTaskIntervalS.minimum ||
        c.backgroundTaskIntervalSeconds > GameOptimizerRangeBackgroundTaskIntervalS.maximum) {
        return fail("backgroundTaskIntervalSeconds ngoài phạm vi 0.1 - 60 giây.");
    }
    if (c.maximumWorkerCount < 0) {
        return fail("maximumWorkerCount không được âm.");
    }

    if (c.seriousFPS < static_cast<int32_t>(GameOptimizerRangeSeriousFPS.minimum) ||
        c.seriousFPS > static_cast<int32_t>(GameOptimizerRangeSeriousFPS.maximum)) {
        return fail("seriousFPS ngoài phạm vi 15 - 120.");
    }
    if (c.criticalFPS < static_cast<int32_t>(GameOptimizerRangeCriticalFPS.minimum) ||
        c.criticalFPS > static_cast<int32_t>(GameOptimizerRangeCriticalFPS.maximum)) {
        return fail("criticalFPS ngoài phạm vi 15 - 120.");
    }
    if (!IsFiniteValue(c.seriousMaxScale) ||
        c.seriousMaxScale < GameOptimizerRangeSeriousMaxScale.minimum ||
        c.seriousMaxScale > GameOptimizerRangeSeriousMaxScale.maximum) {
        return fail("seriousMaxScale ngoài phạm vi 0.50 - 1.00.");
    }
    if (!IsFiniteValue(c.criticalMaxScale) ||
        c.criticalMaxScale < GameOptimizerRangeCriticalMaxScale.minimum ||
        c.criticalMaxScale > GameOptimizerRangeCriticalMaxScale.maximum) {
        return fail("criticalMaxScale ngoài phạm vi 0.50 - 1.00.");
    }

    if (c.cpuOptimizationMode < GameOptimizerCPUModeOff || c.cpuOptimizationMode > GameOptimizerCPUModeStrong) {
        return fail("cpuOptimizationMode không hợp lệ.");
    }
    if (c.upscaleMode < GameOptimizerUpscaleModeNearest || c.upscaleMode > GameOptimizerUpscaleModeBicubicLite) {
        return fail("upscaleMode không hợp lệ.");
    }

    return GameOptimizerResultSuccess;
}

GameOptimizerConfiguration MakeSafeConfiguration(void) {
    GameOptimizerConfiguration c{};
    c.configVersion = GameOptimizerConfigurationCurrentVersion;

    c.masterEnabled = false;

    c.manualRenderScaleEnabled = false;
    c.manualRenderScale = GameOptimizerRangeManualRenderScale.maximum; // 1.00

    c.dynamicResolutionEnabled = false;
    c.minimumRenderScale = GameOptimizerRangeMinimumRenderScale.defaultValue;
    c.maximumRenderScale = GameOptimizerRangeMaximumRenderScale.defaultValue;
    c.scaleStep = GameOptimizerRangeScaleStep.defaultValue;
    c.decreaseDelaySeconds = GameOptimizerRangeDecreaseDelaySeconds.defaultValue;
    c.increaseDelaySeconds = GameOptimizerRangeIncreaseDelaySeconds.defaultValue;
    c.gpuFrameTimeMarginMS = GameOptimizerRangeGPUFrameTimeMarginMS.defaultValue;
    c.scaleChangeCooldownSeconds = GameOptimizerRangeScaleChangeCooldownSec.defaultValue;

    c.fpsLimitEnabled = false;
    c.targetFPS = static_cast<int32_t>(GameOptimizerRangeTargetFPS.defaultValue); // 60

    c.cpuOptimizationEnabled = false;
    c.cpuOptimizationMode = GameOptimizerCPUModeBalanced;
    c.uiMetricsUpdateRateHz = GameOptimizerRangeUIMetricsUpdateRateHz.defaultValue;
    c.backgroundTaskIntervalSeconds = GameOptimizerRangeBackgroundTaskIntervalS.defaultValue;
    c.maximumWorkerCount = GameOptimizerMaximumWorkerCountAuto;

    c.thermalProtectionEnabled = true; // protective feature, safe to keep on
    c.seriousFPS = static_cast<int32_t>(GameOptimizerRangeSeriousFPS.defaultValue);
    c.seriousMaxScale = GameOptimizerRangeSeriousMaxScale.defaultValue;
    c.criticalFPS = static_cast<int32_t>(GameOptimizerRangeCriticalFPS.defaultValue);
    c.criticalMaxScale = GameOptimizerRangeCriticalMaxScale.defaultValue;

    c.upscaleMode = GameOptimizerUpscaleModeBilinear;

    c.floatingButtonHidden = false;
    c.restoreGestureEnabled = true;

    return c;
}

GameOptimizerConfiguration MakePresetConfiguration(GameOptimizerPreset preset,
                                                    const GameOptimizerConfiguration &currentConfiguration) {
    if (preset == GameOptimizerPresetCustom) {
        return currentConfiguration;
    }

    // Start from Safe so every field is well-defined, then override the
    // fields each preset in the spec actually specifies.
    GameOptimizerConfiguration c = MakeSafeConfiguration();
    c.masterEnabled = true;

    switch (preset) {
        case GameOptimizerPresetQuality:
            c.manualRenderScaleEnabled = true;
            c.manualRenderScale = 0.90f;
            c.dynamicResolutionEnabled = false;
            c.minimumRenderScale = 0.80f;
            c.maximumRenderScale = 1.00f;
            c.fpsLimitEnabled = true;
            c.targetFPS = 60;
            break;

        case GameOptimizerPresetBalanced:
            c.manualRenderScaleEnabled = false;
            c.manualRenderScale = 0.75f;
            c.dynamicResolutionEnabled = true;
            c.minimumRenderScale = 0.65f;
            c.maximumRenderScale = 0.90f;
            c.fpsLimitEnabled = true;
            c.targetFPS = 60;
            break;

        case GameOptimizerPresetSmooth:
            c.manualRenderScaleEnabled = false;
            c.manualRenderScale = 0.65f;
            c.dynamicResolutionEnabled = true;
            c.minimumRenderScale = 0.55f;
            c.maximumRenderScale = 0.80f;
            c.fpsLimitEnabled = true;
            c.targetFPS = 60; // spec allows 45 or 60; 60 kept as the safer/less
                               // surprising default, user can pick 45 via quick-pick.
            break;

        case GameOptimizerPresetThermalSafe:
            c.manualRenderScaleEnabled = false;
            c.dynamicResolutionEnabled = true;
            c.minimumRenderScale = 0.60f;
            c.maximumRenderScale = 0.75f;
            c.fpsLimitEnabled = true;
            c.targetFPS = 30;
            c.cpuOptimizationEnabled = true;
            c.cpuOptimizationMode = GameOptimizerCPUModeStrong;
            c.uiMetricsUpdateRateHz = 1.0f;
            c.thermalProtectionEnabled = true;
            break;

        case GameOptimizerPresetSafe:
        default:
            return MakeSafeConfiguration();
    }

    return c;
}

} // namespace GameOptimizer
