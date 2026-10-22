import AppKit
import ApplicationServices
import os
import PodiumCore

/// Tells whether a press was a click on bare desktop wallpaper (not a desktop icon, not a
/// window, the Dock, a menu or a widget, and not a click that only closes a pop-up): a
/// window-list snapshot at mouse-down, then one Accessibility hit-test and two attribute
/// reads after the mouse-up, all on one serial queue off the main thread, so a slow or hung
/// Finder never blocks it.
///
/// The hit-test asks the window server which window takes a click there, so it sees past
/// windows that let clicks through (the Dock's and Podium's full-screen overlays), which a
/// window-list walk would not.
enum WallpaperProbe {
    private static let queue = DispatchQueue(label: "dev.podium.wallpaper-probe", qos: .userInitiated)
    /// Upper bound on each attribute read of the hit element.
    private static let readTimeout: Float = 0.25
    private static let logger = Logger(subsystem: "dev.podium.Podium", category: "wallpaper")
    /// Whether a pop-up was open at the last press's mouse-down. Only touched on `queue`,
    /// where each press's snapshot runs before its own check and after the previous one's.
    nonisolated(unsafe) private static var popUpAtPress = false

    /// A press began on `display` (AX coordinates): notes whether a pop-up (Notification
    /// Center, Control Center, Spotlight, a floating panel) is open there, which the click
    /// would only close. One window-list read, before the click can close it.
    static func pressBegan(display: CGRect) {
        let podium = getpid()
        queue.async {
            popUpAtPress = popUpBlocksWallpaperClick(onScreenWindows(), display: display, podiumPid: podium)
        }
    }

    /// Calls `completion` on the main thread, always once, with whether the press that
    /// ended at `p` (AX coordinates) was a wallpaper click. False without asking when Finder
    /// is not running or hung, or when macOS's own "Click wallpaper to reveal desktop" is
    /// "Always" (both would act on the same click).
    static func check(_ p: CGPoint, completion: @escaping @MainActor (Bool) -> Void) {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        guard let finderPid = finder?.processIdentifier, !AX.isHung(finderPid) else {
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(false) } }
            return
        }
        queue.async {
            let wallpaper: Bool
            if AppleStageManager.revealsDesktopOnWallpaperClick {
                logger.debug("click at \(Int(p.x), privacy: .public),\(Int(p.y), privacy: .public): macOS reveals the desktop itself")
                wallpaper = false
            } else if popUpAtPress {
                logger.debug("click at \(Int(p.x), privacy: .public),\(Int(p.y), privacy: .public): closed a pop-up")
                wallpaper = false
            } else {
                let hit = hitTest(p, finderPid: finderPid)
                wallpaper = isEmptyWallpaper(hit)
                logger.debug("click at \(Int(p.x), privacy: .public),\(Int(p.y), privacy: .public): role \(hit?.role ?? "none", privacy: .public), window \(hit?.windowRole ?? "none", privacy: .public), wallpaper \(wallpaper, privacy: .public)")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(wallpaper) } }
        }
    }

    private static func onScreenWindows() -> [ScreenWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var bundleIDs: [pid_t: String?] = [:]
        return info.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            if bundleIDs[pid] == nil { bundleIDs[pid] = .some(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) }
            return ScreenWindow(pid: pid, bundleID: bundleIDs[pid] ?? nil, layer: layer, bounds: frame,
                                alpha: window[kCGWindowAlpha as String] as? Double ?? 1)
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
