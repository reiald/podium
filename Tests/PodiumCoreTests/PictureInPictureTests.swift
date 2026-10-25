import Testing
@testable import PodiumCore

// A picture-in-picture window floats above everything by design. If Podium managed it, switching
// stages would park it or show it as a strip item.

@Test func picInPicTitlesAreRecognised() {
    #expect(isPictureInPictureTitle("Picture in Picture"))
    #expect(isPictureInPictureTitle("Picture-in-Picture"))
    #expect(isPictureInPictureTitle("picture in picture - YouTube"))
    #expect(!isPictureInPictureTitle("Holiday pictures"))
    #expect(!isPictureInPictureTitle(""))
    #expect(!isPictureInPictureTitle(nil))
}

@Test func aPicInPicWindowIsNotManaged() {
    func manageable(title: String?, level: Int = 0) -> Bool {
        isManageable(role: "AXWindow", subrole: "AXStandardWindow", isFullscreen: false, isMinimized: false,
                     title: title, level: level)
    }
    #expect(manageable(title: "Notes"))
    #expect(manageable(title: nil))
    #expect(!manageable(title: "Picture in Picture"))
    #expect(!manageable(title: "Picture-in-Picture"))
}

@Test func aWindowAboveTheNormalLevelIsNotManaged() {
    // Always-on-top windows (a PiP video that reports a standard subrole) stay where they are.
    func manageable(level: Int) -> Bool {
        isManageable(role: "AXWindow", subrole: "AXStandardWindow", isFullscreen: false, isMinimized: false,
                     title: "Video", level: level)
    }
    #expect(manageable(level: 0))
    #expect(!manageable(level: 3))
    #expect(!manageable(level: 8))
}
