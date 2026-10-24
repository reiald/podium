import CoreGraphics

public enum StripSide: String, Codable, CaseIterable, Sendable {
    case left, right
}

/// Every measurable constant of the strip's look and feel. Values named in
/// `docs/research/2026-10-24-apple-strip-defaults.md` are Apple's own Stage Manager defaults
/// (`WindowManagerPreferencesController`, `WindowManagerSpringBehavior`); the rest are still
/// Podium's estimates.
public struct Tuning: Codable, Equatable, Sendable {
    public var stripEdgeInset: CGFloat
    public var itemMaxSize: CGSize
    public var rowSpacing: CGFloat
    public var maxRowCount: Int
    public var tiltRadians: CGFloat
    public var perspectiveDistance: CGFloat
    public var cornerRadius: CGFloat
    public var pileMaxWindows: Int
    public var pileStepOffset: CGSize
    public var pileStepScale: CGFloat
    public var appIconSize: CGFloat
    public var hoverScaleDistance: CGFloat
    public var clickDownScaleDistance: CGFloat
    public var autoHideDelay: Double
    public var autoHideOverlapThreshold: CGFloat
    public var hiddenPeekWidth: CGFloat
    public var stageInset: CGFloat
    public var transitionSpring: Spring
    public var hoverSpring: Spring

    public static let initial = Tuning(
        stripEdgeInset: 16,
        itemMaxSize: CGSize(width: 290, height: 160),
        rowSpacing: 30,
        maxRowCount: 6,
        tiltRadians: 0.30,
        perspectiveDistance: 900,
        cornerRadius: 8,
        pileMaxWindows: 3,
        pileStepOffset: CGSize(width: 6, height: -6),
        pileStepScale: 0.94,
        appIconSize: 40,
        hoverScaleDistance: 16,
        clickDownScaleDistance: 16,
        autoHideDelay: 0.15,
        autoHideOverlapThreshold: 0.15,
        hiddenPeekWidth: 6,
        stageInset: 24,
        transitionSpring: Spring(response: 0.38, dampingRatio: 1.0),
        hoverSpring: Spring(response: 0.25, dampingRatio: 0.8)
    )
}
