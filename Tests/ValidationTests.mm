#import <XCTest/XCTest.h>
#include "../Sources/GameOptimizer/Utilities/GameOptimizerValidation.hpp"

using namespace GameOptimizer;

// Add this file to an XCTest target that has Sources/GameOptimizer on its
// header search path to run it. See README "Kiểm thử".
@interface ValidationTests : XCTestCase
@end

@implementation ValidationTests

- (void)testParseDecimalPlain {
    ParseResult r = ParseDecimal("0.75");
    XCTAssertTrue(r.ok);
    XCTAssertEqualWithAccuracy(r.value, 0.75, 0.0001);
}

- (void)testParseDecimalComma {
    ParseResult r = ParseDecimal("0,75");
    XCTAssertTrue(r.ok);
    XCTAssertEqualWithAccuracy(r.value, 0.75, 0.0001);
}

- (void)testParseDecimalMixedSeparatorsRejected {
    XCTAssertFalse(ParseDecimal("0,7.5").ok);
}

- (void)testParseDecimalTrailingGarbageRejected {
    XCTAssertFalse(ParseDecimal("1.5abc").ok);
}

- (void)testParseDecimalEmptyRejected {
    XCTAssertFalse(ParseDecimal("").ok);
    XCTAssertFalse(ParseDecimal("   ").ok);
}

- (void)testParseDecimalNaNRejected {
    XCTAssertFalse(ParseDecimal("nan").ok);
}

- (void)testParseDecimalInfinityRejected {
    XCTAssertFalse(ParseDecimal("inf").ok);
    XCTAssertFalse(ParseDecimal("Infinity").ok);
}

- (void)testParseIntegerRejectsFraction {
    XCTAssertFalse(ParseInteger("12.5").ok);
}

- (void)testParseIntegerPlain {
    ParseResult r = ParseInteger("60");
    XCTAssertTrue(r.ok);
    XCTAssertEqual((int)r.value, 60);
}

- (void)testCheckRangeInRange {
    GameOptimizerRange range{0.5f, 1.0f, 0.8f};
    RangeCheckResult r = CheckRange(0.75, range, 2);
    XCTAssertTrue(r.inRange);
    XCTAssertFalse(r.wasClamped);
}

- (void)testCheckRangeClampsAboveMax {
    GameOptimizerRange range{0.5f, 1.0f, 0.8f};
    RangeCheckResult r = CheckRange(5.0, range, 2);
    XCTAssertFalse(r.inRange);
    XCTAssertTrue(r.wasClamped);
    XCTAssertEqualWithAccuracy(r.clampedValue, 1.0, 0.0001);
}

- (void)testCheckRangeClampsBelowMin {
    GameOptimizerRange range{0.5f, 1.0f, 0.8f};
    RangeCheckResult r = CheckRange(-3.0, range, 2);
    XCTAssertTrue(r.wasClamped);
    XCTAssertEqualWithAccuracy(r.clampedValue, 0.5, 0.0001);
}

- (void)testOrderedPairValidation {
    XCTAssertTrue(IsOrderedPairValid(0.5f, 0.8f));
    XCTAssertTrue(IsOrderedPairValid(0.5f, 0.5f));
    XCTAssertFalse(IsOrderedPairValid(0.9f, 0.5f));
}

- (void)testValidateConfigurationRejectsMinGreaterThanMax {
    GameOptimizerConfiguration c = MakeSafeConfiguration();
    c.dynamicResolutionEnabled = true;
    c.minimumRenderScale = 0.9f;
    c.maximumRenderScale = 0.5f;
    std::string detail;
    XCTAssertEqual(ValidateConfiguration(c, &detail), GameOptimizerResultInvalidArgument);
}

- (void)testValidateConfigurationRejectsZeroScaleStep {
    GameOptimizerConfiguration c = MakeSafeConfiguration();
    c.scaleStep = 0.0f;
    std::string detail;
    XCTAssertEqual(ValidateConfiguration(c, &detail), GameOptimizerResultInvalidArgument);
}

- (void)testValidateConfigurationAcceptsSafeDefaults {
    GameOptimizerConfiguration c = MakeSafeConfiguration();
    std::string detail;
    XCTAssertEqual(ValidateConfiguration(c, &detail), GameOptimizerResultSuccess);
}

- (void)testResolveWorkerCountAuto {
    XCTAssertEqual(ResolveWorkerCount(GameOptimizerMaximumWorkerCountAuto, 8), 4);
    XCTAssertEqual(ResolveWorkerCount(GameOptimizerMaximumWorkerCountAuto, 1), 1);
}

- (void)testResolveWorkerCountClampsToHardwareLimit {
    XCTAssertEqual(ResolveWorkerCount(99, 4), 4);
    XCTAssertEqual(ResolveWorkerCount(0 + 1, 4), 1);
}

@end
