import Testing
@testable import PodiumCore

private final class FakePrefs: StageManagerPreferences, @unchecked Sendable {
    var value: Bool?
    var writes: [Bool] = []
    var ignoreWrites = false
    var syncResult = true

    init(_ value: Bool?) { self.value = value }
    func bool(forKey key: String) -> Bool? { key == "GloballyEnabled" ? value : nil }
    func setBool(_ v: Bool, forKey key: String) {
        guard key == "GloballyEnabled" else { return }
        writes.append(v)
        if !ignoreWrites { value = v }
    }
    func synchronize() -> Bool { syncResult }
}

@Suite struct StageManagerSwitchTests {
    @Test func missingKeyReadsAsOff() {
        #expect(!StageManagerSwitch(prefs: FakePrefs(nil)).isEnabled)
    }

    @Test func readsTheStoredValue() {
        #expect(StageManagerSwitch(prefs: FakePrefs(true)).isEnabled)
        #expect(!StageManagerSwitch(prefs: FakePrefs(false)).isEnabled)
    }

    @Test func disableWritesFalseAndConfirms() {
        let p = FakePrefs(true)
        let s = StageManagerSwitch(prefs: p)
        #expect(s.disable())
        #expect(p.writes == [false])
        #expect(!s.isEnabled)
    }

    @Test func enableWritesTrueAndConfirms() {
        let p = FakePrefs(false)
        #expect(StageManagerSwitch(prefs: p).enable())
        #expect(p.value == true)
    }

    @Test func failedWriteReportsFailure() {
        let p = FakePrefs(true)
        p.ignoreWrites = true
        #expect(!StageManagerSwitch(prefs: p).disable())
        let q = FakePrefs(true)
        q.syncResult = false
        #expect(!StageManagerSwitch(prefs: q).disable())
    }
}
