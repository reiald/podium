import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import PodiumCore
import ScreenCaptureKit
import VideoToolbox
// Carbon (via ScreenCaptureKit's AppKit imports) also declares `WindowRef`.
import struct PodiumCore.WindowRef

/// A running live capture, returned by `Capture.startLive`.
struct LiveHandle: Hashable, Sendable {
    fileprivate let id = UUID()
}

enum CaptureError: Error, CustomStringConvertible {
    case permissionMissing
    case windowNotShareable(WindowRef)
    case noImage(WindowRef)

    var description: String {
        switch self {
        case .permissionMissing: return "Screen Recording permission missing"
        case let .windowNotShareable(w): return "window \(w.windowID) (pid \(w.pid)) not shareable"
        case let .noImage(w): return "no image for window \(w.windowID) (pid \(w.pid))"
        }
    }
}

/// Window snapshots and live thumbnails over ScreenCaptureKit.
///
/// Transitions animate snapshots, so they must never wait on a capture: the owner keeps
/// on-stage windows' snapshots fresh with `refreshOnStage` (once per second and right
/// before a transition), and the transition reads `cachedSnapshot`.
///
/// Failures (permission missing, window gone) are logged once per window and surface as
/// a thrown error or nil; they never crash.
actor Capture {
    static let defaultFPS = 5
    static let defaultMaxPixelSize = CGSize(width: 320, height: 320)

    /// When false, `startLive` on a parked window delivers the cached snapshot once and
    /// stops, for when parked (off-screen) windows don't produce live frames.
    var liveCapturesParkedWindows = true

    private let isParked: @MainActor @Sendable (WindowRef) -> Bool
    private var snapshots: [WindowRef: CGImage] = [:]
    private var refreshing: Set<WindowRef> = []
    private var live: [LiveHandle: LiveSession] = [:]
    private var loggedFailures: Set<WindowRef> = []
    private var loggedPermission = false

    /// Parked windows sit off screen, so the list includes off-screen windows. It is
    /// cached briefly so a burst of captures shares one query.
    private var windowList: (fetched: Date, byID: [CGWindowID: SCWindow])?
    private static let windowListMaxAge: TimeInterval = 1

    init(isParked: @escaping @MainActor @Sendable (WindowRef) -> Bool) {
        self.isParked = isParked
    }

    func setLiveCapturesParkedWindows(_ value: Bool) {
        liveCapturesParkedWindows = value
    }

    // MARK: - Snapshots

    /// Captures `w` at `pointSize` (in points; scaled to the window's backing pixels) and
    /// caches the result.
    func snapshot(_ w: WindowRef, pointSize: CGSize) async throws -> CGImage {
        do {
            let window = try await shareableWindow(w)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = max(1, Int((pointSize.width * scale).rounded()))
            config.height = max(1, Int((pointSize.height * scale).rounded()))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            snapshots[w] = image
            loggedFailures.remove(w)
            return image
        } catch {
            logFailure(w, "snapshot", error)
            throw error
        }
    }

    func cachedSnapshot(_ w: WindowRef) -> CGImage? {
        snapshots[w]
    }

    /// Re-captures each window at its current size. Windows already being refreshed are
    /// skipped; failures are logged (once) and leave the previous snapshot in place.
    func refreshOnStage(_ windows: [WindowRef]) async {
        let todo = windows.filter { !refreshing.contains($0) }
        guard !todo.isEmpty else { return }
        refreshing.formUnion(todo)
        defer { refreshing.subtract(todo) }
        for w in todo {
            guard let size = try? await shareableWindow(w).frame.size, size.width > 0, size.height > 0 else {
                continue
            }
            _ = try? await snapshot(w, pointSize: size)
        }
    }

    /// Drops a closed window's cached snapshot.
    func forget(_ w: WindowRef) {
        snapshots[w] = nil
        loggedFailures.remove(w)
    }

    // MARK: - Live thumbnails

    /// Streams `w` at up to `fps`, scaled to fit `maxPixelSize`, calling `onFrame` on the
    /// main queue for each new frame.
    func startLive(
        _ w: WindowRef,
        maxPixelSize: CGSize = Capture.defaultMaxPixelSize,
        fps: Int = Capture.defaultFPS,
        onFrame: @escaping @Sendable (CGImage) -> Void
    ) async throws -> LiveHandle {
        let handle = LiveHandle()
        if !liveCapturesParkedWindows, await isParked(w) {
            // Fallback: the strip shows the last snapshot taken while it was on stage.
            if let image = snapshots[w] {
                DispatchQueue.main.async { onFrame(image) }
            } else {
                logFailure(w, "live (parked fallback)", CaptureError.noImage(w))
            }
            return handle
        }
        do {
            let window = try await shareableWindow(w)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let pixels = Self.fit(CGSize(width: window.frame.width * scale, height: window.frame.height * scale),
                                  within: maxPixelSize)
            let config = SCStreamConfiguration()
            config.width = Int(pixels.width)
            config.height = Int(pixels.height)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 3
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true

            let session = LiveSession(window: w, onFrame: onFrame)
            let stream = SCStream(filter: filter, configuration: config, delegate: session)
            try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.queue)
            try await stream.startCapture()
            session.stream = stream
            live[handle] = session
            loggedFailures.remove(w)
            return handle
        } catch {
            logFailure(w, "live", error)
            throw error
        }
    }

    func stopLive(_ h: LiveHandle) async {
        guard let session = live.removeValue(forKey: h), let stream = session.stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            // Already stopped (e.g. the window closed); nothing to clean up.
            NSLog("Podium: stopping live capture of %u: %@", session.window.windowID, String(describing: error))
        }
    }

    // MARK: - Helpers

    private func shareableWindow(_ w: WindowRef) async throws -> SCWindow {
        guard CGPreflightScreenCaptureAccess() else {
            if !loggedPermission {
                loggedPermission = true
                NSLog("Podium: Screen Recording permission missing; window capture disabled")
                // Shows the system prompt once; the grant takes effect after relaunch.
                CGRequestScreenCaptureAccess()
            }
            throw CaptureError.permissionMissing
        }
        if let list = windowList, Date().timeIntervalSince(list.fetched) <= Self.windowListMaxAge,
           let window = list.byID[w.windowID] {
            return window
        }
        // Stale, or the window is newer than the list: fetch again.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        windowList = (Date(), byID)
        guard let window = byID[w.windowID] else { throw CaptureError.windowNotShareable(w) }
        return window
    }

    private func logFailure(_ w: WindowRef, _ what: String, _ error: Error) {
        if case CaptureError.permissionMissing = error { return } // logged once globally
        guard loggedFailures.insert(w).inserted else { return }
        NSLog("Podium: %@ capture of %u (pid %d) failed: %@", what, w.windowID, w.pid, String(describing: error))
    }

    /// `size` scaled down (never up) to fit `bounds`, keeping its aspect ratio; at least 1x1.
    static func fit(_ size: CGSize, within bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let s = min(1, bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: max(1, (size.width * s).rounded()), height: max(1, (size.height * s).rounded()))
    }
}

/// Receives one live stream's frames on its own queue and hands them to the main queue.
private final class LiveSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let window: WindowRef
    let queue = DispatchQueue(label: "dev.podium.Podium.capture.live")
    /// Set once by `Capture` after the stream starts; only read by `Capture` afterwards.
    var stream: SCStream?
    private let onFrame: @Sendable (CGImage) -> Void

    init(window: WindowRef, onFrame: @escaping @Sendable (CGImage) -> Void) {
        self.window = window
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else { return }
        let onFrame = self.onFrame
        DispatchQueue.main.async { onFrame(image) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Podium: live capture of %u stopped: %@", window.windowID, String(describing: error))
    }

    /// Only `.complete` frames carry new content; idle frames repeat the last one.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
