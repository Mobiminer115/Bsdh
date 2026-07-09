#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GameOptimizerOverlayController : NSObject
+ (nullable instancetype)currentController;
- (void)show;
- (void)hide;
- (void)toggle;
- (BOOL)isVisible;
- (void)teardown;
- (void)setButtonHidden:(BOOL)hidden;
@end

NS_ASSUME_NONNULL_END
