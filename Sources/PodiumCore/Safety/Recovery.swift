import Foundation
import CoreGraphics

public enum RecoveryAction: Equatable, Sendable {
    case restore(WindowRef, to: CGRect)
    case forget(WindowRef)
}

/// Decides how to put parked windows back after a crash or relaunch.
/// Windows that no longer exist are forgotten, never restored. Frames fully inside
/// a visible screen are restored unchanged. Others are capped to the size of the
/// screen they overlap most and moved minimally to fit inside it; frames overlapping
/// no screen are centered on the first visible screen.
public func recoveryActions(
    entries: [ParkedEntry],
    liveWindows: Set<WindowRef>,
    visibleScreens: [CGRect]
) -> [RecoveryAction] {
    entries.map { entry in
        guard liveWindows.contains(entry.window) else { return .forget(entry.window) }
        return .restore(entry.window, to: fitted(entry.originalFrame, to: visibleScreens))
    }
}

/// Fits `frame` onto `screens` (see `recoveryActions`). Shared with `WindowMover` so every
/// restore uses the same rule.
func fitted(_ frame: CGRect, to screens: [CGRect]) -> CGRect {
    guard let first = screens.first else { return frame }
    if screens.contains(where: { $0.contains(frame) }) { return frame }

    func area(_ r: CGRect) -> CGFloat {
        let i = frame.intersection(r)
        return i.isNull ? 0 : i.width * i.height
    }
    var target = first
    var best: CGFloat = 0
    for screen in screens where area(screen) > best {
        best = area(screen)
        target = screen
    }

    let width = min(frame.width, target.width)
    let height = min(frame.height, target.height)
    if best == 0 {
        return CGRect(
            x: target.minX + (target.width - width) / 2,
            y: target.minY + (target.height - height) / 2,
            width: width, height: height)
    }
    // Overlaps the screen but is not fully inside: translate minimally.
    let x = min(max(frame.minX, target.minX), target.maxX - width)
    let y = min(max(frame.minY, target.minY), target.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height)
}
