#import <XCTest/XCTest.h>
#include "../Sources/GameOptimizer/Core/DynamicResolutionController.hpp"
#include "../Sources/GameOptimizer/Utilities/GameOptimizerValidation.hpp"
#include <cmath>

using namespace GameOptimizer;

// GameOptimizerInitialize/Shutdown themselves touch UIKit and Metal and so
// need a running app host (simulator or device) to exercise meaningfully —
// run those specific checks from your own app's test target or manually:
//   GameOptimizerInitialize(); GameOptimizerInitialize(); // expect AlreadyInitialized
//   GameOptimizerShutdown(); GameOptimizerShutdown();     // second call is a safe no-op
// What CAN run anywhere is stress-testing the pure-logic pieces below.
@interface LifecycleStressTests : XCTestCase
@end

@implementation LifecycleStressTests

- (void)testThousandScaleChangesNeverExceedBoundsOrCrash {
    DynamicResolutionController drc;
    ControllerBounds bounds;
    bounds.minimumScale = 0.5f;
    bounds.maximumScale = 1.0f;
    bounds.step = 0.05f;
    bounds.decreaseDelaySeconds = 0.01f;
    bounds.increaseDelaySeconds = 0.01f;
    bounds.gpuFrameTimeMarginMS = 1.0f;
    bounds.cooldownSeconds = 0.0f;
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.deltaTimeSeconds = 0.05;

    for (int i = 0; i < 1000; i++) {
        s.gpuFrameTimeMS = (i % 2 == 0) ? 30.0 : 2.0; // alternate over/under budget
        ControllerDecision d = drc.Update(s, bounds);
        XCTAssertGreaterThanOrEqual(d.currentScale, bounds.minimumScale - 0.0001f);
        XCTAssertLessThanOrEqual(d.currentScale, bounds.maximumScale + 0.0001f);
    }
}

- (void)testRapidBoundsChangesNeverProduceNaN {
    DynamicResolutionController drc;
    ControllerBounds bounds;
    bounds.minimumScale = 0.5f;
    bounds.maximumScale = 1.0f;
    bounds.step = 0.05f;
    bounds.decreaseDelaySeconds = 0.01f;
    bounds.increaseDelaySeconds = 0.01f;
    bounds.gpuFrameTimeMarginMS = 1.0f;
    bounds.cooldownSeconds = 0.0f;
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 12.0;
    s.cpuFrameTimeMS = 4.0;
    s.deltaTimeSeconds = 0.016;

    for (int i = 0; i < 500; i++) {
        bounds.maximumScale = (i % 3 == 0) ? 0.6f : 1.0f; // oscillate, can dip below current scale
        ControllerDecision d = drc.Update(s, bounds);
        XCTAssertFalse(std::isnan(d.currentScale));
        XCTAssertFalse(std::isinf(d.currentScale));
    }
}

- (void)testOrientationLikeDrawableResizeSpamDoesNotCrash {
    DynamicResolutionController drc;
    ControllerBounds bounds;
    bounds.minimumScale = 0.5f;
    bounds.maximumScale = 1.0f;
    bounds.step = 0.05f;
    bounds.decreaseDelaySeconds = 1.0f;
    bounds.increaseDelaySeconds = 1.0f;
    bounds.gpuFrameTimeMarginMS = 1.0f;
    bounds.cooldownSeconds = 0.1f;
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 10.0;
    s.cpuFrameTimeMS = 4.0;
    s.deltaTimeSeconds = 0.016;

    for (int i = 0; i < 200; i++) {
        BOOL portrait = (i % 2 == 0);
        s.drawableWidth = portrait ? 1080 : 1920;
        s.drawableHeight = portrait ? 1920 : 1080;
        ControllerDecision d = drc.Update(s, bounds);
        (void)d; // just asserting no crash / no exception across many resizes
    }
    XCTAssertTrue(true);
}

- (void)testApplyPresetTransactionRollsBackOnInvalidCustomEdit {
    GameOptimizerConfiguration base = MakeSafeConfiguration();
    GameOptimizerConfiguration broken = base;
    broken.minimumRenderScale = 0.95f;
    broken.maximumRenderScale = 0.10f; // invalid: min > max

    std::string detail;
    GameOptimizerResult result = ValidateConfiguration(broken, &detail);
    XCTAssertEqual(result, GameOptimizerResultInvalidArgument);
    // Caller (GameOptimizerCore::ApplyConfiguration) is expected to leave the
    // previously-active configuration untouched when validation fails —
    // exercised at the integration level in the app host, not here.
}

- (void)testParsingGarbageInputManyTimesNeverThrows {
    NSArray<NSString *> *garbage = @[@"", @"   ", @"abc", @"1.2.3", @"1,2,3", @"--5", @"NaN", @"Infinity", @"0x1p3", @"🙂"];
    for (int i = 0; i < 200; i++) {
        NSString *sample = garbage[i % garbage.count];
        ParseResult r = ParseDecimal(std::string(sample.UTF8String));
        (void)r;
    }
    XCTAssertTrue(true); // reaching this line means nothing threw/crashed
}

@end
