import AppKit
import ApplicationServices
import PodiumCore
// Carbon (via AppKit) also declares `WindowRef`; this scoped import makes it mean Podium's.
import struct PodiumCore.WindowRef

/// Owns the stage model and keeps the screen in sync with it: only the active stage's
/// windows stay on screen, every other window is parked.
///
/// After each model change the old and new active stage are diffed: windows that joined are
/// unparked first, then windows that left are parked, so the screen never goes empty
/// mid-switch. Moves are instant here; Task 12 animates them.
@MainActor
final class Coordinator {
    var side: StripSide = .right
    private(set) var board: StageBoard

    private let backend: AXWindowBackend
    private let mover: WindowMover
    private var observer: WindowObserver?
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// Windows Podium is moving right now, until `inFlightWindow` after the move. Moving a
    /// window can make its app report focus changes that must not switch stages.
    private var inFlight: [WindowRef: Date] = [:]
    private static let inFlightWindow: TimeInterval = 0.5

    /// Events that arrive while a change is being applied wait their turn.
    private var applying = false
    private var pending: [WindowEvent] = []

    init(backend: AXWindowBackend, mover: WindowMover) {
        self.backend = backend
        self.mover = mover
        self.board = StageBoard(displayID: Screens.all.first?.id ?? 0)
    }

    // MARK: - Lifecycle

    func start() {
        guard observer == nil else { return }
        seed()
        let observer = WindowObserver { [weak self] in self?.handle($0) }
        self.observer = observer
        observer.start()

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screensChanged()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in
            self?.reseed()
        }
    }

    /// Stops managing windows and puts every parked window back.
    func restoreAll() {
        observer?.stop()
        observer = nil
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

    private func process(_ e: WindowEvent) {
        let old = board
        var minimized: WindowRef?
        switch e {
        case let .opened(w):
            guard isOnBoard(w) || shouldManage(w) else { return }
            board.windowOpened(w)
        case let .closed(w):
            board.windowClosed(w)
        case let .focused(w):
            guard !isInFlight(w), !mover.isParked(w) else { return }
            if !isOnBoard(w) {
                // A window we never saw open (e.g. on another Space at launch).
                guard shouldManage(w) else { return }
                board.windowOpened(w)
            }
            board.windowFocused(w)
        case let .minimized(w):
            // The Dock already took it off screen; never park it. Minimize-to-strip is Task 13.
            minimized = w
            board.minimize(w)
        case let .appActivated(pid):
            guard pid != getpid() else { return }
            board.appActivated(pid: pid)
        case let .appTerminated(pid):
            board.appTerminated(pid: pid)
        }
        apply(from: old, alreadyOffScreen: minimized.map { [$0] } ?? [])
    }

    private func shouldManage(_ w: WindowRef) -> Bool {
        w.pid != getpid() && backend.canManage(w)
    }

    private func isOnBoard(_ w: WindowRef) -> Bool {
        board.stages.contains { $0.windows.contains(w) }
    }

    // MARK: - Applying the model

    private func apply(from old: StageBoard, alreadyOffScreen: Set<WindowRef> = []) {
        guard board != old else { return }
        let oldActive = old.activeStage?.windows ?? []
        let newActive = board.activeStage?.windows ?? []
        let newActiveSet = Set(newActive)
        let entering = newActive.filter { mover.isParked($0) }
        let leaving = oldActive.filter { w in
            !newActiveSet.contains(w) && isOnBoard(w) && !alreadyOffScreen.contains(w)
        }
        show(entering)
        hide(leaving)
        if old.activeStageID != board.activeStageID, let front = newActive.first {
            backend.raise(front)
        }
    }

    /// Unparks; a window that fails stays in the ledger (restoreAll / recovery still own it).
    private func show(_ windows: [WindowRef]) {
        for w in windows {
            markInFlight(w)
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
            markInFlight(w)
            if !mover.park(w, display: screen.frame, displayID: screen.id) {
                NSLog("Podium: could not park %u (pid %d); leaving it on screen", w.windowID, w.pid)
            }
        }
    }

    /// Makes the screen match the board from scratch: active stage shown, all else parked.
    private func reconcile() {
        let active = Set(board.activeStage?.windows ?? [])
        show(board.stages.flatMap(\.windows).filter { active.contains($0) && mover.isParked($0) })
        hide(board.stages.flatMap(\.windows).filter { !active.contains($0) })
        if let front = board.activeStage?.windows.first { backend.raise(front) }
    }

    private func markInFlight(_ w: WindowRef) {
        inFlight[w] = Date().addingTimeInterval(Self.inFlightWindow)
    }

    private func isInFlight(_ w: WindowRef) -> Bool {
        let now = Date()
        inFlight = inFlight.filter { $0.value > now }
        return inFlight[w] != nil
    }

    // MARK: - Seeding

    /// Every on-screen manageable window joins its app's stage, back to front, so the
    /// frontmost app's stage ends up active; then everything else is parked.
    private func seed() {
        for w in onScreenWindowsBackToFront() { board.windowOpened(w) }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            board.appActivated(pid: front)
        }
        reconcile()
    }

    /// After sleep: drop windows that died, add windows that appeared, then re-check
    /// that the screen matches the board and parked windows are still parked.
    private func reseed() {
        let live = backend.liveWindows()
        // An empty answer means the query failed; forget nothing.
        if !live.isEmpty {
            for w in board.stages.flatMap(\.windows) where !live.contains(w) { board.windowClosed(w) }
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
        mover.repark(display: main.frame)
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
