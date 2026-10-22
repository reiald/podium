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

    /// A press is waiting for its mouse-up and can still be a click (held under `holdTime`).
    public func isPending(at now: TimeInterval) -> Bool {
        isPending && now - startTime < Self.holdTime
    }

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

/// A window the window server lists on screen (`CGWindowListCopyWindowInfo`).
public struct ScreenWindow: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var layer: Int
    public var bounds: CGRect
    public var alpha: Double

    public init(pid: Int32, bundleID: String?, layer: Int, bounds: CGRect, alpha: Double) {
        self.pid = pid
        self.bundleID = bundleID
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }
}

/// Apps whose panels a click on the desktop only closes.
public let popUpOwners: Set<String> = ["com.apple.notificationcenterui", "com.apple.controlcenter", "com.apple.Spotlight"]

/// Whether a pop-up is open on `display`, so a click on the wallpaper there only closes it:
/// a visible window of Notification Center, Control Center or Spotlight above the desktop
/// (their desktop widgets sit below normal windows and don't count), outside the menu bar's
/// layers (24, 25: their status items); or any other app's visible window above normal
/// windows and below the Dock (layer 1 to 19: floating panels, pop-overs), Podium's excepted.
public func popUpBlocksWallpaperClick(_ windows: [ScreenWindow], display: CGRect, podiumPid: Int32) -> Bool {
    let menuBarLayers = 24...25
    let belowDock = 1..<20
    return windows.contains { w in
        guard w.pid != podiumPid, w.alpha > 0, w.bounds.intersects(display) else { return false }
        if let id = w.bundleID, popUpOwners.contains(id) { return w.layer >= 0 && !menuBarLayers.contains(w.layer) }
        return belowDock.contains(w.layer)
    }
}

/// The verdicts of wallpaper presses, which arrive late and possibly out of order (each
/// press's hit-test runs off the main thread). Only the latest press's verdict counts, and
/// only if the stage on screen is still the one it was when that press ended.
///
/// While any press waits for its verdict, a Finder activation by it is held (`hold`): it is
/// dropped if the verdict is "wallpaper", and handed back (`release`) once no press waits.
/// After a "wallpaper" verdict, a Finder activation arriving late is ignored for
/// `lateActivationWindow`.
public struct WallpaperVerdicts: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Nothing to do yet.
        case none
        /// Send the stage away.
        case showDesktop
        /// No press waits any more: apply this held Finder activation.
        case release(Int32)
    }

    public static let lateActivationWindow: TimeInterval = 0.3

    private var latest = 0
    /// Presses waiting for a verdict, with the active stage when each ended.
    private var waiting: [Int: UUID] = [:]
    public private(set) var held: Int32?
    private var ignoreFinderUntil = -TimeInterval.infinity

    public init() {}

    /// Some press waits for its verdict.
    public var isWaiting: Bool { !waiting.isEmpty }

    /// A plain click ended with `activeStageID` on screen: its hit-test starts. Returns
    /// the press's number, for `verdict`.
    public mutating func pressEnded(activeStageID: UUID) -> Int {
        latest += 1
        waiting[latest] = activeStageID
        return latest
    }

    /// A press ended that is no wallpaper click (or can't be probed): it supersedes any
    /// earlier press, whose verdict no longer counts.
    public mutating func pressDiscarded() -> Outcome {
        latest += 1
        return releaseIfIdle()
    }

    /// A Finder activation with the desktop focused arrived while a press waits.
    public mutating func hold(_ pid: Int32) {
        held = pid
    }

    /// Whether a Finder activation with the desktop focused, at `now`, is the late echo of a
    /// wallpaper click already acted on.
    public func ignoresFinderActivation(at now: TimeInterval) -> Bool {
        now < ignoreFinderUntil
    }

    public mutating func verdict(_ press: Int, isWallpaper: Bool, activeStageID: UUID?, now: TimeInterval) -> Outcome {
        guard let stage = waiting.removeValue(forKey: press) else { return .none }
        if isWallpaper, press == latest, stage == activeStageID {
            held = nil
            ignoreFinderUntil = now + Self.lateActivationWindow
            return .showDesktop
        }
        return releaseIfIdle()
    }

    /// The setting turned off (or Podium stopped): nothing waits, nothing is held.
    public mutating func reset() {
        latest += 1
        waiting = [:]
        held = nil
    }

    private mutating func releaseIfIdle() -> Outcome {
        guard waiting.isEmpty, let pid = held else { return .none }
        held = nil
        return .release(pid)
    }
}
