import AppKit
import ApplicationServices
import PodiumCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuID { case power, setUp, left, right, minimizeStrip, minimizeDock, autoHide, restore, stageManager }
    private var menuItems: [MenuID: NSMenuItem] = [:]
    private let settings = Settings()
    private var onboarding: OnboardingWindowController?
    /// Accessibility was revoked while running; recovery waits for it to return.
    private var accessibilityLost = false
    /// A debug flag parked windows by hand; no Coordinator may start.
    private var debugHold = false
    private var axWasTrusted = false
    private var hadPermissions = false
    /// Apple's Stage Manager read as on at the last tick.
    private var appleStageManagerWasOn = false
    private var alertShowing = false
    private var statusItem: NSStatusItem?
    private let backend = AXWindowBackend()
    private lazy var ledger = ParkingLedger(fileURL: Self.ledgerURL)
    private lazy var mover = WindowMover(backend: backend, ledger: ledger)
    private var signalSources: [DispatchSourceSignal] = []
    private var trustTimer: Timer?
    private var coordinator: Coordinator?
    private var debugCards: DebugCards?
    private lazy var capture: Capture = {
        let mover = self.mover
        return Capture(isParked: { mover.isParked($0) })
    }()

    private static var ledgerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Podium", isDirectory: true)
            .appendingPathComponent("parked.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--debug-cards") {
            // No permission prompts, no Coordinator, no capture: just cards and springs.
            let debugCards = DebugCards()
            self.debugCards = debugCards
            debugCards.start()
            return
        }
        NSLog("Podium: AXIsProcessTrusted=%d screenRecording=%d", AXIsProcessTrusted(), CGPreflightScreenCaptureAccess())
        installStatusItem()
        installSignalHandlers()

        // A previous run (or crash) may have left windows parked.
        axWasTrusted = AXIsProcessTrusted()
        hadPermissions = hasPermissions
        appleStageManagerWasOn = AppleStageManager.isEnabled
        if axWasTrusted { mover.recover(visibleScreens: backend.visibleScreens()) }
        if !hasPermissions || !settings.onboarded || (settings.enabled && appleStageManagerWasOn) { showOnboarding() }
        syncCoordinator()

        // One poll covers everything permission-related: the first grant, a revoke while
        // running, and the grant coming back. Common modes so menus and alerts don't stall it.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Debug-cards mode never parks anything, so it must not touch other apps' windows.
        guard debugCards == nil else { return }
        restoreWindows()
    }

    // MARK: - Permissions and lifecycle

    private var hasPermissions: Bool { AXIsProcessTrusted() && CGPreflightScreenCaptureAccess() }

    /// Set up: both permissions granted, onboarding completed, and Apple's Stage Manager off
    /// (two Stage Managers would fight over every window).
    private var ready: Bool { hasPermissions && settings.onboarded && !AppleStageManager.isEnabled }

    /// Podium manages windows only when it is on and set up.
    private var shouldManage: Bool { settings.enabled && ready }

    private func tick() {
        let ax = AXIsProcessTrusted()
        if coordinator != nil, !ax {
            axWasTrusted = false
            accessibilityRevoked()
            return
        }
        if ax, !axWasTrusted {
            // Accessibility just (re)appeared: put back whatever is still parked, whether or
            // not Podium is going to manage windows.
            NSLog("Podium: Accessibility is available; recovering")
            mover.recover(visibleScreens: backend.visibleScreens())
        }
        axWasTrusted = ax
        let permitted = hasPermissions
        if permitted, !hadPermissions, !settings.onboarded, onboarding?.isShowing != true {
            showOnboarding()
        }
        hadPermissions = permitted
        if alertShowing { return }
        // Apple's Stage Manager turned on while Podium runs: `syncCoordinator` takes the Off
        // path (every window restored) and the onboarding window says why.
        let appleStageManagerOn = AppleStageManager.isEnabled
        if appleStageManagerOn, !appleStageManagerWasOn, settings.enabled, onboarding?.isShowing != true {
            NSLog("Podium: Apple's Stage Manager is on; restoring windows and pausing")
            showOnboarding()
        }
        appleStageManagerWasOn = appleStageManagerOn
        syncCoordinator()
    }

    /// Without Accessibility no window can move: stop everything but keep the ledger, so the
    /// recovery that runs when the permission returns puts the windows back.
    private func accessibilityRevoked() {
        NSLog("Podium: Accessibility revoked; suspending")
        coordinator?.suspend()
        coordinator = nil
        showAccessibilityAlert(title: "Podium lost Accessibility access",
                               text: "Podium can't move windows without it, so it has stopped. Your windows will be restored as soon as you grant Accessibility access again.")
    }

    /// One alert at a time, shown after the current run-loop pass.
    private func showAccessibilityAlert(title: String, text: String) {
        guard !alertShowing else { return }
        alertShowing = true
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            let open = alert.runModal() == .alertFirstButtonReturn
            self?.alertShowing = false
            if open, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Starts or stops the Coordinator so it matches `shouldManage`.
    private func syncCoordinator() {
        guard debugHold == false else { return }
        let manage = shouldManage
        if manage, coordinator == nil {
            startManaging()
        } else if !manage, let coordinator {
            if AXIsProcessTrusted() { coordinator.restoreAll() } else { coordinator.suspend() }
            self.coordinator = nil
        }
    }

    /// A full fresh start: recovery, then a new Coordinator (seed, observer, tap, strip).
    private func startManaging() {
        mover.recover(visibleScreens: backend.visibleScreens())
        if let bundleID = Self.debugParkBundle() {
            // The kill test parks one app's windows by hand; stage switching would fight it.
            debugHold = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.debugPark(bundleID: bundleID) }
            return
        }
        if let bundleID = Self.debugArgument("--debug-capture-parked") {
            debugHold = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.debugCaptureParked(bundleID: bundleID) }
            return
        }
        let coordinator = Coordinator(backend: backend, mover: mover, ledger: ledger, capture: capture)
        coordinator.setSide(settings.side)
        coordinator.minimizeBehavior = settings.minimizeBehavior
        coordinator.autoHideEnabled = settings.autoHide
        self.coordinator = coordinator
        coordinator.start()
    }

    /// Puts every window back without changing any setting (quit, signals).
    private func restoreWindows() {
        guard AXIsProcessTrusted() else { return }
        if let coordinator {
            // Stops stage switching too, so restored windows stay put.
            coordinator.restoreAll()
            self.coordinator = nil
        } else {
            mover.restoreAll()
        }
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(
                onTurnedOffAppleStageManager: { [weak self] in self?.settings.turnedOffAppleStageManager = true },
                onFinish: { [weak self] completed in
                    guard let self else { return }
                    if completed { self.settings.onboarded = true }
                    self.syncCoordinator()
                })
        }
        onboarding?.show()
    }

    // MARK: - Menu actions

    @objc private func togglePodium() {
        if !settings.enabled, !ready {
            settings.enabled = true
            showOnboarding()
            return
        }
        settings.enabled.toggle()
        syncCoordinator()
    }

    @objc private func setSideLeft() { setSide(.left) }
    @objc private func setSideRight() { setSide(.right) }

    private func setSide(_ side: StripSide) {
        settings.side = side
        coordinator?.setSide(side)
    }

    @objc private func setMinimizeStrip() { setMinimize(.strip) }
    @objc private func setMinimizeDock() { setMinimize(.dock) }

    private func setMinimize(_ behavior: MinimizeBehavior) {
        settings.minimizeBehavior = behavior
        coordinator?.minimizeBehavior = behavior
    }

    @objc private func toggleAutoHide() {
        settings.autoHide.toggle()
        coordinator?.autoHideEnabled = settings.autoHide
    }

    /// Emergency action: restores every window and leaves Podium Off (the menu shows it);
    /// turn it back on from the menu.
    @objc private func restoreAll() {
        settings.enabled = false
        syncCoordinator()
        if AXIsProcessTrusted() {
            mover.restoreAll()
        } else {
            showAccessibilityAlert(title: "Accessibility access is needed",
                                   text: "Podium can't move windows without it. Any parked windows will be restored as soon as you grant Accessibility access again.")
        }
    }

    @objc private func setUpPodium() { showOnboarding() }

    /// Opens Desktop & Dock settings; the item disappears once Stage Manager reads as on.
    @objc private func turnAppleStageManagerBackOn() {
        AppleStageManager.enable()
    }

    // MARK: - Setup

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Podium")

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        func add(_ id: MenuID, _ title: String, _ action: Selector) {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
            m.target = self
            menu.addItem(m)
            menuItems[id] = m
        }
        add(.power, "Turn Podium Off", #selector(togglePodium))
        add(.setUp, "Set Up Podium…", #selector(setUpPodium))
        menu.addItem(.separator())
        add(.left, "Strip on Left", #selector(setSideLeft))
        add(.right, "Strip on Right", #selector(setSideRight))
        menu.addItem(.separator())
        add(.minimizeStrip, "Minimize to Strip", #selector(setMinimizeStrip))
        add(.minimizeDock, "Minimize to Dock", #selector(setMinimizeDock))
        menu.addItem(.separator())
        add(.autoHide, "Auto-hide Strip", #selector(toggleAutoHide))
        menu.addItem(.separator())
        add(.restore, "Restore All Windows", #selector(restoreAll))
        add(.stageManager, "Turn Apple's Stage Manager Back On", #selector(turnAppleStageManagerBackOn))
        if Self.debugMenuEnabled {
            let flip = NSMenuItem(title: "Flip Side", action: #selector(flipSide), keyEquivalent: "")
            flip.target = self
            menu.addItem(flip)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Podium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuItems[.power]?.title = settings.enabled ? "Turn Podium Off" : "Turn Podium On"
        menuItems[.setUp]?.isHidden = ready
        menuItems[.left]?.state = settings.side == .left ? .on : .off
        menuItems[.right]?.state = settings.side == .right ? .on : .off
        menuItems[.minimizeStrip]?.state = settings.minimizeBehavior == .strip ? .on : .off
        menuItems[.minimizeDock]?.state = settings.minimizeBehavior == .dock ? .on : .off
        menuItems[.autoHide]?.state = settings.autoHide ? .on : .off
        if settings.turnedOffAppleStageManager, AppleStageManager.isEnabled {
            settings.turnedOffAppleStageManager = false
        }
        menuItems[.stageManager]?.isHidden = !settings.turnedOffAppleStageManager
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.restoreWindows() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Debug

    /// Debug builds always; release builds only with `--debug-menu`.
    private static var debugMenuEnabled: Bool {
        #if DEBUG
        return true
        #else
        return CommandLine.arguments.contains("--debug-menu")
        #endif
    }

    @objc private func flipSide() {
        setSide(settings.side == .right ? .left : .right)
    }

    private static func debugParkBundle() -> String? {
        debugArgument("--debug-park-bundle")
    }

    private static func debugArgument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Written after a debug park, so scripts/kill-test.sh can tell kills that happened
    /// after parking from kills that happened before it.
    private static var debugParkMarkerURL: URL {
        ledgerURL.deletingLastPathComponent().appendingPathComponent("debug-parked")
    }

    private func debugPark(bundleID: String) {
        var parked = 0
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            for w in backend.manageableWindows(of: app.processIdentifier) {
                guard let frame = backend.frame(of: w), let screen = Screens.containing(frame) else { continue }
                let ok = mover.park(w, display: screen.frame, displayID: screen.id)
                if ok { parked += 1 }
                NSLog("Podium: debug park %u -> %@", w.windowID, ok ? "parked" : "failed")
            }
        }
        guard parked > 0 else { return }
        do {
            try "\(parked)\n".write(to: Self.debugParkMarkerURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Podium: could not write debug park marker: %@", String(describing: error))
        }
    }

    /// Parks one of the app's windows and live-captures it at 5 fps for 30 s, logging each
    /// frame's arrival and whether its content changed, then unparks it. Answers whether
    /// parked windows keep producing live frames (see the research doc, "Still unknown").
    private func debugCaptureParked(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let w = backend.manageableWindows(of: app.processIdentifier).first,
              let frame = backend.frame(of: w) else {
            NSLog("Podium: debug capture: no manageable window of %@", bundleID)
            return
        }
        let capture = self.capture
        Task { @MainActor in
            do {
                _ = try await capture.snapshot(w, pointSize: frame.size)
                NSLog("Podium: debug capture: on-stage snapshot of %u ok", w.windowID)
            } catch {
                NSLog("Podium: debug capture: on-stage snapshot of %u failed: %@", w.windowID, String(describing: error))
            }
            guard let screen = Screens.containing(frame),
                  mover.park(w, display: screen.frame, displayID: screen.id) else {
                NSLog("Podium: debug capture: could not park %u", w.windowID)
                return
            }
            NSLog("Podium: debug capture: parked %u; live at 5 fps for 30 s", w.windowID)

            let stats = DebugFrameStats()
            let handle: LiveHandle
            do {
                handle = try await capture.startLive(w, maxPixelSize: Capture.defaultMaxPixelSize, fps: 5) { image in
                    MainActor.assumeIsolated { stats.record(image) }
                }
            } catch {
                NSLog("Podium: debug capture: startLive failed: %@", String(describing: error))
                _ = mover.unpark(w)
                return
            }
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await capture.stopLive(handle)
            let unparked = mover.unpark(w)
            NSLog("Podium: debug capture: done; frames=%d distinct=%d changes=%d; unpark %@",
                  stats.frames, stats.distinct.count, stats.changes, unparked ? "ok" : "failed")
        }
    }
}

/// Frame log for `--debug-capture-parked`.
@MainActor
private final class DebugFrameStats {
    private(set) var frames = 0
    private(set) var changes = 0
    private(set) var distinct: Set<Int> = []
    private var lastHash: Int?
    private var lastTime: CFAbsoluteTime?

    func record(_ image: CGImage) {
        let now = CFAbsoluteTimeGetCurrent()
        let hash = Self.contentHash(image)
        let changed = lastHash.map { $0 != hash } ?? false
        frames += 1
        if changed { changes += 1 }
        distinct.insert(hash)
        NSLog("Podium: debug capture: frame %d t=%.3f dt=%.3f %dx%d content=%@",
              frames, now, lastTime.map { now - $0 } ?? 0, image.width, image.height,
              changed ? "changed" : (lastHash == nil ? "first" : "same"))
        lastHash = hash
        lastTime = now
    }

    /// Hashes every pixel byte (Data's own hash only looks at a prefix).
    private static func contentHash(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        return hasher.finalize()
    }
}
