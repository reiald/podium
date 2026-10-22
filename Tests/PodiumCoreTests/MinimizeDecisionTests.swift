import Testing
import CoreGraphics
import Foundation
@testable import PodiumCore

@Suite struct MinimizeDecisionTests {
    let minimizeButton = "AXMinimizeButton"
    /// US layout: physical key 46 types "m".
    let keyM: UInt16 = 46

    private func decide(
        _ trigger: MinimizeTrigger,
        behavior: MinimizeBehavior = .strip,
        tapHealthy: Bool = true,
        frontWindowManaged: Bool = true
    ) -> MinimizeDecision {
        decideMinimize(trigger, behavior: behavior, tapHealthy: tapHealthy, frontWindowManaged: frontWindowManaged)
    }

    @Test func interceptsMinimizeButtonClick() {
        let t = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: [])
        #expect(decide(t) == .intercept)
    }

    @Test func interceptsCommandM() {
        let t = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: .command)
        #expect(decide(t) == .intercept)
    }

    @Test func passesThroughOptionClickAndCommandOptionM() {
        let optionClick = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: .option)
        #expect(decide(optionClick) == .passThrough)

        let commandOptionM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: [.command, .option])
        #expect(decide(commandOptionM) == .passThrough)
    }

    @Test func passesThroughWhenBehaviorIsDock() {
        let click = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: [])
        let cmdM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: .command)
        #expect(decide(click, behavior: .dock) == .passThrough)
        #expect(decide(cmdM, behavior: .dock) == .passThrough)
    }

    @Test func passesThroughWhenTapUnhealthy() {
        let click = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: [])
        let cmdM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: .command)
        #expect(decide(click, tapHealthy: false) == .passThrough)
        #expect(decide(cmdM, tapHealthy: false) == .passThrough)
    }

    @Test func passesThroughForUnmanagedWindow() {
        let click = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: [])
        let cmdM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: .command)
        #expect(decide(click, frontWindowManaged: false) == .passThrough)
        #expect(decide(cmdM, frontWindowManaged: false) == .passThrough)
    }

    @Test func passesThroughOtherButtons() {
        let close = MinimizeTrigger.mouseDown(subrole: "AXCloseButton", modifiers: [])
        let zoom = MinimizeTrigger.mouseDown(subrole: "AXZoomButton", modifiers: [])
        let none = MinimizeTrigger.mouseDown(subrole: nil, modifiers: [])
        #expect(decide(close) == .passThrough)
        #expect(decide(zoom) == .passThrough)
        #expect(decide(none) == .passThrough)
    }

    @Test func passesThroughOtherKeysAndExtraModifiers() {
        let otherKey = MinimizeTrigger.keyDown(keyCode: 0, characters: "a", modifiers: .command)
        #expect(decide(otherKey) == .passThrough)

        let cmdShiftM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: [.command, .shift])
        #expect(decide(cmdShiftM) == .passThrough)

        let plainM = MinimizeTrigger.keyDown(keyCode: keyM, characters: "m", modifiers: [])
        #expect(decide(plainM) == .passThrough)
    }

    @Test func passesThroughClickWithAnyModifier() {
        let shiftClick = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: .shift)
        let controlClick = MinimizeTrigger.mouseDown(subrole: minimizeButton, modifiers: .control)
        #expect(decide(shiftClick) == .passThrough)
        #expect(decide(controlClick) == .passThrough)
    }

    /// AZERTY: physical key 46 types ",", and Cmd-, opens Settings. Never Cmd-M.
    @Test func passesThroughCommandCommaOnKey46() {
        let t = MinimizeTrigger.keyDown(keyCode: 46, characters: ",", modifiers: .command)
        #expect(decide(t) == .passThrough)
    }

    /// The character decides, wherever the layout puts it (AZERTY "m" is key 41).
    @Test func interceptsCommandMOnAnyKeyCode() {
        for code: UInt16 in [41, 0, 46] {
            #expect(decide(.keyDown(keyCode: code, characters: "m", modifiers: .command)) == .intercept)
        }
        // Caps Lock on: still Cmd-M.
        #expect(decide(.keyDown(keyCode: 41, characters: "M", modifiers: .command)) == .intercept)
    }

    @Test func passesThroughUnknownCharacters() {
        #expect(decide(.keyDown(keyCode: keyM, characters: nil, modifiers: .command)) == .passThrough)
        #expect(decide(.keyDown(keyCode: keyM, characters: "", modifiers: .command)) == .passThrough)
        #expect(decide(.keyDown(keyCode: keyM, characters: "mm", modifiers: .command)) == .passThrough)
    }
}

@Suite struct DockClickDecisionTests {
    let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")

    private func click(_ url: URL?, modifiers: ModifierSet = [], role: String? = "AXDockItem",
                       subrole: String? = "AXApplicationDockItem") -> DockClick {
        DockClick(modifiers: modifiers, role: role, subrole: subrole, itemURL: url)
    }

    private func decide(_ c: DockClick, enabled: Bool = true, tapHealthy: Bool = true,
                        frontmost: URL? = URL(fileURLWithPath: "/Applications/Safari.app"),
                        onStage: Bool = true) -> MinimizeDecision {
        decideDockClick(c, enabled: enabled, tapHealthy: tapHealthy,
                        frontmostAppURL: frontmost, frontmostAppHasWindowOnStage: onStage)
    }

    @Test func interceptsPlainClickOnFrontmostAppDockItem() {
        #expect(decide(click(safari)) == .intercept)
        // The Dock reports bundle URLs with a trailing slash.
        #expect(decide(click(URL(string: "file:///Applications/Safari.app/")!)) == .intercept)
    }

    @Test func passesThroughOtherAppsDockItem() {
        #expect(decide(click(notes)) == .passThrough)
        #expect(decide(click(safari), frontmost: nil) == .passThrough)
    }

    @Test func passesThroughWhenAppHasNoWindowOnStage() {
        #expect(decide(click(safari), onStage: false) == .passThrough)
    }

    @Test func passesThroughWithModifiers() {
        for m: ModifierSet in [.command, .option, .shift, .control, [.command, .option]] {
            #expect(decide(click(safari, modifiers: m)) == .passThrough)
        }
    }

    @Test func passesThroughWhenDisabled() {
        #expect(decide(click(safari), enabled: false) == .passThrough)
    }

    @Test func passesThroughWhenTapUnhealthy() {
        #expect(decide(click(safari), tapHealthy: false) == .passThrough)
    }

    @Test func passesThroughNonApplicationDockItems() {
        let downloads = URL(fileURLWithPath: "/Users/me/Downloads")
        #expect(decide(click(downloads, subrole: "AXFolderDockItem"), frontmost: downloads) == .passThrough)
        #expect(decide(click(safari, subrole: "AXTrashDockItem")) == .passThrough)
        #expect(decide(click(safari, subrole: nil)) == .passThrough)
        #expect(decide(click(safari, role: "AXButton")) == .passThrough)
        #expect(decide(click(nil)) == .passThrough)
        #expect(decide(click(URL(string: "https://example.com/Safari.app")!),
                       frontmost: URL(string: "https://example.com/Safari.app")!) == .passThrough)
    }
}

@Suite struct DockClickGateTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func growsVisibleDockByItsThickness() {
        let list = CGRect(x: 400, y: 900, width: 700, height: 80)
        let gate = dockClickGate(listFrame: list, screens: [screen])
        #expect(gate == CGRect(x: 320, y: 820, width: 860, height: 162))
    }

    @Test func movesHiddenDockBackOntoItsScreen() {
        // Auto-hidden: slid below the bottom edge.
        let list = CGRect(x: 400, y: 990, width: 700, height: 80)
        let gate = dockClickGate(listFrame: list, screens: [screen, CGRect(x: 1512, y: 0, width: 1920, height: 1080)])
        #expect(gate == CGRect(x: 320, y: 822, width: 860, height: 160))
    }

    @Test func picksTheScreenTheDockIsOn() {
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let list = CGRect(x: 1600, y: 1000, width: 500, height: 60)   // bottom of the second screen
        let gate = dockClickGate(listFrame: list, screens: [screen, second])
        #expect(gate.map { second.contains($0) } == true)
        #expect(gate?.contains(CGPoint(x: 1700, y: 1030)) == true)
    }

    @Test func unknownFrameHasNoGate() {
        #expect(dockClickGate(listFrame: .zero, screens: [screen]) == nil)
        #expect(dockClickGate(listFrame: .null, screens: [screen]) == nil)
        #expect(dockClickGate(listFrame: CGRect(x: 0, y: 0, width: 10, height: 10), screens: []) == nil)
    }
}
