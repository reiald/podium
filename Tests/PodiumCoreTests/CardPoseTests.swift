import CoreGraphics
import Testing
@testable import PodiumCore

@Test func poseRoundTripsThroughVector() {
    let pose = CardPose(center: CGPoint(x: 812.5, y: -40.25), scale: 0.21, tilt: -0.3, alpha: 0.75)
    let vector = pose.vector()
    #expect(vector.count == CardPose.dimension)
    #expect(CardPose(vector: vector) == pose)
}

@Test func poseVectorRetargetsASpringWithoutTouchingVelocity() {
    let from = CardPose(center: .zero, scale: 1, tilt: 0, alpha: 1)
    let to = CardPose(center: CGPoint(x: 100, y: 50), scale: 0.2, tilt: 0.3, alpha: 1)
    var spring = SpringVector(from.vector())
    spring.retarget(to.vector())
    spring.step(dt: 0.05, spring: Spring(response: 0.42, dampingRatio: 0.86))
    let velocity = spring.velocity
    spring.retarget(from.vector())
    #expect(spring.velocity == velocity)
    let mid = CardPose(vector: spring.value)
    #expect(mid.center.x > 0 && mid.center.x < 100)
}
