import AppKit
import ApplicationServices
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

enum WindowEvent {
    case opened(WindowRef)
    case closed(WindowRef)
    case focused(WindowRef)
    case minimized(WindowRef)
    case deminimized(WindowRef)
    case appActivated(Int32)
    case appTerminated(Int32)
}

/// Turns Accessibility and NSWorkspace notifications into `WindowEvent`s.
///
/// One `AXObserver` per running regular app: window created and focused window changed on
/// the app element; destroyed and miniaturized on each window element. All callbacks run on
/// the main run loop.
@MainActor
final class WindowObserver {
    private let onEvent: (WindowEvent) -> Void
    private var apps: [pid_t: AppObservation] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    private final class AppObservation {
        let observer: AXObserver
        let app: AXUIElement
        /// Windows we registered per-window notifications on. A destroyed element can no
        /// longer report its window ID, so it is matched here by CFEqual.
        var windows: [(element: AXUIElement, ref: WindowRef)] = []

        init(observer: AXObserver, app: AXUIElement) {
            self.observer = observer
            self.app = app
        }
    }

    private static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]
    private static let attachRetries = 10
    private static let attachRetryDelay: TimeInterval = 0.5

    init(onEvent: @escaping (WindowEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        for app in NSWorkspace.shared.runningApplications where Self.isObservable(app) {
            // Already-open windows were seeded from the on-screen list; don't re-announce
            // them (that would pull in other Spaces' and hidden apps' windows).
            attach(pid: app.processIdentifier, retriesLeft: Self.attachRetries, announceExisting: false)
        }
        let center = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (NSRunningApplication) -> Void) {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { body(app) }
            })
        }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            guard let self, Self.isObservable(app) else { return }
            self.attach(pid: app.processIdentifier, retriesLeft: Self.attachRetries, announceExisting: true)
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self else { return }
            self.detach(pid: app.processIdentifier)
            self.onEvent(.appTerminated(app.processIdentifier))
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            guard let self, app.processIdentifier != getpid() else { return }
            self.onEvent(.appActivated(app.processIdentifier))
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens = []
        for pid in Array(apps.keys) { detach(pid: pid) }
    }

    private static func isObservable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated
    }

    // MARK: - Per-app observers

    /// Freshly launched apps often refuse AX for a moment, so attaching retries.
    private func attach(pid: pid_t, retriesLeft: Int, announceExisting: Bool) {
        guard apps[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else {
            NSLog("Podium: AXObserverCreate failed for pid %d", pid)
            return
        }
        let app = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for name in Self.appNotifications {
            let err = AXObserverAddNotification(observer, app, name as CFString, refcon)
            if err == .success || err == .notificationAlreadyRegistered {
                attached = true
            } else if retriesLeft == 0 {
                NSLog("Podium: observing %@ for pid %d failed: %d", name, pid, err.rawValue)
            }
        }
        guard attached else {
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachRetryDelay) { [weak self] in
                    MainActor.assumeIsolated { self?.attach(pid: pid, retriesLeft: retriesLeft - 1, announceExisting: announceExisting) }
                }
            } else {
                NSLog("Podium: could not observe pid %d", pid)
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let observation = AppObservation(observer: observer, app: app)
        apps[pid] = observation
        // Subscribe to existing windows; for a just-launched app also report them, since
        // they may have opened before (or while) attaching.
        for e in AX.windows(of: pid) {
            guard let id = AX.windowID(of: e) else { continue }
            let ref = WindowRef(pid: pid, windowID: id)
            registerWindow(e, ref: ref, pid: pid)
            if announceExisting { onEvent(.opened(ref)) }
        }
    }

    private func detach(pid: pid_t) {
        guard let o = apps.removeValue(forKey: pid) else { return }
        for name in Self.appNotifications { AXObserverRemoveNotification(o.observer, o.app, name as CFString) }
        for (e, _) in o.windows {
            for name in Self.windowNotifications { AXObserverRemoveNotification(o.observer, e, name as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o.observer), .defaultMode)
    }

    // MARK: - Notifications

    private static let callback: AXObserverCallback = { _, element, name, refcon in
        guard let refcon else { return }
        let observer = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { observer.received(name as String, element: element) }
    }

    private func received(_ name: String, element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        AX.bounded(element)
        switch name {
        case kAXWindowCreatedNotification:
            windowAppeared(element, pid: pid)
        case kAXFocusedWindowChangedNotification:
            // The element is the newly focused window.
            if let id = AX.windowID(of: element) {
                let ref = WindowRef(pid: pid, windowID: id)
                registerWindow(element, ref: ref, pid: pid)
                onEvent(.focused(ref))
            }
        case kAXUIElementDestroyedNotification:
            guard let o = apps[pid], let i = o.windows.firstIndex(where: { CFEqual($0.element, element) }) else { return }
            let ref = o.windows.remove(at: i).ref
            onEvent(.closed(ref))
        case kAXWindowMiniaturizedNotification:
            if let ref = ref(for: element, pid: pid) { onEvent(.minimized(ref)) }
        case kAXWindowDeminiaturizedNotification:
            if let ref = ref(for: element, pid: pid) { onEvent(.deminimized(ref)) }
        default:
            break
        }
    }

    private func windowAppeared(_ element: AXUIElement, pid: pid_t) {
        guard let id = AX.windowID(of: element) else { return }
        let ref = WindowRef(pid: pid, windowID: id)
        registerWindow(element, ref: ref, pid: pid)
        onEvent(.opened(ref))
    }

    /// Subscribes to a window's own notifications once.
    private func registerWindow(_ element: AXUIElement, ref: WindowRef, pid: pid_t) {
        guard let o = apps[pid], !o.windows.contains(where: { $0.ref == ref }) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            let err = AXObserverAddNotification(o.observer, element, name as CFString, refcon)
            if err != .success && err != .notificationAlreadyRegistered {
                NSLog("Podium: observing %@ on window %u (pid %d) failed: %d", name, ref.windowID, pid, err.rawValue)
            }
        }
        o.windows.append((element, ref))
    }

    private func ref(for element: AXUIElement, pid: pid_t) -> WindowRef? {
        if let id = AX.windowID(of: element) { return WindowRef(pid: pid, windowID: id) }
        return apps[pid]?.windows.first { CFEqual($0.element, element) }?.ref
    }
}
