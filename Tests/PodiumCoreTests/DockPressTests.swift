import CoreGraphics
import Testing
@testable import PodiumCore

@Suite struct DockPressTests {
    let p = CGPoint(x: 100, y: 900)

    private func pressed() -> DockPress {
        var d = DockPress()
        d.began(at: p, time: 10)
        return d
    }

    @Test func quickClickActs() {
        var d = pressed()
        #expect(d.isPending)
        #expect(d.released(at: p, time: 10.1) == .act)
        #expect(!d.isPending)
    }

    @Test func jitterWithinThresholdStillActs() {
        var d = pressed()
        #expect(d.dragged(to: CGPoint(x: 102, y: 902), time: 10.05) == .swallow)
        #expect(d.released(at: CGPoint(x: 103, y: 901), time: 10.1) == .act)
    }

    @Test func dragPastThresholdReplaysThenPasses() {
        var d = pressed()
        #expect(d.dragged(to: CGPoint(x: 110, y: 900), time: 10.05) == .replay)
        #expect(d.dragged(to: CGPoint(x: 150, y: 900), time: 10.1) == .pass)
        #expect(d.released(at: CGPoint(x: 150, y: 900), time: 10.2) == .pass)
        #expect(!d.isPending)
    }

    @Test func holdTimeoutReplaysThenPasses() {
        var d = pressed()
        #expect(d.holdElapsed() == .replay)
        #expect(!d.isPending)
        #expect(d.dragged(to: CGPoint(x: 100, y: 850), time: 11) == .pass)   // into the Dock menu
        #expect(d.released(at: CGPoint(x: 100, y: 850), time: 11.5) == .pass)
    }

    @Test func lateOrMovedReleaseReplays() {
        var late = pressed()
        #expect(late.released(at: p, time: 10.5) == .replay)
        var moved = pressed()
        #expect(moved.released(at: CGPoint(x: 100, y: 880), time: 10.1) == .replay)
    }

    @Test func newMouseDownResets() {
        var d = pressed()
        d.reset()
        #expect(!d.isPending)
        #expect(d.released(at: p, time: 10.1) == .pass)
        #expect(d.holdElapsed() == .pass)
    }

    @Test func idleEventsPass() {
        var d = DockPress()
        #expect(d.dragged(to: p, time: 1) == .pass)
        #expect(d.released(at: p, time: 1) == .pass)
        #expect(d.holdElapsed() == .pass)
    }
}
