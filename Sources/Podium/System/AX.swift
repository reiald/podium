import ApplicationServices
import CoreGraphics
import Foundation
import os
import PodiumCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Accessibility helpers. AX coordinates: origin at the top-left of the primary display.
///
/// Every call goes through `timed`: a main-thread call that times out (a hung app) trips a
/// per-app circuit breaker, and callers skip that app (`isHung`) for `hungCooldown` seconds
/// instead of blocking the main thread a second per call.
enum AX {
    /// Upper bound on how long one AX call may block on an unresponsive app.
    static let messagingTimeout: Float = 1.0
    /// How long an app whose AX call timed out is left alone.
    static let hungCooldown: TimeInterval = 5

    private static let hung = OSAllocatedUnfairLock(initialState: CircuitBreaker<pid_t>(cooldown: hungCooldown))

    /// Whether `pid` timed out an AX call within the last `hungCooldown` seconds.
    static func isHung(_ pid: pid_t) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return hung.withLock { $0.isOpen(pid, now: now) }
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// Gives `e` its own `messagingTimeout`. Elements without one use the global default,
    /// which the minimize interceptor lowers to a few milliseconds for its hit-tests.
    @discardableResult
    static func bounded(_ e: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(e, messagingTimeout)
        return e
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        guard copy(application(pid), kAXWindowsAttribute, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map(bounded)
    }

    /// The app's focused window, if it has one.
    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard copy(application(pid), kAXFocusedWindowAttribute, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return bounded(v as! AXUIElement)
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard copy(window, kAXPositionAttribute, &p) == .success,
              copy(window, kAXSizeAttribute, &s) == .success,
              let pv = p, let sv = s,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setPosition(of window: AXUIElement, to point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return timed(window) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) } == .success
    }

    @discardableResult
    static func setSize(of window: AXUIElement, to size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return timed(window) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) } == .success
    }

    static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard copy(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    @discardableResult
    static func setBool(_ attribute: String, _ value: Bool, of element: AXUIElement) -> Bool {
        timed(element) { AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) } == .success
    }

    static func bool(_ attribute: String, of element: AXUIElement) -> Bool {
        optionalBool(attribute, of: element) ?? false
    }

    /// The attribute, or nil when it can't be read.
    static func optionalBool(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard copy(element, attribute, &value) == .success else { return nil }
        return value as? Bool
    }

    @discardableResult
    static func perform(_ action: String, on element: AXUIElement) -> Bool {
        timed(element) { AXUIElementPerformAction(element, action as CFString) } == .success
    }

    // MARK: - Timeouts

    private static func copy(_ e: AXUIElement, _ attribute: String, _ value: inout CFTypeRef?) -> AXError {
        timed(e) { AXUIElementCopyAttributeValue(e, attribute as CFString, &value) }
    }

    /// Runs one AX call. A main-thread call that fails with `.cannotComplete` after taking at
    /// least half the messaging timeout timed out: its app is marked hung. (The tap thread's
    /// hit-tests use a much shorter timeout and never trip the breaker.)
    private static func timed(_ e: AXUIElement, _ call: () -> AXError) -> AXError {
        let start = ProcessInfo.processInfo.systemUptime
        let err = call()
        guard err == .cannotComplete, Thread.isMainThread else { return err }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - start >= TimeInterval(messagingTimeout) / 2 else { return err }
        var owner: pid_t = 0
        guard AXUIElementGetPid(e, &owner) == .success else { return err }
        let pid = owner
        let wasHung = hung.withLock { breaker -> Bool in
            let was = breaker.isOpen(pid, now: now)
            breaker.trip(pid, now: now)
            return was
        }
        if !wasHung {
            podiumLog("Podium: pid %d did not answer Accessibility within %.1f s; leaving its windows alone for %.0f s",
                  pid, messagingTimeout, hungCooldown)
        }
        return err
    }
}
