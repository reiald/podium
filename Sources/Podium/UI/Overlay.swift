import AppKit
import QuartzCore

/// A view whose origin is the top-left, so layer positions match AX (top-left-origin) coordinates.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Converts a rect between top-left-origin global (AX) and bottom-left-origin AppKit coordinates.
/// The flip is about the primary screen's height and is its own inverse.
func flipToAppKit(_ rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

/// One click-through, borderless window covering a whole display. Cards are added to its
/// flipped root layer, each with its app icon layer. `frame` is in AX coordinates, and cards
/// take poses in AX coordinates too.
@MainActor
final class Overlay {
    let screen: NSScreen
    /// The display's frame in top-left-origin global (AX) coordinates.
    let frame: CGRect
    private let window: NSWindow
    private let root: FlippedView

    init(screen: NSScreen) {
        self.screen = screen
        self.frame = flipToAppKit(screen.frame)

        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        // Not `.fullScreenAuxiliary`: cards must not draw over a full-screen app.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)

        root = FlippedView(frame: CGRect(origin: .zero, size: screen.frame.size))
        root.wantsLayer = true
        window.contentView = root
    }

    func show() { window.orderFrontRegardless() }

    func hide() { window.orderOut(nil) }

    func add(_ card: WindowCard) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.layerOrigin = frame.origin
        root.layer?.addSublayer(card.layer)
        root.layer?.addSublayer(card.iconLayer)
        CATransaction.commit()
    }

    func remove(_ card: WindowCard) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.layer.removeFromSuperlayer()
        card.iconLayer.removeFromSuperlayer()
        CATransaction.commit()
    }
}
