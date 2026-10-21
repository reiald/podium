import Testing
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }
private func board() -> StageBoard { StageBoard(displayID: 1) }

@Test func firstWindowOfNewAppBecomesActiveStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    #expect(b.stages.count == 1)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.isEmpty)
}

@Test func secondWindowOfSameAppJoinsItsStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    #expect(b.stages.count == 1)
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(1, 11)])
}

@Test func newAppPushesPreviousStageToStrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.first?.id == first)
}

@Test func windowOfAppInOtherStageActivatesThatStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.windowOpened(w(1, 11))
    #expect(b.activeStageID == first)
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(1, 11)])
    #expect(b.stages.count == 2)
}

@Test func windowOpenedTwiceIsNoOp() {
    var b = board()
    b.windowOpened(w(1, 10))
    let copy = b
    b.windowOpened(w(1, 10))
    #expect(b == copy)
}

@Test func appActivationBringsItsStageForward() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.appActivated(pid: 1)
    #expect(b.activeStageID == first)
    b.appActivated(pid: 99)
    #expect(b.activeStageID == first)
}

@Test func appActivationUsesMostRecentlyFocusedWindowsStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(3, 30))
    b.addToActiveStage(w(1, 10))              // app 1's window now lives with app 3
    b.windowOpened(w(1, 11))                  // joins active (app 1 has a window there)
    b.moveToOwnStage(w(1, 11))                // app 1 split across two stages
    let ownStage = b.activeStageID!
    b.appActivated(pid: 2)
    #expect(b.activeStageID != ownStage)
    b.windowFocused(w(1, 10))
    let stageOf10 = b.activeStageID!
    b.appActivated(pid: 2)
    b.appActivated(pid: 1)
    #expect(b.activeStageID == stageOf10)
    b.windowFocused(w(1, 11))
    b.appActivated(pid: 2)
    b.appActivated(pid: 1)
    #expect(b.activeStageID == ownStage)
}

@Test func closingLastWindowRemovesStageAndEmptiesStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowClosed(w(1, 10))
    #expect(b.stages.isEmpty)
    #expect(b.activeStageID == nil)
    #expect(b.activeStage == nil)
}

@Test func closingWindowInStripStageKeepsActive() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    let active = b.activeStageID
    b.windowClosed(w(1, 10))
    #expect(b.activeStageID == active)
    #expect(b.stages.count == 1)
    b.windowClosed(w(9, 9)) // unknown: no-op
    #expect(b.stages.count == 1)
}

@Test func appTerminationRemovesAllItsWindows() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(1, 11))   // activates stage of app 1
    b.appTerminated(pid: 1)
    #expect(b.stages.count == 1)
    #expect(b.stages[0].windows == [w(2, 20)])
    #expect(b.activeStageID == nil)
}

@Test func shiftClickAddsWindowToActiveStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(2, 20)])
    #expect(b.stages.count == 1)
}

@Test func shiftClickWithNoActiveStageCreatesOne() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowClosed(w(2, 20))   // active deleted -> desktop
    #expect(b.activeStageID == nil)
    b.windowOpened(w(3, 30))
    b.windowClosed(w(3, 30))
    b.addToActiveStage(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
}

@Test func combineMergesStageIntoActive() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.combineIntoActive(stageID: first)
    #expect(b.stages.count == 1)
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(2, 20)])
    b.combineIntoActive(stageID: b.activeStageID!) // no-op
    #expect(b.stages.count == 1)
}

@Test func dragOutCreatesOwnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.moveToOwnStage(w(1, 11))
    #expect(b.stages.count == 2)
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(b.stripStages.first?.windows == [w(1, 10)])
}

@Test func minimizeSendsWindowToFrontOfStrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.minimize(w(2, 21))
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.first?.windows == [w(2, 21)])
    #expect(b.stripStages.count == 2)
}

@Test func minimizeLastWindowEmptiesActive() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.minimize(w(1, 10))
    #expect(b.activeStageID == nil)
    #expect(b.stages.count == 1)
    #expect(b.stripStages.first?.windows == [w(1, 10)])
}

@Test func stripOrderIsMostRecentlyUsedFirst() {
    var b = board()
    b.windowOpened(w(1, 10)); let s1 = b.activeStageID!
    b.windowOpened(w(2, 20)); let s2 = b.activeStageID!
    b.windowOpened(w(3, 30)); let s3 = b.activeStageID!
    #expect(b.stripStages.map(\.id) == [s2, s1])
    b.activate(stageID: s1)
    #expect(b.stripStages.map(\.id) == [s3, s2])
    b.activate(stageID: nil)
    #expect(b.stripStages.map(\.id) == [s1, s3, s2])
}

@Test func windowFocusedActivatesItsStageAndOrdersWindows() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    b.windowFocused(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10), w(2, 20)])
    b.windowOpened(w(3, 30))
    b.windowFocused(w(1, 10))
    #expect(b.activeStage?.windows.first == w(1, 10))
    #expect(b.activeStage?.windows.contains(w(3, 30)) == false)
}

@Test func unmanageableWindowsAreIgnored() {
    #expect(isManageable(role: "AXWindow", subrole: "AXStandardWindow", isFullscreen: false, isMinimized: false))
    #expect(!isManageable(role: "AXWindow", subrole: "AXDialog", isFullscreen: false, isMinimized: false))
    #expect(!isManageable(role: "AXSheet", subrole: "AXStandardWindow", isFullscreen: false, isMinimized: false))
    #expect(!isManageable(role: "AXWindow", subrole: "AXFloatingWindow", isFullscreen: false, isMinimized: false))
    #expect(!isManageable(role: "AXWindow", subrole: "AXStandardWindow", isFullscreen: true, isMinimized: false))
    #expect(!isManageable(role: "AXWindow", subrole: "AXStandardWindow", isFullscreen: false, isMinimized: true))
    #expect(!isManageable(role: nil, subrole: nil, isFullscreen: false, isMinimized: false))
}

@Test func windowOpenedJoinsStageOfAppsMostRecentWindowWhenSplit() {
    var b = board()
    b.windowOpened(w(1, 10)); let s1 = b.activeStageID!
    b.windowOpened(w(1, 11))
    b.moveToOwnStage(w(1, 11)); let s2 = b.activeStageID!   // app 1 split: s1, s2
    b.windowFocused(w(1, 10))                                // s1 more recent
    b.windowFocused(w(1, 11))                                // s2 more recent
    b.windowOpened(w(2, 20))                                 // other app active
    #expect(b.activeStage?.windows == [w(2, 20)])
    b.windowOpened(w(1, 12))
    #expect(b.activeStageID == s2)
    #expect(Set(b.activeStage!.windows) == [w(1, 11), w(1, 12)])
    #expect(b.stages.first { $0.id == s1 }?.windows == [w(1, 10)])
}

@Test func appActivationSkipsMinimizedOnlyStage() {
    var b = board()
    b.windowOpened(w(1, 10))        // Notes A
    b.windowOpened(w(1, 11))        // Notes B
    b.windowFocused(w(1, 10))       // A is Notes' most recent window...
    b.minimize(w(1, 10))            // ...then goes to the Dock, alone in its own stage
    b.windowOpened(w(2, 20))        // another app comes forward
    b.appActivated(pid: 1)          // Cmd-Tab back to Notes
    #expect(b.activeStage?.windows == [w(1, 11)])
}

@Test func appActivationWithOnlyMinimizedWindowsIsNoOp() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.minimize(w(1, 10))
    b.windowOpened(w(2, 20))
    let active = b.activeStageID
    b.appActivated(pid: 1)
    #expect(b.activeStageID == active)
}

@Test func deminimizeBringsWindowsStageForward() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.minimize(w(1, 11))
    b.windowOpened(w(2, 20))
    b.deminimize(w(1, 11))
    #expect(b.activeStage?.windows == [w(1, 11)])
    // No longer minimized: the app's activation maps to it again.
    b.windowOpened(w(3, 30))
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 11)])
}

@Test func focusingMinimizedWindowUnmarksIt() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.minimize(w(1, 11))
    b.windowFocused(w(1, 11))
    b.windowOpened(w(2, 20))
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 11)])
}

@Test func isMinimizedTracksDockRoundTrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    #expect(!b.isMinimized(w(1, 10)))
    b.minimize(w(1, 10))
    #expect(b.isMinimized(w(1, 10)))
    b.deminimize(w(1, 10))
    #expect(!b.isMinimized(w(1, 10)))
}

// Minimize to strip (Coordinator.minimizeToStrip) composes existing calls; the window is
// parked, not minimized, so it must never be marked minimized.

@Test func minimizeToStripFromSharedStageKeepsRestOnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))                     // app 2 active; app 1 in the strip
    b.addToActiveStage(w(1, 10))                 // stage: 20 and 10
    let previous = b.activeStageID!
    b.moveToOwnStage(w(2, 20))
    b.activate(stageID: previous)
    #expect(b.activeStageID == previous)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.first?.windows == [w(2, 20)])
    #expect(!b.isMinimized(w(2, 20)))
}

@Test func minimizeToStripOfAloneWindowLeavesDesktopAndFrontsItsStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.minimize(w(1, 10))                         // another stage pushed to the strip front
    let previous = b.activeStageID!
    b.activate(stageID: previous)
    b.activate(stageID: nil)
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.id == previous)
    #expect(!b.isMinimized(w(2, 20)))
    // Coming back from the strip is an ordinary activation.
    b.appActivated(pid: 2)
    #expect(b.activeStageID == previous)
}
