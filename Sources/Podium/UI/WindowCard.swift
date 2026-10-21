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
        didSet { withoutActions { apply(pose) } }
    }

    var image: CGImage? {
        didSet { withoutActions { content.contents = image } }
    }

    var appIcon: NSImage? {
        didSet {
            withoutActions {
                badge.contents = appIcon
                badge.isHidden = appIcon == nil
            }
        }
    }

    /// Which side the strip is on. The badge sits on the corner facing the stage:
    /// bottom-right for a left strip, bottom-left for a right strip.
    var side: StripSide {
        didSet { withoutActions { layoutBadge() } }
    }

    var size: CGSize {
        didSet { withoutActions { layoutBounds() } }
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
        layer.addSublayer(content)

        badge.contentsGravity = .resizeAspect
        badge.isHidden = true
        badge.bounds = CGRect(x: 0, y: 0, width: tuning.appIconSize, height: tuning.appIconSize)
        layer.addSublayer(badge)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        content.contentsScale = scale
        badge.contentsScale = scale

        withoutActions {
            layoutBounds()
            apply(self.pose)
        }
    }

    /// Writes `pose` to the layers, with no implicit animation. Scale is kept above zero
    /// (a zero scale is a singular transform) and alpha within 0...1, since springs overshoot.
    func apply(_ pose: CardPose) {
        var pose = pose
        pose.scale = max(pose.scale, Self.minScale)
        pose.alpha = min(max(pose.alpha, 0), 1)
        self.pose = pose
        withoutActions {
            layer.position = CGPoint(x: pose.center.x - layerOrigin.x, y: pose.center.y - layerOrigin.y)
            layer.opacity = Float(pose.alpha)

            var t = CATransform3DIdentity
            t.m34 = -1 / tuning.perspectiveDistance
            t = CATransform3DRotate(t, pose.tilt, 0, 1, 0)
            t = CATransform3DScale(t, pose.scale, pose.scale, 1)
            layer.transform = t

            badge.transform = CATransform3DMakeScale(1 / pose.scale, 1 / pose.scale, 1)
            layoutBadge()
        }
    }

    private static let minScale: CGFloat = 0.001

    /// Every layer write goes through here: standalone layers otherwise animate implicitly
    /// for 0.25 s, which would fight the springs. Nests safely inside the Animator's transaction.
    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
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
        let inset = (tuning.appIconSize / 2) / pose.scale
        let x = side == .left ? size.width - inset : inset
        badge.position = CGPoint(x: x, y: size.height - inset)
    }
}
