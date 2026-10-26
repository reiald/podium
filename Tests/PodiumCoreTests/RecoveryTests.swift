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

@Test func recoveryForgetsAWindowWhoseNumberNowBelongsToAnotherApp() {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    let e = ParkedEntry(window: w(1, 1), bundleID: "com.example.Old", originalFrame: frame, displayID: 1)
    let other = recoveryActions(entries: [e], liveWindows: [e.window], visibleScreens: [screen], bundleID: { _ in "com.example.New" })
    #expect(other == [.forget(e.window)])
    let same = recoveryActions(entries: [e], liveWindows: [e.window], visibleScreens: [screen], bundleID: { _ in "com.example.Old" })
    #expect(same == [.restore(e.window, to: frame)])
    let unknown = recoveryActions(entries: [e], liveWindows: [e.window], visibleScreens: [screen])
    #expect(unknown == [.restore(e.window, to: frame)])
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

@Test func recoveryMovesPartlyOffScreenFrameMinimallyInside() {
    let partly = entry(1, CGRect(x: 900, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [partly], liveWindows: [partly.window], visibleScreens: [screen])
    #expect(actions == [.restore(partly.window, to: CGRect(x: 700, y: 100, width: 300, height: 200))])
}

@Test func recoveryMovesOnePointSliverFullyOnScreen() {
    // Overlaps the screen by a single 1x1 corner, like a parked window.
    let sliver = entry(1, CGRect(x: 999, y: 799, width: 300, height: 200))
    let actions = recoveryActions(entries: [sliver], liveWindows: [sliver.window], visibleScreens: [screen])
    guard case let .restore(_, to: frame)? = actions.first else { Issue.record("no restore"); return }
    #expect(screen.contains(frame))
    #expect(frame == CGRect(x: 700, y: 600, width: 300, height: 200))
}

@Test func recoveryPicksScreenWithLargestOverlap() {
    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    let e = entry(1, CGRect(x: 1900, y: 100, width: 300, height: 200))
    let actions = recoveryActions(entries: [e], liveWindows: [e.window], visibleScreens: [left, right])
    #expect(actions == [.restore(e.window, to: CGRect(x: 1700, y: 100, width: 300, height: 200))])
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
