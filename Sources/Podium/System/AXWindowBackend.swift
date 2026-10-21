import AppKit
import ApplicationServices
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// `WindowBackend` over the Accessibility API. Main thread only.
final class AXWindowBackend: WindowBackend {
    private var elements: [WindowRef: AXUIElement] = [:]

    func frame(of w: WindowRef) -> CGRect? {
        element(for: w).flatMap(AX.frame(of:))
    }

    func setOrigin(_ p: CGPoint, of w: WindowRef) -> Bool {
        guard let e = element(for: w) else { return false }
        return AX.setPosition(of: e, to: p)
    }

    /// Every window of every running regular app, parked ones included (they are still alive).
    func liveWindows() -> Set<WindowRef> {
        var live: [WindowRef: AXUIElement] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for (ref, e) in windows(of: app.processIdentifier) { live[ref] = e }
        }
        elements = live
        return Set(live.keys)
    }

    func bundleID(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Standard, non-minimized, non-full-screen windows of `pid`.
    func manageableWindows(of pid: Int32) -> [WindowRef] {
        windows(of: pid).compactMap { ref, e in
            isManageable(role: AX.string(kAXRoleAttribute, of: e),
                         subrole: AX.string(kAXSubroleAttribute, of: e),
                         isFullscreen: AX.bool("AXFullScreen", of: e),
                         isMinimized: AX.bool(kAXMinimizedAttribute, of: e)) ? ref : nil
        }
    }

    private func windows(of pid: Int32) -> [(WindowRef, AXUIElement)] {
        AX.windows(of: pid).compactMap { e in
            AX.windowID(of: e).map { (WindowRef(pid: pid, windowID: $0), e) }
        }
    }

    private func element(for w: WindowRef) -> AXUIElement? {
        if let e = elements[w] { return e }
        for (ref, e) in windows(of: w.pid) { elements[ref] = e }
        return elements[w]
    }
}
