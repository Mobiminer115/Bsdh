#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GameOptimizerFloatingButton : UIView
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)clampIntoSafeAreaOfView:(UIView *)containerView animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
