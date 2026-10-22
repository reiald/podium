import AppKit
import Carbon.HIToolbox
import os

/// One system-wide hotkey through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission. Fixed to ⌃⌥⌘P.
@MainActor
final class HotKey {
    /// Shown in Settings and as the menu item's key equivalent.
    static let display = "⌃⌥⌘P"
    static let keyEquivalent = "p"
    static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .command]

    private static let logger = Logger(subsystem: "dev.podium.Podium", category: "settings")
    private static let signature: OSType = 0x5044_4D31 // "PDM1"
    /// The handler is a C callback; it reaches the action through this.
    private static var current: HotKey?

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var isRegistered: Bool { hotKeyRef != nil }

    /// Registers ⌃⌥⌘P; false (and logged) when another app already holds it.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { HotKey.current?.action() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
            guard status == noErr else {
                Self.logger.error("Hotkey handler install failed: \(status, privacy: .public)")
                return false
            }
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            hotKeyRef = nil
            Self.logger.error("Registering \(Self.display, privacy: .public) failed (\(status, privacy: .public)); another app may use it")
            return false
        }
        Self.current = self
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if Self.current === self { Self.current = nil }
    }
}
