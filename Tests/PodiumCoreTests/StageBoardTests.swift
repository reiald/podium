import Testing
import CoreGraphics
import Foundation
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

@Test func dockMinimizedStageHasNoStripSlot() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.minimize(w(2, 21))
    // Still a strip stage (the model keeps it), but it gets no slot.
    #expect(b.stripStages.count == 2)
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func dockMinimizedLoneStageHasNoSlotUntilDeminimized() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.minimize(w(2, 20))
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
    b.deminimize(w(2, 20))
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func dockMinimizedStagesDoNotPushRealStagesPastLastRow() {
    var b = board()
    let tuning = Tuning.initial
    // One real strip stage plus more minimized ones than there are rows.
    b.windowOpened(w(1, 10))
    for i in 0..<tuning.maxRowCount { b.windowOpened(w(100 + Int32(i), 1)) }
    for i in 0..<tuning.maxRowCount { b.minimize(w(100 + Int32(i), 1)) }
    b.windowOpened(w(9, 90))
    let slots = stripSlots(for: b.visibleStripStages, in: CGRect(x: 0, y: 0, width: 1440, height: 900),
                           side: .right, tuning: tuning)
    #expect(slots.count == 1)
    #expect(slots.first?.stageID == b.stages.first { $0.windows == [w(1, 10)] }?.id)
}

// MARK: - One at a Time

private func oneAtATime() -> StageBoard {
    var b = board()
    b.setGrouping(.oneAtATime)
    return b
}

/// Board with app 1's windows 10, 11, 12 opened in that order, then app 2's window 20.
private func threeWindowsThenOther() -> StageBoard {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(1, 12))
    b.windowOpened(w(2, 20))
    return b
}

@Test func groupingDefaultsToAllAtOnce() {
    #expect(board().grouping == .allAtOnce)
    #expect(WindowGrouping(rawValue: "oneAtATime") == .oneAtATime)
    #expect(WindowGrouping(rawValue: "bogus") == nil)
}

@Test func oneAtATimeAppActivationShowsOnlyMostRecentWindow() {
    var b = threeWindowsThenOther()
    #expect(b.activeStage?.windows == [w(2, 20)])
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 12)])
    b.windowFocused(w(2, 20))
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 12)])
}

@Test func oneAtATimeOtherWindowsFormOnePile() {
    var b = threeWindowsThenOther()
    #expect(b.stripStages.count == 1)
    #expect(b.stripStages[0].windows == [w(1, 12), w(1, 11), w(1, 10)])
    b.appActivated(pid: 1)
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)], [w(1, 11), w(1, 10)]])
}

@Test func clickingPileCyclesThroughAppWindows() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    let pile = { (b: StageBoard) in b.stripStages.first { $0.windows.allSatisfy { $0.pid == 1 } }! }
    b.select(stageID: pile(b).id)
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(pile(b).windows == [w(1, 10), w(1, 12)])
    b.select(stageID: pile(b).id)
    #expect(b.activeStage?.windows == [w(1, 10)])
    b.select(stageID: pile(b).id)
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.count == 2)          // app 2's stage and app 1's one pile
    // A pile click from another app's stage: that stage goes to the strip as usual.
    b.windowFocused(w(2, 20))
    b.select(stageID: pile(b).id)
    #expect(b.activeStage?.windows.count == 1)
    #expect(b.activeStage?.windows.first?.pid == 1)
    #expect(b.stripStages.contains { $0.windows == [w(2, 20)] })
}

@Test func selectingSingleWindowStageInOneAtATimeActivatesIt() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)
    let other = b.stripStages.first { $0.windows == [w(2, 20)] }!.id
    b.select(stageID: other)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)]])
}

@Test func newWindowTakesStageAndPreviousJoinsPile() {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
    b.windowOpened(w(1, 12))
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
}

@Test func newWindowInCombinedStageReplacesOnlyItsAppsWindow() {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))               // manual combine: 20 + 10 on stage
    b.windowOpened(w(1, 11))
    #expect(Set(b.activeStage!.windows) == [w(2, 20), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func focusingParkedWindowPutsExactlyItOnStage() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    b.windowFocused(w(1, 10))                  // Cmd-` to a parked window
    #expect(b.activeStage?.windows == [w(1, 10)])
    let pile = b.stripStages.first { $0.windows.allSatisfy { $0.pid == 1 } }!
    #expect(pile.windows == [w(1, 12), w(1, 11)])
    #expect(b.stripStages.count == 2)
}

@Test func shiftClickAddsOnlyPilesFrontWindow() {
    var b = threeWindowsThenOther()             // 20 on stage, pile [12, 11, 10]
    let pile = b.stripStages[0].id
    let front = b.stripStages[0].windows[0]
    b.addToActiveStage(front)
    #expect(Set(b.activeStage!.windows) == [w(2, 20), w(1, 12)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
    // Drag-to-stage of a pile: only its front window too.
    b.combineIntoActive(stageID: pile)
    #expect(Set(b.activeStage!.windows) == [w(2, 20), w(1, 12), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func minimizeJoinsAppPile() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    b.moveToPile(w(1, 12))
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.windows == [w(1, 12), w(1, 11), w(1, 10)])
    #expect(b.stripStages.count == 2)
    // With other windows on stage, the rest stays.
    b.windowFocused(w(2, 20))
    b.addToActiveStage(w(1, 12))
    b.moveToPile(w(1, 12))
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)]])
}

@Test func dockMinimizedWindowStaysOutOfPile() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    b.minimize(w(1, 12))
    #expect(b.stripStages.first?.windows == [w(1, 12)])
    #expect(b.stripStages.contains { $0.windows == [w(1, 11), w(1, 10)] })
    b.appActivated(pid: 1)                     // never picks the minimized window
    #expect(b.activeStage?.windows == [w(1, 11)])
    b.deminimize(w(1, 12))
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.contains { $0.windows == [w(1, 11), w(1, 10)] })
}

@Test func switchingAllToOneSplitsAndOneToAllMerges() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.windowFocused(w(1, 10))
    b.addToActiveStage(w(2, 21))               // stage: 21, 10, 11; strip: [20]
    #expect(b.activeStage?.windows == [w(2, 21), w(1, 10), w(1, 11)])
    let activeID = b.activeStageID
    let before = b
    b.setGrouping(.oneAtATime)
    #expect(b.grouping == .oneAtATime)
    #expect(b.activeStageID == activeID)
    #expect(b.activeStage?.windows == [w(2, 21), w(1, 10)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11)], [w(2, 20)]])
    #expect(transitionPlan(from: before, to: b).leaving == [w(1, 11)])
    b.setGrouping(.allAtOnce)
    #expect(b.activeStageID == activeID)
    #expect(Set(b.activeStage!.windows) == [w(2, 21), w(1, 10), w(1, 11), w(2, 20)])
    #expect(b.stripStages.isEmpty)
}

@Test func switchingToOneAtATimeMergesAppsStripStagesIntoOnePile() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.moveToOwnStage(w(1, 11))                 // app 1 split across two stages
    b.windowOpened(w(2, 20))
    #expect(b.stripStages.count == 2)
    b.setGrouping(.oneAtATime)
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
}

@Test func closingWindowsKeepsOnePilePerApp() {
    var b = threeWindowsThenOther()
    b.windowClosed(w(1, 11))
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 10)]])
    b.appTerminated(pid: 1)
    #expect(b.stripStages.isEmpty)
    #expect(b.activeStage?.windows == [w(2, 20)])
}

@Test func activateOnPileKeepsItsFrontOnStage() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    let pile = b.stripStages.first { $0.windows.allSatisfy { $0.pid == 1 } }!.id
    b.activate(stageID: pile)                  // e.g. reseed restoring a stage merged into a pile
    #expect(b.activeStage?.windows == [w(1, 11)])
    b.appActivated(pid: 1)                     // must not swap back to 12
    #expect(b.activeStage?.windows == [w(1, 11)])
}

@Test func singleWindowAppStageBehavesLikeAPileInCombinedStage() {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))                   // 11 on stage, pile [10]
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 11))               // stage: 11 + 20; strip: [10]
    #expect(Set(b.activeStage!.windows) == [w(1, 11), w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
    b.windowFocused(w(1, 10))                  // a lone window, not a 2+ pile
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)], [w(1, 11)]])
}

@Test func newWindowOfAppWithPileButNothingOnStageGetsItsOwnStage() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.windowOpened(w(1, 13))
    #expect(b.activeStage?.windows == [w(1, 13)])
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)], [w(1, 12), w(1, 11), w(1, 10)]])
}

// MARK: - Dock-icon click: sendAppToStrip

@Test func sendAppToStripMovesWholeSingleAppStageToFrontOfStrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))                   // stage: 21, 20; strip: [10]
    let stage = b.activeStageID!
    b.sendAppToStrip(pid: 2)
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.id == stage)
    #expect(Set(b.stripStages.first!.windows) == [w(2, 20), w(2, 21)])
    // Clicking the icon again: the app activates and its stage comes back.
    b.appActivated(pid: 2)
    #expect(b.activeStageID == stage)
}

@Test func sendAppToStripInMixedStageMovesOnlyThatApp() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.addToActiveStage(w(1, 10))               // stage: 10, 21, 20
    let stage = b.activeStageID!
    b.sendAppToStrip(pid: 2)
    #expect(b.activeStageID == stage)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.count == 1)
    #expect(Set(b.stripStages[0].windows) == [w(2, 20), w(2, 21)])
}

@Test func sendAppToStripPutsNewStageAheadOfOlderStripStages() {
    var b = board()
    b.windowOpened(w(3, 30))
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))               // stage: 10, 20; strip: [30]
    b.sendAppToStrip(pid: 2)
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)], [w(3, 30)]])
}

@Test func sendAppToStripIsNoOpWithoutWindowOnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    let before = b
    b.sendAppToStrip(pid: 1)                   // app 1 is in the strip only
    #expect(b == before)
    b.sendAppToStrip(pid: 9)
    #expect(b == before)
    var empty = board()
    empty.sendAppToStrip(pid: 1)
    #expect(empty == board())
}

@Test func sendAppToStripOneAtATimeJoinsPile() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    b.sendAppToStrip(pid: 1)
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.windows == [w(1, 12), w(1, 11), w(1, 10)])
    #expect(b.stripStages.count == 2)
    // Mixed stage: only that app's window leaves.
    b.windowFocused(w(2, 20))
    b.addToActiveStage(w(1, 12))
    b.sendAppToStrip(pid: 1)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)]])
}

@Test func showOneAtATimeBringsExactlyThatWindowOnStageAlone() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.appActivated(pid: 1)                     // 12 on stage, pile [11, 10]
    b.show(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.contains { $0.windows == [w(1, 12), w(1, 11)] })
    // Out of a manual combine: only it comes, the rest of that stage stays in the strip.
    b.windowFocused(w(2, 20))
    b.addToActiveStage(w(1, 10))               // 20 + 10 on stage
    b.windowFocused(w(1, 11))                  // 11 on stage; [20] alone, 10 in the pile
    b.addToActiveStage(w(2, 20))               // 11 + 20 on stage
    b.show(w(1, 12))
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.contains { $0.windows == [w(2, 20)] })
    #expect(Set(b.stages.flatMap(\.windows)) == [w(1, 10), w(1, 11), w(1, 12), w(2, 20)])
}

@Test func showAllAtOnceActivatesStageWithWindowInFront() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))                   // 11 front, 10 behind
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.show(w(1, 10))
    #expect(b.activeStageID == first)
    #expect(b.activeStage?.windows == [w(1, 10), w(1, 11)])
}

@Test func showIsNoOpForDockedOrUnknownWindow() {
    var b = threeWindowsThenOther()
    b.minimize(w(1, 11))
    let before = b
    b.show(w(1, 11))
    b.show(w(9, 90))
    #expect(b == before)
}

@Test func showFromDesktopBringsWindowOnStageInBothGroupings() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.sendAppToStrip(pid: 2)                   // desktop
    b.show(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10), w(1, 11)])
    var one = threeWindowsThenOther()          // 20 on stage, pile [12, 11, 10]
    one.sendAppToStrip(pid: 2)                 // desktop
    one.show(w(1, 11))
    #expect(one.activeStage?.windows == [w(1, 11)])
    #expect(one.stripStages.contains { $0.windows == [w(1, 12), w(1, 10)] })
}

@Test func showOfWindowAlreadyOnStageOnlyBringsItToFront() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    let stage = b.activeStageID!
    b.show(w(1, 10))
    #expect(b.activeStageID == stage)
    #expect(b.activeStage?.windows == [w(1, 10), w(1, 11)])
    var one = oneAtATime()
    one.windowOpened(w(1, 10))
    one.windowOpened(w(2, 20))
    one.addToActiveStage(w(1, 10))             // manual combine: 20 + 10 on stage
    one.show(w(2, 20))
    #expect(one.activeStage?.windows == [w(2, 20), w(1, 10)])
    #expect(one.stripStages.isEmpty)
}

/// One at a Time: a hand-combined strip stage [10, 20] and app 3's window 30 on stage.
private func mixedStripStage() -> (StageBoard, UUID) {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    let mixed = b.activeStageID!
    b.windowOpened(w(3, 30))
    return (b, mixed)
}

@Test func dropOfPileGivesExactlyDraggedWindow() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.combineIntoActive(stageID: b.stripStages[0].id, dragged: w(1, 11))
    #expect(Set(b.activeStage!.windows) == [w(2, 20), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 10)]])
}

@Test func dropOfMixedStageMergesItWhole() {
    var (b, mixed) = mixedStripStage()
    b.combineIntoActive(stageID: mixed, dragged: w(1, 10))
    #expect(Set(b.activeStage!.windows) == [w(3, 30), w(1, 10), w(2, 20)])
    #expect(b.stripStages.isEmpty)
}

@Test func dropOnDesktopSelectsTheWholeStage() {
    var (b, mixed) = mixedStripStage()
    b.sendAppToStrip(pid: 3)                   // desktop
    b.combineIntoActive(stageID: mixed, dragged: w(1, 10))
    #expect(b.activeStageID == mixed)
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(2, 20)])
}

@Test func dropWithStaleDraggedWindowUsesTheStage() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    b.combineIntoActive(stageID: b.stripStages[0].id, dragged: w(9, 90))
    #expect(Set(b.activeStage!.windows) == [w(2, 20), w(1, 12)])
    let before = b
    b.combineIntoActive(stageID: UUID(), dragged: w(1, 11))
    #expect(b == before)
}

// MARK: - Hidden apps (Cmd-H)

@Test func hidingAppAloneOnStageLeavesDesktopAndNoSlot() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.appHidden(pid: 2)
    #expect(b.activeStageID == nil)
    #expect(b.isHidden(pid: 2))
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
    #expect(appWindowItems(board: b, pid: 2).isEmpty)
}

@Test func hidingAppInSharedStageKeepsOtherAppsOnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    #expect(Set(b.activeStage!.windows) == [w(1, 10), w(2, 20)])
    b.appHidden(pid: 2)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.visibleStripStages.isEmpty)
}

@Test func hiddenAppIsNotActivatedUntilUnhidden() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.appHidden(pid: 2)
    b.appActivated(pid: 2)
    #expect(b.activeStageID == nil)
    b.appUnhidden(pid: 2)
    #expect(!b.isHidden(pid: 2))
    #expect(b.visibleStripStages.count == 2)
    b.appActivated(pid: 2)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func hidingOtherAppsTakesTheirStripStagesOut() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(3, 30))
    // Hide Others from app 3.
    b.appHidden(pid: 1)
    b.appHidden(pid: 2)
    #expect(b.activeStage?.windows == [w(3, 30)])
    #expect(b.visibleStripStages.isEmpty)
    // Show All: the strip stages come back, the stage stays as it is.
    b.appUnhidden(pid: 1)
    b.appUnhidden(pid: 2)
    #expect(b.activeStage?.windows == [w(3, 30)])
    #expect(b.visibleStripStages.count == 2)
}

@Test func windowOpenedByHiddenAppDoesNotJoinItsHiddenStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.appHidden(pid: 2)
    b.windowOpened(w(2, 21))
    #expect(b.activeStage?.windows == [w(2, 21)])
}

@Test func terminatingHiddenAppForgetsIt() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.appHidden(pid: 1)
    b.appTerminated(pid: 1)
    #expect(!b.isHidden(pid: 1))
    #expect(b.stages.isEmpty)
}

@Test func oneAtATimeHidingAppSendsItsWindowToItsPile() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)
    b.appHidden(pid: 1)
    #expect(b.activeStageID == nil)
    #expect(b.visibleStripStages.map(\.windows) == [[w(2, 20)]])
    b.appUnhidden(pid: 1)
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 12)])
}

// MARK: - Wallpaper click: showDesktop

@Test func showDesktopSendsWholeActiveStageToFrontOfStrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))                   // stage: 21, 20; strip: [10]
    let stage = b.activeStageID!
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.map(\.id).first == stage)
    #expect(b.stripStages.map(\.windows) == [[w(2, 21), w(2, 20)], [w(1, 10)]])
    // A strip click brings it back.
    b.select(stageID: stage)
    #expect(b.activeStageID == stage)
    #expect(b.activeStage?.windows == [w(2, 21), w(2, 20)])
}

@Test func showDesktopOnDesktopIsNoOp() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.showDesktop()
    let desktop = b
    b.showDesktop()
    #expect(b == desktop)
    #expect(board().stages.isEmpty)
}

@Test func showDesktopPutsActiveStageAheadOfJustMinimizedWindow() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    let stage = b.activeStageID!
    b.minimize(w(2, 21))                        // its stage is ahead of the active one
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)], [w(2, 21)], [w(1, 10)]])
    #expect(b.stripStages.first?.id == stage)
}

@Test func oneAtATimeShowDesktopJoinsWindowToFrontOfItsPile() {
    var b = threeWindowsThenOther()            // stage: [20]; strip: [12, 11, 10]
    b.select(stageID: b.stripStages[0].id)     // stage: [12]; strip: [20], [11, 10]
    #expect(b.activeStage?.windows == [w(1, 12)])
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)], [w(2, 20)]])
    // A strip click brings the same window back alone.
    b.select(stageID: b.stripStages[0].id)
    #expect(b.activeStage?.windows == [w(1, 12)])
}

@Test func oneAtATimeShowDesktopKeepsMixedStageTogether() {
    var b = threeWindowsThenOther()            // stage: [20]; strip: [12, 11, 10]
    b.addToActiveStage(w(1, 12))               // stage: 12, 20; strip: [11, 10]
    let stage = b.activeStageID!
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.id == stage)
    #expect(Set(b.stripStages[0].windows) == [w(1, 12), w(2, 20)])
    #expect(b.stripStages.map(\.windows).last == [w(1, 11), w(1, 10)])
}

@Test func hidingAppWithOnlyStripStagesKeepsTheStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    let active = b.activeStageID
    let order = b.stripStages.map(\.id)
    b.appHidden(pid: 1)
    #expect(b.activeStageID == active)
    #expect(b.stripStages.map(\.id) == order)
    #expect(b.visibleStripStages.isEmpty)
}

@Test func focusingHiddenAppsWindowIsNoOp() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.appHidden(pid: 1)
    let before = b
    b.windowFocused(w(1, 10))
    #expect(b == before)
    #expect(b.activeStage?.windows == [w(2, 20)])
}
