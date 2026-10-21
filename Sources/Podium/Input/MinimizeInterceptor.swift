import AppKit
import ApplicationServices
import os
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Catches the yellow button and Cmd-M before the app sees them, so a managed window can
/// fly into the strip instead of the Dock (`onIntercept`, called on the main thread).
///
/// An event tap sits in front of all system input, so it is deliberately timid: anything
/// it is not sure about (a slow or failed AX hit-test, a modifier, an unmanaged window, a
/// tap macOS just disabled) passes through untouched.
///
/// The tap runs on its own thread and run loop, so system-wide input never waits on
/// Podium's main thread. That thread only reads the `State` the main thread publishes
/// (`update`) and makes its own bounded AX hit-test; interceptions go to main async.
final class MinimizeInterceptor: @unchecked Sendable {
    /// What the main thread tells the tap. Immutable values, swapped under the lock.
    struct State: Sendable {
        var enabled = false
        var behavior: MinimizeBehavior = .dock
        /// Windows whose minimize may go to the strip (on screen in the active stage).
        var managed: Set<WindowRef> = []
    }

    private let onIntercept: @MainActor (WindowRef) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// When the last Option-click or Command-Option key press happened (tap thread writes).
    private let lastMinimizeAllGesture = OSAllocatedUnfairLock(initialState: -CFTimeInterval.infinity)

    // Main thread only.
    private var thread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var finished: DispatchSemaphore?

    /// Written by the tap thread before it signals ready; read by main after the wait.
    private var startedRunLoop: CFRunLoop?

    // Tap thread only.
    private var tap: CFMachPort?
    private var systemWide: AXUIElement?
    /// False after macOS disabled the tap; true again once a callback finishes quickly.
    private var healthy = true
    /// The last left mouse-down was swallowed; its mouse-up must be swallowed too.
    private var swallowedMouseDown = false
    /// Physical key of the last swallowed Cmd-M; its autorepeats are swallowed too.
    private var swallowedKeyCode: Int64?

    /// Upper bound on an AX call made inside the callback.
    static let hitTestTimeout: Float = 0.05
    /// A callback this fast marks an unhealthy tap healthy again.
    static let healthyCallbackTime: CFTimeInterval = 0.005

    init(onIntercept: @escaping @MainActor (WindowRef) -> Void) {
        self.onIntercept = onIntercept
    }

    /// Publishes what the tap may intercept. Call on every board or setting change.
    func update(_ new: State) {
        state.withLock { $0 = new }
    }

    /// Whether an Option-click or Option-Cmd-M happened in the last `seconds`. Such a
    /// gesture may be macOS's "minimize all", whose minimizes must stay in the Dock. Recorded
    /// without any AX work, so any Option-click counts; erring toward the Dock is safe.
    func minimizeAllGesture(within seconds: CFTimeInterval) -> Bool {
        CACurrentMediaTime() - lastMinimizeAllGesture.withLock { $0 } < seconds
    }

    /// Starts the tap thread. Only with Accessibility granted; without a tap, minimizes go
    /// to the Dock and the Coordinator's un-minimize fallback still applies.
    @MainActor
    func start() {
        guard thread == nil else { return }
        guard AXIsProcessTrusted() else {
            NSLog("Podium: not trusted for Accessibility; minimize interceptor off")
            return
        }
        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        startedRunLoop = nil
        // The thread holds `self` until the tap is invalidated, so the unretained refcon
        // never outlives the interceptor.
        let thread = Thread { [self] in
            runTap(ready: ready)
            finished.signal()
        }
        thread.name = "Podium minimize tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard let runLoop = startedRunLoop else { return }
        self.thread = thread
        self.finished = finished
        tapRunLoop = runLoop
    }

    /// Stops the tap; all input reaches apps directly again.
    @MainActor
    func stop() {
        guard let runLoop = tapRunLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
        CFRunLoopWakeUp(runLoop)
        // A callback can be inside a hit-test (bounded at a few tenths of a second).
        if finished?.wait(timeout: .now() + 1) == .timedOut {
            NSLog("Podium: minimize tap thread did not stop within 1 s")
        }
        tapRunLoop = nil
        thread = nil
        finished = nil
    }

    // MARK: - Tap thread

    /// Creates the tap on the current thread, signals `ready` (with `startedRunLoop` set on
    /// success), runs until stopped, then tears down.
    private func runTap(ready: DispatchSemaphore) {
        // Apple: a timeout set on a system-wide element is this process's global default,
        // for every element without its own (Podium's carry their own: `AX.bounded`).
        // 0 restores the default when the tap stops.
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.hitTestTimeout)
        self.systemWide = systemWide
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("Podium: could not create the minimize event tap; minimizes go to the Dock")
            AXUIElementSetMessagingTimeout(systemWide, 0)
            ready.signal()
            return
        }
        let runLoop = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        healthy = true
        startedRunLoop = runLoop
        ready.signal()

        CFRunLoopRun()

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        CFMachPortInvalidate(tap)
        self.tap = nil
        AXUIElementSetMessagingTimeout(systemWide, 0)
        self.systemWide = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<MinimizeInterceptor>.fromOpaque(refcon).takeUnretainedValue()
        return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
    }

    private enum Outcome {
        case pass, swallow
        case intercept(WindowRef)
    }

    /// True to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            NSLog("Podium: minimize tap disabled (%u); re-enabling, passing through until healthy", type.rawValue)
            healthy = false
            swallowedMouseDown = false
            swallowedKeyCode = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseUp:
            // Only the partner of a swallowed mouse-down; never any other mouse-up.
            let swallow = swallowedMouseDown
            swallowedMouseDown = false
            return swallow
        case .leftMouseDown, .keyDown:
            let started = CACurrentMediaTime()
            let wasHealthy = healthy
            let snapshot = state.withLock { $0 }
            let outcome = type == .leftMouseDown ? mouseDown(event, snapshot, tapHealthy: wasHealthy)
                                                 : keyDown(event, snapshot, tapHealthy: wasHealthy)
            if !wasHealthy, CACurrentMediaTime() - started < Self.healthyCallbackTime {
                healthy = true
                NSLog("Podium: minimize tap healthy again")
            }
            switch outcome {
            case .pass:
                return false
            case .swallow:
                return true
            case let .intercept(w):
                let onIntercept = self.onIntercept
                DispatchQueue.main.async { MainActor.assumeIsolated { onIntercept(w) } }
                return true
            }
        default:
            return false
        }
    }

    /// Intercepts a plain click on a managed window's enabled minimize button.
    private func mouseDown(_ event: CGEvent, _ s: State, tapHealthy: Bool) -> Outcome {
        // A new press ends any earlier pair (its mouse-up may have been lost).
        swallowedMouseDown = false
        let modifiers = Self.modifiers(event.flags)
        if modifiers == .option { lastMinimizeAllGesture.withLock { $0 = CACurrentMediaTime() } }
        // Skip the hit-test when nothing could be intercepted anyway.
        guard s.enabled, !s.managed.isEmpty, let systemWide,
              decideMinimize(.mouseDown(subrole: "AXMinimizeButton", modifiers: modifiers), behavior: s.behavior,
                             tapHealthy: tapHealthy, frontWindowManaged: true) == .intercept else { return .pass }
        let p = event.location
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &hit) == .success,
              let button = hit else { return .pass }
        AXUIElementSetMessagingTimeout(button, Self.hitTestTimeout)
        let subrole = AX.string(kAXSubroleAttribute, of: button)
        // A disabled button does nothing in the app either; a failed read counts as disabled.
        guard subrole == "AXMinimizeButton", AX.bool(kAXEnabledAttribute, of: button),
              let window = Self.element(kAXWindowAttribute, of: button),
              let ref = Self.ref(of: window) else { return .pass }
        let decision = decideMinimize(.mouseDown(subrole: subrole, modifiers: modifiers), behavior: s.behavior,
                                      tapHealthy: tapHealthy, frontWindowManaged: s.managed.contains(ref))
        guard decision == .intercept else { return .pass }
        swallowedMouseDown = true
        return .intercept(ref)
    }

    /// Intercepts Cmd-M (by the character typed, so any keyboard layout) on a managed
    /// focused window.
    private func keyDown(_ event: CGEvent, _ s: State, tapHealthy: Bool) -> Outcome {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            // Holding Cmd-M: repeats of an intercepted press do nothing; others pass.
            return swallowedKeyCode == keyCode ? .swallow : .pass
        }
        swallowedKeyCode = nil
        let modifiers = Self.modifiers(event.flags)
        // Option changes the typed character ("µ"), so any Command-Option key counts here.
        if modifiers == [.command, .option] { lastMinimizeAllGesture.withLock { $0 = CACurrentMediaTime() } }
        guard modifiers == .command, s.enabled, !s.managed.isEmpty, let systemWide else { return .pass }
        let trigger = MinimizeTrigger.keyDown(keyCode: UInt16(truncatingIfNeeded: keyCode),
                                              characters: Self.characters(event), modifiers: modifiers)
        guard decideMinimize(trigger, behavior: s.behavior, tapHealthy: tapHealthy,
                             frontWindowManaged: true) == .intercept,
              let app = Self.element(kAXFocusedApplicationAttribute, of: systemWide),
              let window = Self.element(kAXFocusedWindowAttribute, of: app), let ref = Self.ref(of: window),
              decideMinimize(trigger, behavior: s.behavior, tapHealthy: tapHealthy,
                             frontWindowManaged: s.managed.contains(ref)) == .intercept else { return .pass }
        swallowedKeyCode = keyCode
        return .intercept(ref)
    }

    // MARK: - Helpers

    private static func modifiers(_ flags: CGEventFlags) -> ModifierSet {
        var m: ModifierSet = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskControl) { m.insert(.control) }
        return m
    }

    /// The characters the key types in the current layout (Command doesn't change them).
    private static func characters(_ event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length,
                                       unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: min(length, buffer.count))
    }

    /// An element-valued attribute, bounded by `hitTestTimeout`.
    private static func element(_ attribute: String, of e: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let element = v as! AXUIElement
        AXUIElementSetMessagingTimeout(element, hitTestTimeout)
        return element
    }

    private static func ref(of window: AXUIElement) -> WindowRef? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, let id = AX.windowID(of: window) else { return nil }
        return WindowRef(pid: pid, windowID: id)
    }
}
