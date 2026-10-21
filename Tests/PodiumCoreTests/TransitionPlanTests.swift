import Testing
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }

@Test func switchingStagesListsLeavingAndEntering() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    old.windowOpened(w(1, 11))
    let first = old.activeStageID!
    old.windowOpened(w(2, 20))
    // Now stage 2 is active; switch back to stage 1.
    var new = old
    new.activate(stageID: first)

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.leaving == [w(2, 20)])
    #expect(Set(plan.entering) == [w(1, 10), w(1, 11)])
    #expect(plan.entering == new.activeStage!.windows)
}

@Test func minimizeOnlyMovesOneWindow() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    old.windowOpened(w(1, 11))
    old.windowOpened(w(2, 20))
    old.appActivated(pid: 1)
    var new = old
    new.minimize(w(1, 11))

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.leaving == [w(1, 11)])
    #expect(plan.entering.isEmpty)
}

@Test func noOpWhenActiveStageUnchanged() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    old.windowOpened(w(1, 11))
    old.windowOpened(w(2, 20))
    old.appActivated(pid: 1)
    // Refocusing within the active stage only reorders it.
    var new = old
    new.windowFocused(w(1, 10))
    new.windowFocused(w(1, 11))

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.leaving.isEmpty)
    #expect(plan.entering.isEmpty)
    #expect(plan.stripOrder == old.stripStages.map(\.id))

    #expect(transitionPlan(from: old, to: old) == TransitionPlan(leaving: [], entering: [], stripOrder: old.stripStages.map(\.id)))
}

@Test func stripOrderMatchesBoard() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    old.windowOpened(w(2, 20))
    old.windowOpened(w(3, 30))
    var new = old
    new.appActivated(pid: 1)

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.stripOrder == new.stripStages.map(\.id))
    #expect(plan.stripOrder.count == 2)
    #expect(!plan.stripOrder.contains(new.activeStageID!))
}

@Test func closedWindowsNeverLeaveAndNewWindowsNeverEnter() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    old.windowOpened(w(1, 11))
    var new = old
    new.windowClosed(w(1, 11))
    new.windowOpened(w(1, 12))

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.leaving.isEmpty)
    #expect(plan.entering.isEmpty)
}

@Test func combiningBringsTheStripStagesWindowsIn() {
    var old = StageBoard(displayID: 1)
    old.windowOpened(w(1, 10))
    let first = old.activeStageID!
    old.windowOpened(w(2, 20))
    var new = old
    new.combineIntoActive(stageID: first)

    let plan = transitionPlan(from: old, to: new)
    #expect(plan.leaving.isEmpty)
    #expect(plan.entering == [w(1, 10)])
    #expect(plan.stripOrder.isEmpty)
}
