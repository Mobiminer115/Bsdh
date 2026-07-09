#include "FrameMetricsCollector.hpp"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <algorithm>

// -----------------------------------------------------------------------
// Private Objective-C box holding every ObjC-lifetime object this collector
// needs (the display link, itself as its target, and every notification
// token). Kept out of the public header entirely. Notification blocks below
// capture only a raw GameOptimizer::FrameMetricsCollector* by value (a
// trivially-copyable C++ pointer, not an Objective-C object) specifically so
// they never participate in ARC retain graphs — there is nothing here for a
// retain cycle to form around other than this box's own strong properties,
// which Stop() tears down explicitly and deterministically.
// -----------------------------------------------------------------------
@interface GameOptimizerMetricsObserverBox : NSObject
@property (nonatomic, assign) GameOptimizer::FrameMetricsCollector *collector;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) id thermalToken;
@property (nonatomic, strong) id backgroundToken;
@property (nonatomic, strong) id foregroundToken;
@property (nonatomic, strong) id activeToken;
@property (nonatomic, strong) id resignActiveToken;
- (void)displayLinkTick:(CADisplayLink *)link;
@end

@implementation GameOptimizerMetricsObserverBox
- (void)displayLinkTick:(CADisplayLink *)link {
    // Intentionally minimal: this display link exists to make
    // preferredFramesPerSecond / preferredFrameRateRange effective for the
    // FPS-limit feature. No per-tick work is required; FPS itself is
    // computed from the app's own reported frame timestamps in
    // FrameMetricsCollector::RecordFrame, not from this callback.
    (void)link;
}
@end

namespace GameOptimizer {

namespace {
inline ThermalLevel ThermalLevelFromProcessInfoRawValue(int rawValue) {
    switch (static_cast<NSProcessInfoThermalState>(rawValue)) {
        case NSProcessInfoThermalStateNominal:  return ThermalLevel::Nominal;
        case NSProcessInfoThermalStateFair:     return ThermalLevel::Fair;
        case NSProcessInfoThermalStateSerious:  return ThermalLevel::Serious;
        case NSProcessInfoThermalStateCritical: return ThermalLevel::Critical;
        default:                                return ThermalLevel::Nominal;
    }
}
} // namespace

FrameMetricsCollector::FrameMetricsCollector() {}

FrameMetricsCollector::~FrameMetricsCollector() {
    Stop();
}

void FrameMetricsCollector::Start() {
    if (_started) return;
    _started = true;

    GameOptimizerMetricsObserverBox *box = [[GameOptimizerMetricsObserverBox alloc] init];
    box.collector = this;

    // Seed the current thermal state immediately rather than waiting for the
    // first change notification.
    _thermalState = ThermalLevelFromProcessInfoRawValue((int)[[NSProcessInfo processInfo] thermalState]);
    _applicationState = ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
                             ? GameOptimizerApplicationStateBackground
                             : GameOptimizerApplicationStateActive;

    FrameMetricsCollector *rawCollector = this; // trivially-copyable pointer, safe to capture by value
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];

    box.thermalToken = [center addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                            object:nil
                                             queue:mainQueue
                                        usingBlock:^(NSNotification * _Nonnull note) {
        int raw = (int)[[NSProcessInfo processInfo] thermalState];
        rawCollector->HandleThermalStateChanged(raw);
    }];

    box.backgroundToken = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                               object:nil
                                                queue:mainQueue
                                           usingBlock:^(NSNotification * _Nonnull note) {
        rawCollector->HandleDidEnterBackground();
    }];

    box.foregroundToken = [center addObserverForName:UIApplicationWillEnterForegroundNotification
                                               object:nil
                                                queue:mainQueue
                                           usingBlock:^(NSNotification * _Nonnull note) {
        rawCollector->HandleWillEnterForeground();
    }];

    box.activeToken = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                           object:nil
                                            queue:mainQueue
                                       usingBlock:^(NSNotification * _Nonnull note) {
        rawCollector->HandleDidBecomeActive();
    }];

    box.resignActiveToken = [center addObserverForName:UIApplicationWillResignActiveNotification
                                                 object:nil
                                                  queue:mainQueue
                                             usingBlock:^(NSNotification * _Nonnull note) {
        rawCollector->HandleWillResignActive();
    }];

    _displayLinkProxy = (__bridge_retained void *)box;
    // Note: the CADisplayLink itself is created lazily in SetFPSPacingTarget
    // — per the spec we must never have more than one alive, and there is no
    // reason to pay for one at all until FPS limiting is actually enabled.
}

void FrameMetricsCollector::Stop() {
    if (!_started) return;
    _started = false;

    if (_displayLinkProxy) {
        GameOptimizerMetricsObserverBox *box = (__bridge_transfer GameOptimizerMetricsObserverBox *)_displayLinkProxy;
        _displayLinkProxy = nullptr;

        [box.displayLink invalidate];
        box.displayLink = nil;

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        if (box.thermalToken) [center removeObserver:box.thermalToken];
        if (box.backgroundToken) [center removeObserver:box.backgroundToken];
        if (box.foregroundToken) [center removeObserver:box.foregroundToken];
        if (box.activeToken) [center removeObserver:box.activeToken];
        if (box.resignActiveToken) [center removeObserver:box.resignActiveToken];
        box.collector = nullptr;
        // `box` is released when this scope exits (ARC), which is also the
        // point the display link's strong ref to `box` as its target no
        // longer matters since we already invalidated it above.
    }
}

void FrameMetricsCollector::SetFPSPacingTarget(int fps) {
    RunOnMainAsync([this, fps]() {
        if (!_displayLinkProxy) return;
        GameOptimizerMetricsObserverBox *box = (__bridge GameOptimizerMetricsObserverBox *)_displayLinkProxy;

        if (fps <= 0) {
            [box.displayLink invalidate];
            box.displayLink = nil;
            return;
        }

        if (!box.displayLink) {
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:box selector:@selector(displayLinkTick:)];
            [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            box.displayLink = link;
        }

        int clampedFPS = std::max(1, fps);
        if (@available(iOS 15.0, *)) {
            CAFrameRateRange range;
            range.minimum = (float)std::max(10, clampedFPS - 10);
            range.maximum = (float)clampedFPS;
            range.preferred = (float)clampedFPS;
            box.displayLink.preferredFrameRateRange = range;
        } else {
            box.displayLink.preferredFramesPerSecond = clampedFPS;
        }
    });
}

int FrameMetricsCollector::MaximumSupportedFrameRate() const {
    // UIScreen.maximumFramesPerSecond is a simple immutable-after-launch
    // integer property; Apple's own ProMotion guidance shows it being read
    // off the main thread when configuring display-link pacing, so no
    // thread-hop is needed for this specific, narrow read.
    NSInteger maxFPS = [UIScreen mainScreen].maximumFramesPerSecond;
    if (maxFPS < 30 || maxFPS > 480) maxFPS = 60; // defensive fallback
    return (int)maxFPS;
}

void FrameMetricsCollector::RecordFrame(double now) {
    ScopedLock guard(_lock);

    if (_lastFrameTimestamp > 0.0 && now > _lastFrameTimestamp) {
        double dt = now - _lastFrameTimestamp;
        if (dt > 0.0001) {
            double instantFPS = 1.0 / dt;

            if (!_averageFPSInitialized) {
                _averageFPS_EMA = instantFPS;
                _averageFPSInitialized = true;
            } else {
                _averageFPS_EMA = _averageFPS_EMA * 0.9 + instantFPS * 0.1;

                double expectedInterval = (_averageFPS_EMA > 1.0) ? (1.0 / _averageFPS_EMA) : dt;
                if (expectedInterval > 0.0 && dt > expectedInterval * 1.5) {
                    uint64_t missed = static_cast<uint64_t>(dt / expectedInterval);
                    if (missed > 0) _droppedFrames += (missed - 1 > 0 ? missed - 1 : 0);
                }
            }

            _recentFrames.push_back(std::make_pair(now, instantFPS));
        }
    }
    _lastFrameTimestamp = now;
    PruneOldSamples(now);
}

void FrameMetricsCollector::PruneOldSamples(double nowSeconds) {
    // Caller already holds _lock.
    while (!_recentFrames.empty() && (nowSeconds - _recentFrames.front().first) > 10.0) {
        _recentFrames.pop_front();
    }
}

FrameMetricsSnapshot FrameMetricsCollector::Snapshot() {
    ScopedLock guard(_lock);

    FrameMetricsSnapshot snapshot;
    snapshot.currentFPS = _recentFrames.empty() ? 0.0 : _recentFrames.back().second;
    snapshot.averageFPS = _averageFPS_EMA;
    snapshot.droppedFrames = _droppedFrames;
    snapshot.thermalState = _thermalState;
    snapshot.applicationState = _applicationState;

    if (_recentFrames.empty()) {
        snapshot.minimumFPSLast10Seconds = 0.0;
    } else {
        double minFPS = _recentFrames.front().second;
        for (const auto &sample : _recentFrames) {
            minFPS = std::min(minFPS, sample.second);
        }
        snapshot.minimumFPSLast10Seconds = minFPS;
    }

    return snapshot;
}

bool FrameMetricsCollector::ConsumeJustForegroundedFlag() {
    ScopedLock guard(_lock);
    bool value = _pendingJustForegrounded;
    _pendingJustForegrounded = false;
    return value;
}

void FrameMetricsCollector::HandleThermalStateChanged(int processInfoThermalStateRawValue) {
    ScopedLock guard(_lock);
    _thermalState = ThermalLevelFromProcessInfoRawValue(processInfoThermalStateRawValue);
}

void FrameMetricsCollector::HandleDidEnterBackground() {
    ScopedLock guard(_lock);
    _applicationState = GameOptimizerApplicationStateBackground;
}

void FrameMetricsCollector::HandleWillEnterForeground() {
    ScopedLock guard(_lock);
    _applicationState = GameOptimizerApplicationStateInactive; // becomes Active on didBecomeActive
    _pendingJustForegrounded = true;
    _lastFrameTimestamp = -1.0; // don't let the pre-background cadence pollute the next dt/FPS sample
    _averageFPSInitialized = false;
    _recentFrames.clear();
}

void FrameMetricsCollector::HandleDidBecomeActive() {
    ScopedLock guard(_lock);
    _applicationState = GameOptimizerApplicationStateActive;
}

void FrameMetricsCollector::HandleWillResignActive() {
    ScopedLock guard(_lock);
    if (_applicationState == GameOptimizerApplicationStateActive) {
        _applicationState = GameOptimizerApplicationStateInactive;
    }
}

} // namespace GameOptimizer
