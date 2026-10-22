import Testing
import Foundation
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }

/// One at a Time, app 1's windows 10, 11, 12 opened in that order, then app 2's window 20.
private func threeWindowsThenOther() -> StageBoard {
    var b = StageBoard(displayID: 1)
    b.setGrouping(.oneAtATime)
    b.windowOpened(w(1, 10))
    b.windowOpened(w(1, 11))
    b.windowOpened(w(1, 12))
    b.windowOpened(w(2, 20))
    return b
}

@Test func appWindowItemsAreOffStageWindowsMostRecentFirst() {
    var b = threeWindowsThenOther()            // 20 on stage, pile [12, 11, 10]
    #expect(appWindowItems(board: b, pid: 1).map(\.windows) == [[w(1, 12)], [w(1, 11)], [w(1, 10)]])
    b.windowFocused(w(1, 10))                  // 10 on stage: left out
    b.windowFocused(w(1, 11))                  // 11 on stage, 10 most recent off stage
    #expect(appWindowItems(board: b, pid: 1).map(\.windows) == [[w(1, 10)], [w(1, 12)]])
    #expect(appWindowItems(board: b, pid: 2).map(\.windows) == [[w(2, 20)]])
}

@Test func appWindowItemsLeaveOutDockAndOtherApps() {
    var b = threeWindowsThenOther()
    b.minimize(w(1, 11))
    #expect(appWindowItems(board: b, pid: 1).map(\.windows) == [[w(1, 12)], [w(1, 10)]])
    #expect(appWindowItems(board: b, pid: 2).isEmpty)  // on stage
    #expect(appWindowItems(board: b, pid: 9).isEmpty)
}

@Test func appWindowItemIDsAreStableAndNeverRealStageIDs() {
    let b = threeWindowsThenOther()
    let items = appWindowItems(board: b, pid: 1)
    #expect(items.map(\.id) == appWindowItems(board: b, pid: 1).map(\.id))
    #expect(Set(items.map(\.id)).count == 3)
    #expect(Set(items.map(\.id)).isDisjoint(with: b.stages.map(\.id)))
    #expect(appWindowItemID(w(1, 10)) != appWindowItemID(w(10, 1)))
    #expect(appWindowItemID(w(-1, 0)) == appWindowItemID(w(-1, 0)))
    // Version nibble 8: a random (version 4) stage id can never be one.
    #expect(items.allSatisfy { $0.id.uuid.6 >> 4 == 8 })
    #expect(b.stages.allSatisfy { $0.id.uuid.6 >> 4 == 4 })
}
