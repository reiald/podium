import Testing
@testable import PodiumCore

@Test func floatingAppsStartWithTheViewers() {
    let d = FloatingApps.defaults
    #expect(d.enabled)
    #expect(d.bundleIDs == ["com.apple.archiveutility", "com.interversehq.qView", "com.apple.Preview"])
    #expect(d.floats("com.interversehq.qView"))
    #expect(!d.floats("com.apple.finder"))
    #expect(!d.floats(nil))
}

@Test func turnedOffNothingFloats() {
    var f = FloatingApps.defaults
    f.enabled = false
    #expect(!f.floats("com.apple.archiveutility"))
}

@Test func addingAndRemovingApps() {
    var f = FloatingApps.defaults
    f.add("com.example.Viewer")
    f.add("com.example.Viewer")                    // once
    #expect(f.bundleIDs.filter { $0 == "com.example.Viewer" }.count == 1)
    #expect(f.floats("com.example.Viewer"))
    f.remove("com.apple.Preview")
    #expect(!f.floats("com.apple.Preview"))
}
