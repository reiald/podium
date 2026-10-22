import Foundation

/// A per-key circuit breaker: once tripped, a key stays open (calls are skipped) for
/// `cooldown` seconds. Used to stop talking to an app whose Accessibility calls time out,
/// so one hung app can't freeze Podium's main thread a second per call.
public struct CircuitBreaker<Key: Hashable>: Sendable where Key: Sendable {
    public let cooldown: TimeInterval
    private var openUntil: [Key: TimeInterval] = [:]

    public init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    /// The call to `key` timed out at `now`: skip it until `now + cooldown`.
    public mutating func trip(_ key: Key, now: TimeInterval) {
        openUntil[key] = now + cooldown
        openUntil = openUntil.filter { $0.value > now }
    }

    /// Whether calls to `key` are being skipped at `now`.
    public func isOpen(_ key: Key, now: TimeInterval) -> Bool {
        (openUntil[key] ?? -.infinity) > now
    }
}

/// Exponential backoff per key for an operation that keeps failing (an unpark the app
/// refuses): after the n-th failure in a row the next attempt waits
/// `min(base * 2^(n-1), maximum)` seconds. A success clears the key.
public struct RetryBackoff<Key: Hashable>: Sendable where Key: Sendable {
    public let base: TimeInterval
    public let maximum: TimeInterval
    private var state: [Key: (failures: Int, retryAt: TimeInterval)] = [:]

    public init(base: TimeInterval, maximum: TimeInterval) {
        self.base = base
        self.maximum = maximum
    }

    public mutating func failed(_ key: Key, now: TimeInterval) {
        let failures = (state[key]?.failures ?? 0) + 1
        let delay = min(base * pow(2, Double(failures - 1)), maximum)
        state[key] = (failures, now + delay)
    }

    public mutating func succeeded(_ key: Key) {
        state[key] = nil
    }

    /// Whether an attempt on `key` is allowed at `now`.
    public func mayTry(_ key: Key, now: TimeInterval) -> Bool {
        guard let s = state[key] else { return true }
        return now >= s.retryAt
    }
}
