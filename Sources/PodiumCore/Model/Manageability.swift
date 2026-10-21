/// Whether Podium should manage a window: only standard, non-full-screen,
/// non-minimized windows (role `AXWindow`, subrole `AXStandardWindow`).
/// Dialogs, sheets and floating windows are ignored.
public func isManageable(role: String?, subrole: String?, isFullscreen: Bool, isMinimized: Bool) -> Bool {
    role == "AXWindow" && subrole == "AXStandardWindow" && !isFullscreen && !isMinimized
}
