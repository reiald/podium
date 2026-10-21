import Testing
import CoreGraphics
import Foundation
@testable import PodiumCore

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
private let t = Tuning.initial

private func stages(_ n: Int) -> [Stage] {
    (0..<n).map { Stage(id: UUID(), windows: [WindowRef(pid: Int32($0 + 1), windowID: UInt32($0 + 1))]) }
}

@Test func rightSideSlotsHugRightEdge() {
    let slots = stripSlots(for: stages(4), in: screen, side: .right, tuning: t)
    #expect(slots.count == 4)
    for s in slots { #expect(s.frame.maxX == screen.maxX - t.stripEdgeInset) }
}

@Test func leftSideSlotsHugLeftEdge() {
    let slots = stripSlots(for: stages(4), in: screen, side: .left, tuning: t)
    for s in slots { #expect(s.frame.minX == screen.minX + t.stripEdgeInset) }
}

@Test func sidesMirrorEachOther() {
    let st = stages(5)
    let l = stripSlots(for: st, in: screen, side: .left, tuning: t)
    let r = stripSlots(for: st, in: screen, side: .right, tuning: t)
    #expect(l.count == r.count)
    for (a, b) in zip(l, r) {
        #expect(a.stageID == b.stageID)
        #expect(a.frame.minX - screen.minX == screen.maxX - b.frame.maxX)
        #expect(a.frame.minY == b.frame.minY)
        #expect(a.frame.size == b.frame.size)
        #expect(a.tiltRadians == -b.tiltRadians)
        #expect(a.tiltRadians == t.tiltRadians)
    }
}

@Test func slotsAreVerticallyCenteredAndSpaced() {
    let slots = stripSlots(for: stages(3), in: screen, side: .right, tuning: t)
    let union = slots.dropFirst().reduce(slots[0].frame) { $0.union($1.frame) }
    #expect(abs(union.midY - screen.midY) < 0.001)
    for (a, b) in zip(slots, slots.dropFirst()) {
        #expect(abs(b.frame.minY - a.frame.maxY - t.rowSpacing) < 0.001)
    }
    #expect(slots[0].frame.size == t.itemMaxSize)
}

@Test func atMostMaxRowCountSlots() {
    let st = stages(9)
    let slots = stripSlots(for: st, in: screen, side: .right, tuning: t)
    #expect(slots.count == 6)
    #expect(slots.map(\.stageID) == st.prefix(6).map(\.id))
}

@Test func pileCapsAtThreeAndMirrors() {
    let r = pileOffsets(windowCount: 5, side: .right, tuning: t)
    let l = pileOffsets(windowCount: 5, side: .left, tuning: t)
    #expect(r.count == 3)
    #expect(l.count == 3)
    #expect(r[0].offset == .zero && r[0].scale == 1)
    for (a, b) in zip(l, r) {
        #expect(a.offset.width == -b.offset.width)
        #expect(a.offset.height == b.offset.height)
        #expect(a.scale == b.scale)
    }
    #expect(pileOffsets(windowCount: 0, side: .left, tuning: t).isEmpty)
    #expect(pileOffsets(windowCount: 2, side: .left, tuning: t).count == 2)
}

@Test func stageAreaExcludesStripBand() {
    for side in StripSide.allCases {
        let band = stripBand(in: screen, side: side, tuning: t)
        let area = stageArea(in: screen, side: side, tuning: t)
        #expect(!area.intersects(band))
        #expect(screen.contains(band) && screen.contains(area))
    }
}

@Test func parkingLeavesOnePointOnScreen() {
    let size = CGSize(width: 800, height: 600)
    let origin = parkingOrigin(for: size, display: screen)
    let visible = CGRect(origin: origin, size: size).intersection(screen)
    #expect(visible.width == 1 && visible.height == 1)
}
