import Combine
import os
import ServiceManagement

/// "Open Podium at login" through `SMAppService.mainApp`. The system owns the state (the user
/// can change it in System Settings > Login Items), so it is read again each time Settings
/// opens rather than stored.
@MainActor
final class LoginItem: ObservableObject {
    private static let logger = Logger(subsystem: "dev.podium.Podium", category: "settings")

    @Published private(set) var status: SMAppService.Status = .notRegistered
    /// The last register/unregister failure, shown in Settings.
    @Published private(set) var errorText: String?

    init() { refresh() }

    /// Registered, or waiting for the user's approval in Login Items.
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setOn(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorText = nil
        } catch {
            Self.logger.error("Login item \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            errorText = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
