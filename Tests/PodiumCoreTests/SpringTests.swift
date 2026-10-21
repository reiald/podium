import Testing
@testable import PodiumCore

private func run(_ s: inout SpringVector, spring: Spring, dt: Double, seconds: Double) -> Double {
    var peak = -Double.infinity
    let n = Int((seconds / dt).rounded())
    for _ in 0..<n {
        s.step(dt: dt, spring: spring)
        peak = max(peak, s.value[0])
    }
    return peak
}

@Test func convergesToTarget() {
    var s = SpringVector([0])
    s.retarget([100])
    _ = run(&s, spring: Spring(response: 0.5, dampingRatio: 1), dt: 1.0 / 120, seconds: 2)
    #expect(abs(s.value[0] - 100) < 0.01)
    #expect(s.isSettled())
}

@Test func criticallyDampedNeverOvershoots() {
    var s = SpringVector([0])
    s.retarget([100])
    let peak = run(&s, spring: Spring(response: 0.5, dampingRatio: 1), dt: 1.0 / 120, seconds: 2)
    #expect(peak <= 100.0001)
}

@Test func underdampedOvershoots() {
    var s = SpringVector([0])
    s.retarget([100])
    let peak = run(&s, spring: Spring(response: 0.5, dampingRatio: 0.6), dt: 1.0 / 120, seconds: 2)
    #expect(peak > 100)
}

@Test func retargetKeepsVelocity() {
    let spring = Spring(response: 0.5, dampingRatio: 1)
    var s = SpringVector([0])
    s.retarget([100])
    _ = run(&s, spring: spring, dt: 1.0 / 120, seconds: 0.1)
    let v = s.velocity
    #expect(v[0] > 0)
    s.retarget([-50])
    #expect(s.velocity == v)
    #expect(s.target == [-50])
}

@Test func frameRateIndependent() {
    let spring = Spring(response: 0.5, dampingRatio: 0.8)
    var a = SpringVector([0]); a.retarget([100])
    var b = SpringVector([0]); b.retarget([100])
    _ = run(&a, spring: spring, dt: 1.0 / 60, seconds: 1)
    _ = run(&b, spring: spring, dt: 1.0 / 120, seconds: 1)
    #expect(abs(a.value[0] - b.value[0]) < 0.5)
}

@Test func largeDtIsStable() {
    var s = SpringVector([0])
    s.retarget([100])
    for _ in 0..<20 { s.step(dt: 0.25, spring: Spring(response: 0.5, dampingRatio: 1)) }
    #expect(s.value[0].isFinite)
    #expect(abs(s.value[0] - 100) < 1)
}

@Test func snapClearsVelocity() {
    var s = SpringVector([0])
    s.retarget([100])
    _ = run(&s, spring: Spring(response: 0.5, dampingRatio: 1), dt: 1.0 / 120, seconds: 0.1)
    s.snap(to: [5])
    #expect(s.value == [5])
    #expect(s.velocity == [0])
    #expect(s.target == [5])
    #expect(s.isSettled())
}
