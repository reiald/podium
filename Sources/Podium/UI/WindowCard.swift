import AppKit
import PodiumCore
import QuartzCore

/// A stand-in for one window: a shadow container holding a rounded, continuous-corner content
/// layer that shows `image`, plus an app-icon badge on the stage-facing corner.
///
/// `layer.bounds` is the window's full point size; a pose's `scale` shrinks it. The badge is
/// counter-scaled so it stays `appIconSize` points on screen at any card scale.
@MainActor
final class WindowCard {
    let id: UUID
    let layer = CALayer()
    private let content = CALayer()
    private let badge = CALayer()
    private let tuning: Tuning

    /// The pose last written by `apply`. The animator starts new springs from here.
    private(set) var pose: CardPose
    /// The owning overlay's AX origin; poses are global, layers are overlay-local.
    var layerOrigin: CGPoint = .zero {
        didSet { apply(pose) }
    }

    var image: CGImage? {
        didSet { content.contents = image }
    }

    var appIcon: NSImage? {
        didSet {
            badge.contents = appIcon
            badge.isHidden = appIcon == nil
        }
    }

    /// Which side the strip is on. The badge sits on the corner facing the stage:
    /// bottom-right for a left strip, bottom-left for a right strip.
    var side: StripSide {
        didSet { layoutBadge() }
    }

    var size: CGSize {
        didSet { layoutBounds() }
    }

    init(id: UUID = UUID(), size: CGSize, side: StripSide, tuning: Tuning = .initial, pose: CardPose? = nil) {
        self.id = id
        self.size = size
        self.side = side
        self.tuning = tuning
        self.pose = pose ?? CardPose(center: .zero, scale: 1, tilt: 0, alpha: 1)

        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        content.cornerRadius = tuning.cornerRadius
        content.cornerCurve = .continuous
        content.masksToBounds = true
        content.contentsGravity = .resize
        content.backgroundColor = NSColor.windowBackgroundColor.cgColor
        // New snapshots and live frames replace the image instantly, never crossfade.
        content.actions = ["contents": NSNull()]
        badge.actions = ["contents": NSNull()]
        layer.addSublayer(content)

        badge.contentsGravity = .resizeAspect
        badge.isHidden = true
        badge.bounds = CGRect(x: 0, y: 0, width: tuning.appIconSize, height: tuning.appIconSize)
        layer.addSublayer(badge)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        content.contentsScale = scale
        badge.contentsScale = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutBounds()
        apply(self.pose)
        CATransaction.commit()
    }

    /// Writes `pose` to the layers. Callers wrap this in a transaction with actions disabled.
    func apply(_ pose: CardPose) {
        self.pose = pose
        layer.position = CGPoint(x: pose.center.x - layerOrigin.x, y: pose.center.y - layerOrigin.y)
        layer.opacity = Float(pose.alpha)

        var t = CATransform3DIdentity
        t.m34 = -1 / tuning.perspectiveDistance
        t = CATransform3DRotate(t, pose.tilt, 0, 1, 0)
        t = CATransform3DScale(t, pose.scale, pose.scale, 1)
        layer.transform = t

        let inverse = pose.scale > 0.0001 ? 1 / pose.scale : 1
        badge.transform = CATransform3DMakeScale(inverse, inverse, 1)
        layoutBadge()
    }

    private func layoutBounds() {
        let bounds = CGRect(origin: .zero, size: size)
        layer.bounds = bounds
        content.frame = bounds
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: tuning.cornerRadius,
                                  cornerHeight: tuning.cornerRadius, transform: nil)
        layoutBadge()
    }

    /// Centers the badge on the stage-facing bottom corner, inset by half its on-screen size.
    /// The root view is flipped, so the bottom edge is at `bounds.maxY`.
    private func layoutBadge() {
        let inset = (tuning.appIconSize / 2) / max(pose.scale, 0.0001)
        let x = side == .left ? size.width - inset : inset
        badge.position = CGPoint(x: x, y: size.height - inset)
    }
}
