import Foundation

/// Reads and writes one boolean preference (the real implementation is CFPreferences on
/// `com.apple.WindowManager`; tests inject a fake so nothing touches the real system).
public protocol StageManagerPreferences: Sendable {
    func bool(forKey key: String) -> Bool?
    func setBool(_ value: Bool, forKey key: String)
    /// Flushes writes; false if they could not be stored.
    func synchronize() -> Bool
}

/// The on/off switch of Apple's Stage Manager, through an injected preferences store.
public struct StageManagerSwitch: Sendable {
    public static let key = "GloballyEnabled"

    private let prefs: StageManagerPreferences

    public init(prefs: StageManagerPreferences) {
        self.prefs = prefs
    }

    /// A missing key means Stage Manager was never turned on.
    public var isEnabled: Bool { prefs.bool(forKey: Self.key) ?? false }

    /// True if the preference reads back `false` afterwards. (Whether the system visibly
    /// reacted is for the caller to check a moment later.)
    @discardableResult
    public func disable() -> Bool { set(false) }

    @discardableResult
    public func enable() -> Bool { set(true) }

    private func set(_ value: Bool) -> Bool {
        prefs.setBool(value, forKey: Self.key)
        guard prefs.synchronize() else { return false }
        return prefs.bool(forKey: Self.key) == value
    }
}
