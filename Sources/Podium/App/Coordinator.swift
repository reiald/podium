import AppKit
import ApplicationServices
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Owns the stage model and keeps the screen in sync with it: only the active stage's
/// windows stay on screen, every other window is parked.
///
/// After each model change the old and new board are diffed into a `TransitionPlan`, which
/// the `TransitionRunner` plays as card animations (parking and unparking under the cards).
/// The `StripPresenter` turns strip clicks, hover, auto-hide and drags into model changes.
@MainActor
final class Coordinator {
    private(set) var side: StripSide = .right
    private(set) var board: StageBoard
    let tuning = Tuning.initial

    private let backend: AXWindowBackend
    private let mover: WindowMover
    private let ledger: ParkingLedger
    private let capture: Capture
    private var snapshotTimer: Timer?
    private var snapshotTick = 0
    /// Non-focused on-stage windows are refreshed every this many ticks (1 s each).
    private static let backgroundSnapshotEvery = 4
    private var observer: WindowObserver?
    private var runner: TransitionRunner?
    private var presenter: StripPresenter?
    private var interceptor: MinimizeInterceptor?
    /// What the yellow button and Cmd-M do. Settings (Task 14) will own this.
    var minimizeBehavior: MinimizeBehavior = .strip
    /// Windows the minimize fallback is bringing back from the Dock, until the given time:
    /// their own (de)minimize and focus noise must not move stages meanwhile.
    private var unminimizing: [WindowRef: Date] = [:]
    /// Windows the fallback gave up on: their `.minimized` takes the Dock path.
    private var dockFallback: Set<WindowRef> = []
    private static let unminimizePoll: TimeInterval = 0.02
    private static let unminimizeTimeout: TimeInterval = 0.5
    /// How long after the fallback started its window's events are still ignored.
    private static let unminimizeQuiet: TimeInterval = 1.5
    /// Set by `restoreAll`; a start still waiting on launch snapshots then does nothing.
    private var stopped = false
    /// How long launch waits for snapshots of every window before parking (strip cards).
    private static let launchSnapshotWait: TimeInterval = 1
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// Windows Podium moved, until `inFlightWindow` after the batch that moved them ended.
    /// Moving a window can make its app report focus changes that must not switch stages;
    /// stamping at batch end means slow AX calls can't let those through.
    private var inFlight: [WindowRef: Date] = [:]
    private var batchTouched: Set<WindowRef> = []
    private static let inFlightWindow: TimeInterval = 0.5

    /// Events that arrive while a change is being applied wait their turn.
    private var applying = false
    private var pending: [WindowEvent] = []

    init(backend: AXWindowBackend, mover: WindowMover, ledger: ParkingLedger, capture: Capture) {
        self.backend = backend
        self.mover = mover
        self.ledger = ledger
        self.capture = capture
        self.board = StageBoard(displayID: Screens.all.first?.id ?? 0)
    }

    // MARK: - Lifecycle

    func start() {
        guard runner == nil else { return }
        seedBoard()
        guard let runner = TransitionRunner(backend: backend, mover: mover, ledger: ledger, capture: capture,
                                            layout: layout, board: { [weak self] in self?.board ?? StageBoard(displayID: 0) })
        else {
            // No display: nothing to animate on; instant moves only.
            NSLog("Podium: no screen; stage switching without animation")
            finishStart()
            return
        }
        runner.onBatchEnd = { [weak self] in self?.stamp($0) }
        self.runner = runner
        let presenter = StripPresenter(mover: mover, runner: runner,
                                       board: { [weak self] in self?.board ?? StageBoard(displayID: 0) })
        presenter.onSelect = { [weak self] in self?.select(stageID: $0) }
        presenter.onShiftClick = { [weak self] in self?.addFrontWindowToActive(stageID: $0) }
        presenter.onCombine = { [weak self] in self?.combineIntoActive(stageID: $0) }
        presenter.onDragOut = { [weak self] in self?.dragOut($0, restoreTo: $1) }
        self.presenter = presenter
        // Overlay (in the runner) and panel are shown now, not at the first transition.
        presenter.start()

        // Snapshot every window while it is still on screen, so parked stages get strip
        // cards; never hold launch up for more than a moment.
        let windows = board.stages.flatMap(\.windows)
        let capture = self.capture
        Task { @MainActor [weak self] in
            if CGPreflightScreenCaptureAccess() {
                await awaitAtMost(Self.launchSnapshotWait) { await capture.refreshOnStage(windows) }
            }
            self?.finishStart()
        }
    }

    private func finishStart() {
        guard !stopped else { return }
        reconcile()
        let observer = WindowObserver { [weak self] in self?.handle($0) }
        self.observer = observer
        observer.start()

        let interceptor = MinimizeInterceptor(behavior: { [weak self] in self?.minimizeBehavior ?? .dock },
                                              isManaged: { [weak self] in self?.canMinimizeToStrip($0) ?? false },
                                              onIntercept: { [weak self] in self?.minimizeToStrip($0) })
        self.interceptor = interceptor
        interceptor.start()

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screensChanged()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in
            self?.reseed()
            self?.startSnapshotTimer()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.stopSnapshotTimer()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.startSnapshotTimer()
        }
        if !CGPreflightScreenCaptureAccess() {
            // Shows the system prompt once; capture starts working after a relaunch.
            CGRequestScreenCaptureAccess()
        }
        startSnapshotTimer()
    }

    /// Stops managing windows and puts every parked window back.
    func restoreAll() {
        stopped = true
        interceptor?.stop()
        interceptor = nil
        observer?.stop()
        observer = nil
        presenter?.stop()
        presenter = nil
        runner?.shutdown()
        runner = nil
        stopSnapshotTimer()
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens = []
        mover.restoreAll()
    }

    // MARK: - Events

    func handle(_ e: WindowEvent) {
        guard !applying else {
            pending.append(e)
            return
        }
        applying = true
        defer { applying = false }
        process(e)
        while !pending.isEmpty { process(pending.removeFirst()) }
    }

    /// Shows the stage (strip click).
    func select(stageID: UUID) {
        guard isRunning, !applying else { return }
        let old = board
        board.activate(stageID: stageID)
        // Make its front window the app's most recent one, so the app activation that
        // follows maps back to this stage rather than another stage of the same app.
        if let front = board.activeStage?.windows.first { board.windowFocused(front) }
        apply(from: old)
        if let front = board.activeStage?.windows.first,
           let app = NSRunningApplication(processIdentifier: front.pid), !app.isActive {
            app.activate()
        }
    }

    /// Shift-click: the stage's front window joins the active stage.
    func addFrontWindowToActive(stageID: UUID) {
        guard isRunning, !applying, let front = board.stages.first(where: { $0.id == stageID })?.windows.first else { return }
        let old = board
        board.addToActiveStage(front)
        apply(from: old)
    }

    /// A strip thumbnail dragged onto the stage: its windows join the active stage.
    func combineIntoActive(stageID: UUID) {
        guard isRunning, !applying else { return }
        let old = board
        board.combineIntoActive(stageID: stageID)
        apply(from: old)
    }

    /// A stage window's title bar dragged into the strip band: the window gets its own stage
    /// (`moveToOwnStage`), and, as in Stage Manager, that stage goes to the strip while the
    /// rest of the old stage stays on screen. It comes back to `restoreTo`, where it was
    /// before the drag, not to where it was dropped over the band.
    func dragOut(_ w: WindowRef, restoreTo: CGRect) {
        guard isRunning, !applying, let previous = board.activeStageID,
              board.activeStage?.windows.contains(w) == true else { return }
        let old = board
        board.moveToOwnStage(w)
        guard board != old else { return }
        runner?.setRestoreFrame(restoreTo, for: w)
        board.activate(stageID: previous)
        if let front = board.activeStage?.windows.first { board.windowFocused(front) }
        apply(from: old)
    }

    /// Whether a minimize of `w` can go to the strip: an on-screen window of the active stage.
    private func canMinimizeToStrip(_ w: WindowRef) -> Bool {
        isRunning && board.activeStage?.windows.contains(w) == true && !mover.isParked(w) && !board.isMinimized(w)
    }

    /// Minimize to strip: the window is parked, not minimized. It gets its own stage at the
    /// front of the strip and flies there; the rest of its stage stays on screen, and if it
    /// was alone the stage area is left empty (desktop).
    func minimizeToStrip(_ w: WindowRef) {
        guard !applying, canMinimizeToStrip(w), let previous = board.activeStageID,
              let count = board.activeStage?.windows.count else {
            NSLog("Podium: minimize to strip of %u (pid %d) no longer applies", w.windowID, w.pid)
            return
        }
        let old = board
        if count > 1 {
            board.moveToOwnStage(w)
            board.activate(stageID: previous)
            if let front = board.activeStage?.windows.first { board.windowFocused(front) }
        } else {
            // Activating first puts the stage at the front of the most-recently-used order.
            board.activate(stageID: previous)
            board.activate(stageID: nil)
        }
        apply(from: old)
        // The parked window must not keep keyboard focus: the stage's next window takes it.
        if let front = board.activeStage?.windows.first, !mover.isParked(front) {
            backend.raise(front)
            if front.pid != w.pid, let app = NSRunningApplication(processIdentifier: front.pid), !app.isActive {
                app.activate()
            }
        }
    }

    /// Fallback for minimizes the interceptor didn't see (Window menu, custom title bars, a
    /// disabled tap): bring the window back from the Dock, then minimize it to the strip.
    private func unminimizeIntoStrip(_ w: WindowRef) {
        let started = Date()
        unminimizing[w] = started.addingTimeInterval(Self.unminimizeQuiet)
        guard backend.setMinimized(false, of: w) else {
            NSLog("Podium: could not un-minimize %u (pid %d); leaving it in the Dock", w.windowID, w.pid)
            dockInstead(w)
            return
        }
        Timer.scheduledTimer(withTimeInterval: Self.unminimizePoll, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return timer.invalidate() }
                if !self.backend.isMinimized(w) {
                    timer.invalidate()
                    self.minimizeToStrip(w)
                } else if Date().timeIntervalSince(started) > Self.unminimizeTimeout {
                    timer.invalidate()
                    NSLog("Podium: %u (pid %d) still minimized after %.1f s; leaving it in the Dock",
                          w.windowID, w.pid, Self.unminimizeTimeout)
                    self.dockInstead(w)
                }
            }
        }
    }

    /// The fallback failed: handle the minimize the stock way (Task 9).
    private func dockInstead(_ w: WindowRef) {
        unminimizing[w] = nil
        dockFallback.insert(w)
        handle(.minimized(w))
    }

    private func isUnminimizing(_ w: WindowRef) -> Bool {
        let now = Date()
        unminimizing = unminimizing.filter { $0.value > now }
        return unminimizing[w] != nil
    }

    /// Debug menu: moves the strip to the other side; every card retargets live.
    func flipSide() {
        side = side == .right ? .left : .right
        runner?.update(layout: layout)
        presenter?.boardChanged()
    }

    /// Launch finished (windows parked, events observed) and not stopped.
    private var isRunning: Bool { observer != nil }

    private var layout: TransitionRunner.Layout {
        (side: side, screen: Screens.all.first?.frame ?? .zero, tuning: tuning)
    }

    private func process(_ e: WindowEvent) {
        let old = board
        var minimized: WindowRef?
        switch e {
        case let .opened(w):
            guard isOnBoard(w) || shouldManage(w) else { return }
            board.windowOpened(w)
        case let .closed(w):
            // A spurious destroyed notification must not strand a parked window: only a
            // window the window server no longer lists is gone. It may lag the notification,
            // so a window still listed is checked once more a moment later.
            let live = backend.liveWindows()
            if live.contains(w) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeRecheckDelay) { [weak self] in
                    guard let self, !self.backend.liveWindows().contains(w) else { return }
                    self.handle(.closed(w))
                }
                return
            }
            board.windowClosed(w)
            runner?.forget(w)
            // An empty answer means the query failed: keep the ledger entry.
            if !live.isEmpty { mover.forget(w) }
            let capture = self.capture
            Task { await capture.forget(w) }
        case let .focused(w):
            // Parked windows count: Cmd-`, the Window menu, the Dock and Mission Control
            // focus them, and that must bring their stage forward. Minimized ones don't.
            guard !isInFlight(w), !isUnminimizing(w), !backend.isMinimized(w) else { return }
            if !isOnBoard(w) {
                // A window we never saw open (e.g. on another Space at launch).
                guard shouldManage(w) else { return }
                board.windowOpened(w)
            }
            board.windowFocused(w)
        case let .minimized(w):
            if dockFallback.remove(w) == nil, minimizeBehavior == .strip, canMinimizeToStrip(w) {
                // Not intercepted (Window menu, custom title bar): bring it back, then park it.
                guard !isUnminimizing(w) else { return }
                unminimizeIntoStrip(w)
                return
            }
            // The Dock took it off screen; never park it.
            minimized = w
            board.minimize(w)
        case let .deminimized(w):
            // The fallback un-minimizing it: it is about to go to the strip instead.
            guard !isUnminimizing(w) else { return }
            board.deminimize(w)
        case let .appActivated(pid):
            guard pid != getpid() else { return }
            // Prefer the window the app actually focused; fall back to its most recent one.
            // A window Podium just moved doesn't count: after `select`, the app can still
            // report the window that was just parked.
            if let focused = focusedWindow(of: pid), isOnBoard(focused), !isInFlight(focused),
               !backend.isMinimized(focused) {
                board.windowFocused(focused)
            } else {
                board.appActivated(pid: pid)
            }
        case let .appTerminated(pid):
            board.appTerminated(pid: pid)
            let capture = self.capture
            Task { await capture.forgetApp(pid: pid) }
            for e in ledger.entries() where e.window.pid == pid { mover.forget(e.window) }
        }
        apply(from: old, alreadyOffScreen: minimized.map { [$0] } ?? [])
    }

    private static let closeRecheckDelay: TimeInterval = 0.5

    private func focusedWindow(of pid: pid_t) -> WindowRef? {
        AX.focusedWindow(of: pid).flatMap(AX.windowID(of:)).map { WindowRef(pid: pid, windowID: $0) }
    }

    private func shouldManage(_ w: WindowRef) -> Bool {
        w.pid != getpid() && backend.canManage(w)
    }

    private func isOnBoard(_ w: WindowRef) -> Bool {
        board.stages.contains { $0.windows.contains(w) }
    }

    // MARK: - Snapshots

    /// Keeps on-stage snapshots fresh so a transition never waits on a capture: the focused
    /// window every second, the rest every few seconds. Stopped while displays sleep.
    private func startSnapshotTimer() {
        guard snapshotTimer == nil else { return }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapshotTimerFired() }
        }
    }

    private func stopSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    private func snapshotTimerFired() {
        // Without Screen Recording every capture would fail; skip until it's granted.
        guard CGPreflightScreenCaptureAccess() else { return }
        snapshotTick += 1
        refreshSnapshots(all: snapshotTick % Self.backgroundSnapshotEvery == 0)
    }

    /// Re-captures the active stage's on-screen windows (only its front window unless `all`)
    /// in the background. Call it with `all: true` right before a transition starts too; it
    /// never blocks the caller.
    func refreshSnapshots(all: Bool = true) {
        let active = board.activeStage?.windows ?? []
        let windows = (all ? active : Array(active.prefix(1))).filter { w in
            !mover.isParked(w) && !isInFlight(w) && !board.isMinimized(w)
        }
        guard !windows.isEmpty else { return }
        let capture = self.capture
        Task { await capture.refreshOnStage(windows) }
    }

    // MARK: - Applying the model

    private func apply(from old: StageBoard, alreadyOffScreen: Set<WindowRef> = []) {
        guard board != old else { return }
        var plan = transitionPlan(from: old, to: board)
        plan.leaving.removeAll { alreadyOffScreen.contains($0) }
        // A parked window can join the active stage without having been in the strip (it
        // re-joined the board, e.g. a kept ledger entry focused via Cmd-`): it enters too.
        let entering = Set(plan.entering)
        plan.entering += (board.activeStage?.windows ?? []).filter { !entering.contains($0) && mover.isParked($0) }
        for w in alreadyOffScreen { runner?.forget(w) }
        // In flight from the start: the moves happen a few frames (or a whole flight) later,
        // and the focus noise of the app switch must not bounce stages meanwhile.
        stamp(plan.leaving + plan.entering)
        if let runner {
            runner.run(plan, layout: layout)
        } else {
            show(plan.entering.filter { mover.isParked($0) })
            hide(plan.leaving)
            endBatch()
        }
        // Entering windows are raised by the runner once they are unparked.
        if old.activeStageID != board.activeStageID, let front = board.activeStage?.windows.first,
           !mover.isParked(front) {
            backend.raise(front)
        }
        presenter?.boardChanged()
    }

    /// Unparks; a window that fails stays in the ledger (restoreAll / recovery still own it).
    private func show(_ windows: [WindowRef]) {
        for w in windows {
            batchTouched.insert(w)
            if !mover.unpark(w) { NSLog("Podium: could not unpark %u (pid %d)", w.windowID, w.pid) }
        }
    }

    /// Parks; a window that fails stays on screen and in its stage.
    private func hide(_ windows: [WindowRef]) {
        for w in windows where !mover.isParked(w) && !backend.isMinimized(w) {
            guard let frame = backend.frame(of: w) else {
                NSLog("Podium: cannot read frame of %u (pid %d); not parking", w.windowID, w.pid)
                continue
            }
            let screen = Screens.containing(frame)
            batchTouched.insert(w)
            if !mover.park(w, display: screen.frame, displayID: screen.id) {
                NSLog("Podium: could not park %u (pid %d); leaving it on screen", w.windowID, w.pid)
            }
        }
    }

    /// Makes the screen match the board from scratch: active stage shown, all else parked.
    /// Instant; cards of windows it moves are dropped, then the strip is laid out again.
    private func reconcile() {
        let active = Set(board.activeStage?.windows ?? [])
        let toShow = board.stages.flatMap(\.windows).filter { active.contains($0) && mover.isParked($0) }
        runner?.discardCards(for: toShow)
        show(toShow)
        hide(board.stages.flatMap(\.windows).filter { !active.contains($0) })
        if let front = board.activeStage?.windows.first { backend.raise(front) }
        endBatch()
        runner?.update(layout: layout)
        presenter?.boardChanged()
    }

    /// Stamps every window the batch touched, counting from now (the batch's end).
    private func endBatch() {
        stamp(Array(batchTouched))
        batchTouched = []
    }

    /// Marks windows in flight for `inFlightWindow`, counting from now.
    private func stamp(_ windows: [WindowRef]) {
        let until = Date().addingTimeInterval(Self.inFlightWindow)
        for w in windows { inFlight[w] = until }
    }

    private func isInFlight(_ w: WindowRef) -> Bool {
        let now = Date()
        inFlight = inFlight.filter { $0.value > now }
        return inFlight[w] != nil
    }

    // MARK: - Seeding

    /// Every on-screen manageable window joins its app's stage, back to front, so the
    /// frontmost app's stage ends up active. `finishStart` then parks everything else.
    private func seedBoard() {
        for w in onScreenWindowsBackToFront() { board.windowOpened(w) }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            board.appActivated(pid: front)
        }
    }

    /// After sleep: drop windows that died, add windows that appeared, then re-check
    /// that the screen matches the board and parked windows are still parked.
    private func reseed() {
        let live = backend.liveWindows()
        // An empty answer means the query failed; forget nothing.
        if !live.isEmpty {
            for w in board.stages.flatMap(\.windows) where !live.contains(w) { board.windowClosed(w) }
            for e in ledger.entries() where !live.contains(e.window) { mover.forget(e.window) }
        }
        let activeBefore = board.activeStageID
        for w in onScreenWindowsBackToFront() where !isOnBoard(w) { board.windowOpened(w) }
        // New windows may have switched stages; the frontmost app's stage wins, else the old one.
        if let activeBefore { board.activate(stageID: activeBefore) }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            board.appActivated(pid: front)
        }
        reconcile()
        screensChanged()
    }

    private func screensChanged() {
        guard let main = Screens.all.first else { return }
        // Repark moves every parked window (and unparks those it can't keep parked).
        batchTouched.formUnion(ledger.entries().map(\.window))
        mover.repark(display: main.frame)
        endBatch()
        runner?.screensChanged(layout: layout)
        presenter?.boardChanged()
    }

    /// Manageable windows of regular apps, in on-screen z-order from back to front.
    /// Parked windows (still 1 pt on screen) are excluded.
    private func onScreenWindowsBackToFront() -> [WindowRef] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("Podium: CGWindowListCopyWindowInfo failed; seeding nothing")
            return []
        }
        var regular: [pid_t: Bool] = [:]
        func isRegular(_ pid: pid_t) -> Bool {
            if let known = regular[pid] { return known }
            let r = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            regular[pid] = r
            return r
        }
        let frontToBack = info.compactMap { window -> WindowRef? in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let number = window[kCGWindowNumber as String] as? UInt32,
                  pid != getpid(), isRegular(pid) else { return nil }
            let w = WindowRef(pid: pid, windowID: number)
            return !mover.isParked(w) && backend.canManage(w) ? w : nil
        }
        return frontToBack.reversed()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { body() }
        }
        notificationTokens.append((center, token))
    }
}
