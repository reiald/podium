import CoreGraphics
import Foundation
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

@Suite struct WallpaperPendingTests {
    @Test func pressIsPendingOnlyWithinHoldTime() {
        var press = WallpaperPress()
        press.began(at: .zero, time: 10, modifiers: [])
        #expect(press.isPending(at: 10.2))
        #expect(!press.isPending(at: 10.5))
        #expect(press.isPending)  // its mouse-up still ends it
    }
}

@Suite struct PopUpTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let podium: Int32 = 99

    private func window(_ bundleID: String?, layer: Int, pid: Int32 = 5,
                        bounds: CGRect = CGRect(x: 600, y: 30, width: 300, height: 400), alpha: Double = 1) -> ScreenWindow {
        ScreenWindow(pid: pid, bundleID: bundleID, layer: layer, bounds: bounds, alpha: alpha)
    }

    private func blocks(_ windows: [ScreenWindow]) -> Bool {
        popUpBlocksWallpaperClick(windows, display: display, podiumPid: podium)
    }

    @Test func notificationControlCenterAndSpotlightPanelsBlock() {
        #expect(blocks([window("com.apple.notificationcenterui", layer: 23)]))
        #expect(blocks([window("com.apple.controlcenter", layer: 101)]))
        #expect(blocks([window("com.apple.Spotlight", layer: 0)]))
    }

    @Test func desktopWidgetsAndStatusItemsDoNot() {
        #expect(!blocks([window("com.apple.notificationcenterui", layer: -2147483601)]))
        #expect(!blocks([window("com.apple.controlcenter", layer: 25)]))
    }

    @Test func otherAppsFloatingPopUpBlocks() {
        #expect(blocks([window("com.example.app", layer: 3)]))
        #expect(blocks([window(nil, layer: 19)]))
    }

    @Test func normalWindowsDockMenuBarDesktopAndPodiumDoNot() {
        let full = display
        #expect(!blocks([
            window("com.example.app", layer: 0),
            window("com.apple.dock", layer: 20, bounds: full),
            window(nil, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1000, height: 30)),
            window("com.apple.finder", layer: -2147483603, bounds: full),
            window("dev.podium.Podium", layer: 3, pid: podium, bounds: full),
        ]))
    }

    @Test func invisibleOrOtherDisplayWindowsDoNot() {
        #expect(!blocks([window("com.example.app", layer: 3, alpha: 0)]))
        #expect(!blocks([window("com.apple.Spotlight", layer: 8, bounds: CGRect(x: 1200, y: 0, width: 300, height: 300))]))
    }
}

@Suite struct WallpaperVerdictsTests {
    let a = UUID()
    let b = UUID()

    @Test func latestVerdictWithSameStageShowsDesktop() {
        var v = WallpaperVerdicts()
        let press = v.pressEnded(activeStageID: a)
        #expect(v.isWaiting)
        #expect(v.verdict(press, isWallpaper: true, activeStageID: a, now: 1) == .showDesktop)
        #expect(!v.isWaiting)
    }

    @Test func noWallpaperDoesNothing() {
        var v = WallpaperVerdicts()
        let press = v.pressEnded(activeStageID: a)
        #expect(v.verdict(press, isWallpaper: false, activeStageID: a, now: 1) == .none)
    }

    @Test func verdictAfterTheStageChangedIsDropped() {
        var v = WallpaperVerdicts()
        let press = v.pressEnded(activeStageID: a)
        #expect(v.verdict(press, isWallpaper: true, activeStageID: b, now: 1) == .none)
        var gone = WallpaperVerdicts()
        let p2 = gone.pressEnded(activeStageID: a)
        #expect(gone.verdict(p2, isWallpaper: true, activeStageID: nil, now: 1) == .none)
    }

    @Test func verdictOfASupersededPressIsDropped() {
        // Wallpaper click, then a click on a window before the first verdict is back.
        var v = WallpaperVerdicts()
        let first = v.pressEnded(activeStageID: a)
        let second = v.pressEnded(activeStageID: a)
        #expect(v.verdict(first, isWallpaper: true, activeStageID: a, now: 1) == .none)
        #expect(v.verdict(second, isWallpaper: false, activeStageID: a, now: 1) == .none)
        var w = WallpaperVerdicts()
        let p = w.pressEnded(activeStageID: a)
        _ = w.pressDiscarded()
        #expect(w.verdict(p, isWallpaper: true, activeStageID: a, now: 1) == .none)
    }

    @Test func heldActivationWaitsForEveryPress() {
        var v = WallpaperVerdicts()
        let first = v.pressEnded(activeStageID: a)
        v.hold(7)
        let second = v.pressEnded(activeStageID: a)
        // The second press's verdict comes first: the first still waits, so it stays held.
        #expect(v.verdict(second, isWallpaper: false, activeStageID: a, now: 1) == .none)
        #expect(v.held == 7)
        #expect(v.verdict(first, isWallpaper: true, activeStageID: a, now: 1) == .release(7))
        #expect(v.held == nil)
    }

    @Test func wallpaperVerdictDropsHeldActivation() {
        var v = WallpaperVerdicts()
        let press = v.pressEnded(activeStageID: a)
        v.hold(7)
        #expect(v.verdict(press, isWallpaper: true, activeStageID: a, now: 1) == .showDesktop)
        #expect(v.held == nil)
    }

    @Test func discardedPressReleasesHeldActivation() {
        var v = WallpaperVerdicts()
        v.hold(7)
        #expect(v.pressDiscarded() == .release(7))
        #expect(v.pressDiscarded() == .none)
    }

    @Test func lateFinderActivationIgnoredBriefly() {
        var v = WallpaperVerdicts()
        #expect(!v.ignoresFinderActivation(at: 1))
        let press = v.pressEnded(activeStageID: a)
        _ = v.verdict(press, isWallpaper: true, activeStageID: a, now: 1)
        #expect(v.ignoresFinderActivation(at: 1.2))
        #expect(!v.ignoresFinderActivation(at: 1.31))
    }

    @Test func resetDropsHeldAndWaiting() {
        var v = WallpaperVerdicts()
        let press = v.pressEnded(activeStageID: a)
        v.hold(7)
        v.reset()
        #expect(v.held == nil)
        #expect(!v.isWaiting)
        #expect(v.verdict(press, isWallpaper: true, activeStageID: a, now: 1) == .none)
    }
}
