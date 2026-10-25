import AppKit

/// The menu-bar icon: the template image shipped in the app bundle (`Resources/PodiumMenuTemplate*.png`),
/// and the same icon with a slash cut through it for the moment Podium turns off.
enum StatusIcon {
    static let side: CGFloat = 18

    static var normal: NSImage? {
        guard let image = NSImage(named: "PodiumMenuTemplate") else { return nil }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }

    /// `base` with a diagonal gap and slash drawn over it; still a template image.
    static func slashed(_ base: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            base.draw(in: rect)
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 2.5, y: 15.5))
            slash.line(to: NSPoint(x: 15.5, y: 2.5))
            slash.lineCapStyle = .round
            slash.lineWidth = 3.4
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            slash.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            slash.lineWidth = 1.5
            slash.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
