#import "GameOptimizerFloatingButton.h"

static const CGFloat kGOButtonSize = 44.0;
static const CGFloat kGOTapMoveThreshold = 8.0;

@interface GameOptimizerFloatingButton ()
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) CGPoint panStartLocation;
@property (nonatomic, assign) BOOL didDrag;
@end

@implementation GameOptimizerFloatingButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kGOButtonSize, kGOButtonSize)];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
        self.layer.cornerRadius = kGOButtonSize / 2.0;
        self.layer.masksToBounds = YES;

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.text = @"OPT";
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont boldSystemFontOfSize:11];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.dragStartCenter = self.center;
            self.panStartLocation = [gesture locationInView:self.superview];
            self.didDrag = NO;
            break;

        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gesture translationInView:self.superview];
            if (fabs(translation.x) > kGOTapMoveThreshold || fabs(translation.y) > kGOTapMoveThreshold) {
                self.didDrag = YES;
            }
            self.center = CGPointMake(self.dragStartCenter.x + translation.x, self.dragStartCenter.y + translation.y);
            [self clampIntoSafeAreaOfView:self.superview animated:NO];
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self clampIntoSafeAreaOfView:self.superview animated:YES];
            if (!self.didDrag && self.onTap) {
                self.onTap();
            }
            break;
        }

        default:
            break;
    }
}

- (void)clampIntoSafeAreaOfView:(UIView *)containerView animated:(BOOL)animated {
    if (!containerView) return;

    UIEdgeInsets safeInsets = containerView.safeAreaInsets;
    CGRect bounds = containerView.bounds;
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    CGFloat margin = 4.0;

    CGFloat minX = safeInsets.left + halfW + margin;
    CGFloat maxX = bounds.size.width - safeInsets.right - halfW - margin;
    CGFloat minY = safeInsets.top + halfH + margin;
    CGFloat maxY = bounds.size.height - safeInsets.bottom - halfH - margin;

    CGFloat clampedX = MIN(MAX(self.center.x, minX), MAX(minX, maxX));
    CGFloat clampedY = MIN(MAX(self.center.y, minY), MAX(minY, maxY));
    CGPoint clamped = CGPointMake(clampedX, clampedY);

    if (CGPointEqualToPoint(clamped, self.center)) return;

    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{ self.center = clamped; }];
    } else {
        self.center = clamped;
    }
}

@end
