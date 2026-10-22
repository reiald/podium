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
/// the frontmost app's own Dock item while that app has a window on the stage or in the
/// strip (the click then minimizes it, or brings it back), with the setting on and a healthy
/// tap. Anything else (another app's item, a folder or the Trash, a modifier, an app Podium
/// has no window of) passes through to the Dock.
///
/// The item matches the frontmost app by path (also with symlinks resolved), else by bundle
/// identifier (`bundleIdentifier` reads the item's; consulted only then), so an app macOS
/// runs from a translocated copy still matches its Dock icon.
public func decideDockClick(_ c: DockClick, enabled: Bool, tapHealthy: Bool,
                            frontmostAppURL: URL?, frontmostBundleID: String? = nil,
                            frontmostAppHasWindowOnBoard: Bool,
                            bundleIdentifier: (URL) -> String? = { _ in nil }) -> MinimizeDecision {
    guard enabled, tapHealthy, frontmostAppHasWindowOnBoard, c.modifiers.isEmpty,
          c.role == "AXDockItem", c.subrole == "AXApplicationDockItem",
          let item = c.itemURL, item.isFileURL, let front = frontmostAppURL else { return .passThrough }
    if sameBundle(item, front) { return .intercept }
    if let id = frontmostBundleID, !id.isEmpty, bundleIdentifier(item) == id { return .intercept }
    return .passThrough
}

/// File URLs naming the same path ("Safari.app/" and "Safari.app" alike, or through symlinks).
func sameBundle(_ a: URL, _ b: URL) -> Bool {
    guard a.isFileURL, b.isFileURL else { return false }
    let pa = a.standardizedFileURL.path, pb = b.standardizedFileURL.path
    guard !pa.isEmpty, !pb.isEmpty else { return false }
    return pa == pb || a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
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
