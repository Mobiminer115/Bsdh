//
//  GameOptimizerConfiguration.hpp
//  GameOptimizer
//
//  Header-only on purpose: this is just a lock + POD struct, small enough
//  that inlining it avoids an extra translation unit. Validation, presets and
//  the "Safe" default live in GameOptimizerValidation.hpp/.cpp; NSUserDefaults
//  persistence lives in GameOptimizerCore.mm (it is the only place that
//  decides *when* to save, e.g. debounced-after-Apply).
//

#ifndef GAME_OPTIMIZER_CONFIGURATION_HPP
#define GAME_OPTIMIZER_CONFIGURATION_HPP

#include "../Public/GameOptimizerTypes.h"
#include "../Utilities/GameOptimizerThreading.hpp"
#include "../Utilities/GameOptimizerValidation.hpp"

namespace GameOptimizer {

/// Thread-safe holder for exactly one GameOptimizerConfiguration. Every read
/// and every write is a fast, bounded, lock-guarded struct copy — nothing in
/// here ever calls out to Metal, UIKit, or blocks.
class ConfigurationStore {
public:
    ConfigurationStore() : _config(MakeSafeConfiguration()) {}

    /// Cheap: takes the lock just long enough to memcpy the struct out.
    GameOptimizerConfiguration Snapshot() const {
        ScopedLock guard(_lock);
        return _config;
    }

    /// Replaces the entire configuration atomically. Callers are expected to
    /// have already run this through GameOptimizer::ValidateConfiguration —
    /// this class does not re-validate, it only guarantees atomicity of the
    /// swap so a reader on another thread never observes a half-old,
    /// half-new struct.
    void Replace(const GameOptimizerConfiguration &newConfig) {
        ScopedLock guard(_lock);
        _config = newConfig;
    }

    /// Applies a small in-place mutation under the lock. `mutator` must be
    /// fast (no Metal/UIKit calls, no logging, no allocation if avoidable) —
    /// it runs while the lock is held. Used by individual setters like
    /// GameOptimizerSetTargetFPS so we don't need one bespoke locked-copy
    /// dance per field.
    template <typename Mutator>
    void MutateInPlace(Mutator &&mutator) {
        ScopedLock guard(_lock);
        mutator(_config);
    }

private:
    mutable UnfairLock _lock;
    GameOptimizerConfiguration _config;
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_CONFIGURATION_HPP */
