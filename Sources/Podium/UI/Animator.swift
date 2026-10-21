import AppKit
import os
import PodiumCore
import QuartzCore

/// Drives every card's pose with Podium's own spring engine from a single display link.
///
/// `drive` on a card that is already moving only retargets its spring: velocity carries over,
/// so an interruption bends the motion instead of restarting it. The link pauses once every
/// spring has settled and resumes on the next `drive`.
@MainActor
final class Animator {
    struct FrameStats {
        var frames = 0
        var dropped = 0
        var maxDt: Double = 0
    }

    private final class Entry {
        let card: WindowCard
        var spring: Spring
        var vector: SpringVector
        var settled: [() -> Void] = []

        init(card: WindowCard, spring: Spring, vector: SpringVector) {
            self.card = card
            self.spring = spring
            self.vector = vector
        }
    }

    /// Never step more than this in one frame, so a stall or wake from sleep can't fling cards
    /// (and `SpringVector.step` does dt*240 substeps).
    static let maxStep = 1.0 / 30.0
    /// A frame whose dt exceeds this multiple of the display's frame interval is logged as dropped.
    static let dropFactor = 1.5

    private let logger = Logger(subsystem: "dev.podium.Podium", category: "animator")
    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Callbacks waiting for a number of display-link ticks (see `afterFrames`).
    private var frameWaiters: [(remaining: Int, body: () -> Void)] = []
    private var link: CADisplayLink
    private var lastTimestamp: CFTimeInterval?
    private(set) var stats = FrameStats()

    init(screen: NSScreen) {
        let target = LinkTarget()
        link = Self.makeLink(screen: screen, target: target)
        target.animator = self
    }

    private static func makeLink(screen: NSScreen, target: LinkTarget) -> CADisplayLink {
        let link = screen.displayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        return link
    }

    /// Moves the display link to `screen` (after a display change), keeping every running
    /// spring and frame waiter.
    func rebind(to screen: NSScreen) {
        let wasPaused = link.isPaused
        link.invalidate()
        let target = LinkTarget()
        link = Self.makeLink(screen: screen, target: target)
        target.animator = self
        lastTimestamp = nil
        link.isPaused = wasPaused
    }

    /// The screen whose display refreshes fastest; the one link should follow it.
    static func fastestScreen() -> NSScreen? {
        NSScreen.screens.max { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }
    }

    /// The run loop retains the link, and the link's proxy only holds the Animator weakly, so
    /// an Animator that goes away must stop its link or the proxy keeps firing into nothing.
    deinit {
        link.invalidate()
    }

    func invalidate() {
        link.invalidate()
    }

    func drive(_ card: WindowCard, to pose: CardPose, spring: Spring) {
        let key = ObjectIdentifier(card)
        if let entry = entries[key] {
            entry.spring = spring
            entry.vector.retarget(pose.vector())
        } else {
            var vector = SpringVector(card.pose.vector())
            vector.retarget(pose.vector())
            entries[key] = Entry(card: card, spring: spring, vector: vector)
        }
        resume()
    }

    private func resume() {
        if link.isPaused {
            lastTimestamp = nil
            link.isPaused = false
        }
    }

    /// Runs `body` once `card` comes to rest, or right away if it isn't moving.
    func onSettled(_ card: WindowCard, _ body: @escaping () -> Void) {
        guard let entry = entries[ObjectIdentifier(card)] else {
            body()
            return
        }
        entry.settled.append(body)
    }

    /// Runs `body` after `frames` display-link ticks (at least one), after that tick's poses
    /// were written.
    func afterFrames(_ frames: Int, _ body: @escaping () -> Void) {
        frameWaiters.append((max(1, frames), body))
        resume()
    }

    /// Stops `card`'s spring where it is; its settle callbacks never run.
    func cancel(_ card: WindowCard) {
        entries[ObjectIdentifier(card)] = nil
    }

    /// Whether `card` currently has a live spring.
    func isAnimating(_ card: WindowCard) -> Bool {
        entries[ObjectIdentifier(card)] != nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let interval = link.duration > 0 ? link.duration : 1.0 / 60.0
        let dt: Double
        if let last = lastTimestamp {
            dt = link.timestamp - last
            stats.maxDt = max(stats.maxDt, dt)
            if dt > interval * Self.dropFactor {
                stats.dropped += 1
                logger.log("dropped frame: dt=\(dt * 1000, format: .fixed(precision: 2), privacy: .public) ms, interval=\(interval * 1000, format: .fixed(precision: 2), privacy: .public) ms")
            }
        } else {
            dt = interval
        }
        lastTimestamp = link.timestamp
        stats.frames += 1

        let step = min(dt, Self.maxStep)
        var finished: [Entry] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (key, entry) in entries {
            entry.vector.step(dt: step, spring: entry.spring)
            let v = entry.vector
            if CardPose.isSettled(value: v.value, velocity: v.velocity, target: v.target) {
                entry.vector.snap(to: entry.vector.target)
                entries[key] = nil
                finished.append(entry)
            }
            entry.card.apply(CardPose(vector: entry.vector.value))
        }
        CATransaction.commit()

        var due: [() -> Void] = []
        frameWaiters = frameWaiters.compactMap { waiter in
            if waiter.remaining <= 1 {
                due.append(waiter.body)
                return nil
            }
            return (waiter.remaining - 1, waiter.body)
        }

        if entries.isEmpty && frameWaiters.isEmpty {
            link.isPaused = true
            lastTimestamp = nil
        }
        // Callbacks run last: one may drive the card again, which must create a fresh spring.
        for entry in finished {
            entry.settled.forEach { $0() }
        }
        due.forEach { $0() }
    }
}

/// The display link retains its target; this keeps it from retaining the Animator.
private final class LinkTarget: NSObject {
    weak var animator: Animator?

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { animator?.tick(link) }
    }
}
