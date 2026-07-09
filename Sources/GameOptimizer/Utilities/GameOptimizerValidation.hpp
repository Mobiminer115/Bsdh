//
//  GameOptimizerValidation.hpp
//  GameOptimizer
//
//  Pure C++, no Apple-framework dependency. Every place in the codebase that
//  parses a user-typed number or validates a configuration value routes
//  through here, so there is exactly one place that can get "is this a valid
//  float" wrong instead of fifteen slightly-different copies.
//

#ifndef GAME_OPTIMIZER_VALIDATION_HPP
#define GAME_OPTIMIZER_VALIDATION_HPP

#include "../Public/GameOptimizerTypes.h"
#include <string>
#include <cstdint>

namespace GameOptimizer {

/// Result of attempting to parse user-typed text into a number.
struct ParseResult {
    bool   ok = false;          // true only if the ENTIRE string was a finite number
    double value = 0.0;
    std::string errorMessage;   // human-readable (Vietnamese), only set when !ok
};

/// Result of validating a value that parsed successfully against a range.
struct RangeCheckResult {
    bool   inRange = false;
    float  clampedValue = 0.0f; // value if inRange, else the nearest bound
    bool   wasClamped = false;
    std::string noticeMessage;  // Vietnamese, set when wasClamped
};

/// Parses `text` as a decimal number.
///  - Accepts both '.' and ',' as the decimal separator (',' is normalized to
///    '.' before parsing; a string may not contain both).
///  - Rejects empty/whitespace-only strings.
///  - Rejects trailing garbage: "1.5abc" is NOT a valid 1.5, it is an error.
///  - Rejects NaN and +/-Infinity textual forms as well as any parse that
///    produces a non-finite double.
///  - Does NOT clamp to any range; callers combine this with CheckRange.
ParseResult ParseDecimal(const std::string &text);

/// Parses `text` as a base-10 integer with the same strictness as
/// ParseDecimal (no trailing garbage, no empty string), returned as a double
/// for a uniform call site; callers needing an int should round after
/// CheckRange. Rejects fractional input like "12.5" (integer fields use the
/// numberPad keyboard so this should be rare, but background-thread/API
/// callers can pass anything).
ParseResult ParseInteger(const std::string &text);

/// Clamps `value` into [range.minimum, range.maximum]. `wasClamped` is true
/// iff clamping actually changed the value. `noticeMessage` (Vietnamese) is
/// only populated when wasClamped is true, e.g. for showing under a text
/// field: "Giá trị đã được điều chỉnh về 1.00".
RangeCheckResult CheckRange(double value, const GameOptimizerRange &range, int decimalPlacesForMessage);

/// Rounds `value` to at most `decimalPlaces` fractional digits (0...6).
/// Used after parsing so e.g. "0.8333333" typed by a user becomes 0.83.
float RoundToDecimalPlaces(float value, int decimalPlaces);

/// True iff value is neither NaN nor +/-Infinity.
bool IsFiniteValue(double value);

/// Validates minimum/maximum pairs where min must not exceed max (used for
/// render-scale bounds). Returns false (invalid) when minimum > maximum.
bool IsOrderedPairValid(float minimumValue, float maximumValue);

/// Full structural validation of a GameOptimizerConfiguration: every field in
/// range, minimum<=maximum pairs respected, scaleStep non-zero, targetFPS
/// supported, etc. Returns Success or the first InvalidArgument-class problem
/// found; does not mutate `configuration`. `outErrorDetail` receives a short
/// Vietnamese diagnostic when the result is not Success (may be null).
GameOptimizerResult ValidateConfiguration(const GameOptimizerConfiguration &configuration, std::string *outErrorDetail);

/// Returns the compiled-in "Safe" configuration used both as the initial
/// default and as the target of GameOptimizerRestoreSafeDefaults.
GameOptimizerConfiguration MakeSafeConfiguration(void);

/// Returns the requested built-in preset. GameOptimizerPresetCustom simply
/// returns whatever configuration is passed in `currentConfiguration`
/// unchanged, since "Custom" by definition has no fixed values of its own.
GameOptimizerConfiguration MakePresetConfiguration(GameOptimizerPreset preset,
                                                    const GameOptimizerConfiguration &currentConfiguration);

/// Clamps an integer worker-count request into [1, hardwareLimit], resolving
/// GameOptimizerMaximumWorkerCountAuto (0) to a reasonable value derived from
/// activeProcessorCount (roughly half, minimum 1, so the app's own threads
/// are never starved by our background work).
int32_t ResolveWorkerCount(int32_t requested, int32_t activeProcessorCount);

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_VALIDATION_HPP */
