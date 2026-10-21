import CoreGraphics
import os

/// The window server as seen by `WindowMover`. All coordinates are top-left-origin global.
public protocol WindowBackend {
    func frame(of w: WindowRef) -> CGRect?
    func setOrigin(_ p: CGPoint, of w: WindowRef) -> Bool
    func setSize(_ s: CGSize, of w: WindowRef) -> Bool
    /// Every window that still exists, whether or not it can be reached right now.
    func liveWindows() -> Set<WindowRef>
    func bundleID(of pid: Int32) -> String?
    /// Usable frames of the currently attached screens.
    func visibleScreens() -> [CGRect]
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

    /// Parks `w` so only a 1x1 pt corner of it stays on screen, in `display`'s corner.
    /// Returns false, with the window back on stage, if it could not be parked.
    /// An already-parked window keeps its recorded original frame and is moved to
    /// `display`'s corner; if that fails it is unparked.
    public func park(_ w: WindowRef, display: CGRect, displayID: UInt32) -> Bool {
        // Already parked: its current frame is the parked one, never record it as original.
        if entry(for: w) != nil {
            if moveToParking(w, display: display) { return true }
            _ = unpark(w)
            return false
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
        if moveToParking(w, display: display) { return true }

        log.error("Window \(String(describing: w)) did not leave the screen; moving it back")
        if move(w, to: original) {
            forget(w)
        } else {
            // Keep the entry so restoreAll / recovery can still bring it back.
            log.error("Could not move \(String(describing: w)) back; keeping ledger entry")
        }
        return false
    }

    /// Moves `w` back to its original frame, fitted onto the screens attached now.
    /// The ledger entry is removed only once the window reads back there.
    public func unpark(_ w: WindowRef) -> Bool {
        guard let e = entry(for: w) else { return false }
        guard move(w, to: fitted(e.originalFrame, to: backend.visibleScreens())) else {
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
        guard let live = knownLiveWindows() else { return }
        for e in failed where !live.contains(e.window) { forget(e.window) }
    }

    /// Launch-time recovery: puts back every window a previous run left parked, landing
    /// each fully on one of `visibleScreens`.
    public func recover(visibleScreens: [CGRect]) {
        let entries = ledger.entries()
        guard !entries.isEmpty else { return }
        // Liveness unknown: try to restore everything and forget nothing.
        let live = knownLiveWindows() ?? Set(entries.map(\.window))
        let actions = recoveryActions(entries: entries, liveWindows: live, visibleScreens: visibleScreens)
        for action in actions {
            switch action {
            case let .forget(w):
                forget(w)
            case let .restore(w, to: frame):
                if move(w, to: frame) {
                    forget(w)
                } else {
                    log.error("Recovery could not restore \(String(describing: w)); keeping ledger entry")
                }
            }
        }
    }

    /// Moves every parked window to the parking corner of `display` (after a display change).
    /// A window that cannot be parked there is put back on stage.
    public func repark(display: CGRect) {
        for e in ledger.entries() where !moveToParking(e.window, display: display) {
            log.error("Repark of \(String(describing: e.window)) failed; unparking it")
            _ = unpark(e.window)
        }
    }

    // MARK: - Private

    /// nil when liveness is unknown. A logged-in session always has some window (menu
    /// bar, Dock), so an empty answer means the query failed, not that nothing is alive.
    private func knownLiveWindows() -> Set<WindowRef>? {
        let live = backend.liveWindows()
        if live.isEmpty { log.error("Window server reported no live windows; forgetting nothing") }
        return live.isEmpty ? nil : live
    }

    private func entry(for w: WindowRef) -> ParkedEntry? {
        ledger.entries().first { $0.window == w }
    }

    /// Moves to the parking corner, then verifies that in total at most 1x1 pt of the
    /// window is visible, on at most one screen (`display` and every visible screen count).
    private func moveToParking(_ w: WindowRef, display: CGRect) -> Bool {
        guard let current = backend.frame(of: w) else { return false }
        _ = backend.setOrigin(parkingOrigin(for: current.size, display: display), of: w)
        guard let back = backend.frame(of: w) else { return false }

        func overlap(_ screen: CGRect) -> CGRect? {
            let i = back.intersection(screen)
            return i.isNull || i.width <= 0 || i.height <= 0 ? nil : i
        }
        if let onDisplay = overlap(display), onDisplay.width > 1 || onDisplay.height > 1 { return false }
        let shown = backend.visibleScreens().compactMap(overlap)
        let area = shown.reduce(0) { $0 + $1.width * $1.height }
        return shown.count <= 1 && area <= 1 && shown.allSatisfy { $0.width <= 1 && $0.height <= 1 }
    }

    /// Resizes (if needed) and moves to `target`, then verifies the window's origin reads
    /// back within 1 pt of it (apps may round).
    private func move(_ w: WindowRef, to target: CGRect) -> Bool {
        if let current = backend.frame(of: w), current.size != target.size {
            _ = backend.setSize(target.size, of: w)
        }
        _ = backend.setOrigin(target.origin, of: w)
        guard let back = backend.frame(of: w) else { return false }
        return abs(back.minX - target.minX) <= 1 && abs(back.minY - target.minY) <= 1
    }

    private func forget(_ w: WindowRef) {
        do {
            try ledger.remove(w)
        } catch {
            log.error("Could not remove \(String(describing: w)) from ledger: \(String(describing: error))")
        }
    }
}
