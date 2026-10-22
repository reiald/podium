import Testing
@testable import PodiumCore

private final class FakePrefs: StageManagerPreferences, @unchecked Sendable {
    var value: Bool?
    var reads: [String] = []

    init(_ value: Bool?) { self.value = value }
    func bool(forKey key: String) -> Bool? {
        reads.append(key)
        return key == "GloballyEnabled" ? value : nil
    }
}

@Suite struct StageManagerSwitchTests {
    @Test func missingKeyReadsAsOff() {
        #expect(!StageManagerSwitch(prefs: FakePrefs(nil)).isEnabled)
    }

    @Test func readsTheStoredValue() {
        #expect(StageManagerSwitch(prefs: FakePrefs(true)).isEnabled)
        #expect(!StageManagerSwitch(prefs: FakePrefs(false)).isEnabled)
    }

    @Test func readsTheGloballyEnabledKeyEveryTime() {
        let p = FakePrefs(true)
        let s = StageManagerSwitch(prefs: p)
        #expect(s.isEnabled)
        p.value = false
        #expect(!s.isEnabled)
        #expect(p.reads == ["GloballyEnabled", "GloballyEnabled"])
    }
}
