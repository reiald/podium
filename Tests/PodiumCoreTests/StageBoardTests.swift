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
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(1, 11)])
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
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(1, 11)])
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
    b.windowOpened(w(1, 11))                  // app 1's own group: app 1 split across two
    let ownStage = b.activeStageID!
    b.appActivated(pid: 2)
    #expect(b.activeStageID != ownStage)
    b.windowFocused(w(1, 10))
    let stageOf10 = b.activeStageID!
    #expect(stageOf10 != ownStage)
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

// A viewer opened from Finder (qView, Archive Utility) takes the stage; closing its only
// window brings Finder's stage straight back, not an empty desktop until the app quits.
@Test func closingTheLastStageWindowBringsBackThePreviousStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))                     // the viewer: Finder goes to the strip
    #expect(b.activeStage?.windows == [w(2, 20)])
    b.windowClosed(w(2, 20))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(1, 11)])
    #expect(b.activeStage?.windows.first == w(1, 11))
    // Minimizing (or dragging out) the last window still leaves the desktop, as in Apple's.
    b.windowOpened(w(3, 30))
    b.minimizeToStrip(w(3, 30))
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
    #expect(b.stages.first?.windows == [w(2, 20)])
    #expect(b.activeStageID == nil)
}

@Test func shiftClickAddsWindowToActiveStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(2, 20)])
    #expect(b.stages.count == 1)
}

@Test func shiftClickWithNoActiveStageCreatesOne() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.showDesktop()
    #expect(b.activeStageID == nil)
    b.windowOpened(w(3, 30))
    b.windowClosed(w(3, 30))                   // the previous stage comes back
    b.showDesktop()
    b.addToActiveStage(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
}

@Test func combineMergesStageIntoActive() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.combineIntoActive(stageID: first, dragged: nil)
    #expect(b.stages.count == 1)
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(2, 20)])
    let combined = b
    b.combineIntoActive(stageID: b.activeStageID!, dragged: nil) // no-op
    #expect(b == combined)
}

@Test func droppedItemComesToFrontOfStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    let first = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.combineIntoActive(stageID: first, dragged: w(1, 10))
    #expect(b.activeStage?.windows.first == w(1, 10))
}

// R15 and the design: a drag out of the stage minimizes the window into its app's strip item.
@Test func dragOutMinimizesWindowIntoItsAppsStripItem() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    let stage = b.activeStageID
    b.minimizeToStrip(w(1, 11))
    #expect(b.activeStageID == stage)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11)]])
    #expect(b.stripStages.first?.id != stage)
    #expect(b.isMinimizedToStrip(w(1, 11)))
    #expect(!b.isMinimized(w(1, 11)))
}

// R5, R10: a Dock-minimized window stays in its app's group; the group stays in the strip.
@Test func dockMinimizeKeepsWindowInItsAppsGroup() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    let stage = b.activeStageID
    b.minimize(w(2, 21))
    #expect(b.activeStageID == stage)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.count == 2)
    #expect(b.stripStages.contains { $0.windows == [w(2, 21)] })
}

@Test func minimizeLastWindowEmptiesActive() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.minimize(w(1, 10))
    #expect(b.activeStageID == nil)
    #expect(b.stages.count == 1)
    #expect(b.stripStages.first?.windows == [w(1, 10)])
}

// R12 on the board: slots stay; the stage that leaves takes the chosen item's slot, or
// goes after the visible ones when no slot was vacated.
@Test func stableStripKeepsSlotsAndTheLeavingStageTakesTheChosenOnesSlot() {
    var b = board()
    b.windowOpened(w(1, 10)); let s1 = b.activeStageID!
    b.windowOpened(w(2, 20)); let s2 = b.activeStageID!
    b.windowOpened(w(3, 30)); let s3 = b.activeStageID!
    #expect(b.stripStages.map(\.id) == [s1, s2])
    b.select(stageID: s1)
    #expect(b.stripStages.map(\.id) == [s3, s2])
    b.showDesktop()
    #expect(b.stripStages.map(\.id) == [s3, s2, s1])
}

// R11 on the board.
@Test func recencyStripIsMostRecentlyUsedFirst() {
    var b = StageBoard(displayID: 1, replacementOrder: .recency)
    b.windowOpened(w(1, 10)); let s1 = b.activeStageID!
    b.windowOpened(w(2, 20)); let s2 = b.activeStageID!
    b.windowOpened(w(3, 30)); let s3 = b.activeStageID!
    #expect(b.stripStages.map(\.id) == [s2, s1])
    b.select(stageID: s1)
    #expect(b.stripStages.map(\.id) == [s3, s2])
    b.showDesktop()
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

// R17 is off: a new window joins its app's group, not a user set holding the app's windows.
@Test func newWindowJoinsItsAppsGroupNotAUserSet() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))               // 20 + 10
    let combined = b.activeStageID
    b.windowOpened(w(1, 11))
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(b.activeStageID != combined)
    #expect(b.stripStages.contains { Set($0.windows) == [w(1, 10), w(2, 20)] })
}

@Test func appActivationSkipsMinimizedOnlyStage() {
    var b = board()
    b.windowOpened(w(1, 10))        // Notes A
    b.windowOpened(w(1, 11))        // Notes B
    b.windowFocused(w(1, 10))       // A is Notes' most recent window...
    b.minimize(w(1, 10))            // ...then goes to the Dock
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

// All at Once a window back from the Dock comes on stage with its app's other windows.
@Test func deminimizeBringsWindowsAppGroupForward() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.minimize(w(1, 11))
    b.windowOpened(w(2, 20))
    b.deminimize(w(1, 11))
    #expect(b.activeStage?.windows == [w(1, 11), w(1, 10)])
    // No longer minimized: the app's activation maps to it again.
    b.windowOpened(w(3, 30))
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows == [w(1, 11), w(1, 10)])
}

@Test func focusingMinimizedWindowUnmarksIt() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.minimize(w(1, 11))
    b.windowFocused(w(1, 11))
    #expect(!b.isMinimized(w(1, 11)))
    b.windowOpened(w(2, 20))
    b.appActivated(pid: 1)
    #expect(b.activeStage?.windows.first == w(1, 11))
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

// Minimize to strip parks the window: it is minimized to the strip, never to the Dock.

@Test func minimizeToStripFromSharedStageKeepsRestOnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))                     // app 2 active; app 1 in the strip
    b.addToActiveStage(w(1, 10))                 // stage: 10 and 20
    b.minimizeToStrip(w(2, 20))
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)]])
    #expect(!b.isMinimized(w(2, 20)))
}

@Test func minimizeToStripOfAloneWindowLeavesDesktop() throws {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.minimizeToStrip(w(2, 20))
    #expect(b.activeStageID == nil)
    #expect(!b.isMinimized(w(2, 20)))
    let item = try #require(b.stripStages.first { $0.windows == [w(2, 20)] })
    // An activation finds no window to bring; a strip click does.
    b.appActivated(pid: 2)
    #expect(b.activeStageID == nil)
    b.select(stageID: item.id)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(!b.isMinimizedToStrip(w(2, 20)))
}

@Test func dockMinimizedStageHasNoStripSlot() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.minimize(w(2, 21))
    // Still a strip item (the model keeps it), but it gets no slot.
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

@Test func dockMinimizedWindowsAreLeftOutOfAVisibleItem() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.minimize(w(1, 11))
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
    #expect(b.visibleStripStages.map(\.windows) == [[w(1, 10)]])
    #expect(b.visibleStripStages.map(\.id) == b.stripStages.map(\.id))
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

// MARK: - Apple's operations (R14–R16, R18)

// R14
@Test func draggingAWindowOntoTheStageCreatesAUserSetOfTheStageWindowsPlusIt() {
    var b = board()
    b.windowOpened(w(3, 30))
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))                   // stage: 20; strip: 10, 30
    b.addToActiveStage(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10), w(2, 20)])
    let combined = b.activeStageID
    // The stage is a user set now: the next window joins it.
    b.addToActiveStage(w(3, 30))
    #expect(b.activeStageID == combined)
    #expect(b.activeStage?.windows == [w(3, 30), w(1, 10), w(2, 20)])
    #expect(b.stripStages.isEmpty)
    // The set outlives a switch away and back.
    b.windowOpened(w(4, 40))
    b.windowFocused(w(2, 20))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(2, 20), w(3, 30)])
    // It is a set of those windows, not of their apps: app 2's new window is not in it.
    b.windowOpened(w(2, 21))
    #expect(b.activeStage?.windows == [w(2, 21)])
    #expect(b.stripStages.contains { Set($0.windows) == [w(1, 10), w(2, 20), w(3, 30)] })
}

@Test func draggingAWholeAllAtOnceItemOntoTheStageBringsAllItsWindows() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    let app1 = b.activeStageID!
    b.windowOpened(w(2, 20))
    b.combineIntoActive(stageID: app1, dragged: w(1, 10))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(1, 11), w(2, 20)])
    #expect(b.stripStages.isEmpty)
}

// R15
@Test func draggingAWindowOffTheStageTakesItOutOfItsSetAndFrontsAnotherStageWindow() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))                   // stage: 21, 20
    b.addToActiveStage(w(1, 10))               // stage: 10, 21, 20 (a user set)
    b.minimizeToStrip(w(1, 10))
    #expect(b.activeStage?.windows == [w(2, 21), w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
    // Back on stage, it comes alone: it left the set.
    b.windowFocused(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
}

// R16
@Test func aReplacementWindowTakesTheOldOnesPlaceInItsUserSet() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))               // stage: 10, 20
    let combined = b.activeStageID
    b.windowReplaced(old: w(1, 10), new: w(1, 11))
    #expect(b.activeStageID == combined)
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 11), w(2, 20)])
    #expect(!b.stages.contains { $0.windows.contains(w(1, 10)) })
}

// R18
@Test func closingTheFrontWindowFrontsAnotherStageWindowOfTheSameAppFirst() {
    var b = board()
    b.windowOpened(w(3, 30))
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    b.addToActiveStage(w(1, 11))
    b.windowFocused(w(2, 20))
    b.windowFocused(w(1, 11))                  // stage: 11, 20, 10; strip: 30
    b.windowClosed(w(1, 11))
    // 20 was focused more recently, but 10 is of the closed window's app.
    #expect(b.activeStage?.windows.first == w(1, 10))
    b.windowClosed(w(1, 10))
    #expect(b.activeStage?.windows == [w(2, 20)])
    // None left: the stage used before it comes back.
    b.windowClosed(w(2, 20))
    #expect(b.activeStage?.windows == [w(3, 30)])
    #expect(b.stripStages.isEmpty)
}

@Test func stageIDsStayTheSameAcrossChanges() throws {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    let app1 = b.activeStageID!
    b.windowOpened(w(1, 11))
    #expect(b.activeStageID == app1)
    let rest = (try #require(b.stripStages.first)).id                 // app 1's other window
    #expect(rest != app1)
    b.windowOpened(w(2, 20))
    #expect(b.stripStages.map(\.id) == [app1])
    b.windowFocused(w(1, 10))
    #expect(b.activeStageID == app1)
    #expect(b.stripStages.map(\.id).contains(rest))
}

@Test func selectingAnItemWithOnlyMinimizedWindowsUnminimizesItsFrontOne() throws {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.minimizeToStrip(w(1, 11))
    b.minimizeToStrip(w(1, 10))
    #expect(b.activeStageID == nil)
    let item = (try #require(b.stripStages.first))
    #expect(item.windows == [w(1, 10), w(1, 11)])
    b.select(stageID: item.id)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.isMinimizedToStrip(w(1, 11)))
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

@Test func oneAtATimeOtherWindowsFormOneStripItem() throws {
    var b = threeWindowsThenOther()
    #expect(b.stripStages.count == 1)
    #expect((try #require(b.stripStages.first)).windows == [w(1, 12), w(1, 11), w(1, 10)])
    b.appActivated(pid: 1)
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)], [w(2, 20)]])
}

@Test func clickingTheAppsStripItemBringsItsMostRecentOtherWindow() throws {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage; strip: 11, 10
    let item = { (b: StageBoard) throws in try #require(b.stripStages.first { $0.windows.allSatisfy { $0.pid == 1 } }) }
    b.select(stageID: try item(b).id)
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(try item(b).windows == [w(1, 12), w(1, 10)])
    b.select(stageID: try item(b).id)
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.count == 2)          // app 2's item and app 1's one item
    // From another app's stage: that stage goes to the strip as usual.
    b.windowFocused(w(2, 20))
    b.select(stageID: try item(b).id)
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.contains { $0.windows == [w(2, 20)] })
}

@Test func selectingSingleWindowStageInOneAtATimeActivatesIt() throws {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)
    let other = try #require(b.stripStages.first { $0.windows == [w(2, 20)] }).id
    b.select(stageID: other)
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)]])
}

@Test func newWindowTakesStageAndPreviousJoinsTheAppsItem() {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    #expect(b.activeStage?.windows == [w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
    b.windowOpened(w(1, 12))
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
}

@Test func focusingParkedWindowPutsExactlyItOnStage() throws {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage; strip: 11, 10
    b.windowFocused(w(1, 10))                  // Cmd-` to a parked window
    #expect(b.activeStage?.windows == [w(1, 10)])
    let item = try #require(b.stripStages.first { $0.windows.allSatisfy { $0.pid == 1 } })
    #expect(item.windows == [w(1, 12), w(1, 11)])
    #expect(b.stripStages.count == 2)
}

@Test func shiftClickAddsOnlyTheItemsFrontWindow() throws {
    var b = threeWindowsThenOther()             // 20 on stage; strip: 12, 11, 10
    let item = (try #require(b.stripStages.first)).id
    let front = (try #require(b.stripStages.first)).windows[0]
    b.addToActiveStage(front)
    #expect(Set(b.activeStage?.windows ?? []) == [w(2, 20), w(1, 12)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 11), w(1, 10)]])
    // Drag-to-stage of the app's item: only its front window too.
    b.combineIntoActive(stageID: item, dragged: nil)
    #expect(Set(b.activeStage?.windows ?? []) == [w(2, 20), w(1, 12), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
}

@Test func minimizeToStripJoinsTheAppsItem() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage; strip: 11, 10
    b.minimizeToStrip(w(1, 12))
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.first?.windows == [w(1, 12), w(1, 11), w(1, 10)])
    #expect(b.stripStages.count == 2)
    // With other windows on stage, the rest stays.
    b.windowFocused(w(2, 20))
    b.addToActiveStage(w(1, 12))
    b.minimizeToStrip(w(1, 12))
    #expect(b.activeStage?.windows == [w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)]])
}

@Test func dockMinimizedWindowStaysInTheAppsItem() {
    var b = threeWindowsThenOther()
    b.appActivated(pid: 1)                     // 12 on stage; strip: 11, 10
    b.minimize(w(1, 12))
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.contains { $0.windows == [w(1, 12), w(1, 11), w(1, 10)] })
    b.appActivated(pid: 1)                     // never picks the minimized window
    #expect(b.activeStage?.windows == [w(1, 11)])
    b.deminimize(w(1, 12))
    #expect(b.activeStage?.windows == [w(1, 12)])
    #expect(b.stripStages.contains { $0.windows == [w(1, 11), w(1, 10)] })
}

@Test func switchingGroupingSplitsAndMergesTheAppsLooseWindows() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.windowFocused(w(1, 10))                  // stage: 10, 11; strip: 20
    let activeID = b.activeStageID
    let before = b
    b.setGrouping(.oneAtATime)
    #expect(b.grouping == .oneAtATime)
    #expect(b.activeStageID == activeID)
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(Set(b.stripStages.map(\.windows)) == [[w(1, 11)], [w(2, 20)]])
    #expect(transitionPlan(from: before, to: b).leaving == [w(1, 11)])
    b.setGrouping(.allAtOnce)
    #expect(b.activeStageID == activeID)
    #expect(b.activeStage?.windows == [w(1, 10), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(2, 20)]])
}

@Test func switchingGroupingKeepsUserSetsTogether() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    b.windowFocused(w(1, 10))
    b.addToActiveStage(w(2, 20))               // stage: 20, 10, 11 (a user set)
    let stage = b.activeStage
    b.setGrouping(.oneAtATime)
    #expect(b.activeStage == stage)
    #expect(b.stripStages.isEmpty)
}

@Test func closingWindowsKeepsOneItemPerApp() {
    var b = threeWindowsThenOther()
    b.windowClosed(w(1, 11))
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 10)]])
    b.appTerminated(pid: 1)
    #expect(b.stripStages.isEmpty)
    #expect(b.activeStage?.windows == [w(2, 20)])
}

@Test func focusingAWindowOfAUserSetBringsTheWholeSet() {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))                   // 11 on stage; strip: 10
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 11))               // stage: 11 + 20; strip: 10
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 11), w(2, 20)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)]])
    b.windowFocused(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.map { Set($0.windows) } == [[w(1, 11), w(2, 20)]])
    b.windowFocused(w(2, 20))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 11), w(2, 20)])
}

@Test func newWindowOfAppWithWindowsOnlyInTheStripTakesTheStage() {
    var b = threeWindowsThenOther()            // 20 on stage; strip: 12, 11, 10
    b.windowOpened(w(1, 13))
    #expect(b.activeStage?.windows == [w(1, 13)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)], [w(2, 20)]])
}

// MARK: - Dock-icon click: each of the app's windows on stage is minimized to the strip

@Test func dockClickMinimizeOfAppAloneOnStageLeavesDesktop() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))                   // stage: 21, 20; strip: 10
    for x in b.activeStage?.windows ?? [] { b.minimizeToStrip(x) }
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.contains { Set($0.windows) == [w(2, 20), w(2, 21)] })
}

@Test func dockClickMinimizeInMixedStageMovesOnlyThatApp() throws {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    b.addToActiveStage(w(1, 10))               // stage: 10, 21, 20
    for x in b.activeStage?.windows ?? [] where x.pid == 2 { b.minimizeToStrip(x) }
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.count == 1)
    #expect(Set((try #require(b.stripStages.first)).windows) == [w(2, 20), w(2, 21)])
}

@Test func showOneAtATimeBringsExactlyThatWindowOnStageAlone() {
    var b = threeWindowsThenOther()            // 20 on stage; strip: 12, 11, 10
    b.appActivated(pid: 1)                     // 12 on stage; strip: 11, 10
    b.show(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10)])
    #expect(b.stripStages.contains { $0.windows == [w(1, 12), w(1, 11)] })
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
    b.showDesktop()
    b.show(w(1, 10))
    #expect(b.activeStage?.windows == [w(1, 10), w(1, 11)])
    var one = threeWindowsThenOther()          // 20 on stage; strip: 12, 11, 10
    one.showDesktop()
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
    one.addToActiveStage(w(1, 10))             // user set: 10 + 20 on stage
    one.show(w(2, 20))
    #expect(one.activeStage?.windows == [w(2, 20), w(1, 10)])
    #expect(one.stripStages.isEmpty)
}

/// One at a Time: a hand-combined strip item [10, 20] and app 3's window 30 on stage.
private func mixedStripStage() -> (StageBoard, UUID) {
    var b = oneAtATime()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    let mixed = b.activeStageID!
    b.windowOpened(w(3, 30))
    return (b, mixed)
}

@Test func dropOfAppItemGivesExactlyDraggedWindow() throws {
    var b = threeWindowsThenOther()            // 20 on stage; strip: 12, 11, 10
    b.combineIntoActive(stageID: (try #require(b.stripStages.first)).id, dragged: w(1, 11))
    #expect(Set(b.activeStage?.windows ?? []) == [w(2, 20), w(1, 11)])
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 10)]])
}

@Test func dropOfMixedStageMergesItWhole() {
    var (b, mixed) = mixedStripStage()
    b.combineIntoActive(stageID: mixed, dragged: w(1, 10))
    #expect(Set(b.activeStage?.windows ?? []) == [w(3, 30), w(1, 10), w(2, 20)])
    #expect(b.stripStages.isEmpty)
}

@Test func dropOnDesktopSelectsTheWholeStage() {
    var (b, mixed) = mixedStripStage()
    b.showDesktop()
    b.combineIntoActive(stageID: mixed, dragged: w(1, 10))
    #expect(b.activeStageID == mixed)
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(2, 20)])
}

@Test func dropWithStaleDraggedWindowUsesTheStage() throws {
    var b = threeWindowsThenOther()            // 20 on stage; strip: 12, 11, 10
    b.combineIntoActive(stageID: (try #require(b.stripStages.first)).id, dragged: w(9, 90))
    #expect(Set(b.activeStage?.windows ?? []) == [w(2, 20), w(1, 12)])
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
    // Its windows are still on the board.
    #expect(Set(b.stages.flatMap(\.windows)) == [w(1, 10), w(2, 20), w(2, 21)])
}

@Test func hidingAppInSharedStageKeepsOtherAppsOnStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.addToActiveStage(w(1, 10))
    #expect(Set(b.activeStage?.windows ?? []) == [w(1, 10), w(2, 20)])
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

@Test func terminatingHiddenAppForgetsIt() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.appHidden(pid: 1)
    b.appTerminated(pid: 1)
    #expect(!b.isHidden(pid: 1))
    #expect(b.stages.isEmpty)
}

@Test func oneAtATimeHidingAppLeavesDesktopUntilItComesBack() {
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

@Test func showDesktopSendsWholeActiveStageToTheStrip() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))                   // stage: 21, 20; strip: 10
    let stage = b.activeStageID!
    b.showDesktop()
    #expect(b.activeStageID == nil)
    // Stable order: the visible items keep their slots; it goes after them.
    #expect(b.stripStages.map(\.id).last == stage)
    #expect(b.stripStages.map(\.windows) == [[w(1, 10)], [w(2, 21), w(2, 20)]])
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

@Test func oneAtATimeShowDesktopSendsTheWholeAppGroupToTheStrip() throws {
    var b = threeWindowsThenOther()            // stage: [20]; strip: [12, 11, 10]
    b.select(stageID: (try #require(b.stripStages.first)).id)     // stage: [12]; strip: [11, 10], [20]
    #expect(b.activeStage?.windows == [w(1, 12)])
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.map(\.windows) == [[w(1, 12), w(1, 11), w(1, 10)], [w(2, 20)]])
    // A strip click brings the same window back alone.
    b.select(stageID: (try #require(b.stripStages.first)).id)
    #expect(b.activeStage?.windows == [w(1, 12)])
}

@Test func oneAtATimeShowDesktopKeepsMixedStageTogether() {
    var b = threeWindowsThenOther()            // stage: [20]; strip: [12, 11, 10]
    b.addToActiveStage(w(1, 12))               // stage: 12, 20; strip: [11, 10]
    let stage = b.activeStageID!
    b.showDesktop()
    #expect(b.activeStageID == nil)
    #expect(b.stripStages.last?.id == stage)
    #expect(Set(b.stripStages.last?.windows ?? []) == [w(1, 12), w(2, 20)])
    #expect(b.stripStages.first?.windows == [w(1, 11), w(1, 10)])
}

@Test func hidingAppWithOnlyStripStagesKeepsTheStage() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(2, 20))
    let active = b.activeStageID
    b.appHidden(pid: 1)
    #expect(b.activeStageID == active)
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

// MARK: - All at Once: one strip item per app

/// Two Finder windows on stage, then another app comes on stage: Finder's windows share
/// one strip item, and a click on it brings both back. One minimized to the strip stays in
/// that item too.
@Test func allAtOnceAppWindowsShareOneStripItem() {
    let f1 = WindowRef(pid: 1, windowID: 10), f2 = WindowRef(pid: 1, windowID: 11)
    let b = WindowRef(pid: 2, windowID: 20)
    var board = StageBoard(displayID: 1)
    board.windowOpened(b)
    board.windowOpened(f1)
    board.windowOpened(f2)
    board.windowFocused(b)
    let finder = board.stages.filter { $0.windows.contains { $0.pid == 1 } }
    #expect(finder.count == 1)
    #expect(Set(finder.first?.windows ?? []) == [f1, f2])
    board.select(stageID: finder[0].id)
    #expect(Set(board.activeStage?.windows ?? []) == [f1, f2])
    board.minimizeToStrip(f2)
    board.windowFocused(b)
    #expect(board.stages.filter { $0.windows.contains { $0.pid == 1 } }.map { Set($0.windows) } == [[f1, f2]])
}

/// A window minimized to the Dock stays in its app's strip item.
@Test func allAtOnceMinimizedWindowStaysInItsAppsStripItem() {
    let f1 = WindowRef(pid: 1, windowID: 10), f2 = WindowRef(pid: 1, windowID: 11)
    let b = WindowRef(pid: 2, windowID: 20)
    var board = StageBoard(displayID: 1)
    board.windowOpened(b)
    board.windowOpened(f1)
    board.windowOpened(f2)
    board.minimize(f2)
    board.windowFocused(b)
    #expect(board.stages.filter { $0.windows.contains { $0.pid == 1 } }.count == 1)
}

@Test func secondWallpaperClickBringsTheStageBack() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.windowOpened(w(2, 21))
    let stage = b.activeStage
    #expect(!b.canReturnFromDesktop)
    b.showDesktop()
    #expect(b.activeStage == nil)
    #expect(b.canReturnFromDesktop)
    b.returnFromDesktop()
    #expect(b.activeStage == stage)
    #expect(!b.canReturnFromDesktop)
}

@Test func onlyTheWallpaperDesktopComesBack() {
    var b = board()
    b.windowOpened(w(1, 10))
    b.windowOpened(w(2, 20))
    b.showDesktop()
    b.windowFocused(w(1, 10))                    // a strip click ends it
    #expect(!b.canReturnFromDesktop)
    b.minimizeToStrip(w(1, 10))                  // desktop, but not from the wallpaper
    #expect(b.activeStage == nil)
    #expect(!b.canReturnFromDesktop)
    var closed = board()
    closed.windowOpened(w(1, 10))
    closed.showDesktop()
    closed.windowClosed(w(1, 10))                // nothing left to bring back
    #expect(!closed.canReturnFromDesktop)
    let before = closed
    closed.returnFromDesktop()
    #expect(closed == before)
}
