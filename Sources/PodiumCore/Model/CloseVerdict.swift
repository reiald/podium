/// What a "window destroyed" notification means for the board.
public enum CloseVerdict: Equatable, Sendable {
    /// The window is gone: drop it from the board (and the ledger, when `forgetLedger`).
    case closed(forgetLedger: Bool)
    /// Not believed yet: check the window server again a moment later.
    case recheckLater
}

/// Decides how to treat a destroyed notification.
///
/// - An on-screen (unparked) window is taken at its word. Many apps keep a closed window
///   alive and just hide it (Settings windows, some document windows), and the window
///   server still lists it, so a liveness check would leave a ghost stage behind.
/// - A parked window is only dropped once the window server no longer lists it
///   (`listed == false`): a spurious notification must never strand a parked window.
///   `listQueryFailed` (an empty answer) keeps its ledger entry.
public func closeVerdict(isParked: Bool, listed: Bool, listQueryFailed: Bool) -> CloseVerdict {
    guard isParked else { return .closed(forgetLedger: false) }
    if listed { return .recheckLater }
    return .closed(forgetLedger: !listQueryFailed)
}
