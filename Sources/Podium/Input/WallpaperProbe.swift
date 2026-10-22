import AppKit
import ApplicationServices
import os
import PodiumCore

/// Tells whether a point is bare desktop wallpaper (not a desktop icon, not a window, the
/// Dock, a menu or a widget): one Accessibility hit-test and two attribute reads, made off
/// the main thread so a slow or hung Finder never blocks it.
///
/// The hit-test asks the window server which window takes a click there, so it sees past
/// windows that let clicks through (the Dock's and Podium's full-screen overlays), which a
/// window-list walk would not.
enum WallpaperProbe {
    private static let queue = DispatchQueue(label: "dev.podium.wallpaper-probe", qos: .userInitiated)
    /// One probe at a time; a click while one is running is dropped.
    private static let busy = OSAllocatedUnfairLock(initialState: false)
    /// Upper bound on each attribute read of the hit element.
    private static let readTimeout: Float = 0.25
    private static let logger = Logger(subsystem: "dev.podium.Podium", category: "wallpaper")

    /// Calls `completion` on the main thread, always once, with whether `p` (AX coordinates)
    /// is empty wallpaper. False without asking when Finder is not running or hung, or while
    /// another probe is still running.
    static func check(_ p: CGPoint, completion: @escaping @MainActor (Bool) -> Void) {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        guard let finderPid = finder?.processIdentifier, !AX.isHung(finderPid),
              busy.withLock({ wasBusy in defer { wasBusy = true }; return !wasBusy }) else {
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(false) } }
            return
        }
        queue.async {
            let hit = hitTest(p, finderPid: finderPid)
            busy.withLock { $0 = false }
            let wallpaper = isEmptyWallpaper(hit)
            logger.debug("click at \(Int(p.x), privacy: .public),\(Int(p.y), privacy: .public): role \(hit?.role ?? "none", privacy: .public), window \(hit?.windowRole ?? "none", privacy: .public), wallpaper \(wallpaper, privacy: .public)")
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(wallpaper) } }
        }
    }

    /// The hit-test itself is bounded by the process's default timeout (the minimize tap
    /// lowers it to 50 ms while it runs); the reads by `readTimeout`.
    private static func hitTest(_ p: CGPoint, finderPid: pid_t) -> WallpaperHit? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        guard pid == finderPid else { return WallpaperHit(isFinder: false, role: nil, windowRole: nil) }
        AXUIElementSetMessagingTimeout(element, readTimeout)
        var window: CFTypeRef?
        var windowRole: String?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success,
           let w = window, CFGetTypeID(w) == AXUIElementGetTypeID() {
            let windowElement = w as! AXUIElement
            AXUIElementSetMessagingTimeout(windowElement, readTimeout)
            windowRole = AX.string(kAXRoleAttribute, of: windowElement)
        }
        return WallpaperHit(isFinder: true, role: AX.string(kAXRoleAttribute, of: element), windowRole: windowRole)
    }
}
