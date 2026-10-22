import CoreGraphics
import Foundation

/// A press on the frontmost app's Dock icon, decided only once it ends: a quick click
/// minimizes the app to the strip, while a drag (rearranging icons) or a press-and-hold (the
/// icon's menu) is handed back to the Dock as if Podium had never seen it.
///
/// The tap swallows the mouse-down and feeds the rest of the gesture through here; each step
/// says what to do with the event at hand.
public struct DockPress: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Not part of a tracked press: leave the event alone.
        case pass
        /// Still undecided: swallow the event.
        case swallow
        /// A click: swallow the event and minimize the app.
        case act
        /// Not a click after all: re-post the saved mouse-down, then this event (if any),
        /// and pass the rest of the gesture through.
        case replay
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case pending(start: CGPoint, time: TimeInterval)
        /// Replayed to the Dock: the rest of the gesture passes until the mouse-up.
        case passing
    }

    /// Movement beyond this many points makes it a drag.
    public static let dragThreshold: CGFloat = 4
    /// A press held this long is a press-and-hold.
    public static let holdTime: TimeInterval = 0.4

    private var phase = Phase.idle

    public init() {}

    /// A press is waiting to be decided (the tap's hold timer should be running).
    public var isPending: Bool {
        if case .pending = phase { return true }
        return false
    }

    /// The mouse-down was swallowed: start deciding.
    public mutating func began(at p: CGPoint, time: TimeInterval) {
        phase = .pending(start: p, time: time)
    }

    public mutating func dragged(to p: CGPoint, time: TimeInterval) -> Step {
        switch phase {
        case .idle:
            return .pass
        case .passing:
            return .pass
        case let .pending(start, t0):
            guard moved(from: start, to: p) || time - t0 >= Self.holdTime else { return .swallow }
            phase = .passing
            return .replay
        }
    }

    public mutating func released(at p: CGPoint, time: TimeInterval) -> Step {
        let was = phase
        phase = .idle
        switch was {
        case .idle, .passing:
            return .pass
        case let .pending(start, t0):
            return moved(from: start, to: p) || time - t0 >= Self.holdTime ? .replay : .act
        }
    }

    /// The hold timer fired.
    public mutating func holdElapsed() -> Step {
        guard isPending else { return .pass }
        phase = .passing
        return .replay
    }

    /// A new mouse-down (the old mouse-up was lost) or a disabled tap: forget the press.
    public mutating func reset() {
        phase = .idle
    }

    private func moved(from a: CGPoint, to b: CGPoint) -> Bool {
        hypot(b.x - a.x, b.y - a.y) > Self.dragThreshold
    }
}
