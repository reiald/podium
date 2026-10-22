import Testing
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }

/// A on stage, B in the strip.
private func board() -> StageBoard {
    var b = StageBoard(displayID: 1)
    b.windowOpened(w(2, 20))
    b.windowOpened(w(1, 10))
    return b
}

@Test func ignoresFocusOfStripWindowRightAfterClose() {
    var c = CloseFocus()
    c.closed(at: 10)
    #expect(c.ignores(w(2, 20), at: 10.2, board: board()))
    #expect(c.ignores(appActivated: 2, at: 10.2, board: board()))
}

@Test func followsFocusOnceTheCloseIsOld() {
    var c = CloseFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(2, 20), at: 10 + CloseFocus.quiet, board: board()))
    #expect(!c.ignores(appActivated: 2, at: 11, board: board()))
}

@Test func followsFocusThatStaysOnStage() {
    var c = CloseFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(1, 10), at: 10.1, board: board()))
    #expect(!c.ignores(appActivated: 1, at: 10.1, board: board()))
}

@Test func followsFocusOfWindowsPodiumDoesNotHold() {
    var c = CloseFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(3, 30), at: 10.1, board: board()))
    #expect(!c.ignores(appActivated: 3, at: 10.1, board: board()))
}

@Test func followsEverythingBeforeAnyClose() {
    #expect(!CloseFocus().ignores(w(2, 20), at: 0, board: board()))
}
