import AppKit
import os
import PodiumCore
import QuartzCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Plays model changes as card animations, swapping real windows and their snapshot cards
/// without a visible blink, and keeps the strip's cards (piles, hover, auto-hide) in place.
///
/// The no-blink rule:
/// - Leaving the stage: the card appears at the window's exact frame with a cached snapshot,
///   the overlay commit is flushed and one display-link tick passes, then the window is
///   parked and the card flies to its strip slot. If parking fails the card is removed
///   two ticks later and the window stays on stage.
/// - Entering the stage: the card flies from its slot to the window's original frame; once
///   it settles the window is unparked, and two ticks later (the window has drawn) the card
///   is removed.
///
/// A window with no snapshot at all gets Task 9's instant move and no card: never a blank card.
/// Every phase change bumps a per-window generation, so callbacks from an interrupted
/// phase (fast repeated clicks retarget cards mid-flight) do nothing.
@MainActor
final class TransitionRunner {
    typealias Layout = (side: StripSide, screen: CGRect, tuning: Tuning)

    private enum Phase {
        /// On screen, card at its frame, waiting to be parked.
        case preparing
        /// Parked; the card is (on its way to) its strip pose.
        case strip
        /// Parked; the card is flying to the window's frame.
        case entering
        /// Unparked; the card waits two ticks for the window to draw, then goes.
        case revealing
    }

    private final class Track {
        let card: WindowCard
        var phase: Phase
        var generation = 0

        init(card: WindowCard, phase: Phase) {
            self.card = card
            self.phase = phase
        }

        func move(to phase: Phase) {
            self.phase = phase
            generation += 1
        }
    }

    /// Strip cards slide this far beyond the band when hidden, so their shadows go too.
    private static let hiddenShadowMargin: CGFloat = 20
    private static let transitionZ: CGFloat = 1000
    /// How long a leaving window's snapshot refresh may hold up its transition.
    private static let snapshotWait: TimeInterval = 1.0 / 60.0

    /// Called with every window a park/unpark batch touched, right after the batch ends.
    var onBatchEnd: ([WindowRef]) -> Void = { _ in }

    private(set) var layout: Layout
    private(set) var hovered: UUID?
    private(set) var isHidden = false

    private let backend: AXWindowBackend
    private let mover: WindowMover
    private let ledger: ParkingLedger
    private let capture: Capture
    private let board: () -> StageBoard
    private let logger = Logger(subsystem: "dev.podium.Podium", category: "transition")
    private var overlay: Overlay
    private let animator: Animator
    private var tracks: [WindowRef: Track] = [:]
    /// Windows whose leave is waiting on a snapshot (no card yet), by token.
    private var pendingLeave: [WindowRef: Int] = [:]
    private var leaveToken = 0
    /// Parked windows whose cached snapshot is being looked up for a card (strip or enter).
    private var fetching: Set<WindowRef> = []
    /// Where each strip window sat at the last full relayout; an entering window with no
    /// card (deep in a pile, or past the last row) starts its card there.
    private var lastPlacement: [WindowRef: (stage: Stage, index: Int, slot: StripSlot?)] = [:]
    /// Frames to restore a window to instead of where it is when parked (drag-out).
    private var restoreFrames: [WindowRef: CGRect] = [:]
    private var icons: [pid_t: NSImage] = [:]

    /// Nil when there is no display to draw on.
    init?(backend: AXWindowBackend, mover: WindowMover, ledger: ParkingLedger, capture: Capture,
          layout: Layout, board: @escaping () -> StageBoard) {
        guard let primary = NSScreen.screens.first else { return nil }
        self.backend = backend
        self.mover = mover
        self.ledger = ledger
        self.capture = capture
        self.layout = layout
        self.board = board
        overlay = Overlay(screen: primary)
        animator = Animator(screen: Animator.fastestScreen() ?? primary)
        // Shown now, empty and click-through: a new overlay's first composite costs a frame.
        overlay.show()
    }

    // MARK: - Public

    func run(_ plan: TransitionPlan, layout: Layout) {
        self.layout = layout
        for w in plan.entering { enter(w) }
        leave(plan.leaving)
        relayoutStrip(spring: layout.tuning.transitionSpring)
    }

    /// Re-places every strip card (strip order, side, pile) without a model change.
    func update(layout: Layout) {
        self.layout = layout
        relayoutStrip(spring: layout.tuning.transitionSpring)
    }

    func setHovered(_ id: UUID?) {
        guard id != hovered else { return }
        let changed = Set([hovered, id].compactMap { $0 })
        hovered = id
        relayoutStrip(spring: layout.tuning.hoverSpring, onlyStages: changed)
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        relayoutStrip(spring: layout.tuning.transitionSpring)
    }

    /// Drops the cards of windows that were moved behind the runner's back (instant
    /// reconcile) so no stale phase acts on them.
    func discardCards(for windows: [WindowRef]) {
        for w in windows { drop(w) }
    }

    func forget(_ w: WindowRef) {
        drop(w)
        restoreFrames[w] = nil
    }

    /// The next park of `w` records `frame` as the frame to come back to.
    func setRestoreFrame(_ frame: CGRect, for w: WindowRef) {
        restoreFrames[w] = frame
    }

    /// Removes every card and the overlay and stops the display link (before every window
    /// is restored). No pending phase acts afterwards: they all check their track.
    func shutdown() {
        for w in Array(tracks.keys) { drop(w) }
        pendingLeave = [:]
        overlay.hide()
        animator.invalidate()
    }

    /// After a display change: the overlay follows the primary display and the display
    /// link follows the fastest screen.
    func screensChanged(layout: Layout) {
        if let fastest = Animator.fastestScreen() { animator.rebind(to: fastest) }
        if let primary = NSScreen.screens.first, flipToAppKit(primary.frame) != overlay.frame {
            let old = overlay
            overlay = Overlay(screen: primary)
            for t in tracks.values { overlay.add(t.card) }
            overlay.show()
            old.hide()
        }
        update(layout: layout)
    }

    // MARK: - Entering

    private func enter(_ w: WindowRef) {
        pendingLeave[w] = nil
        restoreFrames[w] = nil
        guard let t = tracks[w] else {
            if mover.isParked(w) { enterWithoutCard(w) }
            return
        }
        switch t.phase {
        case .preparing:
            // Never parked; the leave is simply called off.
            drop(w)
        case .strip, .entering:
            guard let frame = originalFrame(of: w), isOnOverlay(frame) else {
                // Unknown, or on another display than the overlay: instant.
                drop(w)
                unparkNow([w])
                return
            }
            t.move(to: .entering)
            let generation = t.generation
            t.card.appIcon = nil
            setZ(t.card, Self.transitionZ)
            animator.drive(t.card, to: framePose(frame, card: t.card), spring: layout.tuning.transitionSpring)
            animator.onSettled(t.card) { [weak self] in self?.entered(w, generation: generation) }
        case .revealing:
            break
        }
    }

    /// A parked window with no card (strip cards exist only for visible pile windows) gets
    /// one on demand from its cached snapshot, starting at its stage's slot; no snapshot,
    /// or no known slot: instant unpark.
    private func enterWithoutCard(_ w: WindowRef) {
        guard !fetching.contains(w) else { return }
        guard let placement = lastPlacement[w], let frame = originalFrame(of: w), isOnOverlay(frame) else {
            unparkNow([w])
            return
        }
        fetching.insert(w)
        let capture = self.capture
        Task { @MainActor [weak self] in
            let image = await capture.cachedSnapshot(w)
            guard let self else { return }
            self.fetching.remove(w)
            // Meanwhile it may have left again, been unparked or gained a card.
            guard self.tracks[w] == nil, self.mover.isParked(w),
                  self.board().activeStage?.windows.contains(w) == true else { return }
            guard let image else {
                self.unparkNow([w])
                return
            }
            let card = self.makeCard(image: image)
            let index = min(placement.index, max(0, self.layout.tuning.pileMaxWindows - 1))
            var start = self.stripPose(card: card, slot: placement.slot, stage: placement.stage, index: index)
            start.alpha = 0
            card.apply(start)
            self.overlay.add(card)
            self.tracks[w] = Track(card: card, phase: .strip)
            self.enter(w)
        }
    }

    private func entered(_ w: WindowRef, generation: Int) {
        guard let t = tracks[w], t.phase == .entering, t.generation == generation else { return }
        let ok = !mover.isParked(w) || mover.unpark(w)
        onBatchEnd([w])
        guard ok else {
            // It stays in the ledger (restoreAll / recovery own it). Dropping the card rather
            // than sending it back keeps the next relayout from retrying forever.
            logger.error("could not unpark \(w.windowID, privacy: .public) (pid \(w.pid, privacy: .public)); keeping ledger entry")
            drop(w)
            return
        }
        raiseActiveFront()
        reveal(w, t)
    }

    /// The window is on stage under its card: let it draw for two ticks, then remove the card.
    private func reveal(_ w: WindowRef, _ t: Track) {
        t.move(to: .revealing)
        let generation = t.generation
        animator.afterFrames(2) { [weak self] in
            guard let self, let t = self.tracks[w], t.phase == .revealing, t.generation == generation else { return }
            self.drop(w)
        }
    }

    private func raiseActiveFront() {
        guard let front = board().activeStage?.windows.first, !mover.isParked(front) else { return }
        backend.raise(front)
    }

    // MARK: - Leaving

    private func leave(_ windows: [WindowRef]) {
        var fresh: [WindowRef] = []
        var ready: [(WindowRef, Int)] = []
        for w in windows {
            if let t = tracks[w] {
                switch t.phase {
                case .entering:
                    // Still parked: it just turns around (relayout drives it back).
                    t.move(to: .strip)
                    t.card.side = layout.side
                case .revealing:
                    // Already on stage with its card at its frame: park it as a fresh leave would.
                    t.move(to: .preparing)
                    setZ(t.card, Self.transitionZ)
                    ready.append((w, t.generation))
                case .strip, .preparing:
                    break
                }
                continue
            }
            guard pendingLeave[w] == nil, !mover.isParked(w), !backend.isMinimized(w) else { continue }
            fresh.append(w)
        }
        if !ready.isEmpty { parkAfterCommit(ready) }
        guard !fresh.isEmpty else { return }

        leaveToken += 1
        let token = leaveToken
        for w in fresh { pendingLeave[w] = token }
        let capture = self.capture
        let leaving = fresh
        Task { @MainActor [weak self] in
            // Fresh snapshots if they come back within a frame; the cached ones otherwise.
            await awaitAtMost(Self.snapshotWait) { await capture.refreshOnStage(leaving) }
            var images: [WindowRef: CGImage] = [:]
            for w in leaving {
                if let image = await capture.cachedSnapshot(w) { images[w] = image }
            }
            self?.showLeaving(leaving, token: token, images: images)
        }
    }

    private func showLeaving(_ windows: [WindowRef], token: Int, images: [WindowRef: CGImage]) {
        var ready: [(WindowRef, Int)] = []
        var instant: [WindowRef] = []
        for w in windows where pendingLeave[w] == token {
            pendingLeave[w] = nil
            guard !mover.isParked(w), !backend.isMinimized(w), let frame = backend.frame(of: w) else { continue }
            guard let image = images[w], isOnOverlay(frame) else {
                // No snapshot (or not on the strip's display): Task 9's instant move, no card.
                instant.append(w)
                continue
            }
            let card = makeCard(image: image)
            card.apply(framePose(frame, card: card))
            setZ(card, Self.transitionZ)
            overlay.add(card)
            let t = Track(card: card, phase: .preparing)
            tracks[w] = t
            ready.append((w, t.generation))
        }
        if !instant.isEmpty {
            parkNow(instant)
            relayoutStrip(spring: layout.tuning.transitionSpring)
        }
        if !ready.isEmpty { parkAfterCommit(ready) }
    }

    /// Commits the cards now on screen at their windows' frames, waits a tick so the
    /// overlay has composited, then parks the windows underneath.
    private func parkAfterCommit(_ ready: [(WindowRef, Int)]) {
        CATransaction.flush()
        animator.afterFrames(1) { [weak self] in self?.parkPrepared(ready) }
    }

    private func parkPrepared(_ ready: [(WindowRef, Int)]) {
        var touched: [WindowRef] = []
        for (w, generation) in ready {
            guard let t = tracks[w], t.phase == .preparing, t.generation == generation else { continue }
            if backend.isMinimized(w) {
                drop(w)
                continue
            }
            if mover.isParked(w) {
                t.move(to: .strip)
                continue
            }
            guard let frame = backend.frame(of: w) else {
                logger.error("cannot read frame of \(w.windowID, privacy: .public); not parking")
                drop(w)
                continue
            }
            guard let screen = Screens.containing(frame) else {
                // No screen to park on: the window stays on stage, the card goes.
                logger.error("no screen attached; not parking \(w.windowID, privacy: .public)")
                reveal(w, t)
                continue
            }
            touched.append(w)
            if mover.park(w, display: screen.frame, displayID: screen.id,
                          restoreFrame: restoreFrames.removeValue(forKey: w)) {
                t.move(to: .strip)
            } else {
                // The window is back on stage under its card; nothing to fly back from.
                logger.error("could not park \(w.windowID, privacy: .public) (pid \(w.pid, privacy: .public)); leaving it on screen")
                reveal(w, t)
            }
        }
        onBatchEnd(touched)
        relayoutStrip(spring: layout.tuning.transitionSpring)
    }

    // MARK: - Instant moves (no snapshot)

    private func parkNow(_ windows: [WindowRef]) {
        var touched: [WindowRef] = []
        for w in windows where !mover.isParked(w) && !backend.isMinimized(w) {
            guard let frame = backend.frame(of: w), let screen = Screens.containing(frame) else { continue }
            touched.append(w)
            if !mover.park(w, display: screen.frame, displayID: screen.id,
                           restoreFrame: restoreFrames.removeValue(forKey: w)) {
                logger.error("could not park \(w.windowID, privacy: .public) (pid \(w.pid, privacy: .public)); leaving it on screen")
            }
        }
        onBatchEnd(touched)
    }

    private func unparkNow(_ windows: [WindowRef]) {
        for w in windows where !mover.unpark(w) {
            logger.error("could not unpark \(w.windowID, privacy: .public) (pid \(w.pid, privacy: .public))")
        }
        onBatchEnd(windows)
        raiseActiveFront()
    }

    // MARK: - Strip

    /// Drives every strip card to its slot, pile position, hover and hide state. Drops cards
    /// whose window left the board or was unparked behind our back, and looks up snapshots
    /// for parked strip windows that have no card yet.
    private func relayoutStrip(spring: Spring, onlyStages: Set<UUID>? = nil) {
        let b = board()
        let onBoard = Set(b.stages.flatMap(\.windows))
        for (w, t) in tracks where !onBoard.contains(w) || (t.phase == .strip && !mover.isParked(w)) {
            drop(w)
        }
        if let active = b.activeStage {
            for w in active.windows where tracks[w]?.phase == .strip { enter(w) }
        }

        let stages = b.stripStages
        let slots = stripSlots(for: stages, in: layout.screen, side: layout.side, tuning: layout.tuning)
        if onlyStages == nil { lastPlacement = [:] }
        for stage in stages where onlyStages?.contains(stage.id) ?? true {
            let slot = slots.first { $0.stageID == stage.id }
            for (index, w) in stage.windows.enumerated() {
                if onlyStages == nil { lastPlacement[w] = (stage, index, slot) }
                // Only the visible pile windows have cards (full-res cards cost GPU memory).
                let visible = slot != nil && index < layout.tuning.pileMaxWindows
                guard let t = tracks[w] else {
                    if visible && mover.isParked(w) && onlyStages == nil { fetchStripCard(w) }
                    continue
                }
                guard t.phase == .strip else { continue }
                t.card.side = layout.side
                t.card.appIcon = index == 0 ? icon(for: w.pid) : nil
                setZ(t.card, CGFloat(layout.tuning.pileMaxWindows - index))
                animator.drive(t.card, to: stripPose(card: t.card, slot: slot, stage: stage, index: index),
                               spring: spring)
                if !visible {
                    // Fades out while tucking away, then goes.
                    let generation = t.generation
                    animator.onSettled(t.card) { [weak self] in
                        guard let self, let t = self.tracks[w], t.phase == .strip, t.generation == generation,
                              !self.isVisibleInStrip(w) else { return }
                        self.drop(w)
                    }
                }
            }
        }
    }

    private func isVisibleInStrip(_ w: WindowRef) -> Bool {
        let stages = board().stripStages
        guard let row = stages.firstIndex(where: { $0.windows.contains(w) }),
              let index = stages[row].windows.firstIndex(of: w) else { return false }
        return row < layout.tuning.maxRowCount && index < layout.tuning.pileMaxWindows
    }

    private func isOnOverlay(_ frame: CGRect) -> Bool {
        overlay.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func stripPose(card: WindowCard, slot: StripSlot?, stage: Stage, index: Int) -> CardPose {
        let tuning = layout.tuning
        let band = stripBand(in: layout.screen, side: layout.side, tuning: tuning)
        let offsets = pileOffsets(windowCount: stage.windows.count, side: layout.side, tuning: tuning)
        // Past the pile's depth or the strip's rows: tucked behind, invisible.
        let visible = slot != nil && index < offsets.count
        let pile = offsets.isEmpty ? (offset: CGSize.zero, scale: CGFloat(1)) : offsets[min(index, offsets.count - 1)]
        let frame = slot?.frame ?? CGRect(x: band.midX - tuning.itemMaxSize.width / 2, y: band.maxY,
                                          width: tuning.itemMaxSize.width, height: tuning.itemMaxSize.height)
        let fit = min(frame.width / card.size.width, frame.height / card.size.height) * pile.scale
        var scale = fit
        if hovered == stage.id {
            // Grow by a fixed number of points, whatever the card's displayed size.
            let shown = max(card.size.width, card.size.height) * fit
            if shown > 0 { scale = fit * (shown + tuning.hoverScaleDistance) / shown }
        }
        var center = CGPoint(x: frame.midX + pile.offset.width, y: frame.midY + pile.offset.height)
        if isHidden {
            let outward: CGFloat = layout.side == .right ? 1 : -1
            center.x += outward * (band.width + Self.hiddenShadowMargin)
        }
        return CardPose(center: center, scale: scale, tilt: slot?.tiltRadians ?? 0, alpha: visible ? 1 : 0)
    }

    /// A parked strip window without a card (parked at launch, or moved instantly) gets one
    /// from its cached snapshot, fading in at its slot. No snapshot: no card.
    private func fetchStripCard(_ w: WindowRef) {
        guard !fetching.contains(w) else { return }
        fetching.insert(w)
        let capture = self.capture
        Task { @MainActor [weak self] in
            let image = await capture.cachedSnapshot(w)
            guard let self else { return }
            self.fetching.remove(w)
            guard let image, self.tracks[w] == nil, self.mover.isParked(w), self.isVisibleInStrip(w),
                  let stage = self.board().stripStages.first(where: { $0.windows.contains(w) }) else { return }
            let card = self.makeCard(image: image)
            let slots = stripSlots(for: self.board().stripStages, in: self.layout.screen,
                                   side: self.layout.side, tuning: self.layout.tuning)
            var start = self.stripPose(card: card, slot: slots.first { $0.stageID == stage.id }, stage: stage,
                                       index: stage.windows.firstIndex(of: w) ?? 0)
            start.alpha = 0
            card.apply(start)
            self.overlay.add(card)
            self.tracks[w] = Track(card: card, phase: .strip)
            self.relayoutStrip(spring: self.layout.tuning.transitionSpring, onlyStages: [stage.id])
        }
    }

    // MARK: - Cards

    private func makeCard(image: CGImage) -> WindowCard {
        // Always the snapshot's point size: `contentsGravity = .resize` distorts otherwise.
        let scale = overlay.screen.backingScaleFactor
        let size = CGSize(width: max(1, CGFloat(image.width) / scale), height: max(1, CGFloat(image.height) / scale))
        let card = WindowCard(size: size, side: layout.side, tuning: layout.tuning)
        card.image = image
        return card
    }

    private func framePose(_ frame: CGRect, card: WindowCard) -> CardPose {
        CardPose(center: CGPoint(x: frame.midX, y: frame.midY),
                 scale: frame.width / card.size.width, tilt: 0, alpha: 1)
    }

    private func setZ(_ card: WindowCard, _ z: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.layer.zPosition = z
        CATransaction.commit()
    }

    private func drop(_ w: WindowRef) {
        pendingLeave[w] = nil
        guard let t = tracks.removeValue(forKey: w) else { return }
        animator.cancel(t.card)
        overlay.remove(t.card)
    }

    private func originalFrame(of w: WindowRef) -> CGRect? {
        ledger.entries().first { $0.window == w }?.originalFrame
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }
}

/// Runs `work` and returns when it finishes or after `seconds`, whichever comes first.
/// `work` keeps running in the background if it takes longer.
@MainActor
func awaitAtMost(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> Void) async {
    final class Once {
        var continuation: CheckedContinuation<Void, Never>?
        func fire() {
            continuation?.resume()
            continuation = nil
        }
    }
    let once = Once()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        once.continuation = continuation
        Task { @MainActor in
            await work()
            once.fire()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { once.fire() }
        }
    }
}
