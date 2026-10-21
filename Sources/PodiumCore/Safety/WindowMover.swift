import CoreGraphics
import os

/// The window server as seen by `WindowMover`. All coordinates are top-left-origin global.
public protocol WindowBackend {
    func frame(of w: WindowRef) -> CGRect?
    func setOrigin(_ p: CGPoint, of w: WindowRef) -> Bool
    func liveWindows() -> Set<WindowRef>
    func bundleID(of pid: Int32) -> String?
}

/// Moves windows off-stage and back without ever losing one.
///
/// The ledger is the source of truth: a window is recorded before it moves, and its
/// entry is only removed once the window reads back where it belongs. Every decision
/// re-reads the ledger, so all of this works across launches.
public final class WindowMover {
    private let backend: WindowBackend
    private let ledger: ParkingLedger
    private let log = Logger(subsystem: "dev.podium.Podium", category: "WindowMover")

    public init(backend: WindowBackend, ledger: ParkingLedger) {
        self.backend = backend
        self.ledger = ledger
    }

    /// Parks `w` so only a 1x1 pt corner stays on `display`. Returns false, with the
    /// window back at its original position, if it could not be parked.
    public func park(_ w: WindowRef, display: CGRect, displayID: UInt32) -> Bool {
        // Already parked: its current frame is the parked one, never record it as original.
        if let existing = entry(for: w) {
            return moveToParking(w, size: existing.originalFrame.size, display: display)
        }
        guard let original = backend.frame(of: w) else { return false }
        let e = ParkedEntry(window: w, bundleID: backend.bundleID(of: w.pid),
                            originalFrame: original, displayID: displayID)
        do {
            try ledger.record(e)
        } catch {
            log.error("Not parking \(String(describing: w)): ledger record failed: \(String(describing: error))")
            return false
        }
        if moveToParking(w, size: original.size, display: display) { return true }

        log.error("Window \(String(describing: w)) did not leave the screen; moving it back")
        if move(w, to: original.origin) {
            forget(w)
        } else {
            // Keep the entry so restoreAll / recovery can still bring it back.
            log.error("Could not move \(String(describing: w)) back; keeping ledger entry")
        }
        return false
    }

    /// Moves `w` back to its original position. The ledger entry is removed only once
    /// the window reads back there.
    public func unpark(_ w: WindowRef) -> Bool {
        guard let e = entry(for: w) else { return false }
        guard move(w, to: e.originalFrame.origin) else {
            log.error("Unpark of \(String(describing: w)) did not land on screen; keeping ledger entry")
            return false
        }
        forget(w)
        return true
    }

    public func isParked(_ w: WindowRef) -> Bool { entry(for: w) != nil }

    /// Unparks every window in the ledger; windows that no longer exist are forgotten.
    /// Every entry gets an unpark attempt first, so a window missing from `liveWindows`
    /// by mistake is still put back rather than forgotten.
    public func restoreAll() {
        let entries = ledger.entries()
        guard !entries.isEmpty else { return }
        let failed = entries.filter { !unpark($0.window) }
        guard !failed.isEmpty else { return }
        let live = backend.liveWindows()
        for e in failed where !live.contains(e.window) { forget(e.window) }
    }

    /// Launch-time recovery: puts back every window a previous run left parked, landing
    /// each fully on one of `visibleScreens`.
    public func recover(visibleScreens: [CGRect]) {
        let actions = recoveryActions(entries: ledger.entries(), liveWindows: backend.liveWindows(),
                                      visibleScreens: visibleScreens)
        for action in actions {
            switch action {
            case let .forget(w):
                forget(w)
            case let .restore(w, to: frame):
                if move(w, to: frame.origin) {
                    forget(w)
                } else {
                    log.error("Recovery could not restore \(String(describing: w)); keeping ledger entry")
                }
            }
        }
    }

    /// Moves every parked window to the parking corner of `display` (after a display change).
    public func repark(display: CGRect) {
        for e in ledger.entries() {
            _ = moveToParking(e.window, size: e.originalFrame.size, display: display)
        }
    }

    // MARK: - Private

    private func entry(for w: WindowRef) -> ParkedEntry? {
        ledger.entries().first { $0.window == w }
    }

    /// Moves to the parking corner, then verifies at most 1x1 pt still covers the display.
    private func moveToParking(_ w: WindowRef, size: CGSize, display: CGRect) -> Bool {
        _ = backend.setOrigin(parkingOrigin(for: size, display: display), of: w)
        guard let back = backend.frame(of: w) else { return false }
        let visible = back.intersection(display)
        return visible.isNull || (visible.width <= 1 && visible.height <= 1)
    }

    /// Moves to `origin`, then verifies the window reads back there within 1 pt (apps may round).
    private func move(_ w: WindowRef, to origin: CGPoint) -> Bool {
        _ = backend.setOrigin(origin, of: w)
        guard let back = backend.frame(of: w) else { return false }
        return abs(back.minX - origin.x) <= 1 && abs(back.minY - origin.y) <= 1
    }

    private func forget(_ w: WindowRef) {
        do {
            try ledger.remove(w)
        } catch {
            log.error("Could not remove \(String(describing: w)) from ledger: \(String(describing: error))")
        }
    }
}
