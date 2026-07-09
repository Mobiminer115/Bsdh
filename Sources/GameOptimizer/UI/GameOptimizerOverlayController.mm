#import "GameOptimizerOverlayController.h"
#import "GameOptimizerFloatingButton.h"
#import "GameOptimizerPerformanceViewController.h"
#import "GameOptimizerGuideViewController.h"
#import "GameOptimizerStatusViewController.h"
#include "../Core/GameOptimizerCore.hpp"

using namespace GameOptimizer;

@interface GameOptimizerPassthroughWindow : UIWindow
@end

@implementation GameOptimizerPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static __weak GameOptimizerOverlayController *gGOCurrentController = nil;

@interface GameOptimizerOverlayController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) GameOptimizerPassthroughWindow *window;
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic, strong) GameOptimizerFloatingButton *button;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) UIView *childContainer;
@property (nonatomic, strong) GameOptimizerPerformanceViewController *performanceVC;
@property (nonatomic, strong) GameOptimizerGuideViewController *guideVC;
@property (nonatomic, strong) GameOptimizerStatusViewController *statusVC;
@property (nonatomic, strong, nullable) UIViewController *currentChildVC;
@property (nonatomic, strong, nullable) UITapGestureRecognizer *restoreGesture;
@property (nonatomic, weak, nullable) UIWindow *observedAppWindow;
@end

@implementation GameOptimizerOverlayController

+ (instancetype)currentController {
    return gGOCurrentController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        gGOCurrentController = self;
        [self setupOnMainThread];
    }
    return self;
}

- (nullable UIWindowScene *)activeWindowScene {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
        if (!fallback) fallback = ws;
    }
    return fallback;
}

- (void)setupOnMainThread {
    UIWindowScene *scene = [self activeWindowScene];
    if (!scene) return;

    self.window = [[GameOptimizerPassthroughWindow alloc] initWithWindowScene:scene];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];

    self.rootViewController = [[UIViewController alloc] init];
    self.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.window.rootViewController = self.rootViewController;
    self.window.hidden = NO;

    [self buildButton];
    [self buildMenu];
    self.menuView.hidden = YES;

    [self attachRestoreGesture];

    GameOptimizerConfiguration config = GameOptimizerCore::Shared().GetConfiguration();
    self.button.hidden = config.floatingButtonHidden;
}

- (void)buildButton {
    self.button = [[GameOptimizerFloatingButton alloc] init];
    self.button.center = CGPointMake(self.rootViewController.view.bounds.size.width - 40,
                                      self.rootViewController.view.bounds.size.height * 0.35);
    __weak typeof(self) weakSelf = self;
    self.button.onTap = ^{ [weakSelf toggle]; };
    [self.rootViewController.view addSubview:self.button];
    [self.button clampIntoSafeAreaOfView:self.rootViewController.view animated:NO];
}

- (void)buildMenu {
    CGRect screenBounds = self.rootViewController.view.bounds;
    CGFloat width = MIN(340, screenBounds.size.width - 32);
    CGFloat height = MIN(480, screenBounds.size.height - 80);

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    self.menuView.center = CGPointMake(screenBounds.size.width / 2.0, screenBounds.size.height / 2.0);
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    self.menuView.layer.cornerRadius = 14;
    self.menuView.layer.masksToBounds = YES;
    self.menuView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                      UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.rootViewController.view addSubview:self.menuView];

    CGFloat y = 12;
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, width - 140, 28)];
    self.titleLabel.text = @"GameOptimizer";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.menuView addSubview:self.titleLabel];

    self.masterSwitch = [[UISwitch alloc] init];
    self.masterSwitch.frame = CGRectMake(width - 130, y - 4, self.masterSwitch.frame.size.width, self.masterSwitch.frame.size.height);
    [self.masterSwitch addTarget:self action:@selector(masterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:self.masterSwitch];

    UIButton *minimizeButton = [self chromeButtonWithTitle:@"–" frame:CGRectMake(width - 68, y - 4, 28, 28)];
    [minimizeButton addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:minimizeButton];

    UIButton *closeButton = [self chromeButtonWithTitle:@"×" frame:CGRectMake(width - 36, y - 4, 28, 28)];
    [closeButton addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeButton];

    y += 36;
    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Tối ưu", @"Hướng dẫn", @"Trạng thái"]];
    self.tabControl.frame = CGRectMake(12, y, width - 24, 30);
    self.tabControl.selectedSegmentIndex = 0;
    [self.tabControl addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:self.tabControl];

    y += 38;
    self.childContainer = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, height - y)];
    self.childContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.menuView addSubview:self.childContainer];

    self.performanceVC = [[GameOptimizerPerformanceViewController alloc] init];
    self.guideVC = [[GameOptimizerGuideViewController alloc] init];
    self.statusVC = [[GameOptimizerStatusViewController alloc] init];

    [self showChildViewController:self.performanceVC];
}

- (UIButton *)chromeButtonWithTitle:(NSString *)title frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    b.layer.cornerRadius = 6;
    return b;
}

- (void)showChildViewController:(UIViewController *)vc {
    if (self.currentChildVC == vc) return;
    [self.currentChildVC.view removeFromSuperview];
    [self.currentChildVC removeFromParentViewController];

    self.currentChildVC = vc;
    vc.view.frame = self.childContainer.bounds;
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.rootViewController addChildViewController:vc];
    [self.childContainer addSubview:vc.view];
    [vc didMoveToParentViewController:self.rootViewController];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0: [self showChildViewController:self.performanceVC]; break;
        case 1: [self showChildViewController:self.guideVC]; break;
        case 2: [self showChildViewController:self.statusVC]; break;
        default: break;
    }
}

- (void)masterSwitchChanged:(UISwitch *)sender {
    GameOptimizerCore::Shared().SetMasterEnabled(sender.isOn);
}

- (void)refreshMasterSwitch {
    GameOptimizerConfiguration config = GameOptimizerCore::Shared().GetConfiguration();
    self.masterSwitch.on = config.masterEnabled;
}

- (void)attachRestoreGesture {
    UIWindowScene *scene = [self activeWindowScene];
    UIWindow *appWindow = nil;
    for (UIWindow *w in scene.windows) {
        if (w.isKeyWindow) { appWindow = w; break; }
    }
    if (!appWindow) appWindow = scene.windows.firstObject;
    if (!appWindow) return;

    self.observedAppWindow = appWindow;
    self.restoreGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleRestoreGesture:)];
    self.restoreGesture.numberOfTouchesRequired = 3;
    self.restoreGesture.numberOfTapsRequired = 2;
    self.restoreGesture.cancelsTouchesInView = NO;
    self.restoreGesture.delegate = self;
    [appWindow addGestureRecognizer:self.restoreGesture];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleRestoreGesture:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    GameOptimizerConfiguration config = GameOptimizerCore::Shared().GetConfiguration();
    if (!config.restoreGestureEnabled) return;
    [self setButtonHidden:NO];
}

- (void)setButtonHidden:(BOOL)hidden {
    self.button.hidden = hidden;
}

- (void)show {
    if (!self.window) return;
    [self refreshMasterSwitch];
    self.menuView.hidden = NO;
}

- (void)hide {
    self.menuView.hidden = YES;
}

- (void)toggle {
    if (self.menuView.hidden) {
        [self show];
    } else {
        [self hide];
    }
}

- (BOOL)isVisible {
    return self.menuView != nil && !self.menuView.hidden;
}

- (void)teardown {
    if (self.observedAppWindow && self.restoreGesture) {
        [self.observedAppWindow removeGestureRecognizer:self.restoreGesture];
    }
    self.restoreGesture = nil;
    self.observedAppWindow = nil;

    [self.currentChildVC.view removeFromSuperview];
    [self.currentChildVC removeFromParentViewController];
    self.currentChildVC = nil;

    self.window.hidden = YES;
    self.window.rootViewController = nil;
    self.window = nil;

    if (gGOCurrentController == self) gGOCurrentController = nil;
}

@end
