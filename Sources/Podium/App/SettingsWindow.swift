import AppKit
import PodiumCore
import SwiftUI

/// The Settings window: login item and hotkey, strip look (thumbnail size, tilt, app icons)
/// and the strip options the menu also has. Every control writes `Settings` (or the login
/// item); the AppDelegate applies changes live.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Podium at login",
                       isOn: Binding(get: { loginItem.isOn }, set: { loginItem.setOn($0) }))
                if loginItem.status == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items") { loginItem.openLoginItemsSettings() }
                    } label: {
                        Text("Needs your approval")
                        Text("Allow Podium in System Settings > General > Login Items.")
                    }
                }
                if let error = loginItem.errorText {
                    Text("Couldn't change the login item: \(error)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: $settings.hotKeyEnabled) {
                    Text("Turn Podium on or off with \(HotKey.display)")
                    if settings.hotKeyEnabled, settings.hotKeyUnavailable {
                        Text("\(HotKey.display) is in use by another app, so it isn't available.")
                    }
                }
            }
            Section("Strip") {
                Picker("Strip side", selection: $settings.side) {
                    Text("Left").tag(StripSide.left)
                    Text("Right").tag(StripSide.right)
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Thumbnail size", value: $settings.customization.thumbnailWidth,
                              range: StripCustomization.thumbnailWidthRange, wholePoints: true,
                              label: { "\(Int($0.rounded())) pt" })
                Picker("Thumbnail sizes", selection: $settings.customization.uniformThumbnails) {
                    Text("Match Windows").tag(false)
                    Text("Uniform").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Tilt", value: $settings.customization.tiltDegrees,
                              range: StripCustomization.tiltDegreesRange, wholePoints: false,
                              label: { "\(Int($0.rounded()))°" })
                Toggle("Auto-hide strip", isOn: $settings.autoHide)
            }
            Section("App Icons") {
                Toggle("Show app icons", isOn: $settings.customization.showAppIcons)
                LabeledSlider(title: "Icon size", value: $settings.customization.appIconSize,
                              range: StripCustomization.appIconSizeRange, wholePoints: true,
                              label: { "\(Int($0.rounded())) pt" })
                    .disabled(!settings.customization.showAppIcons)
            }
            Section("Windows") {
                Picker("Show windows from an app", selection: $settings.windowGrouping) {
                    Text("All at Once").tag(WindowGrouping.allAtOnce)
                    Text("One at a Time").tag(WindowGrouping.oneAtATime)
                }
                Picker("Minimize to", selection: $settings.minimizeBehavior) {
                    Text("Strip").tag(MinimizeBehavior.strip)
                    Text("Dock").tag(MinimizeBehavior.dock)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.dockClickMinimizes) {
                    Text("Click an app's Dock icon to minimize it to the strip")
                    Text("Turn off the same option in other apps, such as Vorssaint.")
                }
                Toggle(isOn: $settings.dockShiftClickAdds) {
                    Text("Shift-click a Dock icon to add its app to the stage")
                    Text("A plain click still switches to the app.")
                }
                Toggle("Click wallpaper to show desktop", isOn: $settings.clickWallpaperShowsDesktop)
                if settings.clickWallpaperShowsDesktop, settings.macOSRevealsDesktopOnClick {
                    LabeledContent {
                        Button("Open Desktop & Dock") { AppleStageManager.openDesktopSettings() }
                    } label: {
                        Text("macOS also reveals the desktop on a wallpaper click. In Desktop & Dock, set "
                            + "'Click wallpaper to reveal desktop' to 'Only in Stage Manager' so Podium can do it.")
                    }
                }
            }
            Section("Floating Apps") {
                Toggle(isOn: $settings.floatingApps.enabled) {
                    Text("Open these apps over the stage")
                    Text("Their windows don't get a stage, so the apps you're using stay put. Applies to windows opened from now on.")
                }
                ForEach(settings.floatingApps.bundleIDs, id: \.self) { id in
                    LabeledContent {
                        Button("Remove") { settings.floatingApps.remove(id) }
                    } label: {
                        Text(Self.appName(id))
                    }
                }
                .disabled(!settings.floatingApps.enabled)
                Button("Add App…") { addFloatingApp() }
                    .disabled(!settings.floatingApps.enabled)
            }
            HStack {
                Spacer()
                Button("Reset to Defaults") { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsView {
    /// The app's name for a bundle ID, or the ID itself when it isn't installed.
    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    func addFloatingApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { settings.floatingApps.add(id) }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    /// Rounds to whole points while dragging. A stepped slider is avoided: it draws tick marks.
    /// Tilt stays continuous (its default, ≈17.2°, is not a whole degree).
    let wholePoints: Bool
    let label: (CGFloat) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { value },
                                      set: { value = wholePoints ? $0.rounded() : $0 }),
                       in: range)
                Text(label(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

/// Hosts the settings view in one reused window. Podium has no Dock icon, so showing it
/// activates the app.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let loginItem = LoginItem()
    private var keyObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
    }

    func show() {
        // The user may have changed it in System Settings since the last look.
        loginItem.refresh()
        settings.refreshMacOSWallpaperClick()
        if window == nil {
            let w = SettingsNSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, loginItem: loginItem)))
            w.title = "Podium Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            // Back from System Settings (Login Items, Desktop & Dock): read the state again.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loginItem.refresh()
                    self?.settings.refreshMacOSWallpaperClick()
                }
            }
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settings.refreshMacOSWallpaperClick() }
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Podium has no main menu (LSUIElement), so Cmd-W is handled here.
private final class SettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
