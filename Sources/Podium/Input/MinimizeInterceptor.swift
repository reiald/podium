import AppKit
import ApplicationServices
import os
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Catches the yellow button and Cmd-M before the app sees them, so a managed window can
/// fly into the strip instead of the Dock (`onIntercept`, called on the main thread). With
/// the Dock-click setting on, a plain click on the frontmost app's Dock icon sends that app's
/// on-stage windows to the strip, or brings them back from it (`onDockClick`). That press is swallowed but decided only
/// when it ends (`DockPress`): a drag or press-and-hold is replayed to the Dock untouched.
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
        /// Apps with a window in the strip (off stage, not in the Dock).
        var inStrip: Set<pid_t> = []
        /// "Click an app's Dock icon to minimize it to the strip".
        var dockClickEnabled = false
        /// The frontmost app and its bundle.
        var frontmostPid: pid_t?
        var frontmostURL: URL?
        var frontmostBundleID: String?
    }

    private let onIntercept: @MainActor (WindowRef) -> Void
    private let onDockClick: @MainActor (pid_t) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Where a click may land on a Dock icon (`dockClickGate`); refreshed on main by
    /// `refreshDockFrame`, read by the tap. Nil: unknown, so no Dock click is intercepted.
    private let dockGate = OSAllocatedUnfairLock<CGRect?>(initialState: nil)
    /// When the last Option-click or Command-Option key press happened (tap thread writes).
    private let lastMinimizeAllGesture = OSAllocatedUnfairLock(initialState: -CFTimeInterval.infinity)

    // Main thread only.
    private var thread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var finished: DispatchSemaphore?
    private var dockFrameTimer: Timer?
    private var dockFrameReading = false

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
    /// The swallowed press on the frontmost app's Dock icon, until it is a click or replayed.
    private var dockPress = DockPress()
    /// That press's app and mouse-down (re-posted if it turns out not to be a click).
    private var dockPressPid: pid_t?
    private var dockPressDown: CGEvent?
    /// Replays the press once it is held for `DockPress.holdTime` (the Dock's icon menu).
    private var dockHoldTimer: CFRunLoopTimer?

    /// Marks events Podium re-posts (`eventSourceUserData`), so the tap never touches them.
    private static let replayTag: Int64 = 0x506F_6469_756D   // "Podium"

    /// Upper bound on an AX call made inside the callback.
    static let hitTestTimeout: Float = 0.05
    /// How often the Dock's frame is re-read while the Dock-click setting is on (it moves when
    /// apps launch or quit, or the Dock is resized).
    static let dockFrameRefresh: TimeInterval = 2
    /// A callback this fast marks an unhealthy tap healthy again.
    static let healthyCallbackTime: CFTimeInterval = 0.005

    init(onIntercept: @escaping @MainActor (WindowRef) -> Void, onDockClick: @escaping @MainActor (pid_t) -> Void) {
        self.onIntercept = onIntercept
        self.onDockClick = onDockClick
    }

    /// Publishes what the tap may intercept. Call on every board or setting change.
    @MainActor
    func update(_ new: State) {
        let wasDockClick = state.withLock { s -> Bool in
            defer { s = new }
            return s.dockClickEnabled
        }
        if new.dockClickEnabled, !wasDockClick { refreshDockFrame() }
    }

    /// Re-reads where the Dock's icons are (off the main thread; one AX read of the Dock),
    /// only while the Dock-click setting is on. Call on screen changes too.
    @MainActor
    func refreshDockFrame() {
        guard tapRunLoop != nil, state.withLock({ $0.dockClickEnabled }), !dockFrameReading,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        dockFrameReading = true
        let pid = dock.processIdentifier
        DispatchQueue.global(qos: .utility).async { [self] in
            let frame = Self.dockListFrame(pid: pid)
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    dockFrameReading = false
                    let gate = frame.flatMap { dockClickGate(listFrame: $0, screens: Screens.all.map(\.frame)) }
                    dockGate.withLock { $0 = gate }
                }
            }
        }
    }

    /// The frame of the Dock's icon list (`AXList`), in AX coordinates.
    private static func dockListFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, dockReadTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            AXUIElementSetMessagingTimeout(child, dockReadTimeout)
            if AX.string(kAXRoleAttribute, of: child) == kAXListRole, let frame = AX.frame(of: child) { return frame }
        }
        return nil
    }

    /// Upper bound on each AX call reading the Dock's frame (off the main thread).
    private static let dockReadTimeout: Float = 0.25

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
            podiumLog("Podium: not trusted for Accessibility; minimize interceptor off")
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
        dockFrameTimer = Timer.scheduledTimer(withTimeInterval: Self.dockFrameRefresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDockFrame() }
        }
        refreshDockFrame()
    }

    /// Stops the tap; all input reaches apps directly again.
    @MainActor
    func stop() {
        dockFrameTimer?.invalidate()
        dockFrameTimer = nil
        guard let runLoop = tapRunLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
        CFRunLoopWakeUp(runLoop)
        // A callback can be inside a hit-test (bounded at a few tenths of a second).
        if finished?.wait(timeout: .now() + 1) == .timedOut {
            podiumLog("Podium: minimize tap thread did not stop within 1 s")
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
            | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            podiumLog("Podium: could not create the minimize event tap; minimizes go to the Dock")
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

        endDockPress()
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
        /// A press on the frontmost app's Dock icon began (swallowed, decided later).
        case dockPress(pid_t)
    }

    /// True to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type != .tapDisabledByTimeout, type != .tapDisabledByUserInput,
           event.getIntegerValueField(.eventSourceUserData) == Self.replayTag { return false }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            podiumLog("Podium: minimize tap disabled (%u); re-enabling, passing through until healthy", type.rawValue)
            healthy = false
            swallowedMouseDown = false
            swallowedKeyCode = nil
            dockPress.reset()
            endDockPress()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDragged:
            return dockPressStep(dockPress.dragged(to: event.location, time: CACurrentMediaTime()), event)
        case .leftMouseUp:
            let step = dockPress.released(at: event.location, time: CACurrentMediaTime())
            if step != .pass { return dockPressStep(step, event) }
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
                podiumLog("Podium: minimize tap healthy again")
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
            case let .dockPress(pid):
                beginDockPress(event, pid: pid)
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
        dockPress.reset()
        endDockPress()
        let modifiers = Self.modifiers(event.flags)
        if modifiers == .option { lastMinimizeAllGesture.withLock { $0 = CACurrentMediaTime() } }
        var dockHit: AXUIElement?
        switch dockClick(event, s, modifiers: modifiers, tapHealthy: tapHealthy) {
        case .notInDock: break
        case let .notDockItem(element): dockHit = element
        case let .decided(outcome): return outcome
        }
        // Skip the hit-test when nothing could be intercepted anyway.
        guard s.enabled, !s.managed.isEmpty, let systemWide,
              decideMinimize(.mouseDown(subrole: "AXMinimizeButton", modifiers: modifiers), behavior: s.behavior,
                             tapHealthy: tapHealthy, frontWindowManaged: true) == .intercept else { return .pass }
        let p = event.location
        // The Dock check may already have hit-tested this point (a window under the Dock's slack).
        var hit = dockHit
        if hit == nil {
            guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &hit) == .success else { return .pass }
            if let hit { AXUIElementSetMessagingTimeout(hit, Self.hitTestTimeout) }
        }
        guard let button = hit else { return .pass }
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

    private enum DockHit {
        /// Outside the Dock's icon area, or the setting can't apply: no AX work was done.
        case notInDock
        /// Hit-tested, but not a Dock item (e.g. a window under the area's slack).
        case notDockItem(AXUIElement)
        case decided(Outcome)
    }

    /// A press inside the Dock's icon area, when the Dock-click setting could apply: a plain
    /// press on the frontmost app's own icon starts a `DockPress`; any other item passes.
    private func dockClick(_ event: CGEvent, _ s: State, modifiers: ModifierSet, tapHealthy: Bool) -> DockHit {
        let p = event.location
        let onBoard = s.frontmostPid.map { pid in s.managed.contains { $0.pid == pid } || s.inStrip.contains(pid) } ?? false
        guard s.dockClickEnabled, modifiers.isEmpty, tapHealthy, let pid = s.frontmostPid,
              let front = s.frontmostURL, let systemWide, onBoard,
              dockGate.withLock({ $0?.contains(p) }) == true else { return .notInDock }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &hit) == .success,
              let item = hit else { return .decided(.pass) }
        AXUIElementSetMessagingTimeout(item, Self.hitTestTimeout)
        let role = AX.string(kAXRoleAttribute, of: item)
        // Only a Dock item is worth the remaining reads.
        guard role == "AXDockItem" else { return .notDockItem(item) }
        let click = DockClick(modifiers: modifiers, role: role, subrole: AX.string(kAXSubroleAttribute, of: item),
                              itemURL: Self.url(kAXURLAttribute, of: item))
        guard decideDockClick(click, enabled: s.dockClickEnabled, tapHealthy: tapHealthy, frontmostAppURL: front,
                              frontmostBundleID: s.frontmostBundleID,
                              frontmostAppHasWindowOnBoard: onBoard,
                              bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier }) == .intercept
        else { return .decided(.pass) }
        return .decided(.dockPress(pid))
    }

    // MARK: - Dock press

    /// The mouse-down was swallowed: keep it, and replay it if the press is held.
    private func beginDockPress(_ down: CGEvent, pid: pid_t) {
        dockPressDown = down.copy()
        dockPressPid = pid
        dockPress.began(at: down.location, time: CACurrentMediaTime())
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + DockPress.holdTime,
                                                    0, 0, 0) { [weak self] _ in
            guard let self else { return }
            _ = self.dockPressStep(self.dockPress.holdElapsed(), nil)
        }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        dockHoldTimer = timer
    }

    /// Applies a `DockPress` step to `event` (nil: the hold timer fired). True to swallow it.
    private func dockPressStep(_ step: DockPress.Step, _ event: CGEvent?) -> Bool {
        switch step {
        case .pass:
            return false
        case .swallow:
            return true
        case .act:
            let pid = dockPressPid
            endDockPress()
            if let pid {
                let onDockClick = self.onDockClick
                DispatchQueue.main.async { MainActor.assumeIsolated { onDockClick(pid) } }
            }
            return true
        case .replay:
            // The Dock gets the press after all: the saved mouse-down, then this event, in
            // that order and past this tap; the rest of the gesture passes through.
            let down = dockPressDown
            endDockPress()
            for e in [down, event?.copy()].compactMap({ $0 }) {
                e.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
                e.post(tap: .cgAnnotatedSessionEventTap)
            }
            return event != nil
        }
    }

    /// Forgets the saved mouse-down and stops the hold timer.
    private func endDockPress() {
        if let t = dockHoldTimer { CFRunLoopTimerInvalidate(t) }
        dockHoldTimer = nil
        dockPressDown = nil
        dockPressPid = nil
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

    /// A URL-valued attribute (bounded by the element's own timeout).
    private static func url(_ attribute: String, of e: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == CFURLGetTypeID() else { return nil }
        return (v as! CFURL) as URL
    }

    private static func ref(of window: AXUIElement) -> WindowRef? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, let id = AX.windowID(of: window) else { return nil }
        return WindowRef(pid: pid, windowID: id)
    }
}
