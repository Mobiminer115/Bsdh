#import <XCTest/XCTest.h>
#include "../Sources/GameOptimizer/Core/DynamicResolutionController.hpp"

using namespace GameOptimizer;

@interface DynamicResolutionTests : XCTestCase
@end

@implementation DynamicResolutionTests

- (ControllerBounds)defaultBounds {
    ControllerBounds b;
    b.minimumScale = 0.65f;
    b.maximumScale = 1.00f;
    b.step = 0.05f;
    b.decreaseDelaySeconds = 0.5f; // shortened for fast tests
    b.increaseDelaySeconds = 0.5f;
    b.gpuFrameTimeMarginMS = 1.0f;
    b.cooldownSeconds = 0.1f;
    return b;
}

- (void)testHoldsWhenDrawableIsZero {
    DynamicResolutionController drc;
    drc.ResetScale(1.0f, [self defaultBounds]);
    FrameSample s;
    s.drawableWidth = 0;
    s.drawableHeight = 0;
    ControllerDecision d = drc.Update(s, [self defaultBounds]);
    XCTAssertFalse(d.changedThisUpdate);
    XCTAssertEqual(d.reason, ScaleChangeReason::HeldForInvalidDrawable);
}

- (void)testDecreasesWhenSustainedOverBudget {
    DynamicResolutionController drc;
    ControllerBounds bounds = [self defaultBounds];
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0; // budget ~16.67ms
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 25.0; // well over budget
    s.cpuFrameTimeMS = 5.0;
    s.deltaTimeSeconds = 0.2;

    ControllerDecision last;
    for (int i = 0; i < 10; i++) {
        last = drc.Update(s, bounds);
        if (last.changedThisUpdate) break;
    }
    XCTAssertTrue(last.changedThisUpdate);
    XCTAssertEqual(last.reason, ScaleChangeReason::DecreasedOverBudget);
    XCTAssertLessThan(drc.CurrentScale(), 1.0f);
}

- (void)testDoesNotIncreaseDuringSeriousThermal {
    DynamicResolutionController drc;
    ControllerBounds bounds = [self defaultBounds];
    drc.ResetScale(0.65f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 2.0; // far under budget
    s.cpuFrameTimeMS = 2.0;
    s.deltaTimeSeconds = 0.2;
    s.thermalState = ThermalLevel::Serious;

    for (int i = 0; i < 10; i++) {
        drc.Update(s, bounds);
    }
    XCTAssertEqualWithAccuracy(drc.CurrentScale(), 0.65f, 0.001f);
}

- (void)testIgnoresFirstFrameAfterForeground {
    DynamicResolutionController drc;
    ControllerBounds bounds = [self defaultBounds];
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 200.0; // huge spike, as if resuming from background
    s.cpuFrameTimeMS = 200.0;
    s.deltaTimeSeconds = 0.2;
    s.justForegrounded = true;

    ControllerDecision d = drc.Update(s, bounds);
    XCTAssertEqual(d.reason, ScaleChangeReason::HeldForForeground);
    XCTAssertEqualWithAccuracy(d.smoothedFrameTimeMS, 0.0, 0.001);
}

- (void)testRespectsCooldownBetweenChanges {
    DynamicResolutionController drc;
    ControllerBounds bounds = [self defaultBounds];
    bounds.decreaseDelaySeconds = 0.05f;
    bounds.cooldownSeconds = 5.0f; // long cooldown
    drc.ResetScale(1.0f, bounds);

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 30.0;
    s.cpuFrameTimeMS = 5.0;
    s.deltaTimeSeconds = 0.2;

    int changeCount = 0;
    for (int i = 0; i < 20; i++) {
        ControllerDecision d = drc.Update(s, bounds);
        if (d.changedThisUpdate) changeCount++;
    }
    XCTAssertEqual(changeCount, 1); // cooldown should block further changes within this short test window
}

- (void)testClampsCurrentScaleWhenBoundsShrink {
    DynamicResolutionController drc;
    ControllerBounds bounds = [self defaultBounds];
    drc.ResetScale(1.0f, bounds);

    ControllerBounds tighter = bounds;
    tighter.maximumScale = 0.7f;

    FrameSample s;
    s.drawableWidth = 1920;
    s.drawableHeight = 1080;
    s.targetFPS = 60.0;
    s.gpuTimeValid = true;
    s.gpuFrameTimeMS = 10.0;
    s.cpuFrameTimeMS = 5.0;
    s.deltaTimeSeconds = 0.1;

    ControllerDecision d = drc.Update(s, tighter);
    XCTAssertTrue(d.changedThisUpdate);
    XCTAssertLessThanOrEqual(drc.CurrentScale(), 0.7f);
}

@end
