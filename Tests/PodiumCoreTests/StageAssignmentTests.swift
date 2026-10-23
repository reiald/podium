import Testing
@testable import PodiumCore

// Rules R1–R13 of docs/research/2026-10-23-apple-stage-assignment.md, against the pure
// assignment.

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }
private let s1 = UserSetID(1)

private func groups(_ zOrder: [WindowRef], sets: [UserSetID: [WindowRef]] = [:], minimized: Set<WindowRef> = [],
                    hidden: Set<Int32> = [], _ grouping: WindowGrouping) -> [ContainerGroup] {
    assign(AssignmentInput(zOrder: zOrder, userSets: sets, minimized: minimized, hidden: hidden,
                           grouping: grouping)).groups
}

// R1
@Test func eachAppGetsOneGroupHoldingOneSetPerWindowInZOrder() {
    let g = groups([w(1, 10), w(2, 20), w(1, 11)], .oneAtATime)
    #expect(g == [
        ContainerGroup(.process(1), [WindowSet(.window(w(1, 10)), [w(1, 10)]), WindowSet(.window(w(1, 11)), [w(1, 11)])]),
        ContainerGroup(.process(2), [WindowSet(.window(w(2, 20)), [w(2, 20)])]),
    ])
}

// R2
@Test func allAtOnceMergesLooseWindowsIntoOneAppSetWhereTheFirstLooseOneWas() {
    let looseFirst = groups([w(1, 10), w(1, 11), w(1, 13), w(1, 12)], sets: [s1: [w(1, 11), w(1, 12)]], .allAtOnce)
    #expect(looseFirst.map(\.sets) == [[
        WindowSet(.process(1), [w(1, 10), w(1, 13)]),
        WindowSet(.userSet(s1), [w(1, 11), w(1, 12)]),
    ]])
    let userSetFirst = groups([w(1, 11), w(1, 10), w(1, 12), w(1, 13)], sets: [s1: [w(1, 11), w(1, 12)]], .allAtOnce)
    #expect(userSetFirst.map(\.sets) == [[
        WindowSet(.userSet(s1), [w(1, 11), w(1, 12)]),
        WindowSet(.process(1), [w(1, 10), w(1, 13)]),
    ]])
}

// R3
@Test func oneAtATimeKeepsOneSetPerLooseWindow() {
    let g = groups([w(1, 10), w(1, 11), w(1, 13), w(1, 12)], sets: [s1: [w(1, 11), w(1, 12)]], .oneAtATime)
    #expect(g.map(\.sets) == [[
        WindowSet(.window(w(1, 10)), [w(1, 10)]),
        WindowSet(.userSet(s1), [w(1, 11), w(1, 12)]),
        WindowSet(.window(w(1, 13)), [w(1, 13)]),
    ]])
}

// R4
@Test func crossAppUserSetGetsItsOwnGroupAndSingleAppOneStaysInTheAppsGroup() {
    let cross = groups([w(1, 10), w(2, 20), w(1, 11)], sets: [s1: [w(2, 20), w(1, 10)]], .allAtOnce)
    #expect(cross == [
        ContainerGroup(.crossAppSet(s1), [WindowSet(.userSet(s1), [w(1, 10), w(2, 20)])]),
        ContainerGroup(.process(1), [WindowSet(.process(1), [w(1, 11)])]),
    ])
    let single = groups([w(1, 10), w(2, 20), w(1, 11)], sets: [s1: [w(1, 11), w(1, 10)]], .allAtOnce)
    #expect(single == [
        ContainerGroup(.process(1), [WindowSet(.userSet(s1), [w(1, 10), w(1, 11)])]),
        ContainerGroup(.process(2), [WindowSet(.process(2), [w(2, 20)])]),
    ])
}

// R5
@Test func minimizedWindowsSplitIntoSetsOfTheirOwnInTheSameGroup() {
    let behind = groups([w(1, 10), w(1, 11), w(1, 12)], minimized: [w(1, 11)], .allAtOnce)
    #expect(behind.map(\.sets) == [[
        WindowSet(.process(1), [w(1, 10), w(1, 12)]),
        WindowSet(.minimized(w(1, 11)), [w(1, 11)]),
    ]])
    let front = groups([w(1, 10), w(1, 11), w(1, 12)], minimized: [w(1, 10)], .allAtOnce)
    #expect(front.map(\.sets) == [[
        WindowSet(.minimized(w(1, 10)), [w(1, 10)]),
        WindowSet(.process(1), [w(1, 11), w(1, 12)]),
    ]])
}

@Test func aMinimizedSetIsNeverTheStageWindowSet() {
    let a = assign(AssignmentInput(zOrder: [w(1, 10), w(1, 11)], minimized: [w(1, 10)], proposal: w(1, 10)))
    #expect(a.stageGroup == .process(1))
    #expect(a.stageWindowSet == .process(1))
    #expect(a.stageWindows == [w(1, 11)])
}

// R6
@Test func groupsAreOrderedByTheirFrontWindow() {
    let g = groups([w(2, 20), w(1, 10), w(3, 30), w(2, 21)], .allAtOnce)
    #expect(g.map(\.id) == [.process(2), .process(1), .process(3)])
}

@Test func hiddenAppsWindowsAreLeftOut() {
    let g = groups([w(2, 20), w(1, 10)], hidden: [2], .allAtOnce)
    #expect(g.map(\.id) == [.process(1)])
}

// R7
@Test func stageIsTheGroupOfTheProposedWindow() {
    let a = assign(AssignmentInput(zOrder: [w(1, 10), w(2, 20)], proposal: w(2, 20)))
    #expect(a.stageGroup == .process(2))
    #expect(a.stageWindows == [w(2, 20)])
}

@Test func withoutProposalStageIsFirstGroupWithAWindowNotMinimized() {
    let a = assign(AssignmentInput(zOrder: [w(1, 10), w(2, 20)], minimized: [w(1, 10)], proposal: nil))
    #expect(a.stageGroup == .process(2))
    let stale = assign(AssignmentInput(zOrder: [w(1, 10), w(2, 20)], proposal: w(9, 90)))
    #expect(stale.stageGroup == .process(1))
}

// R8
@Test func emptyStageStyleLeavesNoStageGroupNorSet() {
    let a = assign(AssignmentInput(zOrder: [w(1, 10), w(2, 20)], proposal: w(1, 10), emptyStage: true))
    #expect(a.stageGroup == nil)
    #expect(a.stageWindowSet == nil)
    #expect(a.strip == [.process(1), .process(2)])
}

// R9
@Test func stageWindowSetIsTheStageGroupsFirstSetNotMinimized() {
    let a = assign(AssignmentInput(zOrder: [w(1, 10), w(1, 11), w(1, 12)], minimized: [w(1, 10)],
                                   grouping: .oneAtATime, proposal: w(1, 12)))
    #expect(a.stageGroup == .process(1))
    #expect(a.stageWindowSet == .window(w(1, 11)))
}

// R10
@Test func stageGroupLeavesTheStripOnlyWhenItIsOneSetNotMinimized() {
    let whole = assign(AssignmentInput(zOrder: [w(1, 10), w(1, 11), w(2, 20)], proposal: w(1, 10)))
    #expect(whole.strip == [.process(2)])
    let oneAtATime = assign(AssignmentInput(zOrder: [w(1, 10), w(1, 11), w(2, 20)], grouping: .oneAtATime,
                                            proposal: w(1, 10)))
    #expect(oneAtATime.strip.contains(.process(1)))
    let withMinimized = assign(AssignmentInput(zOrder: [w(1, 10), w(1, 11), w(2, 20)], minimized: [w(1, 11)],
                                               proposal: w(1, 10)))
    #expect(withMinimized.strip.contains(.process(1)))
}

// R11
@Test func recencyStripIsGroupOrderWithoutTheStage() {
    let previous = StripState(sortedStrip: [.process(3), .process(2)], stageGroup: .process(1))
    let a = assign(AssignmentInput(zOrder: [w(2, 20), w(1, 10), w(3, 30)], proposal: w(2, 20),
                                   replacementOrder: .recency, previous: previous))
    #expect(a.strip == [.process(1), .process(3)])
}

// R12
@Test func stableLRUKeepsSlotsAndGivesTheVacatedOneToThePreviousStage() {
    // Stage 1; strip 2, 3, 4. A click on 3 puts it on stage: 1 takes its slot.
    let previous = StripState(sortedStrip: [.process(2), .process(3), .process(4)], stageGroup: .process(1))
    let a = assign(AssignmentInput(zOrder: [w(3, 30), w(1, 10), w(2, 20), w(4, 40)], proposal: w(3, 30),
                                   previous: previous))
    #expect(a.stageGroup == .process(3))
    #expect(a.strip == [.process(2), .process(1), .process(4)])
    #expect(a.state == StripState(sortedStrip: a.strip, stageGroup: .process(3)))
}

@Test func stableLRUFillsAVacatedSlotWithTheNextGroupNotVisibleAndAppendsTheRest() {
    // Two visible rows: 2 and 3. 3 closes; no previous stage group is waiting.
    let previous = StripState(sortedStrip: [.process(2), .process(3), .process(4), .process(5)], stageGroup: .process(1))
    let a = stripOrder(candidates: [.process(5), .process(2), .process(4)], previous: previous,
                       replacementOrder: .stableLeastRecentlyUsed, maximumRowCount: 2)
    #expect(a == [.process(2), .process(5), .process(4)])
}

// R13
@Test func maximumRowCountNeverHidesGroups() {
    let windows = (1...8).map { w(Int32($0), UInt32($0 * 10)) }
    let a = assign(AssignmentInput(zOrder: windows, proposal: windows[0], maximumRowCount: 3))
    #expect(a.strip.count == 7)
    #expect(Set(a.strip) == Set((2...8).map { GroupID.process(Int32($0)) }))
}
