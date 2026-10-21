import AppKit

/// Screens in top-left-origin global (AX) coordinates.
enum Screens {
    struct Screen {
        let id: UInt32
        let frame: CGRect
        let visibleFrame: CGRect
    }

    static var all: [Screen] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        return screens.map { s in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return Screen(id: id, frame: flip(s.frame), visibleFrame: flip(s.visibleFrame))
        }
    }

    /// The screen containing the center of `frame`, else the primary screen.
    static func containing(_ frame: CGRect) -> Screen {
        let screens = all
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.frame.contains(center) } ?? screens[0]
    }
}
