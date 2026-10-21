// THROWAWAY SPIKE: does a snapshot-based "fly into a right-side strip" feel like Stage Manager?
// Primary display only. Static snapshots (no live thumbnails). Not Podium's real architecture.
import AppKit
import ApplicationServices
import QuartzCore
import ScreenCaptureKit

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum Tuning {
    static let stripWidth: CGFloat = 200
    static let thumbBox = CGSize(width: 150, height: 110)
    static let slotSpacing: CGFloat = 28
    static let edgeInset: CGFloat = 22
    static let tilt: CGFloat = 0.30
    static let perspective: CGFloat = 800
    static let windowCornerRadius: CGFloat = 16
    static let springDuration: Double = 0.5
    static let springBounce: Double = 0.08
    static let hoverScale: CGFloat = 1.08
    static let autoHideDelay: TimeInterval = 0.3
}

// MARK: - Accessibility helpers (AX coordinates: origin at top-left of the primary display)

func focusedWindow(of pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
    return (value as! AXUIElement)
}

func frame(of window: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func setPosition(of window: AXUIElement, to point: CGPoint) {
    var point = point
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
}

func snapshot(windowID: CGWindowID, size: CGSize) async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
        throw NSError(domain: "spike", code: 1, userInfo: [NSLocalizedDescriptionKey: "window \(windowID) not shareable"])
    }
    let config = SCStreamConfiguration()
    let scale = NSScreen.screens[0].backingScaleFactor
    config.width = Int(size.width * scale)
    config.height = Int(size.height * scale)
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
}

// MARK: - Views

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

final class ClickCatcher: FlippedView {
    var onClick: ((CGPoint) -> Void)?
    var onHover: ((CGPoint?) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) { onHover?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
}

struct Parked {
    let window: AXUIElement
    let app: NSRunningApplication
    let originalFrame: CGRect
    let layer: CALayer
}

// MARK: - App

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    let screen = NSScreen.screens[0].frame
    var overlay: NSWindow!
    var root: FlippedView!
    var panel: StripPanel!
    var parked: [Parked] = []
    var signalSources: [DispatchSourceSignal] = []
    let status = NSTextField(labelWithString: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        CGRequestScreenCaptureAccess()

        overlay = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        root = FlippedView(frame: CGRect(origin: .zero, size: screen.size))
        root.wantsLayer = true
        overlay.contentView = root
        overlay.orderFrontRegardless()

        let stripRect = CGRect(x: screen.maxX - Tuning.stripWidth, y: screen.minY, width: Tuning.stripWidth, height: screen.height)
        panel = StripPanel(contentRect: stripRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // Explicitly false so the clear panel still catches clicks (transparent areas otherwise fall through).
        panel.ignoresMouseEvents = false
        let catcher = ClickCatcher(frame: CGRect(origin: .zero, size: stripRect.size))
        catcher.onClick = { [weak self] p in self?.stripClicked(at: CGPoint(x: stripRect.minX + p.x, y: p.y)) }
        catcher.onHover = { [weak self] p in self?.hover(at: p.map { CGPoint(x: stripRect.minX + $0.x, y: $0.y) }) }
        panel.contentView = catcher
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickAutoHide() }
        }

        let hud = NSVisualEffectView(frame: CGRect(x: 12, y: 60, width: 176, height: 130))
        hud.material = .hudWindow
        hud.state = .active
        hud.wantsLayer = true
        hud.layer!.cornerRadius = 14
        let title = NSTextField(labelWithString: "Podium Spike")
        title.font = .boldSystemFont(ofSize: 13)
        title.frame = CGRect(x: 16, y: 100, width: 150, height: 18)
        let park = NSButton(title: "Park front window", target: self, action: #selector(parkTapped))
        park.frame = CGRect(x: 8, y: 64, width: 160, height: 30)
        let quit = NSButton(title: "Quit spike", target: self, action: #selector(quitTapped))
        quit.frame = CGRect(x: 8, y: 32, width: 160, height: 30)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = CGRect(x: 16, y: 10, width: 150, height: 16)
        status.stringValue = AXIsProcessTrusted() ? "Ready" : "No Accessibility permission"
        [title, park, quit, status].forEach(hud.addSubview)
        catcher.addSubview(hud)
        panel.orderFrontRegardless()

        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in self?.restoreAll(); exit(0) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ note: Notification) { restoreAll() }

    @objc func parkTapped() { Task { await parkFrontWindow() } }
    @objc func quitTapped() { NSApp.terminate(nil) }

    func restoreAll() {
        for item in parked { setPosition(of: item.window, to: item.originalFrame.origin) }
        parked.removeAll()
    }

    // MARK: Stage -> strip

    func fail(_ reason: String) {
        status.stringValue = reason
        NSLog("PodiumSpike: \(reason)")
        NSSound.beep()
    }

    func parkFrontWindow() async {
        guard AXIsProcessTrusted() else { return fail("No Accessibility permission") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return fail("No front app") }
        guard let window = focusedWindow(of: app.processIdentifier) else { return fail("No window in \(app.localizedName ?? "app")") }
        guard let windowFrame = frame(of: window) else { return fail("Can't read window frame") }
        guard !parked.contains(where: { CFEqual($0.window, window) }) else { return fail("Already parked") }
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success else { return fail("Can't get window ID") }
        let image: CGImage
        do { image = try await snapshot(windowID: windowID, size: windowFrame.size) } catch {
            return fail("Snapshot failed (Screen Recording?)")
        }
        status.stringValue = "Parked \(app.localizedName ?? "window")"

        let layer = makeCard(image: image, size: windowFrame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        root.layer!.addSublayer(layer)
        CATransaction.commit()
        CATransaction.flush()
        // Let the stand-in reach the screen before the real window leaves, so there is no blink.
        try? await Task.sleep(for: .milliseconds(20))
        setPosition(of: window, to: CGPoint(x: screen.maxX - 1, y: screen.maxY - 1))

        parked.insert(Parked(window: window, app: app, originalFrame: windowFrame, layer: layer), at: 0)
        layoutStrip()
    }

    // MARK: Strip -> stage (swapping out whatever is in front, like Stage Manager)

    func stripClicked(at point: CGPoint) {
        guard let index = parked.indices.first(where: { slotRect(for: $0).insetBy(dx: -10, dy: -10).contains(point) }) else { return }
        let item = parked.remove(at: index)
        Task {
            await parkFrontWindow()
            unpark(item)
        }
    }

    func unpark(_ item: Parked) {
        let target = item.originalFrame
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            setPosition(of: item.window, to: target.origin)
            AXUIElementPerformAction(item.window, kAXRaiseAction as CFString)
            item.app.activate()
            // Let the real window draw before the stand-in disappears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                item.layer.removeFromSuperlayer()
                CATransaction.commit()
            }
        }
        spring(item.layer, "position", to: NSValue(point: CGPoint(x: target.midX, y: target.midY)))
        spring(item.layer, "transform", to: NSValue(caTransform3D: CATransform3DIdentity))
        CATransaction.commit()
        layoutStrip()
    }

    // MARK: Hover & auto-hide

    var hoveredIndex: Int?
    var stripHidden = false
    var mouseLeftStripAt: Date?

    func hover(at point: CGPoint?) {
        let index = point.flatMap { p in parked.indices.first { slotRect(for: $0).insetBy(dx: -10, dy: -10).contains(p) } }
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        layoutStrip()
    }

    func tickAutoHide() {
        let m = NSEvent.mouseLocation
        let mouse = CGPoint(x: m.x, y: screen.maxY - m.y)
        let stripRect = CGRect(x: screen.maxX - Tuning.stripWidth, y: 0, width: Tuning.stripWidth, height: screen.height)
        let inStrip = stripRect.contains(mouse)
        if inStrip { mouseLeftStripAt = nil } else if mouseLeftStripAt == nil { mouseLeftStripAt = Date() }

        var hide = stripHidden
        if stripHidden {
            if mouse.x >= screen.maxX - 3 { hide = false }
        } else if !inStrip, let left = mouseLeftStripAt, Date().timeIntervalSince(left) > Tuning.autoHideDelay,
                  frontWindowOverlaps(stripRect) {
            hide = true
        }
        guard hide != stripHidden else { return }
        stripHidden = hide
        panel.ignoresMouseEvents = hide
        hoveredIndex = nil
        layoutStrip()
    }

    func frontWindowOverlaps(_ rect: CGRect) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let window = focusedWindow(of: app.processIdentifier), let f = frame(of: window) else { return false }
        // Parked windows sit off-screen at the corner; they don't count.
        return f.minX < screen.maxX - 5 && f.intersects(rect)
    }

    // MARK: Layout & animation

    func slotRect(for index: Int) -> CGRect {
        let count = CGFloat(parked.count)
        let total = count * Tuning.thumbBox.height + (count - 1) * Tuning.slotSpacing
        let top = (screen.height - total) / 2
        let y = top + CGFloat(index) * (Tuning.thumbBox.height + Tuning.slotSpacing)
        let x = screen.maxX - Tuning.edgeInset - Tuning.thumbBox.width
        return CGRect(x: x, y: y, width: Tuning.thumbBox.width, height: Tuning.thumbBox.height)
    }

    func layoutStrip() {
        for (i, item) in parked.enumerated() {
            let slot = slotRect(for: i)
            let size = item.originalFrame.size
            let hover: CGFloat = i == hoveredIndex ? Tuning.hoverScale : 1
            let scale = min(slot.width / size.width, slot.height / size.height) * hover
            var t = CATransform3DIdentity
            t.m34 = -1 / Tuning.perspective
            t = CATransform3DRotate(t, Tuning.tilt, 0, 1, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            let x = slot.midX + (stripHidden ? Tuning.stripWidth : 0)
            spring(item.layer, "position", to: NSValue(point: CGPoint(x: x, y: slot.midY)))
            spring(item.layer, "transform", to: NSValue(caTransform3D: t))
        }
    }

    func makeCard(image: CGImage, size: CGSize) -> CALayer {
        let card = CALayer()
        card.bounds = CGRect(origin: .zero, size: size)
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.35
        card.shadowRadius = 18
        card.shadowOffset = CGSize(width: 0, height: 8)
        card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: Tuning.windowCornerRadius, cornerHeight: Tuning.windowCornerRadius, transform: nil)
        let content = CALayer()
        content.frame = card.bounds
        content.contents = image
        content.contentsGravity = .resize
        content.cornerRadius = Tuning.windowCornerRadius
        content.cornerCurve = .continuous
        content.masksToBounds = true
        card.addSublayer(content)
        return card
    }

    func spring(_ layer: CALayer, _ keyPath: String, to value: NSValue) {
        let anim = CASpringAnimation(perceptualDuration: Tuning.springDuration, bounce: Tuning.springBounce)
        anim.keyPath = keyPath
        anim.fromValue = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        anim.toValue = value
        anim.duration = anim.settlingDuration
        layer.setValue(value, forKeyPath: keyPath)
        layer.add(anim, forKey: keyPath)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Spike()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
