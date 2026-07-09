#include "GameOptimizerLogger.hpp"

#import <QuartzCore/QuartzCore.h> // CACurrentMediaTime
#import <os/log.h>

namespace GameOptimizer {

namespace {
inline int64_t SecondBucket(double timestampSeconds) {
    return static_cast<int64_t>(timestampSeconds);
}
} // namespace

Logger::Logger() {
#if defined(DEBUG) && DEBUG
    _minimumLevel = LogLevel::Debug;
#else
    _minimumLevel = LogLevel::Warning;
#endif
}

Logger &Logger::Shared() {
    static Logger *instance = new Logger(); // intentionally never destroyed; process-lifetime singleton
    return *instance;
}

void Logger::SetMinimumLevel(LogLevel level) {
    os_unfair_lock_lock(&_lock);
    _minimumLevel = level;
    os_unfair_lock_unlock(&_lock);
}

LogLevel Logger::MinimumLevel() const {
    os_unfair_lock_lock(&_lock);
    LogLevel level = _minimumLevel;
    os_unfair_lock_unlock(&_lock);
    return level;
}

void Logger::Log(LogLevel level, const std::string &message) {
    os_unfair_lock_lock(&_lock);

    if (static_cast<int>(level) > static_cast<int>(_minimumLevel)) {
        os_unfair_lock_unlock(&_lock);
        return;
    }

    double now = CACurrentMediaTime();
    int64_t bucket = SecondBucket(now);
    if (bucket != _rateLimitWindowStart) {
        _rateLimitWindowStart = bucket;
        _rateLimitCountInWindow = 0;
    }
    _rateLimitCountInWindow++;
    if (_rateLimitCountInWindow > kMaxLogsPerSecond) {
        _droppedByRateLimit++;
        os_unfair_lock_unlock(&_lock);
        return;
    }

    LogEvent event;
    event.level = level;
    event.message = message;
    event.timestampSeconds = now;

    _events.push_front(event);
    while (_events.size() > kMaxEventsRetained) {
        _events.pop_back();
    }

    if (level == LogLevel::Error) {
        _lastErrorMessage = message;
        _lastErrorTimestamp = now;
    }

    os_unfair_lock_unlock(&_lock);

    // Mirror into the system log too (visible in Console.app / device logs),
    // at a rate-limited cadence already enforced above. os_log itself is
    // cheap and async so this is safe to call from the render thread.
    os_log_type_t osType = OS_LOG_TYPE_DEFAULT;
    switch (level) {
        case LogLevel::Error:   osType = OS_LOG_TYPE_ERROR; break;
        case LogLevel::Warning: osType = OS_LOG_TYPE_DEFAULT; break;
        case LogLevel::Info:    osType = OS_LOG_TYPE_INFO; break;
        case LogLevel::Debug:   osType = OS_LOG_TYPE_DEBUG; break;
    }
    os_log_with_type(OS_LOG_DEFAULT, osType, "[GameOptimizer] %{public}s", message.c_str());
}

std::vector<LogEvent> Logger::RecentEvents(size_t maxCount) const {
    os_unfair_lock_lock(&_lock);
    size_t count = std::min(maxCount, _events.size());
    std::vector<LogEvent> result;
    result.reserve(count);
    for (size_t i = 0; i < count; i++) {
        result.push_back(_events[i]);
    }
    os_unfair_lock_unlock(&_lock);
    return result;
}

std::string Logger::LastErrorMessage() const {
    os_unfair_lock_lock(&_lock);
    std::string msg = _lastErrorMessage;
    os_unfair_lock_unlock(&_lock);
    return msg;
}

double Logger::SecondsSinceLastError(double nowSeconds) const {
    os_unfair_lock_lock(&_lock);
    double ts = _lastErrorTimestamp;
    os_unfair_lock_unlock(&_lock);
    if (ts < 0.0) return -1.0;
    double delta = nowSeconds - ts;
    return delta < 0.0 ? 0.0 : delta;
}

void Logger::ClearEvents() {
    os_unfair_lock_lock(&_lock);
    _events.clear();
    _lastErrorMessage.clear();
    _lastErrorTimestamp = -1.0;
    os_unfair_lock_unlock(&_lock);
}

} // namespace GameOptimizer
