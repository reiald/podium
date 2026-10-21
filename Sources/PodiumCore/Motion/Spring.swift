import Foundation

/// Spring parameters using the SwiftUI convention (mass 1).
public struct Spring: Equatable, Codable, Sendable {
    public var response: Double
    public var dampingRatio: Double

    public init(response: Double, dampingRatio: Double) {
        self.response = response
        self.dampingRatio = dampingRatio
    }

    var stiffness: Double {
        let w = 2 * Double.pi / response
        return w * w
    }

    var damping: Double { 4 * Double.pi * dampingRatio / response }
}

/// A multi-dimensional spring-driven value. Retargeting never touches velocity,
/// so motion stays continuous when interrupted mid-flight.
public struct SpringVector: Equatable, Sendable {
    public private(set) var value: [Double]
    public private(set) var velocity: [Double]
    public private(set) var target: [Double]

    private static let substep = 1.0 / 240.0

    public init(_ value: [Double]) {
        self.value = value
        self.velocity = [Double](repeating: 0, count: value.count)
        self.target = value
    }

    public mutating func retarget(_ target: [Double]) {
        precondition(target.count == value.count, "SpringVector dimension mismatch")
        self.target = target
    }

    public mutating func step(dt: Double, spring: Spring) {
        guard dt > 0 else { return }
        let k = spring.stiffness
        let c = spring.damping
        var remaining = dt
        while remaining > 1e-12 {
            let h = min(Self.substep, remaining)
            remaining -= h
            for i in value.indices {
                let accel = k * (target[i] - value[i]) - c * velocity[i]
                velocity[i] += accel * h
                value[i] += velocity[i] * h
            }
        }
    }

    public func isSettled(epsilon: Double = 0.001) -> Bool {
        for i in value.indices {
            if abs(value[i] - target[i]) >= epsilon || abs(velocity[i]) >= epsilon * 10 { return false }
        }
        return true
    }

    public mutating func snap(to: [Double]) {
        precondition(to.count == value.count, "SpringVector dimension mismatch")
        value = to
        target = to
        velocity = [Double](repeating: 0, count: to.count)
    }
}
