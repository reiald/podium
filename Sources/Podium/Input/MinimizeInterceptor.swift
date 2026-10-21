import AppKit
import ApplicationServices
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Catches the yellow button and Cmd-M before the app sees them, so a managed window can
/// fly into the strip instead of the Dock (`onIntercept`).
///
/// An event tap sits in front of all system input, so it is deliberately timid: anything
/// it is not sure about (a slow or failed AX hit-test, a modifier, an unmanaged window, a
/// tap macOS just disabled) passes through untouched. The callback runs on the main run
/// loop and only does a bounded AX hit-test plus `decideMinimize`; the actual parking is
/// dispatched to the next main-loop turn.
@MainActor
final class MinimizeInterceptor {
    private let behavior: () -> MinimizeBehavior
    private let isManaged: (WindowRef) -> Bool
    private let onIntercept: (WindowRef) -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// False after macOS disabled the tap; true again once a callback finishes quickly.
    private var healthy = true
    /// The last left mouse-down was swallowed; its mouse-up must be swallowed too.
    private var swallowedMouseDown = false
    /// The last Cmd-M was swallowed; its key repeats are swallowed too.
    private var swallowedKeyDown = false
    private let systemWide: AXUIElement
    /// When the last Option-click or Option-Cmd-M (minimize all, passed to macOS) happened.
    private var lastMinimizeAllGesture: CFTimeInterval = -.infinity

    /// Upper bound on an AX call made inside the callback.
    static let hitTestTimeout: Float = 0.05
    /// A callback this fast marks an unhealthy tap healthy again.
    static let healthyCallbackTime: CFTimeInterval = 0.005
    private static let mKeyCode: Int64 = 46

    init(behavior: @escaping () -> MinimizeBehavior, isManaged: @escaping (WindowRef) -> Bool,
         onIntercept: @escaping (WindowRef) -> Void) {
        self.behavior = behavior
        self.isManaged = isManaged
        self.onIntercept = onIntercept
        systemWide = AXUIElementCreateSystemWide()
    }

    /// Installs the tap. Only with Accessibility granted; without a tap, minimizes go to
    /// the Dock and the Coordinator's un-minimize fallback still applies.
    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            NSLog("Podium: not trusted for Accessibility; minimize interceptor off")
            return
        }
        // Note: on the system-wide element this is the default for every AX element that
        // has no timeout of its own (see `AX.bounded`).
        AXUIElementSetMessagingTimeout(systemWide, Self.hitTestTimeout)
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("Podium: could not create the minimize event tap; minimizes go to the Dock")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        healthy = true
        swallowedMouseDown = false
        swallowedKeyDown = false
    }

    /// Removes the tap; all input reaches apps directly again.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowedMouseDown = false
        swallowedKeyDown = false
    }

    /// Whether an Option-click or Option-Cmd-M happened in the last `seconds`. Such a
    /// gesture may be macOS's "minimize all", whose minimizes must stay in the Dock. Recorded
    /// without any AX work, so any Option-click counts; erring toward the Dock is safe.
    func minimizeAllGesture(within seconds: CFTimeInterval) -> Bool {
        CACurrentMediaTime() - lastMinimizeAllGesture < seconds
    }

    // MARK: - Callback

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<MinimizeInterceptor>.fromOpaque(refcon).takeUnretainedValue()
        let swallow = MainActor.assumeIsolated { me.handle(type, event) }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// True to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            NSLog("Podium: minimize tap disabled (%u); re-enabling, passing through until healthy", type.rawValue)
            healthy = false
            swallowedMouseDown = false
            swallowedKeyDown = false
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
            let outcome = type == .leftMouseDown ? mouseDown(event, tapHealthy: wasHealthy)
                                                 : keyDown(event, tapHealthy: wasHealthy)
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
                DispatchQueue.main.async { onIntercept(w) }
                return true
            }
        default:
            return false
        }
    }

    private enum Outcome {
        case pass, swallow
        case intercept(WindowRef)
    }

    /// Intercepts a plain click on a managed window's minimize button.
    private func mouseDown(_ event: CGEvent, tapHealthy: Bool) -> Outcome {
        // A new press ends any earlier pair (its mouse-up may have been lost).
        swallowedMouseDown = false
        let modifiers = Self.modifiers(event.flags)
        if modifiers == .option { lastMinimizeAllGesture = CACurrentMediaTime() }
        // Skip the hit-test when nothing could be intercepted anyway.
        guard decideMinimize(.mouseDown(subrole: "AXMinimizeButton", modifiers: modifiers), behavior: behavior(),
                             tapHealthy: tapHealthy, frontWindowManaged: true) == .intercept else { return .pass }
        let p = event.location
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &hit) == .success,
              let button = hit else { return .pass }
        AXUIElementSetMessagingTimeout(button, Self.hitTestTimeout)
        let subrole = AX.string(kAXSubroleAttribute, of: button)
        guard subrole == "AXMinimizeButton", let window = Self.element(kAXWindowAttribute, of: button),
              let ref = Self.ref(of: window) else { return .pass }
        let decision = decideMinimize(.mouseDown(subrole: subrole, modifiers: modifiers), behavior: behavior(),
                                      tapHealthy: tapHealthy, frontWindowManaged: isManaged(ref))
        guard decision == .intercept else { return .pass }
        swallowedMouseDown = true
        return .intercept(ref)
    }

    /// Intercepts Cmd-M on a managed focused window.
    private func keyDown(_ event: CGEvent, tapHealthy: Bool) -> Outcome {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            // Holding Cmd-M: repeats of an intercepted press do nothing; others pass.
            return swallowedKeyDown && keyCode == Self.mKeyCode ? .swallow : .pass
        }
        swallowedKeyDown = false
        let modifiers = Self.modifiers(event.flags)
        if keyCode == Self.mKeyCode, modifiers == [.command, .option] { lastMinimizeAllGesture = CACurrentMediaTime() }
        let trigger = MinimizeTrigger.keyDown(keyCode: UInt16(truncatingIfNeeded: keyCode), modifiers: modifiers)
        guard decideMinimize(trigger, behavior: behavior(), tapHealthy: tapHealthy,
                             frontWindowManaged: true) == .intercept else { return .pass }
        guard let app = Self.element(kAXFocusedApplicationAttribute, of: systemWide) else { return .pass }
        AXUIElementSetMessagingTimeout(app, Self.hitTestTimeout)
        guard let window = Self.element(kAXFocusedWindowAttribute, of: app), let ref = Self.ref(of: window),
              decideMinimize(trigger, behavior: behavior(), tapHealthy: tapHealthy,
                             frontWindowManaged: isManaged(ref)) == .intercept else { return .pass }
        swallowedKeyDown = true
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
