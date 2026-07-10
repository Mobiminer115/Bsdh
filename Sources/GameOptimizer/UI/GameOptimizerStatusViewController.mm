#import "GameOptimizerStatusViewController.h"
#include "../Public/GameOptimizer.h"
#include "../Core/GameOptimizerCore.hpp"
#include "../Utilities/GameOptimizerLogger.hpp"
#include <cstring>

using namespace GameOptimizer;

@interface GameOptimizerStatusViewController ()
@property (nonatomic, strong) UILabel *metricsLabel;
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation GameOptimizerStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.metricsLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, self.view.bounds.size.width - 24, 220)];
    self.metricsLabel.numberOfLines = 0;
    self.metricsLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.metricsLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:self.metricsLabel];

    CGFloat y = 236;
    y = [self addButtonTitle:@"Xóa số liệu" y:y action:@selector(clearMetricsTapped)];
    y = [self addButtonTitle:@"Sao chép trạng thái" y:y action:@selector(copyStatusTapped)];
    y = [self addButtonTitle:@"Khôi phục cấu hình an toàn" y:y action:@selector(restoreSafeTapped)];

    [self refresh];
}

- (CGFloat)addButtonTitle:(NSString *)title y:(CGFloat)y action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.frame = CGRectMake(12, y, self.view.bounds.size.width - 24, 34);
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return y + 42;
}

- (void)willMoveToParentViewController:(nullable UIViewController *)parent {
    [super willMoveToParentViewController:parent];
    if (parent == nil) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
    }
}

- (void)didMoveToParentViewController:(nullable UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (parent != nil) {
        [self startTimer];
    }
}

- (void)startTimer {
    [self.pollTimer invalidate];
    GameOptimizerConfiguration c = GameOptimizerCore::Shared().GetConfiguration();
    NSTimeInterval interval = c.uiMetricsUpdateRateHz > 0.01 ? (1.0 / c.uiMetricsUpdateRateHz) : 0.5;
    __weak __typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf refresh];
    }];
}

- (void)dealloc {
    [_pollTimer invalidate];
}

- (void)refresh {
    if (!GameOptimizerIsInitialized()) return;
    GameOptimizerMetrics m = GameOptimizerGetMetrics();

    NSString *thermalName;
    switch (m.thermalState) {
        case GameOptimizerThermalStateNominal: thermalName = @"Nominal"; break;
        case GameOptimizerThermalStateFair: thermalName = @"Fair"; break;
        case GameOptimizerThermalStateSerious: thermalName = @"Serious"; break;
        case GameOptimizerThermalStateCritical: thermalName = @"Critical"; break;
        default: thermalName = @"?"; break;
    }
    NSString *appStateName;
    switch (m.applicationState) {
        case GameOptimizerApplicationStateActive: appStateName = @"active"; break;
        case GameOptimizerApplicationStateInactive: appStateName = @"inactive"; break;
        case GameOptimizerApplicationStateBackground: appStateName = @"background"; break;
        default: appStateName = @"?"; break;
    }

    char errBuf[160];
    GameOptimizerCopyLastError(errBuf, sizeof(errBuf));
    NSString *lastError = (strlen(errBuf) > 0) ? [NSString stringWithUTF8String:errBuf] : @"(không có)";

    self.metricsLabel.text = [NSString stringWithFormat:
        @"FPS hiện tại: %.1f\nFPS trung bình: %.1f\nFPS thấp nhất (10s): %.1f\n"
        @"CPU frame time: %.2f ms\nGPU frame time: %.2f ms\nTổng frame time: %.2f ms\n"
        @"Render scale: %.2f\nRender size: %u x %u\nDrawable size: %u x %u\n"
        @"Target FPS: %d\nFrame drop: %llu\nSố lần đổi scale: %llu\n"
        @"Thermal state: %@\nMemory (thư viện): %.2f MB\n"
        @"Pipeline ready: %@\nCPU Optimization: %@\nApp state: %@\n"
        @"Lỗi gần nhất: %@\nThời gian từ lỗi gần nhất: %@",
        m.currentFPS, m.averageFPS, m.minimumFPSLast10Seconds,
        m.cpuFrameTimeMS, m.gpuFrameTimeMS, m.totalFrameTimeMS,
        m.currentRenderScale, m.renderWidth, m.renderHeight, m.drawableWidth, m.drawableHeight,
        m.targetFPS, m.droppedFrames, m.renderScaleChangeCount,
        thermalName, m.memoryUsageBytes / (1024.0 * 1024.0),
        m.pipelineReady ? @"có" : @"chưa", m.cpuOptimizationEnabled ? @"bật" : @"tắt", appStateName,
        lastError, m.secondsSinceLastError >= 0 ? [NSString stringWithFormat:@"%.0f giây trước", m.secondsSinceLastError] : @"—"];
}

- (void)clearMetricsTapped {
    Logger::Shared().ClearEvents();
    [self refresh];
}

- (void)copyStatusTapped {
    [UIPasteboard generalPasteboard].string = self.metricsLabel.text ?: @"";
}

- (void)restoreSafeTapped {
    GameOptimizerRestoreSafeDefaults();
    [self refresh];
}

@end
