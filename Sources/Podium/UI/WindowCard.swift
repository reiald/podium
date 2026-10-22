import AppKit
import PodiumCore
import QuartzCore

/// A stand-in for one window: a shadow container holding a rounded, continuous-corner content
/// layer that shows `image`, plus an app icon on the stage-facing bottom corner.
///
/// `layer.bounds` is the window's full point size; a pose's `scale` shrinks it. The icon is a
/// separate layer (`iconLayer`, added next to the card by the overlay), so it never tilts and
/// stays `appIconSize` points on screen; every pose moves it with the card.
@MainActor
final class WindowCard {
    let id: UUID
    let layer = CALayer()
    private let content = CALayer()
    /// The app icon, drawn above the card. The overlay adds it next to `layer`.
    let iconLayer = CALayer()
    /// Live-changeable (Settings window): a new `appIconSize` resizes the icon.
    var tuning: Tuning {
        didSet {
            guard tuning != oldValue else { return }
            withoutActions {
                iconLayer.bounds = CGRect(x: 0, y: 0, width: tuning.appIconSize, height: tuning.appIconSize)
                layoutBounds()
                apply(pose)
            }
        }
    }

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
                iconLayer.contents = appIcon
                iconLayer.isHidden = appIcon == nil
            }
        }
    }

    /// Which side the strip is on. The icon sits on the corner facing the stage:
    /// bottom-right for a left strip, bottom-left for a right strip.
    var side: StripSide {
        didSet { withoutActions { apply(pose) } }
    }

    /// Stacking order on the overlay; the icon stays just above its card.
    var zPosition: CGFloat {
        get { layer.zPosition }
        set {
            withoutActions {
                layer.zPosition = newValue
                iconLayer.zPosition = newValue + 0.5
            }
        }
    }

    /// The icon's on-screen rect in AX coordinates; nil while it is hidden or faded out.
    var iconFrame: CGRect? {
        guard appIcon != nil, pose.alpha > 0.5 else { return nil }
        let center = iconCenter
        let side = tuning.appIconSize
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
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

        iconLayer.contentsGravity = .resizeAspect
        iconLayer.isHidden = true
        iconLayer.bounds = CGRect(x: 0, y: 0, width: tuning.appIconSize, height: tuning.appIconSize)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        content.contentsScale = scale
        iconLayer.contentsScale = scale

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

            let icon = iconCenter
            iconLayer.position = CGPoint(x: icon.x - layerOrigin.x, y: icon.y - layerOrigin.y)
            iconLayer.opacity = Float(pose.alpha)
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
    }

    /// The icon's center in AX coordinates: on the card's stage-facing bottom corner, inset by
    /// half the icon's on-screen size, projected through the card's tilt and perspective (the
    /// layer's transform, about its center). The root view is flipped: bottom is +y.
    private var iconCenter: CGPoint {
        let inset = (tuning.appIconSize / 2) / max(pose.scale, Self.minScale)
        let x = (side == .left ? size.width - inset : inset) - size.width / 2
        let y = size.height / 2 - inset
        let t = layer.transform
        let w = x * t.m14 + y * t.m24 + t.m44
        guard w > 0 else { return pose.center }
        return CGPoint(x: pose.center.x + (x * t.m11 + y * t.m21 + t.m41) / w,
                       y: pose.center.y + (x * t.m12 + y * t.m22 + t.m42) / w)
    }
}
