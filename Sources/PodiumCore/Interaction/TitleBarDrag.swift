import CoreGraphics

/// The active-stage window the user dragged by its title bar into the strip `band`, with its
/// frame before the press; nil if the press was not such a drag.
///
/// The press began outside the band and ended in it, exactly one window moved without
/// changing size, the press began on it, and it moved with the pointer. A wide window reaches
/// into the band, and a click on it there that nudges it was never dragged into the band.
/// Apps also move their own windows (Teams settles its main window after it is unparked);
/// such a window that happens to move during a click elsewhere is no drag.
/// Frames and points are in global top-left coordinates.
public func titleBarDragged(before: [WindowRef: CGRect], after: [WindowRef: CGRect],
                            pressedAt start: CGPoint, releasedAt end: CGPoint,
                            band: CGRect) -> (WindowRef, CGRect)? {
    guard !band.contains(start), band.contains(end) else { return nil }
    let pointer = CGVector(dx: end.x - start.x, dy: end.y - start.y)
    let pointerDistance = hypot(pointer.dx, pointer.dy)
    guard pointerDistance >= TitleBarDrag.minimumPointerTravel else { return nil }
    let moved = before.filter { w, frame in
        guard let now = after[w] else { return false }
        let sameSize = abs(now.width - frame.width) <= 1 && abs(now.height - frame.height) <= 1
        return sameSize && hypot(now.minX - frame.minX, now.minY - frame.minY) >= TitleBarDrag.minimumWindowTravel
    }
    guard moved.count == 1, let (w, frame) = moved.first, let now = after[w], frame.contains(start) else { return nil }
    // The app may clamp the window short of the pointer (menu bar, screen edges).
    let off = hypot(now.minX - frame.minX - pointer.dx, now.minY - frame.minY - pointer.dy)
    guard off <= max(TitleBarDrag.followSlack, pointerDistance / 2) else { return nil }
    return (w, frame)
}

public enum TitleBarDrag {
    public static let minimumPointerTravel: CGFloat = 4
    public static let minimumWindowTravel: CGFloat = 2
    /// How far the window may end up from where the pointer took it.
    public static let followSlack: CGFloat = 24
}
