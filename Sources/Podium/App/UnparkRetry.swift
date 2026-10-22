import Foundation
import PodiumCore
// Carbon (via Foundation's AppKit-adjacent imports) may also declare `WindowRef`.
import struct PodiumCore.WindowRef

/// Unparks with backoff: a window whose unpark failed is not retried on every board change
/// (each attempt is several AX calls, up to a second each on a slow app) but after 1, 2,
/// 4 … up to 10 s. A window of an app marked hung is skipped without counting as a failure.
/// A skipped or failed window stays parked with its ledger entry kept.
@MainActor
final class UnparkRetry {
    private let mover: WindowMover
    private var backoff = RetryBackoff<WindowRef>(base: 1, maximum: 10)

    init(mover: WindowMover) {
        self.mover = mover
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Whether an automatic retry of `w` may happen now.
    func mayTry(_ w: WindowRef) -> Bool {
        !AX.isHung(w.pid) && backoff.mayTry(w, now: now)
    }

    /// Unparks `w`, or skips it while its app is hung. True only if it is now unparked.
    func unpark(_ w: WindowRef) -> Bool {
        guard !AX.isHung(w.pid) else { return false }
        if mover.unpark(w) {
            backoff.succeeded(w)
            return true
        }
        backoff.failed(w, now: now)
        return false
    }
}
