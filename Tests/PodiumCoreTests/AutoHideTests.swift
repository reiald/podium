import CoreGraphics
import Foundation
import Testing
@testable import PodiumCore

@Suite struct AutoHideTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let band = CGRect(x: 800, y: 0, width: 200, height: 800)
    let outside = CGPoint(x: 300, y: 400)
    let tuning = Tuning.initial

    @Test func hidesAfterDelayWhenOverlapped() {
        var h = AutoHide(tuning: tuning)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0)
        #expect(!h.isHidden)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: tuning.autoHideDelay)
        #expect(h.isHidden)
    }

    @Test func doesNotHideBeforeDelay() {
        var h = AutoHide(tuning: tuning)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0.1)
        #expect(!h.isHidden)
    }

    @Test func doesNotHideWhileOverlapBelowThreshold() {
        var h = AutoHide(tuning: tuning)
        h.update(overlapFraction: 0.15, pointer: outside, band: band, screen: screen, side: .right, now: 0)
        h.update(overlapFraction: 0.15, pointer: outside, band: band, screen: screen, side: .right, now: 5)
        #expect(!h.isHidden)
    }

    @Test func neverHidesWhilePointerInBand() {
        var h = AutoHide(tuning: tuning)
        let inBand = CGPoint(x: 900, y: 400)
        for t in stride(from: 0.0, through: 5.0, by: 0.5) {
            h.update(overlapFraction: 0.9, pointer: inBand, band: band, screen: screen, side: .right, now: t)
            #expect(!h.isHidden)
        }
    }

    @Test func reenteringBandResetsTimer() {
        var h = AutoHide(tuning: tuning)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 900, y: 10), band: band, screen: screen, side: .right, now: 0.2)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0.3)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0.3 + tuning.autoHideDelay * 0.8)
        #expect(!h.isHidden)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 0.3 + tuning.autoHideDelay + 0.01)
        #expect(h.isHidden)
    }

    @Test func revealsAtStripEdgeOnly() {
        var h = hidden(side: .right)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 0, y: 400), band: band, screen: screen, side: .right, now: 10)
        #expect(h.isHidden)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 1000 - tuning.hiddenPeekWidth - 1, y: 400), band: band, screen: screen, side: .right, now: 10.1)
        #expect(h.isHidden)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 1000 - tuning.hiddenPeekWidth, y: 400), band: band, screen: screen, side: .right, now: 10.2)
        #expect(!h.isHidden)
    }

    @Test func leftSideRevealsAtLeftEdge() {
        let leftBand = CGRect(x: 0, y: 0, width: 200, height: 800)
        var h = hidden(side: .left, band: leftBand)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 999, y: 400), band: leftBand, screen: screen, side: .left, now: 10)
        #expect(h.isHidden)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: tuning.hiddenPeekWidth, y: 400), band: leftBand, screen: screen, side: .left, now: 10.1)
        #expect(!h.isHidden)
    }

    @Test func staysShownAfterRevealUntilDelayElapsesAgain() {
        var h = hidden(side: .right)
        h.update(overlapFraction: 0.5, pointer: CGPoint(x: 999, y: 400), band: band, screen: screen, side: .right, now: 10)
        #expect(!h.isHidden)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 10.1)
        #expect(!h.isHidden)
        h.update(overlapFraction: 0.5, pointer: outside, band: band, screen: screen, side: .right, now: 10.1 + tuning.autoHideDelay)
        #expect(h.isHidden)
    }

    private func hidden(side: StripSide, band b: CGRect? = nil) -> AutoHide {
        var h = AutoHide(tuning: tuning)
        let bb = b ?? band
        h.update(overlapFraction: 0.5, pointer: outside, band: bb, screen: screen, side: side, now: 0)
        h.update(overlapFraction: 0.5, pointer: outside, band: bb, screen: screen, side: side, now: 1)
        precondition(h.isHidden)
        return h
    }
}
