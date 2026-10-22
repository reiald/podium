import CoreGraphics
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

/// A left mouse-down on the Dock, as the event tap's hit-test saw it.
public struct DockClick: Equatable, Sendable {
    public var modifiers: ModifierSet
    public var role: String?
    public var subrole: String?
    /// The clicked item's URL (an app item's bundle).
    public var itemURL: URL?

    public init(modifiers: ModifierSet, role: String?, subrole: String?, itemURL: URL?) {
        self.modifiers = modifiers
        self.role = role
        self.subrole = subrole
        self.itemURL = itemURL
    }
}

/// "Click an app's Dock icon to minimize it to the strip": intercept only a plain click on
/// the frontmost app's own Dock item while that app has a window on the active stage, with
/// the setting on and a healthy tap. Anything else (another app's item, a folder or the
/// Trash, a modifier, an app with nothing on stage) passes through to the Dock.
public func decideDockClick(_ c: DockClick, enabled: Bool, tapHealthy: Bool,
                            frontmostAppURL: URL?, frontmostAppHasWindowOnStage: Bool) -> MinimizeDecision {
    guard enabled, tapHealthy, frontmostAppHasWindowOnStage, c.modifiers.isEmpty,
          c.role == "AXDockItem", c.subrole == "AXApplicationDockItem",
          let item = c.itemURL, let front = frontmostAppURL,
          sameBundle(item, front) else { return .passThrough }
    return .intercept
}

/// File URLs naming the same path ("Safari.app/" and "Safari.app" alike).
func sameBundle(_ a: URL, _ b: URL) -> Bool {
    guard a.isFileURL, b.isFileURL else { return false }
    let pa = a.standardizedFileURL.path, pb = b.standardizedFileURL.path
    return !pa.isEmpty && pa == pb
}

/// Where a click may be on the Dock's icons, so the tap hit-tests only there: the Dock's
/// icon list (`listFrame`, top-left global coordinates) moved onto the screen it hugs (an
/// auto-hidden Dock can report a frame slid off screen) and grown by its own thickness
/// (at least `minSlack`) for magnified icons, clipped to that screen. Nil when unknown.
public func dockClickGate(listFrame: CGRect, screens: [CGRect], minSlack: CGFloat = 64) -> CGRect? {
    guard !listFrame.isNull, !listFrame.isEmpty, !screens.isEmpty else { return nil }
    func clamped(into s: CGRect) -> CGRect {
        let w = min(listFrame.width, s.width), h = min(listFrame.height, s.height)
        let x = min(max(listFrame.minX, s.minX), s.maxX - w)
        let y = min(max(listFrame.minY, s.minY), s.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    func displacement(_ s: CGRect) -> CGFloat {
        let c = clamped(into: s)
        return abs(c.minX - listFrame.minX) + abs(c.minY - listFrame.minY)
    }
    let screen = screens.min { displacement($0) < displacement($1) }!
    let shown = clamped(into: screen)
    let slack = max(min(shown.width, shown.height), minSlack)
    let gate = shown.insetBy(dx: -slack, dy: -slack).intersection(screen)
    return gate.isNull || gate.isEmpty ? nil : gate
}
