import Testing
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
