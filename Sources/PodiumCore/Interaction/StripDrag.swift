import CoreGraphics
import Foundation

/// A press on a strip item: a click (or shift-click) until the pointer moves past the drag
/// threshold, a drag of the item's card for the rest of the press after that. A drag
/// released outside the strip band drops the item on the stage; one released inside the
/// band, or called off with Esc, springs back.
///
/// The strip panel feeds the press through here; each step says what to do with the event.
public struct StripDrag: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// Just became a drag: lift the card.
        case began
        /// The drag goes on: the card follows the pointer.
        case moved
        /// Released without moving: a click.
        case click
        /// A drag released outside the band: the item joins the stage.
        case drop
        /// A drag released inside the band, or Esc: the card springs back.
        case cancel
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case pressed(start: CGPoint)
        case dragging
        /// Esc ended the drag; the rest of the press does nothing.
        case cancelled
    }

    /// Movement beyond this many points makes it a drag.
    public static let dragThreshold: CGFloat = 4

    private var phase = Phase.idle

    public init() {}

    public var isDragging: Bool { phase == .dragging }

    public mutating func began(at p: CGPoint) {
        phase = .pressed(start: p)
    }

    public mutating func dragged(to p: CGPoint) -> Step {
        switch phase {
        case .idle, .cancelled:
            return .none
        case .dragging:
            return .moved
        case let .pressed(start):
            guard moved(from: start, to: p) else { return .none }
            phase = .dragging
            return .began
        }
    }

    public mutating func released(at p: CGPoint, inBand: Bool) -> Step {
        let was = phase
        phase = .idle
        switch was {
        case .idle, .cancelled:
            return .none
        case .dragging:
            return inBand ? .cancel : .drop
        case let .pressed(start):
            // Moved with no drag event in between: still a drag.
            guard moved(from: start, to: p) else { return .click }
            return inBand ? .cancel : .drop
        }
    }

    /// Esc: calls off a drag; a press that is not (yet) a drag ignores it.
    public mutating func escape() -> Step {
        guard phase == .dragging else { return .none }
        phase = .cancelled
        return .cancel
    }

    /// A new mouse-down (the old mouse-up was lost): forget the press.
    public mutating func reset() {
        phase = .idle
    }

    private func moved(from a: CGPoint, to b: CGPoint) -> Bool {
        hypot(b.x - a.x, b.y - a.y) > Self.dragThreshold
    }
}
