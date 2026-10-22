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

    init(settings: Settings) {
        self.settings = settings
    }

    func show() {
        // The user may have changed it in System Settings since the last look.
        loginItem.refresh()
        if window == nil {
            let w = SettingsNSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, loginItem: loginItem)))
            w.title = "Podium Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
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
