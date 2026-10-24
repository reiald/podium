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
    var c = SystemFocus()
    c.closed(at: 10)
    #expect(c.ignores(w(2, 20), at: 10.2, board: board()))
    #expect(c.ignores(appActivated: 2, at: 10.2, board: board()))
}

@Test func followsFocusOnceTheCloseIsOld() {
    var c = SystemFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(2, 20), at: 10 + SystemFocus.quiet, board: board()))
    #expect(!c.ignores(appActivated: 2, at: 11, board: board()))
}

@Test func followsFocusThatStaysOnStage() {
    var c = SystemFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(1, 10), at: 10.1, board: board()))
    #expect(!c.ignores(appActivated: 1, at: 10.1, board: board()))
}

@Test func followsFocusOfWindowsPodiumDoesNotHold() {
    var c = SystemFocus()
    c.closed(at: 10)
    #expect(!c.ignores(w(3, 30), at: 10.1, board: board()))
    #expect(!c.ignores(appActivated: 3, at: 10.1, board: board()))
}

@Test func followsEverythingBeforeAnyClose() {
    #expect(!SystemFocus().ignores(w(2, 20), at: 0, board: board()))
}

/// One at a Time, a strip click on one of Teams' two windows: Teams then reports its other window, still in
/// the strip, as focused. That must not swap it in for the one chosen.
@Test func ignoresTheAppsOtherStripWindowRightAfterAStripClick() {
    var b = StageBoard(displayID: 1)
    b.setGrouping(.oneAtATime)
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    let chosen = b.stages.first { $0.windows == [w(1, 10)] }!.id
    b.select(stageID: chosen)
    var c = SystemFocus()
    c.stageChosen(at: 10)
    #expect(c.ignores(w(1, 11), at: 10.3, board: b))
    #expect(!c.ignores(w(1, 11), at: 10 + SystemFocus.quiet, board: b))
}

// Photoshop closes a small helper window (not on the board) whenever it loses focus; that
// close must not make Podium ignore the Dock click on another app that caused it.
@Test func onlyAClosedStageWindowMovesFocus() {
    let b = board()                                    // A (1,10) on stage, B (2,20) in the strip
    var helper = SystemFocus()
    helper.windowClosed(w(1, 99), at: 10, board: b)    // never on the board
    #expect(!helper.ignores(appActivated: 2, at: 10.1, board: b))
    var parked = SystemFocus()
    parked.windowClosed(w(2, 20), at: 10, board: b)    // in the strip: no focus moves
    #expect(!parked.ignores(appActivated: 2, at: 10.1, board: b))
    var onStage = SystemFocus()
    onStage.windowClosed(w(1, 10), at: 10, board: b)   // on stage: macOS focuses another window
    #expect(onStage.ignores(appActivated: 2, at: 10.1, board: b))
}
