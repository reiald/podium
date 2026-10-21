import Foundation

/// What a minimize gesture does: slide the window into the strip, or leave it to macOS.
public enum MinimizeBehavior: String, Codable, Sendable {
    case strip, dock
}

public struct ModifierSet: OptionSet, Equatable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let control = ModifierSet(rawValue: 1 << 3)
}

public enum MinimizeTrigger: Equatable, Sendable {
    case mouseDown(subrole: String?, modifiers: ModifierSet)
    /// `characters`: what the key types ignoring modifiers (layout-aware); `keyCode` is the
    /// physical key, informational only (key 46 is "m" on US but "," on AZERTY).
    case keyDown(keyCode: UInt16, characters: String?, modifiers: ModifierSet)
}

public enum MinimizeDecision: Equatable, Sendable {
    case intercept, passThrough
}

/// Intercept only clear minimize gestures on a managed window with a healthy event tap.
/// Anything else passes through to macOS. When in doubt, pass through.
public func decideMinimize(_ t: MinimizeTrigger, behavior: MinimizeBehavior,
                           tapHealthy: Bool, frontWindowManaged: Bool) -> MinimizeDecision {
    guard behavior == .strip, tapHealthy, frontWindowManaged else { return .passThrough }

    switch t {
    case let .mouseDown(subrole, modifiers):
        return subrole == "AXMinimizeButton" && modifiers.isEmpty ? .intercept : .passThrough
    case let .keyDown(_, characters, modifiers):
        return characters?.lowercased() == "m" && modifiers == .command ? .intercept : .passThrough
    }
}
