import AppKit
import os
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// The strip's input side: the StripPanel's clicks, hover and thumbnail drags, auto-hide,
/// and dragging a stage window's title bar into the band. It reads the board and tells the Coordinator
/// what the user asked for; the TransitionRunner draws.
///
/// Nothing here makes AX calls: the poll and the mouse monitors run constantly, and an AX
/// call to a hung app blocks the main thread (and every animation) for up to a second.
/// Window frames come from the window server's list instead.
///
/// An item's app icon opens the app view: the strip lists only that app's off-stage windows,
/// one per item (`TransitionRunner.setAppView`). Clicking one brings exactly that window on
/// stage; a shift-click or drop adds it to the stage. The view closes on Esc, the icon again,
/// a click outside the strip, the app running out of off-stage windows (or quitting), and
/// any board change that brings more of the app's windows on stage.
@MainActor
final class StripPresenter {
    var onSelect: (UUID) -> Void = { _ in }
    var onShiftClick: (UUID) -> Void = { _ in }
    /// The dropped stage, and the window whose card was dragged (nil if the press never
    /// became a drag before the release).
    var onCombine: (UUID, WindowRef?) -> Void = { _, _ in }
    /// The dragged window and its frame before the drag.
    var onDragOut: (WindowRef, CGRect) -> Void = { _, _ in }
    /// App view click: exactly this window on stage.
    var onShowWindow: (WindowRef) -> Void = { _ in }
    /// App view shift-click or drop: this window joins the stage.
    var onAddWindow: (WindowRef) -> Void = { _ in }

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
    private var autoHideEnabled = true
    private var pointerInPanel: CGPoint?
    private var pollTimer: Timer?
    private var pollTick = 0
    private var stageFrames: [CGRect] = []
    private var monitors: [Any] = []
    /// The window whose strip card is being dragged (the stage's front window when the drag
    /// began); while set, the strip must not hide under it.
    private var draggedWindow: WindowRef?
    private var isDraggingThumbnail = false
    /// When the poll first saw no button down mid-drag (see `checkLostMouseUp`).
    private var releasedSince: TimeInterval?
    /// A mouse-up normally arrives well within this; past it, it was lost.
    private static let lostMouseUpDelay: TimeInterval = 0.25
    /// Active-stage window frames at the last mouse-down (drag-out detection).
    private var framesAtMouseDown: [WindowRef: CGRect] = [:]
    /// While the app view is open: the app's windows on the active stage (more closes it).
    private var appViewOnStage: Set<WindowRef> = []
    /// Esc monitors, only while the app view is open.
    private var escapeMonitors: [Any] = []
    private static let escapeKeyCode: UInt16 = 53
    private let logger = Logger(subsystem: "dev.podium.Podium", category: "strip")

    private var layout: TransitionRunner.Layout { runner.layout }
    private var band: CGRect { stripBand(in: layout.screen, side: layout.side, tuning: layout.tuning) }

    init(mover: WindowMover, runner: TransitionRunner, board: @escaping () -> StageBoard) {
        self.mover = mover
        self.runner = runner
        self.board = board
        autoHide = AutoHide(tuning: runner.layout.tuning)
        panel = StripPanel(band: stripBand(in: runner.layout.screen, side: runner.layout.side,
                                           tuning: runner.layout.tuning))
        panel.onClick = { [weak self] in self?.clicked($0, shift: false) }
        panel.onShiftClick = { [weak self] in self?.clicked($0, shift: true) }
        panel.onIconClick = { [weak self] in self?.iconClicked($0) }
        panel.iconTarget = { [weak runner] in runner?.iconTarget(at: $0) }
        panel.onDragBegan = { [weak self] id, p in
            guard let self else { return }
            self.isDraggingThumbnail = true
            self.draggedWindow = self.runner.stripStages().first { $0.id == id }?.windows.first
            self.runner.beginDrag(stageID: id, at: p)
        }
        panel.onDragMoved = { [weak self] in self?.runner.dragTo($0) }
        panel.onDragEnded = { [weak self] id, dropped in self?.dragEnded(id, dropped: dropped) }
        // The panel only sees the pointer while it takes the mouse; the pointer's real
        // position (read in `trackPointer`) drives hover either way, so no exit flicker.
        panel.onHover = { [weak self] _ in self?.trackPointer() }
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
        // Pointer moves over other apps: the panel must take the mouse as soon as the pointer
        // reaches a slot, before the click, without waiting for the next poll.
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }) { monitors.append(moved) }
    }

    func stop() {
        closeAppView(reason: "stop")
        panel.cancelDrag()
        pollTimer?.invalidate()
        pollTimer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    /// The board or the layout changed: new hit targets, band and hover.
    func boardChanged() {
        checkAppView()
        if panel.band != band { panel.setBand(band) }
        panel.targets = slots().map { ($0.stageID, $0.frame) }
        updateMouseTaking()
        updateHover()
    }

    private func slots() -> [StripSlot] {
        stripSlots(for: runner.stripStages(), in: layout.screen, side: layout.side, tuning: layout.tuning)
    }

    private func updateHover() {
        latch.update(pointer: runner.isHidden ? nil : pointerInPanel, slots: slots())
        runner.setHovered(latch.hovered)
    }

    /// Reads the pointer: hover follows it inside the band, and the panel takes the mouse
    /// only while it is over a target.
    private func trackPointer() {
        let p = Self.pointer()
        let inBand = !runner.isHidden && band.contains(p) ? p : nil
        if inBand != pointerInPanel {
            pointerInPanel = inBand
            updateHover()
        }
        updateMouseTaking(pointer: p)
    }

    /// The panel takes the mouse only while the pointer is over a slot target of a shown
    /// strip. Everywhere else in the band (gaps, empty rows, a hidden strip) clicks, scroll
    /// and drags reach the windows underneath.
    private func updateMouseTaking(pointer: CGPoint? = nil) {
        let p = pointer ?? Self.pointer()
        // Mid-press, whoever got the mouse-down keeps the mouse until it is released.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let overTarget = !runner.isHidden
            && (panel.targets.contains { $0.frame.contains(p) } || runner.iconTarget(at: p) != nil)
        if panel.ignoresMouseEvents == overTarget { panel.ignoresMouseEvents = !overTarget }
    }

    // MARK: - Auto-hide

    /// Off: the strip never hides, and shows again if it was hidden.
    func setAutoHideEnabled(_ enabled: Bool) {
        autoHideEnabled = enabled
        guard !enabled else { return }
        autoHide = AutoHide(tuning: runner.layout.tuning)
        guard runner.isHidden else { return }
        runner.setHidden(false)
        updateMouseTaking()
        updateHover()
    }

    private func poll() {
        pollTick += 1
        checkLostMouseUp()
        trackPointer()
        if pollTick % Self.frameRefreshEvery == 1 { refreshStageFrames() }
        let band = self.band
        let area = band.width * band.height
        let covered = stageFrames.reduce(CGFloat(0)) { sum, frame in
            let i = frame.intersection(band)
            return i.isNull ? sum : sum + i.width * i.height
        }
        let overlap = area > 0 ? min(1, Double(covered / area)) : 0
        guard autoHideEnabled, !isDraggingThumbnail else { return }
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

    // MARK: - Thumbnail drag

    /// The card springs back or, dropped, enters from where it is as the stage combines.
    private func dragEnded(_ id: UUID, dropped: Bool) {
        let w = draggedWindow
        isDraggingThumbnail = false
        draggedWindow = nil
        releasedSince = nil
        runner.endDrag(dropped: dropped)
        guard dropped else { return }
        if runner.appView != nil {
            if let w { onAddWindow(w) }
        } else {
            onCombine(id, w)
        }
    }

    /// Mission Control or a screen lock can eat the mouse-up, leaving the drag open (card
    /// frozen, auto-hide off). A release the panel hasn't heard about shortly after is called
    /// off; the grace keeps a poll that runs just before the queued mouse-up from cancelling.
    private func checkLostMouseUp() {
        guard isDraggingThumbnail, NSEvent.pressedMouseButtons & 1 == 0 else {
            releasedSince = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let since = releasedSince ?? now
        releasedSince = since
        if now - since >= Self.lostMouseUpDelay { panel.cancelDrag() }
    }

    // MARK: - Drag-out

    private func mouseDown() {
        // Another app got the click: it was outside the strip's items.
        closeAppView(reason: "click outside")
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

    // MARK: - App view

    /// In the app view an item is one window: a click shows exactly it, a shift-click adds it.
    private func clicked(_ id: UUID, shift: Bool) {
        guard runner.appView != nil else { return shift ? onShiftClick(id) : onSelect(id) }
        guard let w = runner.stripStages().first(where: { $0.id == id })?.windows.first else { return }
        if shift {
            onAddWindow(w)
        } else {
            closeAppView(reason: "window chosen")
            onShowWindow(w)
        }
    }

    /// Opens the app view of the item's front app; with one off-stage window it is just a
    /// click on the item. A second icon click closes it.
    private func iconClicked(_ id: UUID) {
        guard runner.appView == nil else { return closeAppView(reason: "icon clicked again") }
        let b = board()
        guard let pid = runner.stripStages().first(where: { $0.id == id })?.windows.first?.pid else { return }
        guard appWindowItems(board: b, pid: pid).count > 1 else { return onSelect(id) }
        appViewOnStage = appWindowsOnStage(pid, b)
        runner.setAppView(pid: pid, anchor: slots().first { $0.stageID == id })
        watchEscape()
        boardChanged()
    }

    /// Closes the app view once the app has no off-stage window left or more of its
    /// windows came on stage.
    private func checkAppView() {
        guard let pid = runner.appView?.pid else { return }
        let b = board()
        let onStage = appWindowsOnStage(pid, b)
        if appWindowItems(board: b, pid: pid).isEmpty {
            closeAppView(reason: "no off-stage windows")
        } else if !onStage.isSubset(of: appViewOnStage) {
            closeAppView(reason: "app came on stage")
        } else {
            appViewOnStage = onStage
        }
    }

    private func appWindowsOnStage(_ pid: pid_t, _ b: StageBoard) -> Set<WindowRef> {
        Set((b.activeStage?.windows ?? []).filter { $0.pid == pid })
    }

    private func closeAppView(reason: String) {
        guard runner.appView != nil else { return }
        logger.log("closing app view: \(reason, privacy: .public)")
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
        appViewOnStage = []
        runner.setAppView(pid: nil)
        boardChanged()
    }

    /// The panel never becomes key, so Esc reaches whichever app is active: a global monitor
    /// sees it there, a local one if Podium is active.
    private func watchEscape() {
        let escape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return false }
            return MainActor.assumeIsolated {
                guard let self, self.runner.appView != nil else { return false }
                self.closeAppView(reason: "Esc")
                return true
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = escape($0) }) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { escape($0) ? nil : $0 }) {
            escapeMonitors.append(local)
        }
    }

    /// The pointer in AX (top-left-origin) coordinates.
    private static func pointer() -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
