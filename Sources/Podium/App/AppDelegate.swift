import AppKit
import ApplicationServices
import PodiumCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        NSLog("Podium: AXIsProcessTrusted=%d", AXIsProcessTrusted())
        installStatusItem()
        installSignalHandlers()

        if AXIsProcessTrusted() {
            accessibilityGranted()
        } else {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                MainActor.assumeIsolated { self?.accessibilityGranted() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Debug-cards mode never parks anything, so it must not touch other apps' windows.
        guard debugCards == nil else { return }
        restoreAll()
    }

    private func accessibilityGranted() {
        mover.recover(visibleScreens: backend.visibleScreens())
        if let bundleID = Self.debugParkBundle() {
            // The kill test parks one app's windows by hand; stage switching would fight it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.debugPark(bundleID: bundleID) }
            return
        }
        if let bundleID = Self.debugArgument("--debug-capture-parked") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.debugCaptureParked(bundleID: bundleID) }
            return
        }
        let coordinator = Coordinator(backend: backend, mover: mover, ledger: ledger, capture: capture)
        self.coordinator = coordinator
        coordinator.start()
    }

    @objc private func restoreAll() {
        guard AXIsProcessTrusted() else { return }
        if let coordinator {
            // Stops stage switching too, so restored windows stay put.
            coordinator.restoreAll()
            self.coordinator = nil
        } else {
            mover.restoreAll()
        }
    }

    // MARK: - Setup

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Podium")

        let menu = NSMenu()
        let restore = NSMenuItem(title: "Restore All Windows", action: #selector(restoreAll), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
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

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.restoreAll() }
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
        coordinator?.flipSide()
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
                guard let frame = backend.frame(of: w) else { continue }
                let screen = Screens.containing(frame)
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
            let screen = Screens.containing(frame)
            guard mover.park(w, display: screen.frame, displayID: screen.id) else {
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
