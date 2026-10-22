import Foundation

/// Reads one boolean preference (the real implementation is CFPreferences on
/// `com.apple.WindowManager`, synchronized before each read; tests inject a fake).
/// Podium never writes this domain: turning Stage Manager on or off is the user's job.
public protocol StageManagerPreferences: Sendable {
    func bool(forKey key: String) -> Bool?
}

/// Whether Apple's Stage Manager is on, through an injected preferences reader.
public struct StageManagerSwitch: Sendable {
    public static let key = "GloballyEnabled"

    private let prefs: StageManagerPreferences

    public init(prefs: StageManagerPreferences) {
        self.prefs = prefs
    }

    /// A missing key means Stage Manager was never turned on.
    public var isEnabled: Bool { prefs.bool(forKey: Self.key) ?? false }

    /// Desktop & Dock's "Click wallpaper to reveal desktop": 1 is "Always", 0 "Only in Stage
    /// Manager".
    public static let clickToShowDesktopKey = "EnableStandardClickToShowDesktop"

    /// macOS itself sweeps windows aside on a wallpaper click, outside Stage Manager too.
    /// A missing key reads as "Always", macOS's default.
    public var revealsDesktopOnWallpaperClick: Bool { prefs.bool(forKey: Self.clickToShowDesktopKey) ?? true }
}
