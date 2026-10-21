import CoreGraphics

/// Everything the animator springs for one card: where its center sits (top-left-origin
/// global coordinates), its uniform scale, its y-axis tilt in radians and its opacity.
public struct CardPose: Equatable, Sendable {
    public var center: CGPoint
    public var scale: CGFloat
    public var tilt: CGFloat
    public var alpha: CGFloat

    /// Length of `vector()`: x, y, scale, tilt, alpha.
    public static let dimension = 5

    public init(center: CGPoint, scale: CGFloat, tilt: CGFloat, alpha: CGFloat) {
        self.center = center
        self.scale = scale
        self.tilt = tilt
        self.alpha = alpha
    }

    public func vector() -> [Double] {
        [Double(center.x), Double(center.y), Double(scale), Double(tilt), Double(alpha)]
    }

    public init(vector: [Double]) {
        precondition(vector.count == Self.dimension, "CardPose vector must have \(Self.dimension) components")
        self.init(center: CGPoint(x: vector[0], y: vector[1]),
                  scale: CGFloat(vector[2]), tilt: CGFloat(vector[3]), alpha: CGFloat(vector[4]))
    }
}
