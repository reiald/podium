// Usage: swift scripts/check-onscreen.swift <bundleID> [--min N]
// Exits 1 if any on-screen layer-0 window of the app is not fully inside a screen,
// or if fewer than N such windows exist. Exits 2 on bad usage or if the app isn't running.
import AppKit
import CoreGraphics

var args = Array(CommandLine.arguments.dropFirst())
var minimum = 0
if let i = args.firstIndex(of: "--min"), i + 1 < args.count, let n = Int(args[i + 1]) {
    minimum = n
    args.removeSubrange(i...(i + 1))
}
guard args.count == 1 else {
    FileHandle.standardError.write("usage: check-onscreen.swift <bundleID> [--min N]\n".data(using: .utf8)!)
    exit(2)
}
let bundleID = args[0]

let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
guard !pids.isEmpty else {
    print("\(bundleID) is not running")
    exit(2)
}

// NSScreen frames are bottom-left origin; CGWindowList bounds are top-left global.
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let screens = NSScreen.screens.map { s in
    CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
}

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var count = 0
var bad = 0
for w in info {
    guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
          (w[kCGWindowLayer as String] as? Int) == 0,
          let dict = w[kCGWindowBounds as String] as CFTypeRef?,
          let bounds = CGRect(dictionaryRepresentation: dict as! CFDictionary) else { continue }
    count += 1
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let inside = screens.contains { $0.contains(bounds) }
    if !inside { bad += 1 }
    print("\(inside ? "ok " : "OFF") window \(id) \(bounds)")
}
print("\(bundleID): \(count) window(s), \(bad) not fully on screen")
if bad > 0 || count < minimum { exit(1) }
