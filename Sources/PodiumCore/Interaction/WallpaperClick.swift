import CoreGraphics
import Foundation

/// A press that may be a click on empty wallpaper ("Click wallpaper to show desktop"),
/// decided only once it ends: a short press that barely moved, with no modifier, and no menu
/// (of any app) open during it. A drag (a rubber-band selection, an icon drag), a
/// press-and-hold or a click that only closes a menu is never one.
///
/// It only says the press was a plain click; whether the point is wallpaper rather than a
/// desktop icon or a window is `isEmptyWallpaper`'s call.
public struct WallpaperPress: Equatable, Sendable {
    /// Movement beyond this many points makes it a drag.
    public static let dragThreshold: CGFloat = 4
    /// A press held this long is a press-and-hold.
    public static let holdTime: TimeInterval = 0.4
    /// A menu that closed this soon before the press began counts as closed by it (the
    /// news of the close can be stamped a moment before the press's own time).
    public static let menuCloseSlack: TimeInterval = 0.1

    private var start: CGPoint?
    private var startTime: TimeInterval = 0
    private var menuOpen = false
    private var menuClosedAt = -TimeInterval.infinity

    public init() {}

    /// A press is waiting for its mouse-up.
    public var isPending: Bool { start != nil }

    /// A press began. With a modifier held it can't be a wallpaper click.
    public mutating func began(at p: CGPoint, time: TimeInterval, modifiers: ModifierSet) {
        guard modifiers.isEmpty else { return reset() }
        start = p
        startTime = time
    }

    /// Some app began (true) or ended (false) tracking a menu.
    public mutating func menuTracking(_ open: Bool, time: TimeInterval) {
        if menuOpen, !open { menuClosedAt = time }
        menuOpen = open
    }

    /// The press ended: true if it was a plain click at the point it began.
    public mutating func released(at p: CGPoint, time: TimeInterval) -> Bool {
        defer { reset() }
        guard let start, !menuOpen, menuClosedAt < startTime - Self.menuCloseSlack else { return false }
        return hypot(p.x - start.x, p.y - start.y) <= Self.dragThreshold && time - startTime < Self.holdTime
    }

    /// Forgets the press (not the menu state).
    public mutating func reset() {
        start = nil
    }
}

/// What the Accessibility hit-test found under a click.
public struct WallpaperHit: Equatable, Sendable {
    /// The element belongs to Finder, which draws the desktop.
    public var isFinder: Bool
    public var role: String?
    /// The role of the element's `AXWindow`. The desktop's is its scroll area; an element
    /// in one of Finder's windows has a real `AXWindow`.
    public var windowRole: String?

    public init(isFinder: Bool, role: String?, windowRole: String?) {
        self.isFinder = isFinder
        self.role = role
        self.windowRole = windowRole
    }
}

/// Whether the hit is the bare desktop: Finder's desktop scroll area or the icon group in
/// it, not an icon (`AXImage`) or its name, and not anything in a window. Nil (the
/// hit-test failed or timed out) is never wallpaper.
public func isEmptyWallpaper(_ hit: WallpaperHit?) -> Bool {
    guard let hit, hit.isFinder else { return false }
    let desktopRoles: Set<String> = ["AXScrollArea", "AXGroup"]
    return hit.role.map(desktopRoles.contains) == true && hit.windowRole == "AXScrollArea"
}
