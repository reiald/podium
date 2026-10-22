import CoreGraphics
import Testing
@testable import PodiumCore

@Suite struct WallpaperPressTests {
    let p = CGPoint(x: 400, y: 600)

    private func pressed(modifiers: ModifierSet = []) -> WallpaperPress {
        var press = WallpaperPress()
        press.began(at: p, time: 10, modifiers: modifiers)
        return press
    }

    @Test func quickClickCounts() {
        var press = pressed()
        #expect(press.isPending)
        #expect(press.released(at: p, time: 10.1) == true)
        #expect(!press.isPending)
    }

    @Test func jitterWithinThresholdStillCounts() {
        var press = pressed()
        #expect(press.released(at: CGPoint(x: 403, y: 602), time: 10.1) == true)
    }

    @Test func dragOrRubberBandDoesNot() {
        var press = pressed()
        #expect(press.released(at: CGPoint(x: 420, y: 600), time: 10.1) == false)
    }

    @Test func pressAndHoldDoesNot() {
        var press = pressed()
        #expect(press.released(at: p, time: 10.5) == false)
    }

    @Test func modifiersDoNot() {
        for m: ModifierSet in [.command, .shift, .option, .control] {
            var press = pressed(modifiers: m)
            #expect(!press.isPending)
            #expect(press.released(at: p, time: 10.1) == false)
        }
    }

    @Test func clickWhileMenuOpenDoesNot() {
        var press = WallpaperPress()
        press.menuTracking(true, time: 9)
        press.began(at: p, time: 10, modifiers: [])
        #expect(press.released(at: p, time: 10.1) == false)
    }

    @Test func clickThatClosedAMenuDoesNot() {
        var press = WallpaperPress()
        press.menuTracking(true, time: 9)
        press.began(at: p, time: 10, modifiers: [])
        press.menuTracking(false, time: 10.01)  // the click closed it
        #expect(press.released(at: p, time: 10.1) == false)
        // Heard just before the press's own time stamp: still the same click.
        press.menuTracking(true, time: 11)
        press.menuTracking(false, time: 11.95)
        press.began(at: p, time: 12, modifiers: [])
        #expect(press.released(at: p, time: 12.1) == false)
    }

    @Test func clickWellAfterAMenuClosedCounts() {
        var press = WallpaperPress()
        press.menuTracking(true, time: 9)
        press.menuTracking(false, time: 9.5)
        press.began(at: p, time: 10, modifiers: [])
        #expect(press.released(at: p, time: 10.1) == true)
    }

    @Test func releaseWithoutPressDoesNot() {
        var press = WallpaperPress()
        #expect(press.released(at: p, time: 1) == false)
    }

    @Test func eachPressIsDecidedOnce() {
        var press = pressed()
        #expect(press.released(at: p, time: 10.1) == true)
        #expect(press.released(at: p, time: 10.2) == false)
    }

    @Test func ineligiblePressForgetsEarlierOne() {
        var press = pressed()
        press.began(at: p, time: 11, modifiers: .command)
        #expect(press.released(at: p, time: 11.1) == false)
    }
}

@Suite struct EmptyWallpaperTests {
    @Test func desktopGroupAndScrollAreaAreWallpaper() {
        #expect(isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXGroup", windowRole: "AXScrollArea")))
        #expect(isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXScrollArea", windowRole: "AXScrollArea")))
    }

    @Test func desktopIconAndItsNameAreNot() {
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXImage", windowRole: "AXScrollArea")))
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXTextField", windowRole: "AXScrollArea")))
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXStaticText", windowRole: "AXScrollArea")))
    }

    @Test func finderWindowContentIsNot() {
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXGroup", windowRole: "AXWindow")))
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: "AXScrollArea", windowRole: nil)))
    }

    @Test func otherAppsAreNot() {
        // A desktop widget, another app's window, the Dock, a menu.
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: false, role: "AXGroup", windowRole: "AXScrollArea")))
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: false, role: "AXDockItem", windowRole: nil)))
    }

    @Test func failedHitTestIsNot() {
        #expect(!isEmptyWallpaper(nil))
        #expect(!isEmptyWallpaper(WallpaperHit(isFinder: true, role: nil, windowRole: nil)))
    }
}
