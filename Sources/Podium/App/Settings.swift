import Combine
import Foundation
import PodiumCore

/// User settings, persisted in `UserDefaults` as they change.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var side: StripSide { didSet { defaults.set(side.rawValue, forKey: "side") } }
    @Published var minimizeBehavior: MinimizeBehavior {
        didSet { defaults.set(minimizeBehavior.rawValue, forKey: "minimizeBehavior") }
    }
    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: "autoHide") } }
    /// Keep the strip thumbnails updating continuously. macOS shows its screen-sharing indicator
    /// the whole time; off, Podium captures a window only when it leaves the stage.
    @Published var liveThumbnails: Bool { didSet { defaults.set(liveThumbnails, forKey: "liveThumbnails") } }
    /// "Show windows from an app": all at once or one at a time.
    @Published var windowGrouping: WindowGrouping {
        didSet { defaults.set(windowGrouping.rawValue, forKey: "appWindowGrouping") }
    }
    /// "Click an app's Dock icon to minimize it to the strip".
    @Published var dockClickMinimizes: Bool { didSet { defaults.set(dockClickMinimizes, forKey: "dockClickMinimizes") } }
    /// Apps whose windows float over the stage.
    @Published var floatingApps: FloatingApps {
        didSet {
            defaults.set(floatingApps.enabled, forKey: "floatingAppsEnabled")
            defaults.set(floatingApps.bundleIDs, forKey: "floatingAppIDs")
        }
    }
    /// "Shift-click a Dock icon to add its app to the stage".
    @Published var dockShiftClickAdds: Bool { didSet { defaults.set(dockShiftClickAdds, forKey: "dockShiftClickAdds") } }
    /// "Click wallpaper to show desktop".
    @Published var clickWallpaperShowsDesktop: Bool {
        didSet { defaults.set(clickWallpaperShowsDesktop, forKey: "clickWallpaperShowsDesktop") }
    }
    /// macOS's own "Click wallpaper to reveal desktop" is "Always", so Podium's does nothing.
    /// Read from Apple's preferences (`refreshMacOSWallpaperClick`); not stored.
    @Published private(set) var macOSRevealsDesktopOnClick = false
    /// The onboarding window was completed once.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    /// Podium turned Apple's Stage Manager off (so the menu offers to turn it back on).
    @Published var turnedOffAppleStageManager: Bool {
        didSet { defaults.set(turnedOffAppleStageManager, forKey: "turnedOffAppleStageManager") }
    }
    /// ⌃⌥⌘P turns Podium on or off from anywhere.
    @Published var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled") } }
    /// The hotkey is on but could not be registered (another app holds it). Not stored.
    @Published var hotKeyUnavailable = false
    /// Thumbnail size, tilt and app icons (the Settings window). Stored clamped; out-of-range
    /// values are clamped again wherever they are applied.
    @Published var customization: StripCustomization {
        didSet {
            let c = customization.clamped()
            defaults.set(Double(c.thumbnailWidth), forKey: "thumbnailWidth")
            defaults.set(Double(c.tiltDegrees), forKey: "tiltDegrees")
            defaults.set(c.showAppIcons, forKey: "showAppIcons")
            defaults.set(Double(c.appIconSize), forKey: "appIconSize")
            defaults.set(c.uniformThumbnails, forKey: "uniformThumbnails")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        side = defaults.string(forKey: "side").flatMap(StripSide.init(rawValue:)) ?? .right
        minimizeBehavior = defaults.string(forKey: "minimizeBehavior").flatMap(MinimizeBehavior.init(rawValue:)) ?? .strip
        autoHide = defaults.object(forKey: "autoHide") as? Bool ?? true
        liveThumbnails = defaults.bool(forKey: "liveThumbnails")
        windowGrouping = defaults.string(forKey: "appWindowGrouping").flatMap(WindowGrouping.init(rawValue:)) ?? .allAtOnce
        dockClickMinimizes = defaults.bool(forKey: "dockClickMinimizes")
        dockShiftClickAdds = defaults.object(forKey: "dockShiftClickAdds") as? Bool ?? true
        floatingApps = FloatingApps(
            enabled: defaults.object(forKey: "floatingAppsEnabled") as? Bool ?? FloatingApps.defaults.enabled,
            bundleIDs: defaults.stringArray(forKey: "floatingAppIDs") ?? FloatingApps.defaults.bundleIDs)
        clickWallpaperShowsDesktop = defaults.object(forKey: "clickWallpaperShowsDesktop") as? Bool ?? true
        onboarded = defaults.bool(forKey: "onboarded")
        turnedOffAppleStageManager = defaults.bool(forKey: "turnedOffAppleStageManager")
        hotKeyEnabled = defaults.object(forKey: "hotKeyEnabled") as? Bool ?? true
        let d = StripCustomization.defaults
        func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
            (defaults.object(forKey: key) as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
        }
        customization = StripCustomization(
            thumbnailWidth: number("thumbnailWidth", d.thumbnailWidth),
            tiltDegrees: number("tiltDegrees", d.tiltDegrees),
            showAppIcons: defaults.object(forKey: "showAppIcons") as? Bool ?? d.showAppIcons,
            appIconSize: number("appIconSize", d.appIconSize),
            uniformThumbnails: defaults.bool(forKey: "uniformThumbnails")
        ).clamped()
    }

    func refreshMacOSWallpaperClick() {
        let on = AppleStageManager.revealsDesktopOnWallpaperClick
        if on != macOSRevealsDesktopOnClick { macOSRevealsDesktopOnClick = on }
    }

    /// The Settings window's Reset to Defaults: the customization and the strip options.
    func resetToDefaults() {
        customization = .defaults
        side = .right
        minimizeBehavior = .strip
        autoHide = true
        liveThumbnails = false
        windowGrouping = .allAtOnce
        dockClickMinimizes = false
        dockShiftClickAdds = true
        floatingApps = .defaults
        clickWallpaperShowsDesktop = true
    }
}
