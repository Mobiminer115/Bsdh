#import "GameOptimizerPerformanceViewController.h"
#import "GameOptimizerNumericFieldView.h"
#import "GameOptimizerOverlayController.h"
#include "../Public/GameOptimizer.h"
#include "../Core/GameOptimizerCore.hpp"

using namespace GameOptimizer;

static void GOMutateConfig(void (^mutator)(GameOptimizerConfiguration &c)) {
    GameOptimizerConfiguration config = GameOptimizerCore::Shared().GetConfiguration();
    mutator(config);
    GameOptimizerCore::Shared().ApplyConfiguration(config);
}

@interface GameOptimizerPerformanceViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UISwitch *manualScaleSwitch;
@property (nonatomic, strong) GameOptimizerNumericFieldView *manualScaleField;

@property (nonatomic, strong) UISwitch *dynResSwitch;
@property (nonatomic, strong) GameOptimizerNumericFieldView *minScaleField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *maxScaleField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *stepField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *decreaseDelayField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *increaseDelayField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *marginField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *cooldownField;

@property (nonatomic, strong) UISwitch *fpsLimitSwitch;
@property (nonatomic, strong) GameOptimizerNumericFieldView *targetFPSField;

@property (nonatomic, strong) UISwitch *cpuOptSwitch;
@property (nonatomic, strong) UISegmentedControl *cpuModeControl;
@property (nonatomic, strong) GameOptimizerNumericFieldView *uiRateField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *bgIntervalField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *maxWorkerField;

@property (nonatomic, strong) UISwitch *thermalSwitch;
@property (nonatomic, strong) GameOptimizerNumericFieldView *seriousFPSField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *seriousScaleField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *criticalFPSField;
@property (nonatomic, strong) GameOptimizerNumericFieldView *criticalScaleField;

@property (nonatomic, strong) UISwitch *hideButtonSwitch;
@property (nonatomic, strong) UISwitch *restoreGestureSwitch;

@property (nonatomic, assign) CGFloat cursorY;
@end

@implementation GameOptimizerPerformanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    dismissTap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:dismissTap];

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 0)];
    [self.scrollView addSubview:self.contentView];

    self.cursorY = 8;
    [self buildMasterRow];
    [self buildManualScaleSection];
    [self buildDynamicResolutionSection];
    [self buildFPSSection];
    [self buildCPUSection];
    [self buildThermalSection];
    [self buildButtonVisibilitySection];
    [self buildPresetsSection];
    [self buildSafeRestoreButton];

    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.cursorY + 16);
    self.scrollView.contentSize = self.contentView.frame.size;

    [self refreshFromCurrentConfiguration];
}

- (void)dismissKeyboard { [self.view endEditing:YES]; }

#pragma mark - Layout helpers

- (UILabel *)addSectionHeader:(NSString *)title {
    self.cursorY += 6;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, self.cursorY, self.contentView.bounds.size.width - 24, 18)];
    l.text = title;
    l.font = [UIFont boldSystemFontOfSize:12];
    l.textColor = [UIColor systemYellowColor];
    [self.contentView addSubview:l];
    self.cursorY += 22;
    return l;
}

- (UISwitch *)addSwitchRow:(NSString *)label action:(SEL)action {
    CGFloat w = self.contentView.bounds.size.width;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, self.cursorY, w - 80, 30)];
    l.text = label;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = [UIColor whiteColor];
    l.numberOfLines = 2;
    [self.contentView addSubview:l];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame = CGRectMake(w - 62, self.cursorY, sw.frame.size.width, sw.frame.size.height);
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:sw];

    self.cursorY += 38;
    return sw;
}

- (GameOptimizerNumericFieldView *)addFieldName:(NSString *)name
                                            unit:(nullable NSString *)unit
                                           range:(GameOptimizerRange)range
                                       isInteger:(BOOL)isInteger
                                   decimalPlaces:(NSInteger)decimalPlaces
                                         onApply:(void (^)(float))onApply {
    CGFloat w = self.contentView.bounds.size.width - 24;
    GameOptimizerNumericFieldView *field = [[GameOptimizerNumericFieldView alloc] initWithName:name
                                                                                            unit:unit
                                                                                           range:range
                                                                                       isInteger:isInteger
                                                                                   decimalPlaces:decimalPlaces];
    field.frame = CGRectMake(12, self.cursorY, w, field.preferredHeight);
    field.onApply = onApply;
    [self.contentView addSubview:field];
    self.cursorY += field.preferredHeight + 10;
    return field;
}

#pragma mark - Sections

- (void)buildMasterRow {
    self.cursorY += 4;
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, self.cursorY, self.contentView.bounds.size.width - 24, 32)];
    hint.text = @"Công tắc bật/tắt toàn bộ hệ thống tối ưu nằm ở thanh tiêu đề phía trên.";
    hint.font = [UIFont systemFontOfSize:11];
    hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    hint.numberOfLines = 2;
    [self.contentView addSubview:hint];
    self.cursorY += 36;
}

- (void)buildManualScaleSection {
    [self addSectionHeader:@"Manual Render Scale"];
    self.manualScaleSwitch = [self addSwitchRow:@"Bật Manual Render Scale" action:@selector(manualScaleSwitchChanged:)];
    self.manualScaleField = [self addFieldName:@"Render Scale" unit:@"x" range:GameOptimizerRangeManualRenderScale
                                      isInteger:NO decimalPlaces:2
                                        onApply:^(float v) {
        GameOptimizerSetManualRenderScale(v);
    }];
}

- (void)buildDynamicResolutionSection {
    [self addSectionHeader:@"Dynamic Resolution Scaling"];
    self.dynResSwitch = [self addSwitchRow:@"Bật Dynamic Resolution" action:@selector(dynResSwitchChanged:)];

    self.minScaleField = [self addFieldName:@"Minimum Render Scale" unit:@"x" range:GameOptimizerRangeMinimumRenderScale
                                   isInteger:NO decimalPlaces:2 onApply:^(float v) { GameOptimizerSetMinimumRenderScale(v); }];
    self.maxScaleField = [self addFieldName:@"Maximum Render Scale" unit:@"x" range:GameOptimizerRangeMaximumRenderScale
                                   isInteger:NO decimalPlaces:2 onApply:^(float v) { GameOptimizerSetMaximumRenderScale(v); }];
    self.stepField = [self addFieldName:@"Scale Step" unit:@"x" range:GameOptimizerRangeScaleStep
                               isInteger:NO decimalPlaces:2 onApply:^(float v) { GameOptimizerSetScaleStep(v); }];
    self.decreaseDelayField = [self addFieldName:@"Thời gian trước khi giảm scale" unit:@"giây"
                                            range:GameOptimizerRangeDecreaseDelaySeconds isInteger:NO decimalPlaces:2
                                          onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.decreaseDelaySeconds = v; }); }];
    self.increaseDelayField = [self addFieldName:@"Thời gian trước khi tăng scale" unit:@"giây"
                                            range:GameOptimizerRangeIncreaseDelaySeconds isInteger:NO decimalPlaces:2
                                          onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.increaseDelaySeconds = v; }); }];
    self.marginField = [self addFieldName:@"GPU Frame Time Margin" unit:@"ms" range:GameOptimizerRangeGPUFrameTimeMarginMS
                                 isInteger:NO decimalPlaces:2
                                   onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.gpuFrameTimeMarginMS = v; }); }];
    self.cooldownField = [self addFieldName:@"Cooldown giữa hai lần đổi scale" unit:@"giây"
                                       range:GameOptimizerRangeScaleChangeCooldownSec isInteger:NO decimalPlaces:2
                                     onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.scaleChangeCooldownSeconds = v; }); }];
}

- (void)buildFPSSection {
    [self addSectionHeader:@"Target FPS"];
    self.fpsLimitSwitch = [self addSwitchRow:@"Bật giới hạn FPS" action:@selector(fpsLimitSwitchChanged:)];
    self.targetFPSField = [self addFieldName:@"Target FPS" unit:nil range:GameOptimizerRangeTargetFPS
                                    isInteger:YES decimalPlaces:0
                                      onApply:^(float v) { GameOptimizerSetTargetFPS((int)v); }];

    CGFloat w = self.contentView.bounds.size.width - 24;
    NSArray<NSNumber *> *quickValues = @[@30, @45, @60, @90, @120];
    CGFloat bw = (w - 4 * 6) / 5.0;
    for (NSInteger i = 0; i < quickValues.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:[NSString stringWithFormat:@"%@", quickValues[i]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12];
        b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        b.layer.cornerRadius = 6;
        b.tag = quickValues[i].integerValue;
        b.frame = CGRectMake(12 + i * (bw + 6), self.cursorY, bw, 30);
        [b addTarget:self action:@selector(quickFPSTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }
    self.cursorY += 40;
}

- (void)buildCPUSection {
    [self addSectionHeader:@"CPU Optimization"];
    self.cpuOptSwitch = [self addSwitchRow:@"Bật tối ưu CPU" action:@selector(cpuOptSwitchChanged:)];

    self.cpuModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Off", @"Nhẹ", @"Cân bằng", @"Mạnh"]];
    self.cpuModeControl.frame = CGRectMake(12, self.cursorY, self.contentView.bounds.size.width - 24, 30);
    [self.cpuModeControl addTarget:self action:@selector(cpuModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.cpuModeControl];
    self.cursorY += 40;

    self.uiRateField = [self addFieldName:@"UI Metrics Update Rate" unit:@"Hz" range:GameOptimizerRangeUIMetricsUpdateRateHz
                                 isInteger:NO decimalPlaces:1
                                   onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.uiMetricsUpdateRateHz = v; }); }];
    self.bgIntervalField = [self addFieldName:@"Background Task Interval" unit:@"giây" range:GameOptimizerRangeBackgroundTaskIntervalS
                                     isInteger:NO decimalPlaces:2
                                       onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.backgroundTaskIntervalSeconds = v; }); }];

    GameOptimizerRange workerRange;
    workerRange.minimum = 0;
    workerRange.maximum = (float)[[NSProcessInfo processInfo] activeProcessorCount];
    workerRange.defaultValue = 0;
    self.maxWorkerField = [self addFieldName:@"Maximum Worker Count (0 = tự động)" unit:nil range:workerRange
                                    isInteger:YES decimalPlaces:0
                                      onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.maximumWorkerCount = (int32_t)v; }); }];
}

- (void)buildThermalSection {
    [self addSectionHeader:@"Thermal Protection"];
    self.thermalSwitch = [self addSwitchRow:@"Bật bảo vệ nhiệt độ" action:@selector(thermalSwitchChanged:)];

    self.seriousFPSField = [self addFieldName:@"FPS khi nhiệt độ Serious" unit:nil range:GameOptimizerRangeSeriousFPS
                                     isInteger:YES decimalPlaces:0
                                       onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.seriousFPS = (int32_t)v; }); }];
    self.seriousScaleField = [self addFieldName:@"Maximum Scale khi Serious" unit:@"x" range:GameOptimizerRangeSeriousMaxScale
                                       isInteger:NO decimalPlaces:2
                                         onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.seriousMaxScale = v; }); }];
    self.criticalFPSField = [self addFieldName:@"FPS khi nhiệt độ Critical" unit:nil range:GameOptimizerRangeCriticalFPS
                                      isInteger:YES decimalPlaces:0
                                        onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.criticalFPS = (int32_t)v; }); }];
    self.criticalScaleField = [self addFieldName:@"Maximum Scale khi Critical" unit:@"x" range:GameOptimizerRangeCriticalMaxScale
                                        isInteger:NO decimalPlaces:2
                                          onApply:^(float v) { GOMutateConfig(^(GameOptimizerConfiguration &c){ c.criticalMaxScale = v; }); }];
}

- (void)buildButtonVisibilitySection {
    [self addSectionHeader:@"Nút OPT"];
    self.hideButtonSwitch = [self addSwitchRow:@"Ẩn nút OPT" action:@selector(hideButtonSwitchChanged:)];
    self.restoreGestureSwitch = [self addSwitchRow:@"Cho phép cử chỉ khôi phục (chạm 3 ngón, 2 lần)"
                                              action:@selector(restoreGestureSwitchChanged:)];
}

- (void)buildPresetsSection {
    [self addSectionHeader:@"Cấu hình gợi ý"];
    NSArray<NSString *> *titles = @[@"Safe", @"Quality", @"Balanced", @"Smooth", @"Thermal Safe"];
    NSArray<NSNumber *> *presets = @[@(GameOptimizerPresetSafe), @(GameOptimizerPresetQuality),
                                      @(GameOptimizerPresetBalanced), @(GameOptimizerPresetSmooth),
                                      @(GameOptimizerPresetThermalSafe)];
    CGFloat w = self.contentView.bounds.size.width - 24;
    CGFloat bw = (w - 4 * 6) / 5.0;
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:10];
        b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        b.layer.cornerRadius = 6;
        b.tag = presets[i].integerValue;
        b.frame = CGRectMake(12 + i * (bw + 6), self.cursorY, bw, 34);
        [b addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }
    self.cursorY += 44;

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(12, self.cursorY, w, 32)];
    note.text = @"Các cấu hình trên chỉ là điểm khởi đầu, kết quả phụ thuộc thiết bị và ứng dụng.";
    note.font = [UIFont systemFontOfSize:10];
    note.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    note.numberOfLines = 2;
    [self.contentView addSubview:note];
    self.cursorY += 36;
}

- (void)buildSafeRestoreButton {
    CGFloat w = self.contentView.bounds.size.width - 24;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:@"Khôi phục cấu hình an toàn" forState:UIControlStateNormal];
    [b setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    b.frame = CGRectMake(12, self.cursorY, w, 36);
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:@selector(restoreSafeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:b];
    self.cursorY += 46;
}

#pragma mark - Actions

- (void)manualScaleSwitchChanged:(UISwitch *)sw {
    GOMutateConfig(^(GameOptimizerConfiguration &c){ c.manualRenderScaleEnabled = sw.isOn; });
}
- (void)dynResSwitchChanged:(UISwitch *)sw { GameOptimizerSetDynamicResolutionEnabled(sw.isOn); }
- (void)fpsLimitSwitchChanged:(UISwitch *)sw { GameOptimizerSetFPSLimitEnabled(sw.isOn); }
- (void)cpuOptSwitchChanged:(UISwitch *)sw { GameOptimizerSetCPUOptimizationEnabled(sw.isOn); }
- (void)thermalSwitchChanged:(UISwitch *)sw { GameOptimizerSetThermalProtectionEnabled(sw.isOn); }

- (void)hideButtonSwitchChanged:(UISwitch *)sw {
    GOMutateConfig(^(GameOptimizerConfiguration &c){ c.floatingButtonHidden = sw.isOn; });
    [[GameOptimizerOverlayController currentController] setButtonHidden:sw.isOn];
}
- (void)restoreGestureSwitchChanged:(UISwitch *)sw {
    GOMutateConfig(^(GameOptimizerConfiguration &c){ c.restoreGestureEnabled = sw.isOn; });
}

- (void)cpuModeChanged:(UISegmentedControl *)sender {
    GameOptimizerSetCPUOptimizationMode((GameOptimizerCPUMode)sender.selectedSegmentIndex);
}

- (void)quickFPSTapped:(UIButton *)sender {
    GameOptimizerSetTargetFPS((int)sender.tag);
    [self.targetFPSField setDisplayedValue:(float)sender.tag];
}

- (void)presetTapped:(UIButton *)sender {
    GameOptimizerApplyPreset((GameOptimizerPreset)sender.tag);
    [self refreshFromCurrentConfiguration];
}

- (void)restoreSafeTapped {
    GameOptimizerRestoreSafeDefaults();
    [self refreshFromCurrentConfiguration];
}

#pragma mark - Refresh

- (void)refreshFromCurrentConfiguration {
    GameOptimizerConfiguration c = GameOptimizerCore::Shared().GetConfiguration();

    self.manualScaleSwitch.on = c.manualRenderScaleEnabled;
    [self.manualScaleField setDisplayedValue:c.manualRenderScale];

    self.dynResSwitch.on = c.dynamicResolutionEnabled;
    [self.minScaleField setDisplayedValue:c.minimumRenderScale];
    [self.maxScaleField setDisplayedValue:c.maximumRenderScale];
    [self.stepField setDisplayedValue:c.scaleStep];
    [self.decreaseDelayField setDisplayedValue:c.decreaseDelaySeconds];
    [self.increaseDelayField setDisplayedValue:c.increaseDelaySeconds];
    [self.marginField setDisplayedValue:c.gpuFrameTimeMarginMS];
    [self.cooldownField setDisplayedValue:c.scaleChangeCooldownSeconds];

    self.fpsLimitSwitch.on = c.fpsLimitEnabled;
    [self.targetFPSField setDisplayedValue:(float)c.targetFPS];

    self.cpuOptSwitch.on = c.cpuOptimizationEnabled;
    self.cpuModeControl.selectedSegmentIndex = (NSInteger)c.cpuOptimizationMode;
    [self.uiRateField setDisplayedValue:c.uiMetricsUpdateRateHz];
    [self.bgIntervalField setDisplayedValue:c.backgroundTaskIntervalSeconds];
    [self.maxWorkerField setDisplayedValue:(float)c.maximumWorkerCount];

    self.thermalSwitch.on = c.thermalProtectionEnabled;
    [self.seriousFPSField setDisplayedValue:(float)c.seriousFPS];
    [self.seriousScaleField setDisplayedValue:c.seriousMaxScale];
    [self.criticalFPSField setDisplayedValue:(float)c.criticalFPS];
    [self.criticalScaleField setDisplayedValue:c.criticalMaxScale];

    self.hideButtonSwitch.on = c.floatingButtonHidden;
    self.restoreGestureSwitch.on = c.restoreGestureEnabled;
}

@end
