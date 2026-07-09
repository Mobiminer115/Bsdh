//
//  GameOptimizerThreading.hpp
//  GameOptimizer
//
//  Small, deliberately boring concurrency primitives. The rule enforced by
//  construction here: never dispatch_sync onto the main queue (the spec
//  explicitly forbids it, and it's a classic deadlock source if the caller
//  might itself already be on a queue the main thread is waiting on), and
//  never hold a lock while calling out to unknown code (encoding Metal
//  commands, invoking a callback, etc).
//

#ifndef GAME_OPTIMIZER_THREADING_HPP
#define GAME_OPTIMIZER_THREADING_HPP

#include <os/lock.h>
#include <functional>

namespace GameOptimizer {

/// Thin wrapper around os_unfair_lock: fast, non-reentrant, priority-aware.
/// Never hold one of these while calling into Metal encode/present or into
/// any UIKit method — only ever use it to guard a POD struct copy in/out.
class UnfairLock {
public:
    UnfairLock() = default;
    UnfairLock(const UnfairLock &) = delete;
    UnfairLock &operator=(const UnfairLock &) = delete;

    void Lock()   { os_unfair_lock_lock(&_lock); }
    void Unlock() { os_unfair_lock_unlock(&_lock); }

private:
    os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
};

/// RAII scope guard for UnfairLock. Keep these scopes tiny — struct copies
/// only, never Metal or UIKit calls inside the guarded region.
class ScopedLock {
public:
    explicit ScopedLock(UnfairLock &lock) : _lock(lock) { _lock.Lock(); }
    ~ScopedLock() { _lock.Unlock(); }
    ScopedLock(const ScopedLock &) = delete;
    ScopedLock &operator=(const ScopedLock &) = delete;

private:
    UnfairLock &_lock;
};

/// True if called from the main thread.
bool IsMainThread(void);

/// If already on the main thread, runs `block` synchronously right now (no
/// hop, no latency). Otherwise dispatch_async's it to the main queue and
/// returns immediately — this function NEVER blocks the calling thread and
/// NEVER uses dispatch_sync, by design.
void RunOnMainAsync(std::function<void(void)> block);

/// Returns the device's active processor count (>= 1), used to resolve
/// "auto" worker counts. Cheap; safe to call every frame if ever needed,
/// though callers should still cache it since it cannot change at runtime.
int ActiveProcessorCount(void);

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_THREADING_HPP */
