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
    /// "Show windows from an app": all at once or one at a time.
    @Published var windowGrouping: WindowGrouping {
        didSet { defaults.set(windowGrouping.rawValue, forKey: "appWindowGrouping") }
    }
    /// The onboarding window was completed once.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    /// Podium turned Apple's Stage Manager off (so the menu offers to turn it back on).
    @Published var turnedOffAppleStageManager: Bool {
        didSet { defaults.set(turnedOffAppleStageManager, forKey: "turnedOffAppleStageManager") }
    }
    /// Thumbnail size, tilt and app icons (the Settings window). Stored clamped; out-of-range
    /// values are clamped again wherever they are applied.
    @Published var customization: StripCustomization {
        didSet {
            let c = customization.clamped()
            defaults.set(Double(c.thumbnailWidth), forKey: "thumbnailWidth")
            defaults.set(Double(c.tiltDegrees), forKey: "tiltDegrees")
            defaults.set(c.showAppIcons, forKey: "showAppIcons")
            defaults.set(Double(c.appIconSize), forKey: "appIconSize")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        side = defaults.string(forKey: "side").flatMap(StripSide.init(rawValue:)) ?? .right
        minimizeBehavior = defaults.string(forKey: "minimizeBehavior").flatMap(MinimizeBehavior.init(rawValue:)) ?? .strip
        autoHide = defaults.object(forKey: "autoHide") as? Bool ?? true
        windowGrouping = defaults.string(forKey: "appWindowGrouping").flatMap(WindowGrouping.init(rawValue:)) ?? .allAtOnce
        onboarded = defaults.bool(forKey: "onboarded")
        turnedOffAppleStageManager = defaults.bool(forKey: "turnedOffAppleStageManager")
        let d = StripCustomization.defaults
        func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
            (defaults.object(forKey: key) as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
        }
        customization = StripCustomization(
            thumbnailWidth: number("thumbnailWidth", d.thumbnailWidth),
            tiltDegrees: number("tiltDegrees", d.tiltDegrees),
            showAppIcons: defaults.object(forKey: "showAppIcons") as? Bool ?? d.showAppIcons,
            appIconSize: number("appIconSize", d.appIconSize)
        ).clamped()
    }

    /// The Settings window's Reset to Defaults: the customization and the strip options.
    func resetToDefaults() {
        customization = .defaults
        side = .right
        minimizeBehavior = .strip
        autoHide = true
        windowGrouping = .allAtOnce
    }
}
