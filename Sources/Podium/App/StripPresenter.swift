import AppKit
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// The strip's input side: the StripPanel's clicks and hover, auto-hide, and dragging a
/// stage window's title bar into the band. It reads the board and tells the Coordinator
/// what the user asked for; the TransitionRunner draws.
@MainActor
final class StripPresenter {
    var onSelect: (UUID) -> Void = { _ in }
    var onShiftClick: (UUID) -> Void = { _ in }
    var onCombine: (UUID) -> Void = { _ in }
    var onDragOut: (WindowRef) -> Void = { _ in }

    private static let pollInterval = 1.0 / 30.0
    /// Overlap frames are re-read from AX every this many polls (30 Hz / 3 = 10 Hz).
    private static let frameRefreshEvery = 3
    /// A title-bar drag must move the window at least this far to count.
    private static let minimumDragDistance: CGFloat = 2

    private let backend: AXWindowBackend
    private let mover: WindowMover
    private let runner: TransitionRunner
    private let board: () -> StageBoard
    private let panel: StripPanel
    private var latch = HoverLatch()
    private var autoHide: AutoHide
    private var pointerInPanel: CGPoint?
    private var pollTimer: Timer?
    private var pollTick = 0
    private var stageFrames: [CGRect] = []
    private var monitors: [Any] = []
    /// Active-stage window frames at the last mouse-down (drag-out detection).
    private var framesAtMouseDown: [WindowRef: CGRect] = [:]

    private var layout: TransitionRunner.Layout { runner.layout }
    private var band: CGRect { stripBand(in: layout.screen, side: layout.side, tuning: layout.tuning) }

    init(backend: AXWindowBackend, mover: WindowMover, runner: TransitionRunner, board: @escaping () -> StageBoard) {
        self.backend = backend
        self.mover = mover
        self.runner = runner
        self.board = board
        autoHide = AutoHide(tuning: runner.layout.tuning)
        panel = StripPanel(band: stripBand(in: runner.layout.screen, side: runner.layout.side,
                                           tuning: runner.layout.tuning))
        panel.onClick = { [weak self] in self?.onSelect($0) }
        panel.onShiftClick = { [weak self] in self?.onShiftClick($0) }
        panel.onDragToStage = { [weak self] in self?.onCombine($0) }
        panel.onHover = { [weak self] point in
            self?.pointerInPanel = point
            self?.updateHover()
        }
    }

    /// Shows the (clear) panel right away: a new window's first composite costs a frame.
    func start() {
        panel.show()
        boardChanged()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { monitors.append(down) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }) { monitors.append(up) }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    /// The board or the layout changed: new hit targets, band and hover.
    func boardChanged() {
        if panel.band != band { panel.setBand(band) }
        panel.targets = slots().map { ($0.stageID, $0.frame) }
        updateMouseTaking()
        updateHover()
    }

    private func slots() -> [StripSlot] {
        stripSlots(for: board().stripStages, in: layout.screen, side: layout.side, tuning: layout.tuning)
    }

    private func updateHover() {
        latch.update(pointer: runner.isHidden ? nil : pointerInPanel, slots: slots())
        runner.setHovered(latch.hovered)
    }

    /// Hidden, or nothing to click: clicks in the band reach the windows underneath.
    private func updateMouseTaking() {
        panel.ignoresMouseEvents = runner.isHidden || panel.targets.isEmpty
    }

    // MARK: - Auto-hide

    private func poll() {
        pollTick += 1
        if pollTick % Self.frameRefreshEvery == 1 { refreshStageFrames() }
        let band = self.band
        let area = band.width * band.height
        let covered = stageFrames.reduce(CGFloat(0)) { sum, frame in
            let i = frame.intersection(band)
            return i.isNull ? sum : sum + i.width * i.height
        }
        let overlap = area > 0 ? min(1, Double(covered / area)) : 0
        let wasHidden = autoHide.isHidden
        autoHide.update(overlapFraction: overlap, pointer: Self.pointer(), band: band,
                        screen: layout.screen, side: layout.side, now: ProcessInfo.processInfo.systemUptime)
        guard autoHide.isHidden != wasHidden else { return }
        runner.setHidden(autoHide.isHidden)
        if autoHide.isHidden { pointerInPanel = nil }
        updateMouseTaking()
        updateHover()
    }

    /// AX frames of the active stage's on-screen windows.
    private func refreshStageFrames() {
        let b = board()
        stageFrames = (b.activeStage?.windows ?? []).compactMap { w in
            mover.isParked(w) || b.isMinimized(w) ? nil : backend.frame(of: w)
        }
    }

    // MARK: - Drag-out

    private func mouseDown() {
        let b = board()
        var frames: [WindowRef: CGRect] = [:]
        for w in b.activeStage?.windows ?? [] where !mover.isParked(w) {
            if let frame = backend.frame(of: w) { frames[w] = frame }
        }
        framesAtMouseDown = frames
    }

    /// A stage window whose title bar was dragged and released over the band.
    private func mouseUp() {
        defer { framesAtMouseDown = [:] }
        guard !framesAtMouseDown.isEmpty, !runner.isHidden, band.contains(Self.pointer()),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let id = AX.focusedWindow(of: pid).flatMap(AX.windowID(of:)) else { return }
        let w = WindowRef(pid: pid, windowID: id)
        guard let before = framesAtMouseDown[w], let after = backend.frame(of: w) else { return }
        let moved = hypot(after.minX - before.minX, after.minY - before.minY) >= Self.minimumDragDistance
        // A resize also moves the origin; only a move keeps the size.
        let sameSize = abs(after.width - before.width) <= 1 && abs(after.height - before.height) <= 1
        guard moved, sameSize else { return }
        onDragOut(w)
    }

    /// The pointer in AX (top-left-origin) coordinates.
    private static func pointer() -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
