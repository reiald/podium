import AppKit
import PodiumCore

/// The only part of Podium's UI that takes the mouse: a clear, non-activating panel covering
/// just the strip band. Everything is reported in top-left-origin global (AX) coordinates.
///
/// It starts click-through; the `StripPresenter` turns mouse-taking on only while the pointer
/// is over a target, so the band's empty space (and windows under it) still get clicks.
///
/// `targets` maps stage IDs to their hit rects (AX coordinates). A press on a target is a
/// click (or shift-click) until the pointer moves past `StripDrag`'s threshold; then it is a
/// drag, reported as it goes, which drops on the stage if released outside the band.
///
/// An item's app icon (`iconTarget`) sits above its card and takes the press first: released
/// on that icon (or within the drag threshold of the press), it is an icon click; it never drags.
@MainActor
final class StripPanel: NSPanel {
    var onClick: (UUID) -> Void = { _ in }
    var onShiftClick: (UUID) -> Void = { _ in }
    var onIconClick: (UUID) -> Void = { _ in }
    var onHover: (CGPoint?) -> Void = { _ in }
    /// The pressed stage and the pointer, once the press became a drag.
    var onDragBegan: (UUID, CGPoint) -> Void = { _, _ in }
    var onDragMoved: (CGPoint) -> Void = { _ in }
    /// The dragged stage, and whether it was dropped on the stage (else called off).
    var onDragEnded: (UUID, Bool) -> Void = { _, _ in }

    var targets: [(id: UUID, frame: CGRect)] = []
    /// The item whose app icon is under a point, as drawn (AX coordinates).
    var iconTarget: (CGPoint) -> UUID? = { _ in nil }

    /// The band in AX coordinates.
    private(set) var band: CGRect
    private let catcher: MouseCatcher

    init(band: CGRect) {
        self.band = band
        catcher = MouseCatcher(frame: CGRect(origin: .zero, size: band.size))
        super.init(contentRect: flipToAppKit(band), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // Not `.fullScreenAuxiliary`: the strip must not sit over a full-screen app.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Click-through until the pointer is over a target (set explicitly: a clear window's
        // default depends on its content).
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        contentView = catcher
        catcher.panel = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setBand(_ band: CGRect) {
        self.band = band
        setFrame(flipToAppKit(band), display: false)
    }

    func show() { orderFrontRegardless() }

    /// Calls off a drag in progress (a lost mouse-up, or teardown), as Esc would.
    func cancelDrag() { catcher.cancelDrag() }

    fileprivate func target(at point: CGPoint) -> UUID? {
        targets.first { $0.frame.contains(point) }?.id
    }

    /// Converts a point in the catcher view (flipped, so top-left origin) to AX coordinates.
    fileprivate func global(_ local: CGPoint) -> CGPoint {
        CGPoint(x: band.minX + local.x, y: band.minY + local.y)
    }
}

private final class MouseCatcher: FlippedView {
    weak var panel: StripPanel?
    private var pressed: (id: UUID, shift: Bool)?
    private var pressedIcon: (id: UUID, at: CGPoint)?
    private var drag = StripDrag()
    private var escapeMonitors: [Any] = []
    private static let escapeKeyCode: UInt16 = 53

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint? {
        panel?.global(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) { panel?.onHover(globalPoint(event)) }
    override func mouseEntered(with event: NSEvent) { panel?.onHover(globalPoint(event)) }
    override func mouseExited(with event: NSEvent) { panel?.onHover(nil) }

    override func mouseDown(with event: NSEvent) {
        // A drag whose mouse-up was lost is called off before the new press.
        if drag.isDragging, let pressed { end(pressed.id, dropped: false) }
        drag.reset()
        pressed = nil
        pressedIcon = nil
        guard let panel, let p = globalPoint(event) else { return }
        if let icon = panel.iconTarget(p) {
            pressedIcon = (icon, p)
            return
        }
        guard let id = panel.target(at: p) else { return }
        pressed = (id, event.modifierFlags.contains(.shift))
        drag.began(at: p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel, let pressed, let p = globalPoint(event) else { return }
        switch drag.dragged(to: p) {
        case .began:
            watchEscape()
            panel.onDragBegan(pressed.id, p)
        case .moved:
            panel.onDragMoved(p)
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        if let icon = pressedIcon {
            pressedIcon = nil
            guard let panel, let p = globalPoint(event) else { return }
            let still = hypot(p.x - icon.at.x, p.y - icon.at.y) <= StripDrag.dragThreshold
            if still || panel.iconTarget(p) == icon.id { panel.onIconClick(icon.id) }
            return
        }
        guard let panel, let pressed, let p = globalPoint(event) else { return }
        switch drag.released(at: p, inBand: panel.band.contains(p)) {
        case .click:
            if pressed.shift { panel.onShiftClick(pressed.id) } else { panel.onClick(pressed.id) }
        case .drop:
            end(pressed.id, dropped: true)
        case .cancel:
            end(pressed.id, dropped: false)
        default:
            break
        }
    }

    // MARK: - Esc

    /// The panel never becomes key, so Esc reaches whichever app is active: a global monitor
    /// sees it there, a local one if Podium is active. Both exist only during a drag.
    private func watchEscape() {
        stopWatchingEscape()
        // Swallowed (locally) only if it actually called off a drag.
        let escape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return false }
            return MainActor.assumeIsolated { self?.cancelDrag() ?? false }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = escape($0) }) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { escape($0) ? nil : $0 }) {
            escapeMonitors.append(local)
        }
    }

    private func stopWatchingEscape() {
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
    }

    /// Calls off a drag; the rest of the press does nothing. False if there was none.
    @discardableResult
    func cancelDrag() -> Bool {
        guard let pressed, drag.escape() == .cancel else {
            stopWatchingEscape()
            return false
        }
        end(pressed.id, dropped: false)
        return true
    }

    private func end(_ id: UUID, dropped: Bool) {
        stopWatchingEscape()
        panel?.onDragEnded(id, dropped)
    }
}
