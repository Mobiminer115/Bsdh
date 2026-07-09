#include "GameOptimizerThreading.hpp"

#import <Foundation/Foundation.h>

namespace GameOptimizer {

bool IsMainThread(void) {
    return [NSThread isMainThread];
}

void RunOnMainAsync(std::function<void(void)> block) {
    if (IsMainThread()) {
        // Run inline: no reason to pay a dispatch hop when we're already
        // where we need to be, and this keeps call sites like
        // GameOptimizerShowMenu() feeling synchronous when called from the
        // main thread (the common case).
        block();
        return;
    }

    // Copy the std::function onto the heap implicitly via the block capture;
    // dispatch_async retains the block for us until it runs.
    dispatch_async(dispatch_get_main_queue(), ^{
        block();
    });
}

int ActiveProcessorCount(void) {
    NSInteger count = [[NSProcessInfo processInfo] activeProcessorCount];
    if (count < 1) count = 1;
    return static_cast<int>(count);
}

} // namespace GameOptimizer
