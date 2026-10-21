import AppKit

/// The only part of Podium's UI that takes the mouse: a clear, non-activating panel covering
/// just the strip band. Everything is reported in top-left-origin global (AX) coordinates.
///
/// `targets` maps stage IDs to their hit rects (AX coordinates). A press on a target that is
/// released inside the band is a click (or shift-click); one released outside the band is a
/// drag to the stage.
@MainActor
final class StripPanel: NSPanel {
    var onClick: (UUID) -> Void = { _ in }
    var onShiftClick: (UUID) -> Void = { _ in }
    var onHover: (CGPoint?) -> Void = { _ in }
    var onDragToStage: (UUID) -> Void = { _ in }

    var targets: [(id: UUID, frame: CGRect)] = []

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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // A clear window lets clicks fall through unless this is set explicitly.
        ignoresMouseEvents = false
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
        guard let panel, let p = globalPoint(event), let id = panel.target(at: p) else {
            pressed = nil
            return
        }
        pressed = (id, event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let panel, let pressed, let p = globalPoint(event) else { return }
        if !panel.band.contains(p) {
            panel.onDragToStage(pressed.id)
        } else if pressed.shift {
            panel.onShiftClick(pressed.id)
        } else {
            panel.onClick(pressed.id)
        }
    }
}
