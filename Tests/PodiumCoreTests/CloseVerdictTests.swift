import Testing
@testable import PodiumCore

@Test func unparkedWindowCloseIsBelievedRightAway() {
    // Apps that hide a window on close keep it listed; it must not linger as a ghost stage.
    #expect(closeVerdict(isParked: false, listed: true, listQueryFailed: false) == .closed(forgetLedger: false))
    #expect(closeVerdict(isParked: false, listed: false, listQueryFailed: true) == .closed(forgetLedger: false))
}

@Test func parkedWindowCloseNeedsTheWindowServerToAgree() {
    #expect(closeVerdict(isParked: true, listed: true, listQueryFailed: false) == .recheckLater)
    #expect(closeVerdict(isParked: true, listed: false, listQueryFailed: false) == .closed(forgetLedger: true))
    #expect(closeVerdict(isParked: true, listed: false, listQueryFailed: true) == .closed(forgetLedger: false))
}
