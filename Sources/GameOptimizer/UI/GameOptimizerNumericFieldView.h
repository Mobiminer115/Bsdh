#import <UIKit/UIKit.h>
#include "../Public/GameOptimizerTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface GameOptimizerNumericFieldView : UIView <UITextFieldDelegate>

@property (nonatomic, copy, nullable) void (^onApply)(float validatedValue);

- (instancetype)initWithName:(NSString *)name
                         unit:(nullable NSString *)unit
                        range:(GameOptimizerRange)range
                    isInteger:(BOOL)isInteger
                decimalPlaces:(NSInteger)decimalPlaces;

- (void)setDisplayedValue:(float)value;
- (CGFloat)preferredHeight;

@end

NS_ASSUME_NONNULL_END
