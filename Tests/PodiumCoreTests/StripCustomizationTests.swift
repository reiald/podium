import Testing
import CoreGraphics
import Foundation
@testable import PodiumCore

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

@Test func customizationDefaultsReproduceInitialTuning() {
    let d = StripCustomization.defaults
    #expect(d.thumbnailWidth == 290)
    #expect(abs(d.tiltDegrees - 17.188733853924695) < 1e-9)
    #expect(d.showAppIcons)
    #expect(d.appIconSize == 40)
    #expect(d.applied(to: .initial) == Tuning.initial)
    #expect(d.clamped() == d)
}

@Test func customizationClampsToRanges() {
    let low = StripCustomization(thumbnailWidth: 10, tiltDegrees: -5, showAppIcons: false, appIconSize: 2).clamped()
    #expect(low == StripCustomization(thumbnailWidth: 100, tiltDegrees: 0, showAppIcons: false, appIconSize: 16))
    let high = StripCustomization(thumbnailWidth: 900, tiltDegrees: 90, showAppIcons: true, appIconSize: 200).clamped()
    #expect(high == StripCustomization(thumbnailWidth: 320, tiltDegrees: 30, showAppIcons: true, appIconSize: 48))
    let bad = StripCustomization(thumbnailWidth: .nan, tiltDegrees: .infinity, showAppIcons: true, appIconSize: -.infinity).clamped()
    #expect(bad == .defaults)
}

@Test func customizationWidthKeepsAspect() {
    let t = StripCustomization(thumbnailWidth: 240, tiltDegrees: 10, showAppIcons: true, appIconSize: 28).applied(to: .initial)
    #expect(t.itemMaxSize.width == 240)
    #expect(abs(t.itemMaxSize.height - 240 * 160 / 290) < 1e-9)
}

@Test func customizationTiltIsDegrees() {
    let t = StripCustomization(thumbnailWidth: 160, tiltDegrees: 30, showAppIcons: true, appIconSize: 28).applied(to: .initial)
    #expect(abs(t.tiltRadians - .pi / 6) < 1e-12)
    let flat = StripCustomization(thumbnailWidth: 160, tiltDegrees: 0, showAppIcons: true, appIconSize: 28).applied(to: .initial)
    #expect(flat.tiltRadians == 0)
}

@Test func customizationAppliedClampsAndKeepsOtherConstants() {
    let t = StripCustomization(thumbnailWidth: 1000, tiltDegrees: 45, showAppIcons: false, appIconSize: 40).applied(to: .initial)
    #expect(t.itemMaxSize.width == StripCustomization.thumbnailWidthRange.upperBound)
    #expect(t.appIconSize == 40)
    var rest = t
    rest.itemMaxSize = Tuning.initial.itemMaxSize
    rest.tiltRadians = Tuning.initial.tiltRadians
    rest.appIconSize = Tuning.initial.appIconSize
    #expect(rest == Tuning.initial)
}

@Test func customizationBandFollowsWidth() {
    let t = StripCustomization(thumbnailWidth: 220, tiltDegrees: 17, showAppIcons: true, appIconSize: 28).applied(to: .initial)
    for side in StripSide.allCases {
        let band = stripBand(in: screen, side: side, tuning: t)
        #expect(band.width == t.stripEdgeInset + 220 + t.stripEdgeInset)
        let area = stageArea(in: screen, side: side, tuning: t)
        #expect(!area.intersects(band))
        let slots = stripSlots(for: [Stage(id: UUID(), windows: [WindowRef(pid: 1, windowID: 1)])],
                               in: screen, side: side, tuning: t)
        #expect(band.contains(slots[0].frame))
    }
}
