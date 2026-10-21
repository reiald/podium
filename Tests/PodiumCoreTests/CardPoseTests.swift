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

@Test func cardSettlesInPointsForPositionAndUnitsForTheRest() {
    let target = CardPose(center: CGPoint(x: 100, y: 100), scale: 0.2, tilt: 0.3, alpha: 1).vector()
    let zero = [Double](repeating: 0, count: CardPose.dimension)
    // 0.2 pt off and drifting at 2 pt/s is visually at rest.
    var near = target; near[0] += 0.2
    var slow = zero; slow[1] = 2
    #expect(CardPose.isSettled(value: near, velocity: slow, target: target))
    // 0.3 pt off is not.
    var far = target; far[0] += 0.3
    #expect(!CardPose.isSettled(value: far, velocity: zero, target: target))
    // 3 pt/s is still moving.
    var fast = zero; fast[0] = 3
    #expect(!CardPose.isSettled(value: target, velocity: fast, target: target))
    // Scale, tilt and alpha use 1e-3 displacement and 1e-2 velocity.
    var scaleOff = target; scaleOff[2] += 0.002
    #expect(!CardPose.isSettled(value: scaleOff, velocity: zero, target: target))
    var tiltSpin = zero; tiltSpin[3] = 0.02
    #expect(!CardPose.isSettled(value: target, velocity: tiltSpin, target: target))
    var tiny = target; tiny[4] -= 0.0005
    var tinyV = zero; tinyV[2] = 0.005
    #expect(CardPose.isSettled(value: tiny, velocity: tinyV, target: target))
}
