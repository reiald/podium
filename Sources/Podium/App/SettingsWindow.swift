import AppKit
import PodiumCore
import SwiftUI

/// The Settings window: strip look (thumbnail size, tilt, app icons) and the strip options
/// the menu also has. Every control writes `Settings`; the AppDelegate applies changes live.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
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
                Picker("Minimize to", selection: $settings.minimizeBehavior) {
                    Text("Strip").tag(MinimizeBehavior.strip)
                    Text("Dock").tag(MinimizeBehavior.dock)
                }
                .pickerStyle(.segmented)
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

    init(settings: Settings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
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
