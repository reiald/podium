/// Whether a window title names a picture-in-picture window ("Picture in Picture", "Picture-in-Picture").
public func isPictureInPictureTitle(_ title: String?) -> Bool {
    guard let title = title?.lowercased() else { return false }
    return title.contains("picture in picture") || title.contains("picture-in-picture")
}

/// Whether Podium should manage a window: only standard, non-full-screen,
/// non-minimized windows (role `AXWindow`, subrole `AXStandardWindow`).
/// Dialogs, sheets and floating windows are ignored. So is any window above the normal level
/// (`level` is its window-server layer, 0 for an ordinary window) and any picture-in-picture
/// window: they stay on top by design, so they must never be parked or shown in the strip.
public func isManageable(role: String?, subrole: String?, isFullscreen: Bool, isMinimized: Bool,
                         title: String? = nil, level: Int = 0) -> Bool {
    role == "AXWindow" && subrole == "AXStandardWindow" && !isFullscreen && !isMinimized
        && level == 0 && !isPictureInPictureTitle(title)
}
