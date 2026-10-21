import Foundation
import CoreGraphics

/// A window that has been parked off-screen, with the frame it must be restored to.
public struct ParkedEntry: Codable, Equatable, Sendable {
    public let window: WindowRef
    public let bundleID: String?
    public let originalFrame: CGRect
    public let displayID: UInt32

    public init(window: WindowRef, bundleID: String?, originalFrame: CGRect, displayID: UInt32) {
        self.window = window
        self.bundleID = bundleID
        self.originalFrame = originalFrame
        self.displayID = displayID
    }
}

public enum ParkingLedgerError: Error, Equatable {
    /// An unrecognized ledger file could not be set aside; writing would destroy it.
    case unrecognizedFileInTheWay
}

/// Crash-safe record of every parked window's true original frame.
///
/// The whole file is rewritten atomically on every change. In-memory state only
/// changes after the write succeeded, so memory never claims more than disk.
public final class ParkingLedger: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var stored: [ParkedEntry]
    private var fileInTheWay = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let loaded = Self.load(from: fileURL)
        self.stored = loaded.entries
        self.fileInTheWay = loaded.fileInTheWay
    }

    public func entries() -> [ParkedEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// Records a parked window. If the window is already present the existing
    /// entry is kept: its frame is the true original, never a parked one.
    public func record(_ e: ParkedEntry) throws {
        lock.lock(); defer { lock.unlock() }
        if fileInTheWay { throw ParkingLedgerError.unrecognizedFileInTheWay }
        guard !stored.contains(where: { $0.window == e.window }) else { return }
        try persist(stored + [e])
    }

    public func remove(_ w: WindowRef) throws {
        lock.lock(); defer { lock.unlock() }
        if fileInTheWay { throw ParkingLedgerError.unrecognizedFileInTheWay }
        guard stored.contains(where: { $0.window == w }) else { return }
        try persist(stored.filter { $0.window != w })
    }

    private func persist(_ new: [ParkedEntry]) throws {
        let data = try JSONEncoder().encode(new)
        try data.write(to: fileURL, options: .atomic)
        stored = new
    }

    private static func load(from url: URL) -> (entries: [ParkedEntry], fileInTheWay: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return ([], false) }
        let data: Data
        do {
            data = try readWithOneRetry(url)
        } catch {
            return ([], !setAside(url, label: "unreadable"))
        }
        do {
            return (try JSONDecoder().decode([ParkedEntry].self, from: data), false)
        } catch {
            return ([], !setAside(url, label: "corrupt"))
        }
    }

    private static func readWithOneRetry(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch {
            if !FileManager.default.fileExists(atPath: url.path) { throw error }
            return try Data(contentsOf: url)
        }
    }

    /// Moves the file to a unique name; returns whether it succeeded.
    private static func setAside(_ url: URL, label: String) -> Bool {
        let name = "\(url.lastPathComponent).\(label)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
        let aside = url.deletingLastPathComponent().appendingPathComponent(name)
        do { try FileManager.default.moveItem(at: url, to: aside); return true } catch { return false }
    }
}
