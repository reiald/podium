import AppKit
import ApplicationServices
import PodiumCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let backend = AXWindowBackend()
    private lazy var mover = WindowMover(backend: backend, ledger: ParkingLedger(fileURL: Self.ledgerURL))
    private var signalSources: [DispatchSourceSignal] = []
    private var trustTimer: Timer?

    private static var ledgerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Podium", isDirectory: true)
            .appendingPathComponent("parked.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
                self?.accessibilityGranted()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreAll()
    }

    private func accessibilityGranted() {
        mover.recover(visibleScreens: backend.visibleScreens())
        if let bundleID = Self.debugParkBundle() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.debugPark(bundleID: bundleID) }
        }
    }

    @objc private func restoreAll() {
        guard AXIsProcessTrusted() else { return }
        mover.restoreAll()
    }

    // MARK: - Setup

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Podium")

        let menu = NSMenu()
        let restore = NSMenuItem(title: "Restore All Windows", action: #selector(restoreAll), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
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
                self?.restoreAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Debug

    private static func debugParkBundle() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--debug-park-bundle"), i + 1 < args.count else { return nil }
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
}
