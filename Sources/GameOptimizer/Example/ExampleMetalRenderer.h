#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

// Minimal example renderer: clears the screen to a color. Stands in for your
// own 3D scene renderer — the only parts that matter for integration are in
// IntegrationExample.mm, not the (trivial) drawing done here.
@interface ExampleMetalRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end

NS_ASSUME_NONNULL_END
