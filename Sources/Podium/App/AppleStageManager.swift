import AppKit
import PodiumCore

/// CFPreferences on `com.apple.WindowManager`.
private struct SystemStageManagerPreferences: StageManagerPreferences {
    private var app: CFString { "com.apple.WindowManager" as CFString }

    func bool(forKey key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, app) as? Bool
    }

    func setBool(_ value: Bool, forKey key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFBoolean, app)
    }

    func synchronize() -> Bool {
        CFPreferencesAppSynchronize(app)
    }
}

/// Apple's own Stage Manager, which must be off for Podium to be the only one.
/// `disable()` / `enable()` change a system setting: only call them on a user's click.
enum AppleStageManager {
    private static let control = StageManagerSwitch(prefs: SystemStageManagerPreferences())
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!

    static var isEnabled: Bool { control.isEnabled }

    /// Writes the preference; true if it reads back as off. Check `isEnabled` a moment later
    /// to see whether the system really followed (see `disableOrOpenSettings`).
    static func disable() -> Bool { control.disable() }

    static func enable() -> Bool { control.enable() }

    /// Turns it off; if the system still reports it on a second later, opens Desktop & Dock
    /// settings so the user can do it by hand. `completion(true)` once it is off.
    @MainActor
    static func disableOrOpenSettings(completion: @escaping @MainActor (Bool) -> Void) {
        _ = disable()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                let off = !isEnabled
                if !off { NSWorkspace.shared.open(settingsURL) }
                completion(off)
            }
        }
    }
}
