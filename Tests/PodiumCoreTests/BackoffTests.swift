import Testing
@testable import PodiumCore

@Test func breakerOpensForCooldownAfterTrip() {
    var b = CircuitBreaker<Int32>(cooldown: 5)
    #expect(!b.isOpen(7, now: 100))
    b.trip(7, now: 100)
    #expect(b.isOpen(7, now: 100))
    #expect(b.isOpen(7, now: 104.9))
    #expect(!b.isOpen(7, now: 105))
    #expect(!b.isOpen(8, now: 101))
}

@Test func breakerRetripExtendsCooldown() {
    var b = CircuitBreaker<Int32>(cooldown: 5)
    b.trip(7, now: 100)
    b.trip(7, now: 104)
    #expect(b.isOpen(7, now: 108))
    #expect(!b.isOpen(7, now: 109))
}

@Test func backoffDoublesUpToMaximumAndClearsOnSuccess() {
    var r = RetryBackoff<Int>(base: 1, maximum: 4)
    #expect(r.mayTry(1, now: 0))
    r.failed(1, now: 0)
    #expect(!r.mayTry(1, now: 0.5))
    #expect(r.mayTry(1, now: 1))
    r.failed(1, now: 1)
    #expect(!r.mayTry(1, now: 2.9))
    #expect(r.mayTry(1, now: 3))
    r.failed(1, now: 3)
    r.failed(1, now: 7)
    // Capped at 4 s.
    #expect(!r.mayTry(1, now: 10.9))
    #expect(r.mayTry(1, now: 11))
    #expect(r.mayTry(2, now: 0))
    r.succeeded(1)
    #expect(r.mayTry(1, now: 7))
}
