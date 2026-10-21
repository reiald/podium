import Foundation
import CoreGraphics

public enum RecoveryAction: Equatable, Sendable {
    case restore(WindowRef, to: CGRect)
    case forget(WindowRef)
}

/// Decides how to put parked windows back after a crash or relaunch.
/// Windows that no longer exist are forgotten, never restored. Frames that touch
/// a visible screen are restored unchanged; others are shrunk to fit and centered
/// on the first visible screen.
public func recoveryActions(
    entries: [ParkedEntry],
    liveWindows: Set<WindowRef>,
    visibleScreens: [CGRect]
) -> [RecoveryAction] {
    entries.map { entry in
        guard liveWindows.contains(entry.window) else { return .forget(entry.window) }
        return .restore(entry.window, to: clamped(entry.originalFrame, to: visibleScreens))
    }
}

private func clamped(_ frame: CGRect, to screens: [CGRect]) -> CGRect {
    guard let first = screens.first else { return frame }
    let onScreen = screens.contains { screen in
        let i = frame.intersection(screen)
        return !i.isNull && i.width > 0 && i.height > 0
    }
    if onScreen { return frame }
    let width = min(frame.width, first.width)
    let height = min(frame.height, first.height)
    return CGRect(
        x: first.minX + (first.width - width) / 2,
        y: first.minY + (first.height - height) / 2,
        width: width, height: height)
}
