import AppKit
import Carbon.HIToolbox
import Testing

@testable import TextAdder

private func keyEvent(
    characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: 0, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false,
        keyCode: keyCode)!
}

@Suite struct HotKeyComboFromEventTests {
    @Test func controlOptionCombo() throws {
        let combo = try #require(
            HotKeyCenter.combo(
                from: keyEvent(characters: "t", keyCode: 17, flags: [.control, .option])))
        #expect(combo.keyCode == 17)
        #expect(combo.modifiers == UInt32(controlKey | optionKey))
        #expect(combo.display == "⌃⌥T")
    }

    @Test func commandShiftCombo() throws {
        let combo = try #require(
            HotKeyCenter.combo(
                from: keyEvent(characters: "d", keyCode: 2, flags: [.command, .shift])))
        #expect(combo.modifiers == UInt32(cmdKey | shiftKey))
        #expect(combo.display == "⇧⌘D")
    }

    @Test func noModifiersRejected() {
        let event = keyEvent(characters: "a", keyCode: 0, flags: [])
        #expect(HotKeyCenter.combo(from: event) == nil)
    }

    @Test func shiftOnlyRejected() {
        let event = keyEvent(characters: "a", keyCode: 0, flags: .shift)
        #expect(HotKeyCenter.combo(from: event) == nil)
    }

    @Test func specialKeyNames() {
        #expect(
            HotKeyCenter.keyName(for: keyEvent(characters: "\r", keyCode: 36, flags: []))
                == "⏎")
        #expect(
            HotKeyCenter.keyName(for: keyEvent(characters: " ", keyCode: 49, flags: []))
                == "Space")
        #expect(
            HotKeyCenter.keyName(for: keyEvent(characters: "x", keyCode: 123, flags: []))
                == "←")
        #expect(
            HotKeyCenter.keyName(for: keyEvent(characters: "q", keyCode: 12, flags: []))
                == "Q")
    }

    @Test @MainActor func registerAndRemoveAllDoNotCrash() {
        let center = HotKeyCenter()
        center.register(
            HotKeyCombo(
                keyCode: 111, modifiers: UInt32(cmdKey | optionKey | controlKey),
                display: "test")
        ) {}
        center.removeAll()
    }
}

/// Window-creating smoke tests. Skipped on CI, where there is no window server.
private let onCI = ProcessInfo.processInfo.environment["CI"] != nil

@Suite(.disabled(if: onCI, "No window server on CI"))
struct UISmokeTests {
    @Test @MainActor func overlayPanelConfiguration() {
        let panel = OverlayPanel()
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.level == .screenSaver)
        #expect(!panel.isOpaque)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test @MainActor func overlayManagerLifecycle() {
        let state = makeState()
        let manager = OverlayManager(state: state)
        manager.reconcile()

        state.addItem()
        manager.reconcile()

        manager.snapSelected(to: .topLeft)
        manager.nudgeSelected(dx: 10, dy: -10)
        manager.resetSelectedPosition()
        manager.showSelectedTemporarily()

        state.removeSelected()
        manager.reconcile()
        #expect(state.items.count == 1)
    }

    @Test @MainActor func keystrokeControllerDisableAlwaysSucceeds() {
        let controller = KeystrokeDisplayController()
        #expect(controller.setEnabled(false))
    }
}
