import Testing
import CoreGraphics
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }
private func entry(_ id: UInt32, _ frame: CGRect) -> ParkedEntry {
    ParkedEntry(window: w(1, id), bundleID: nil, originalFrame: frame, displayID: 1)
}
private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

@Test func recoveryRestoresLiveWindowsToOriginalFrames() {
    let a = entry(1, CGRect(x: 100, y: 100, width: 300, height: 200))
    let b = entry(2, CGRect(x: 500, y: 300, width: 400, height: 300))
    let actions = recoveryActions(entries: [a, b], liveWindows: [a.window, b.window], visibleScreens: [screen])
    #expect(actions == [.restore(a.window, to: a.originalFrame), .restore(b.window, to: b.originalFrame)])
}

@Test func recoveryDropsWindowsThatNoLongerExist() {
    let a = entry(1, CGRect(x: 100, y: 100, width: 300, height: 200))
    let b = entry(2, CGRect(x: 500, y: 300, width: 400, height: 300))
    let actions = recoveryActions(entries: [a, b], liveWindows: [b.window], visibleScreens: [screen])
    #expect(actions == [.forget(a.window), .restore(b.window, to: b.originalFrame)])
}

@Test func recoveryClampsFramesOntoVisibleScreen() {
    let gone = entry(1, CGRect(x: 3000, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [gone], liveWindows: [gone.window], visibleScreens: [screen])
    #expect(actions == [.restore(gone.window, to: CGRect(x: 350, y: 300, width: 300, height: 200))])
}

@Test func recoveryShrinksOversizedFramesToScreen() {
    let big = entry(1, CGRect(x: 3000, y: 3000, width: 2000, height: 500))
    let actions = recoveryActions(entries: [big], liveWindows: [big.window], visibleScreens: [screen])
    guard case let .restore(_, to: frame)? = actions.first else { Issue.record("no restore"); return }
    #expect(frame == CGRect(x: 0, y: 150, width: 1000, height: 500))
    #expect(screen.contains(frame))
}

@Test func recoveryLeavesPartlyVisibleFramesUnchanged() {
    let partly = entry(1, CGRect(x: 900, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [partly], liveWindows: [partly.window], visibleScreens: [screen])
    #expect(actions == [.restore(partly.window, to: partly.originalFrame)])
}

@Test func recoveryTreatsTouchingEdgeAsOffScreen() {
    let edge = entry(1, CGRect(x: 1000, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [edge], liveWindows: [edge.window], visibleScreens: [screen])
    #expect(actions == [.restore(edge.window, to: CGRect(x: 350, y: 300, width: 300, height: 200))])
}

@Test func recoveryWithNoVisibleScreensRestoresUnchanged() {
    let a = entry(1, CGRect(x: 3000, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [a], liveWindows: [a.window], visibleScreens: [])
    #expect(actions == [.restore(a.window, to: a.originalFrame)])
}
