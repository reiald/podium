import CoreGraphics
import Foundation

/// Tracks which strip thumbnail is hovered. The current slot is latched: it stays hovered while the
/// pointer is inside its frame expanded by `latchMargin`, so crossing the gap between neighbors doesn't flicker.
public struct HoverLatch: Sendable {
    public private(set) var hovered: UUID?

    public init() {}

    public mutating func update(pointer: CGPoint?, slots: [StripSlot], latchMargin: CGFloat = 10) {
        if let id = hovered, !slots.contains(where: { $0.stageID == id }) { hovered = nil }
        guard let pointer else { hovered = nil; return }

        if let id = hovered,
           let current = slots.first(where: { $0.stageID == id }),
           current.frame.insetBy(dx: -latchMargin, dy: -latchMargin).contains(pointer) {
            return
        }
        hovered = slots.first(where: { $0.frame.contains(pointer) })?.stageID
    }
}
