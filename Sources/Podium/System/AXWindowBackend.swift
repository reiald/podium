import AppKit
import ApplicationServices
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// `WindowBackend` over the Accessibility API. Main thread only.
///
/// An app that just timed out an AX call (`AX.isHung`) is skipped for a few seconds: its
/// windows read as unreachable (no frame, moves refused), so they stay exactly where they
/// are and their ledger entries are kept, without blocking the main thread on each call.
final class AXWindowBackend: WindowBackend {
    private var elements: [WindowRef: AXUIElement] = [:]

    func frame(of w: WindowRef) -> CGRect? {
        element(for: w).flatMap(AX.frame(of:))
    }

    func setOrigin(_ p: CGPoint, of w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return AX.setPosition(of: e, to: p)
    }

    func setSize(_ s: CGSize, of w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return AX.setSize(of: e, to: s)
    }

    /// Every window the window server knows, on every Space, whose process is alive.
    /// Deliberately independent of AX: a window AX cannot reach right now (another
    /// Space, a hung app, a non-regular app) is still alive and must not be forgotten.
    func liveWindows() -> Set<WindowRef> {
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            podiumLog("Podium: CGWindowListCopyWindowInfo failed; reporting no live windows")
            return []
        }
        var pidAlive: [Int32: Bool] = [:]
        var live = Set<WindowRef>()
        for window in info {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let number = window[kCGWindowNumber as String] as? UInt32 else { continue }
            let alive = pidAlive[pid] ?? { let a = Self.isAlive(pid); pidAlive[pid] = a; return a }()
            if alive { live.insert(WindowRef(pid: pid, windowID: number)) }
        }
        // Merge, don't replace: only drop cached elements of windows that are gone.
        elements = elements.filter { live.contains($0.key) }
        return live
    }

    func visibleScreens() -> [CGRect] {
        Screens.all.map(\.visibleFrame)
    }

    func screenFrames() -> [CGRect] {
        Screens.all.map(\.frame)
    }

    func bundleID(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Standard, non-minimized, non-full-screen windows of `pid`.
    func manageableWindows(of pid: Int32) -> [WindowRef] {
        windows(of: pid).compactMap { ref, e in Self.manageable(e) ? ref : nil }
    }

    /// Whether `w` is a standard, non-minimized, non-full-screen window.
    func canManage(_ w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return Self.manageable(e)
    }

    func isMinimized(_ w: WindowRef) -> Bool {
        element(for: w).map { AX.bool(kAXMinimizedAttribute, of: $0) } ?? false
    }

    /// Whether macOS hid the app (Cmd-H, Hide Others). No AX call.
    func isAppHidden(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.isHidden == true
    }

    /// Whether `w` is full screen (or in Split View), on a Space of its own. False when it
    /// can't be read.
    func isFullScreen(_ w: WindowRef) -> Bool {
        element(for: w).map { AX.bool(Self.fullScreenAttribute, of: $0) } ?? false
    }

    /// AXMinimized, or nil when it can't be read (window gone or app not answering).
    func minimizedState(of w: WindowRef) -> Bool? {
        element(for: w).flatMap { AX.optionalBool(kAXMinimizedAttribute, of: $0) }
    }

    /// Sets AXMinimized; false brings a window back from the Dock.
    @discardableResult
    func setMinimized(_ minimized: Bool, of w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return AX.setBool(kAXMinimizedAttribute, minimized, of: e)
    }

    /// Brings `w` to the front of its app's windows.
    @discardableResult
    func raise(_ w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return AX.perform(kAXRaiseAction, on: e)
    }

    static func manageable(_ e: AXUIElement) -> Bool {
        isManageable(role: AX.string(kAXRoleAttribute, of: e),
                     subrole: AX.string(kAXSubroleAttribute, of: e),
                     isFullscreen: AX.bool(fullScreenAttribute, of: e),
                     isMinimized: AX.bool(kAXMinimizedAttribute, of: e))
    }

    private static let fullScreenAttribute = "AXFullScreen"

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func windows(of pid: Int32) -> [(WindowRef, AXUIElement)] {
        AX.windows(of: pid).compactMap { e in
            AX.windowID(of: e).map { (WindowRef(pid: pid, windowID: $0), e) }
        }
    }

    private func element(for w: WindowRef) -> AXUIElement? {
        guard !AX.isHung(w.pid) else { return nil }
        if let e = elements[w] { return e }
        for (ref, e) in windows(of: w.pid) { elements[ref] = e }
        return elements[w]
    }
}
