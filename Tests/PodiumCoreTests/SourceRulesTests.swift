import Foundation
import Testing

/// Repo rules a change that compiles can still break. Each failure names what to use instead.

private let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources")

private func swiftFiles() -> [URL] {
    let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
}

/// NSLog from Podium never reaches the unified log (`log show` finds none of its lines), so
/// every fallback and error message written with it is lost.
@Test func noNSLog() throws {
    var hits: [String] = []
    for file in swiftFiles() {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("NSLog(") {
            hits.append("\(file.lastPathComponent):\(i + 1)")
        }
    }
    #expect(hits.isEmpty, "NSLog never reaches the unified log; use podiumLog(...) (Sources/Podium/System/PodiumLog.swift) or a Logger: \(hits.joined(separator: ", "))")
}
