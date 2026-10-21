import Testing
import Foundation
import CoreGraphics
@testable import PodiumCore

private func w(_ pid: Int32, _ id: UInt32) -> WindowRef { WindowRef(pid: pid, windowID: id) }

private func entry(_ pid: Int32, _ id: UInt32, frame: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200)) -> ParkedEntry {
    ParkedEntry(window: w(pid, id), bundleID: "com.example.app", originalFrame: frame, displayID: 1)
}

private func withTempDir(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

@Test func recordPersistsAcrossInstances() throws {
    try withTempDir { dir in
        let url = dir.appendingPathComponent("parked.json")
        let e = entry(1, 10)
        try ParkingLedger(fileURL: url).record(e)
        #expect(ParkingLedger(fileURL: url).entries() == [e])
    }
}

@Test func removeDeletesOnlyThatWindow() throws {
    try withTempDir { dir in
        let url = dir.appendingPathComponent("parked.json")
        let ledger = ParkingLedger(fileURL: url)
        try ledger.record(entry(1, 10))
        try ledger.record(entry(1, 11))
        try ledger.remove(w(1, 10))
        #expect(ledger.entries() == [entry(1, 11)])
        #expect(ParkingLedger(fileURL: url).entries() == [entry(1, 11)])
        try ledger.remove(w(9, 9))
        #expect(ledger.entries().count == 1)
    }
}

@Test func recordingSameWindowTwiceKeepsFirstFrame() throws {
    try withTempDir { dir in
        let url = dir.appendingPathComponent("parked.json")
        let ledger = ParkingLedger(fileURL: url)
        let first = entry(1, 10)
        let parked = entry(1, 10, frame: CGRect(x: 5000, y: 5000, width: 300, height: 200))
        try ledger.record(first)
        try ledger.record(parked)
        #expect(ledger.entries() == [first])
        #expect(ParkingLedger(fileURL: url).entries() == [first])
    }
}

@Test func corruptFileIsSetAsideNotFatal() throws {
    try withTempDir { dir in
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("parked.json")
        try Data("garbage".utf8).write(to: url)
        let ledger = ParkingLedger(fileURL: url)
        #expect(ledger.entries().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("parked.json.corrupt-") })
        // Ledger is usable afterwards.
        try ledger.record(entry(1, 10))
        #expect(ParkingLedger(fileURL: url).entries() == [entry(1, 10)])
    }
}

@Test func missingFileAndMissingDirectoryGiveEmptyLedger() throws {
    try withTempDir { dir in
        let url = dir.appendingPathComponent("nested/parked.json")
        let ledger = ParkingLedger(fileURL: url)
        #expect(ledger.entries().isEmpty)
        try ledger.record(entry(1, 10))
        #expect(ParkingLedger(fileURL: url).entries().count == 1)
    }
}

@Test func writeFailureThrowsAndDoesNotChangeEntries() throws {
    try withTempDir { dir in
        let url = dir.appendingPathComponent("parked.json")
        let ledger = ParkingLedger(fileURL: url)
        try ledger.record(entry(1, 10))
        // Replace the file with a directory so atomic writes fail.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("x"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try ledger.record(entry(1, 11)) }
        #expect(ledger.entries() == [entry(1, 10)])
    }
}

@Test func corruptFileBytesArePreservedInSetAsideFile() throws {
    try withTempDir { dir in
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("parked.json")
        let bytes = Data("not json \u{1}\u{2}".utf8)
        try bytes.write(to: url)
        _ = ParkingLedger(fileURL: url)
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .first { $0.hasPrefix("parked.json.corrupt-") }
        #expect(aside != nil)
        #expect(try Data(contentsOf: dir.appendingPathComponent(aside!)) == bytes)
    }
}

@Test func unreadableFileIsSetAsideAsUnreadable() throws {
    try withTempDir { dir in
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("parked.json")
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let ledger = ParkingLedger(fileURL: url)
        #expect(ledger.entries().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("parked.json.unreadable-") })
        #expect(!names.contains { $0.hasPrefix("parked.json.corrupt-") })
    }
}

@Test func failedSetAsideBlocksWritesInsteadOfOverwriting() throws {
    try withTempDir { dir in
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("parked.json")
        let bytes = Data("garbage".utf8)
        try bytes.write(to: url)
        // A read-only directory makes the rename fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let ledger = ParkingLedger(fileURL: url)
        #expect(ledger.entries().isEmpty)
        #expect(throws: ParkingLedgerError.unrecognizedFileInTheWay) { try ledger.record(entry(1, 10)) }
        #expect(throws: ParkingLedgerError.unrecognizedFileInTheWay) { try ledger.remove(w(1, 10)) }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
