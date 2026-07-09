#import "GameOptimizerNumericFieldView.h"
#include "../Utilities/GameOptimizerValidation.hpp"

using namespace GameOptimizer;

@interface GameOptimizerNumericFieldView ()
@property (nonatomic, copy) NSString *fieldName;
@property (nonatomic, copy, nullable) NSString *unit;
@property (nonatomic, assign) GameOptimizerRange range;
@property (nonatomic, assign) BOOL isInteger;
@property (nonatomic, assign) NSInteger decimalPlaces;

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UILabel *errorLabel;
@end

@implementation GameOptimizerNumericFieldView

- (instancetype)initWithName:(NSString *)name
                         unit:(nullable NSString *)unit
                        range:(GameOptimizerRange)range
                    isInteger:(BOOL)isInteger
                decimalPlaces:(NSInteger)decimalPlaces {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _fieldName = [name copy];
        _unit = [unit copy];
        _range = range;
        _isInteger = isInteger;
        _decimalPlaces = decimalPlaces;
        [self buildSubviews];
        [self setDisplayedValue:range.defaultValue];
    }
    return self;
}

- (CGFloat)preferredHeight { return 96.0; }

- (NSString *)formatValue:(float)value {
    if (self.isInteger) return [NSString stringWithFormat:@"%d", (int)lroundf(value)];
    return [NSString stringWithFormat:@"%.*f", (int)self.decimalPlaces, value];
}

- (void)buildSubviews {
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:13];
    self.nameLabel.textColor = [UIColor whiteColor];
    NSString *unitSuffix = self.unit.length > 0 ? [NSString stringWithFormat:@" (%@)", self.unit] : @"";
    self.nameLabel.text = [self.fieldName stringByAppendingString:unitSuffix];
    [self addSubview:self.nameLabel];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = [UIFont systemFontOfSize:10];
    self.hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self.hintLabel.text = [NSString stringWithFormat:@"Min %@ · Max %@ · Mặc định %@",
                            [self formatValue:self.range.minimum],
                            [self formatValue:self.range.maximum],
                            [self formatValue:self.range.defaultValue]];
    [self addSubview:self.hintLabel];

    self.textField = [[UITextField alloc] init];
    self.textField.borderStyle = UITextBorderStyleRoundedRect;
    self.textField.keyboardType = self.isInteger ? UIKeyboardTypeNumberPad : UIKeyboardTypeDecimalPad;
    self.textField.textColor = [UIColor blackColor];
    self.textField.delegate = self;
    self.textField.inputAccessoryView = [self buildDoneToolbar];
    [self addSubview:self.textField];

    self.applyButton = [self smallButtonWithTitle:@"Áp dụng" action:@selector(applyTapped)];
    [self addSubview:self.applyButton];

    self.resetButton = [self smallButtonWithTitle:@"Mặc định" action:@selector(resetTapped)];
    [self addSubview:self.resetButton];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = [UIFont systemFontOfSize:10];
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.numberOfLines = 2;
    self.errorLabel.hidden = YES;
    [self addSubview:self.errorLabel];
}

- (UIButton *)smallButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:11];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIToolbar *)buildDoneToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                            target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                            target:self action:@selector(doneTapped)];
    toolbar.items = @[flex, done];
    return toolbar;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    self.nameLabel.frame = CGRectMake(0, 0, w, 16);
    self.hintLabel.frame = CGRectMake(0, 16, w, 14);

    CGFloat buttonW = 66;
    self.textField.frame = CGRectMake(0, 34, w - buttonW * 2 - 12, 32);
    self.applyButton.frame = CGRectMake(w - buttonW * 2 - 6, 34, buttonW, 32);
    self.resetButton.frame = CGRectMake(w - buttonW, 34, buttonW, 32);
    self.errorLabel.frame = CGRectMake(0, 70, w, 24);
}

- (void)setDisplayedValue:(float)value {
    self.textField.text = [self formatValue:value];
    self.errorLabel.hidden = YES;
}

- (void)doneTapped {
    [self commit];
    [self.textField resignFirstResponder];
}

- (void)applyTapped {
    [self commit];
    [self.textField resignFirstResponder];
}

- (void)resetTapped {
    [self setDisplayedValue:self.range.defaultValue];
    if (self.onApply) self.onApply(self.range.defaultValue);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self commit];
    [textField resignFirstResponder];
    return YES;
}

- (void)commit {
    std::string text = self.textField.text ? std::string(self.textField.text.UTF8String) : std::string();
    ParseResult parsed = self.isInteger ? ParseInteger(text) : ParseDecimal(text);

    if (!parsed.ok) {
        self.errorLabel.text = [NSString stringWithFormat:@"%s Giới hạn: %@ - %@", parsed.errorMessage.c_str(),
                                 [self formatValue:self.range.minimum], [self formatValue:self.range.maximum]];
        self.errorLabel.hidden = NO;
        return;
    }

    RangeCheckResult check = CheckRange(parsed.value, self.range, (int)self.decimalPlaces);
    float finalValue = check.clampedValue;

    if (check.wasClamped) {
        self.errorLabel.text = [NSString stringWithUTF8String:check.noticeMessage.c_str()];
        self.errorLabel.hidden = NO;
    } else {
        self.errorLabel.hidden = YES;
    }

    [self setDisplayedValue:finalValue];
    self.errorLabel.hidden = !check.wasClamped;
    if (self.onApply) self.onApply(finalValue);
}

@end
