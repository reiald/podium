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

/// Crash-safe record of every parked window's true original frame.
///
/// The whole file is rewritten atomically on every change. In-memory state only
/// changes after the write succeeded, so memory never claims more than disk.
public final class ParkingLedger: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var stored: [ParkedEntry]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.stored = Self.load(from: fileURL)
    }

    public func entries() -> [ParkedEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// Records a parked window. If the window is already present the existing
    /// entry is kept: its frame is the true original, never a parked one.
    public func record(_ e: ParkedEntry) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stored.contains(where: { $0.window == e.window }) else { return }
        try persist(stored + [e])
    }

    public func remove(_ w: WindowRef) throws {
        lock.lock(); defer { lock.unlock() }
        guard stored.contains(where: { $0.window == w }) else { return }
        try persist(stored.filter { $0.window != w })
    }

    private func persist(_ new: [ParkedEntry]) throws {
        let data = try JSONEncoder().encode(new)
        try data.write(to: fileURL, options: .atomic)
        stored = new
    }

    private static func load(from url: URL) -> [ParkedEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ParkedEntry].self, from: data)
        } catch {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            return []
        }
    }
}
