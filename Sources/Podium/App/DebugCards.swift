import AppKit
import os
import PodiumCore

/// `--debug-cards`: three colored cards fly between a stage pose and a strip slot. Every
/// 350 ms (always mid-flight) and on every click of a card's strip slot, each card's target
/// flips. After 10 s it logs frame stats and quits. It touches no other app's windows and
/// asks for no permissions.
@MainActor
final class DebugCards {
    private static let retargetInterval = 0.35
    private static let duration = 10.0

    private let tuning = Tuning.initial
    private let side = StripSide.right
    private let logger = Logger(subsystem: "dev.podium.Podium", category: "animator")
    private var overlay: Overlay?
    private var panel: StripPanel?
    private var animator: Animator?
    private var cards: [(card: WindowCard, stage: CardPose, strip: CardPose)] = []
    private var inStrip: [UUID: Bool] = [:]
    private var timer: Timer?
    private var retargets = 0

    func start() {
        guard let screen = NSScreen.screens.first else { return }
        let overlay = Overlay(screen: screen)
        let animator = Animator(screen: screen)
        let display = overlay.frame
        let band = stripBand(in: display, side: side, tuning: tuning)
        let stage = stageArea(in: display, side: side, tuning: tuning)

        let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen]
        let windowSize = CGSize(width: 640, height: 420)
        let slotSize = tuning.itemMaxSize
        let rowStep = slotSize.height + tuning.rowSpacing
        let top = display.midY - (CGFloat(colors.count) * slotSize.height + CGFloat(colors.count - 1) * tuning.rowSpacing) / 2
        let tilt = side == .left ? tuning.tiltRadians : -tuning.tiltRadians
        let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        let fit = min(slotSize.width / windowSize.width, slotSize.height / windowSize.height)

        var targets: [(id: UUID, frame: CGRect)] = []
        for (i, color) in colors.enumerated() {
            let offset = CGFloat(i - 1) * 60
            let stagePose = CardPose(center: CGPoint(x: stage.midX + offset, y: stage.midY + offset),
                                     scale: 1, tilt: 0, alpha: 1)
            let slot = CGRect(x: band.midX - slotSize.width / 2, y: top + CGFloat(i) * rowStep,
                              width: slotSize.width, height: slotSize.height)
            let stripPose = CardPose(center: CGPoint(x: slot.midX, y: slot.midY), scale: fit, tilt: tilt, alpha: 1)
            let card = WindowCard(size: windowSize, side: side, tuning: tuning, pose: stagePose)
            card.image = Self.image(size: windowSize, color: color, label: "\(i + 1)")
            card.appIcon = icon
            overlay.add(card)
            cards.append((card, stagePose, stripPose))
            inStrip[card.id] = false
            targets.append((card.id, slot))
        }

        let panel = StripPanel(band: band)
        panel.targets = targets
        panel.onClick = { [weak self] id in self?.flip(only: id) }
        panel.onShiftClick = { [weak self] id in self?.flip(only: id) }
        panel.onDragToStage = { [weak self] id in self?.flip(only: id) }

        overlay.show()
        panel.show()
        self.overlay = overlay
        self.panel = panel
        self.animator = animator

        logger.log("debug-cards: started on \(Int(display.width), privacy: .public)x\(Int(display.height), privacy: .public)")
        // Let the freshly shown windows composite once before motion starts; their first frame
        // is slow (~27 ms) and isn't animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.run() }
    }

    private func run() {
        flipAll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.retargetInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flipAll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { [weak self] in self?.finish() }
    }

    private func flipAll() {
        for entry in cards { flip(entry.card) }
    }

    private func flip(only id: UUID) {
        guard let entry = cards.first(where: { $0.card.id == id }) else { return }
        flip(entry.card)
    }

    private func flip(_ card: WindowCard) {
        guard let animator, let entry = cards.first(where: { $0.card === card }) else { return }
        let toStrip = !(inStrip[card.id] ?? false)
        inStrip[card.id] = toStrip
        retargets += 1
        animator.drive(card, to: toStrip ? entry.strip : entry.stage, spring: tuning.transitionSpring)
    }

    private func finish() {
        timer?.invalidate()
        guard let stats = animator?.stats else { return }
        let line = String(format: "Podium debug-cards: frames=%d dropped=%d maxDt=%.2f ms",
                          stats.frames, stats.dropped, stats.maxDt * 1000)
        logger.log("\(line, privacy: .public) retargets=\(self.retargets, privacy: .public)")
        NSLog("%@", line)
        animator?.invalidate()
        NSApp.terminate(nil)
    }

    /// A flat-colored "window" with a darker title bar along the top edge and a big label,
    /// so an upside-down or mirrored card is obvious.
    private static func image(size: CGSize, color: NSColor, label: String) -> CGImage? {
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // CG's origin is bottom-left: the title bar is the top 32 pt.
        ctx.setFillColor(color.blended(withFraction: 0.45, of: .black)!.cgColor)
        ctx.fill(CGRect(x: 0, y: size.height - 32, width: size.width, height: 32))
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: 12, y: size.height - 22, width: 12, height: 12))

        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 160),
                                                    .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: label, attributes: attrs)
        let textSize = text.size()
        text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - 32 - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
