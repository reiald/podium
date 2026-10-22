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

    /// Whether a card's spring is visually at rest. Position is in points (displacement under
    /// 0.25 pt, speed under 2.5 pt/s); scale, tilt and alpha are unitless (displacement under
    /// 1e-3, speed under 1e-2). A single epsilon would hold position for ~0.5 s of invisible motion.
    public static func isSettled(value: [Double], velocity: [Double], target: [Double]) -> Bool {
        precondition(value.count == dimension && velocity.count == dimension && target.count == dimension,
                     "CardPose vectors must have \(dimension) components")
        for i in 0..<dimension {
            // Position within 1 pt and slower than 30 pt/s: the real window can take over
            // without a visible jump, without waiting out the spring's invisible tail.
            let (maxOffset, maxSpeed) = i < 2 ? (1.0, 30.0) : (1e-3, 1e-2)
            if abs(value[i] - target[i]) >= maxOffset || abs(velocity[i]) >= maxSpeed { return false }
        }
        return true
    }

    public init(vector: [Double]) {
        precondition(vector.count == Self.dimension, "CardPose vector must have \(Self.dimension) components")
        self.init(center: CGPoint(x: vector[0], y: vector[1]),
                  scale: CGFloat(vector[2]), tilt: CGFloat(vector[3]), alpha: CGFloat(vector[4]))
    }
}
