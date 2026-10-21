import AppKit
import ApplicationServices
import SwiftUI

/// Live permission state for the onboarding window, polled every second.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    @Published private(set) var appleStageManagerOn = AppleStageManager.isEnabled
    /// Set after a failed attempt to turn Apple's Stage Manager off from here.
    @Published private(set) var needsManualStageManagerOff = false
    private var timer: Timer?

    var ready: Bool { accessibility && screenRecording }

    func startPolling() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        appleStageManagerOn = AppleStageManager.isEnabled
        if !appleStageManagerOn { needsManualStageManagerOff = false }
    }

    /// Asking once makes macOS add Podium to the list; then the pane opens on it.
    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func turnOffAppleStageManager(didTurnOff: @escaping @MainActor () -> Void) {
        AppleStageManager.disableOrOpenSettings { [weak self] off in
            self?.refresh()
            if off {
                didTurnOff()
            } else {
                self?.needsManualStageManagerOff = true
            }
        }
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onTurnedOffAppleStageManager: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Podium").font(.title2.bold())
                Text("Two permissions and you're done. Podium needs them to move and show your windows.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                PermissionRow(title: "Accessibility", detail: "Lets Podium move and raise windows.",
                              granted: model.accessibility, action: model.requestAccessibility)
                PermissionRow(title: "Screen Recording", detail: "Lets Podium draw live thumbnails of your windows. Nothing is recorded or sent anywhere.",
                              granted: model.screenRecording, action: model.requestScreenRecording)
            }

            if model.appleStageManagerOn {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple's Stage Manager is on").font(.headline)
                            Text("Turn it off so the two don't fight. You can turn it back on from Podium's menu.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Turn off Apple's Stage Manager") {
                            model.turnOffAppleStageManager(didTurnOff: onTurnedOffAppleStageManager)
                        }
                    }
                    if model.needsManualStageManagerOff {
                        Text("macOS didn't switch it off. In Desktop & Dock settings, turn off Stage Manager yourself.")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Text(model.ready ? "All set." : "Waiting for both permissions...")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.ready)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityLabel(granted ? "Granted" : "Not granted")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(granted ? "Open Settings" : "Grant Access", action: action)
        }
    }
}

/// Hosts the onboarding view in a small window. Podium has no Dock icon, so showing it
/// activates the app.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()
    private let onTurnedOffAppleStageManager: () -> Void
    /// The window ended: `true` for Done (or closed with everything granted).
    private let onFinish: (_ completed: Bool) -> Void

    init(onTurnedOffAppleStageManager: @escaping () -> Void, onFinish: @escaping (Bool) -> Void) {
        self.onTurnedOffAppleStageManager = onTurnedOffAppleStageManager
        self.onFinish = onFinish
    }

    var isShowing: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let view = OnboardingView(model: model, onTurnedOffAppleStageManager: onTurnedOffAppleStageManager) { [weak self] in
                self?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Podium"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        onFinish(model.ready)
    }
}
