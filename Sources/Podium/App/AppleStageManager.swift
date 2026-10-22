import AppKit
import PodiumCore

/// CFPreferences on `com.apple.WindowManager`, read only.
private struct SystemStageManagerPreferences: StageManagerPreferences {
    private var app: CFString { "com.apple.WindowManager" as CFString }

    func bool(forKey key: String) -> Bool? {
        // Pick up changes the user just made in System Settings.
        CFPreferencesAppSynchronize(app)
        return CFPreferencesCopyAppValue(key as CFString, app) as? Bool
    }
}

/// Apple's own Stage Manager, which must be off for Podium to be the only one.
/// Podium never changes it: `disable()` / `enable()` open Desktop & Dock settings, where
/// the user flips the switch; `isEnabled` then reflects what they did.
enum AppleStageManager {
    private static let control = StageManagerSwitch(prefs: SystemStageManagerPreferences())
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!

    static var isEnabled: Bool { control.isEnabled }

    /// Desktop & Dock's "Click wallpaper to reveal desktop" is "Always": macOS itself sweeps
    /// windows aside on a wallpaper click. Read only; safe off the main thread.
    static var revealsDesktopOnWallpaperClick: Bool { control.revealsDesktopOnWallpaperClick }

    @discardableResult
    static func openDesktopSettings() -> Bool { NSWorkspace.shared.open(settingsURL) }

    @discardableResult
    static func disable() -> Bool { NSWorkspace.shared.open(settingsURL) }

    @discardableResult
    static func enable() -> Bool { NSWorkspace.shared.open(settingsURL) }
}
