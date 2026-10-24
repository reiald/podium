import CoreGraphics
import Foundation

/// The strip settings a user can change: thumbnail size, tilt and the app-icon badge.
/// `applied(to:)` maps them onto a `Tuning`; every other constant stays as it is.
public struct StripCustomization: Equatable, Codable, Sendable {
    /// Thumbnail max width in points; the height keeps `Tuning.initial`'s aspect.
    public var thumbnailWidth: CGFloat
    public var tiltDegrees: CGFloat
    public var showAppIcons: Bool
    public var appIconSize: CGFloat

    public static let thumbnailWidthRange: ClosedRange<CGFloat> = 100...320
    public static let tiltDegreesRange: ClosedRange<CGFloat> = 0...30
    public static let appIconSizeRange: ClosedRange<CGFloat> = 16...48

    /// Reproduces `Tuning.initial` exactly.
    public static let defaults = StripCustomization(
        thumbnailWidth: Tuning.initial.itemMaxSize.width,
        tiltDegrees: Tuning.initial.tiltRadians * 180 / .pi,
        showAppIcons: true,
        appIconSize: Tuning.initial.appIconSize
    )

    public init(thumbnailWidth: CGFloat, tiltDegrees: CGFloat, showAppIcons: Bool, appIconSize: CGFloat) {
        self.thumbnailWidth = thumbnailWidth
        self.tiltDegrees = tiltDegrees
        self.showAppIcons = showAppIcons
        self.appIconSize = appIconSize
    }

    /// Every value within its range; a non-finite value falls back to its default.
    public func clamped() -> StripCustomization {
        func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>, _ fallback: CGFloat) -> CGFloat {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        let d = Self.defaults
        return StripCustomization(
            thumbnailWidth: clamp(thumbnailWidth, Self.thumbnailWidthRange, d.thumbnailWidth),
            tiltDegrees: clamp(tiltDegrees, Self.tiltDegreesRange, d.tiltDegrees),
            showAppIcons: showAppIcons,
            appIconSize: clamp(appIconSize, Self.appIconSizeRange, d.appIconSize)
        )
    }

    /// `tuning` with the (clamped) thumbnail size, tilt and icon size. The strip band
    /// follows the width, since it is derived from `itemMaxSize`.
    public func applied(to tuning: Tuning) -> Tuning {
        let c = clamped()
        let aspect = Tuning.initial.itemMaxSize.height / Tuning.initial.itemMaxSize.width
        var t = tuning
        t.itemMaxSize = CGSize(width: c.thumbnailWidth, height: c.thumbnailWidth * aspect)
        // The degrees round trip is off by an ulp; the default must give back exactly 0.30.
        t.tiltRadians = c.tiltDegrees == Self.defaults.tiltDegrees
            ? Tuning.initial.tiltRadians : c.tiltDegrees * .pi / 180
        t.appIconSize = c.appIconSize
        return t
    }
}
