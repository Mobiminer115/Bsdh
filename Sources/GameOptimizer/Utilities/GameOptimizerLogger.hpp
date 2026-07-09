//
//  GameOptimizerLogger.hpp
//  GameOptimizer
//
//  A tiny, allocation-frugal logger. Never writes to disk, never logs every
//  frame, and caps how much it will log per second so a misbehaving call site
//  can't turn this into a hot-path cost or a stall.
//

#ifndef GAME_OPTIMIZER_LOGGER_HPP
#define GAME_OPTIMIZER_LOGGER_HPP

#include <string>
#include <vector>
#include <cstdint>
#include <deque>
#include <os/lock.h>

namespace GameOptimizer {

enum class LogLevel : int {
    Error = 0,
    Warning = 1,
    Info = 2,
    Debug = 3,
};

struct LogEvent {
    LogLevel level;
    std::string message; // never contains file paths, pointers, or personal data
    double timestampSeconds; // CACurrentMediaTime()-relative, monotonic
};

/// Thread-safe. All methods may be called from any thread, including the
/// render thread — logging itself never blocks on I/O and never allocates
/// more than a bounded ring buffer's worth of memory.
class Logger {
public:
    static Logger &Shared();

    /// Release builds default to Error+Warning only. Debug builds default to
    /// everything. Call this to override at runtime (e.g. from the status
    /// menu) regardless of build configuration.
    void SetMinimumLevel(LogLevel level);
    LogLevel MinimumLevel() const;

    void Log(LogLevel level, const std::string &message);
    void LogError(const std::string &message)   { Log(LogLevel::Error, message); }
    void LogWarning(const std::string &message) { Log(LogLevel::Warning, message); }
    void LogInfo(const std::string &message)    { Log(LogLevel::Info, message); }
    void LogDebug(const std::string &message)   { Log(LogLevel::Debug, message); }

    /// Most recent events first, capped at 100 total retained and (per the
    /// spec) the UI only ever asks for the most recent 20.
    std::vector<LogEvent> RecentEvents(size_t maxCount) const;

    /// Convenience accessors mirroring "Lỗi gần nhất" / "Thời gian kể từ lần
    /// lỗi gần nhất" in the status menu. Returns empty string / -1 if no
    /// error has been logged yet this run.
    std::string LastErrorMessage() const;
    double SecondsSinceLastError(double nowSeconds) const;

    void ClearEvents();

private:
    Logger();
    Logger(const Logger &) = delete;
    Logger &operator=(const Logger &) = delete;

    static constexpr size_t kMaxEventsRetained = 100;
    static constexpr int kMaxLogsPerSecond = 20;

    mutable os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
    std::deque<LogEvent> _events;      // front = most recent
    LogLevel _minimumLevel;
    std::string _lastErrorMessage;
    double _lastErrorTimestamp = -1.0;

    // Simple fixed-window rate limiter.
    int64_t _rateLimitWindowStart = -1;
    int _rateLimitCountInWindow = 0;
    uint64_t _droppedByRateLimit = 0;
};

} // namespace GameOptimizer

#endif /* GAME_OPTIMIZER_LOGGER_HPP */
