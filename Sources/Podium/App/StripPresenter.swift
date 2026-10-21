import AppKit
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// The strip's input side: the StripPanel's clicks and hover, auto-hide, and dragging a
/// stage window's title bar into the band. It reads the board and tells the Coordinator
/// what the user asked for; the TransitionRunner draws.
///
/// Nothing here makes AX calls: the poll and the mouse monitors run constantly, and an AX
/// call to a hung app blocks the main thread (and every animation) for up to a second.
/// Window frames come from the window server's list instead.
@MainActor
final class StripPresenter {
    var onSelect: (UUID) -> Void = { _ in }
    var onShiftClick: (UUID) -> Void = { _ in }
    var onCombine: (UUID) -> Void = { _ in }
    /// The dragged window and its frame before the drag.
    var onDragOut: (WindowRef, CGRect) -> Void = { _, _ in }

    private static let pollInterval = 1.0 / 30.0
    /// Overlap frames are re-read every this many polls (30 Hz / 3 = 10 Hz).
    private static let frameRefreshEvery = 3
    /// A title-bar drag must move the window at least this far to count.
    private static let minimumDragDistance: CGFloat = 2

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

    init(mover: WindowMover, runner: TransitionRunner, board: @escaping () -> StageBoard) {
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

    private func refreshStageFrames() {
        stageFrames = Array(activeStageFrames().values)
    }

    /// Window-server bounds (top-left-origin global, like AX) of the active stage's
    /// on-screen windows. No app IPC, so a hung app can't stall the caller.
    private func activeStageFrames() -> [WindowRef: CGRect] {
        let b = board()
        let wanted = (b.activeStage?.windows ?? []).filter { !mover.isParked($0) && !b.isMinimized($0) }
        guard !wanted.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        let byID = Dictionary(wanted.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var frames: [WindowRef: CGRect] = [:]
        for window in info {
            guard let number = window[kCGWindowNumber as String] as? UInt32, let w = byID[number],
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            frames[w] = frame
        }
        return frames
    }

    // MARK: - Drag-out

    private func mouseDown() {
        framesAtMouseDown = activeStageFrames()
    }

    /// A stage window whose title bar was dragged and released over the band: the one
    /// active-stage window that moved without changing size since the mouse went down.
    private func mouseUp() {
        defer { framesAtMouseDown = [:] }
        guard !framesAtMouseDown.isEmpty, !runner.isHidden, band.contains(Self.pointer()) else { return }
        let now = activeStageFrames()
        let moved = framesAtMouseDown.filter { w, before in
            guard let after = now[w] else { return false }
            let distance = hypot(after.minX - before.minX, after.minY - before.minY)
            // A resize also moves the origin; only a move keeps the size.
            let sameSize = abs(after.width - before.width) <= 1 && abs(after.height - before.height) <= 1
            return distance >= Self.minimumDragDistance && sameSize
        }
        guard moved.count == 1, let (w, before) = moved.first else { return }
        onDragOut(w, before)
    }

    /// The pointer in AX (top-left-origin) coordinates.
    private static func pointer() -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
