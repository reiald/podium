import AppKit
import ApplicationServices
import SwiftUI

/// Live permission state for the onboarding window, polled every second.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    @Published private(set) var appleStageManagerOn = AppleStageManager.isEnabled
    /// Screen Recording was requested from here and still reads false: macOS may only
    /// register the grant after a relaunch.
    @Published private(set) var screenRecordingRequested = false
    /// The user was sent to Desktop & Dock settings to turn Stage Manager off.
    private var awaitingStageManagerOff = false
    var onStageManagerTurnedOff: () -> Void = {}
    private var timer: Timer?

    var permissionsGranted: Bool { accessibility && screenRecording }
    /// Podium can run: both permissions, and Apple's Stage Manager off.
    var ready: Bool { permissionsGranted && !appleStageManagerOn }

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
        if awaitingStageManagerOff, !appleStageManagerOn {
            awaitingStageManagerOff = false
            onStageManagerTurnedOff()
        }
    }

    /// Asking once makes macOS add Podium to the list; then the pane opens on it.
    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        screenRecordingRequested = true
        Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openStageManagerSettings() {
        awaitingStageManagerOff = true
        AppleStageManager.disable()
    }

    /// Starts a new instance, then quits this one (quitting restores any parked windows).
    func quitAndReopen() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
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
                if model.screenRecordingRequested, !model.screenRecording {
                    HStack {
                        Text("If you've turned it on and it still isn't ticked, macOS needs Podium to restart.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Quit & Reopen Podium", action: model.quitAndReopen)
                    }
                }
            }

            if model.appleStageManagerOn {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple's Stage Manager is on").font(.headline)
                        Text("Podium can't run alongside it, so it stays paused with your windows in place. Turn Stage Manager off, then come back.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Open Stage Manager settings", action: model.openStageManagerSettings)
                }
            }

            HStack {
                Text(model.ready ? "All set."
                     : model.permissionsGranted ? "Waiting for Apple's Stage Manager to be turned off..."
                     : "Waiting for both permissions...")
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
    /// The window ended: `true` for Done (or closed with everything granted).
    private let onFinish: (_ completed: Bool) -> Void

    init(onTurnedOffAppleStageManager: @escaping () -> Void, onFinish: @escaping (Bool) -> Void) {
        model.onStageManagerTurnedOff = onTurnedOffAppleStageManager
        self.onFinish = onFinish
    }

    var isShowing: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let view = OnboardingView(model: model) { [weak self] in
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
        model.startPolling()
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
