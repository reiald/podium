import CoreGraphics
import Testing
@testable import PodiumCore

@Suite struct StripDragTests {
    let p = CGPoint(x: 80, y: 400)

    private func pressed() -> StripDrag {
        var d = StripDrag()
        d.began(at: p)
        return d
    }

    @Test func clickStaysAClick() {
        var d = pressed()
        #expect(!d.isDragging)
        #expect(d.released(at: p, inBand: true) == .click)
    }

    @Test func jitterWithinThresholdStillClicks() {
        var d = pressed()
        #expect(d.dragged(to: CGPoint(x: 83, y: 402)) == .none)
        #expect(!d.isDragging)
        #expect(d.released(at: CGPoint(x: 82, y: 403), inBand: true) == .click)
    }

    @Test func exactlyTheThresholdIsStillAClick() {
        var d = pressed()
        let edge = CGPoint(x: p.x + StripDrag.dragThreshold, y: p.y)
        #expect(d.dragged(to: edge) == .none)
        #expect(d.released(at: edge, inBand: true) == .click)
    }

    @Test func pastThresholdIsADragForTheRestOfThePress() {
        var d = pressed()
        #expect(d.dragged(to: CGPoint(x: 90, y: 400)) == .began)
        #expect(d.isDragging)
        // Coming back near the press point does not make it a click again.
        #expect(d.dragged(to: p) == .moved)
        #expect(d.released(at: p, inBand: true) == .cancel)
        #expect(!d.isDragging)
    }

    @Test func dragReleasedOutsideTheBandDrops() {
        var d = pressed()
        _ = d.dragged(to: CGPoint(x: 300, y: 400))
        #expect(d.dragged(to: CGPoint(x: 600, y: 380)) == .moved)
        #expect(d.released(at: CGPoint(x: 600, y: 380), inBand: false) == .drop)
    }

    @Test func movedReleaseWithoutDragEventsIsADrag() {
        var out = pressed()
        #expect(out.released(at: CGPoint(x: 600, y: 400), inBand: false) == .drop)
        var inside = pressed()
        #expect(inside.released(at: CGPoint(x: 80, y: 420), inBand: true) == .cancel)
    }

    @Test func escapeCancelsADragAndSilencesTheRestOfThePress() {
        var d = pressed()
        _ = d.dragged(to: CGPoint(x: 300, y: 400))
        #expect(d.escape() == .cancel)
        #expect(!d.isDragging)
        #expect(d.dragged(to: CGPoint(x: 400, y: 400)) == .none)
        #expect(d.released(at: CGPoint(x: 600, y: 400), inBand: false) == .none)
        #expect(d.escape() == .none)
    }

    @Test func escapeBeforeADragDoesNothing() {
        var d = pressed()
        #expect(d.escape() == .none)
        #expect(d.released(at: p, inBand: true) == .click)
    }

    @Test func resetForgetsThePress() {
        var d = pressed()
        _ = d.dragged(to: CGPoint(x: 300, y: 400))
        d.reset()
        #expect(!d.isDragging)
        #expect(d.released(at: CGPoint(x: 600, y: 400), inBand: false) == .none)
    }

    @Test func idleEventsDoNothing() {
        var d = StripDrag()
        #expect(d.dragged(to: p) == .none)
        #expect(d.released(at: p, inBand: false) == .none)
        #expect(d.escape() == .none)
    }
}
