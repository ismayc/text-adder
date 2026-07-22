import AppKit
import SwiftUI
import Testing

@testable import TextAdder

private let onCI = ProcessInfo.processInfo.environment["CI"] != nil

/// Deeper UI-path tests: exercise the overlay manager's styling branches,
/// fades, badges, the settings panel controller, and the keystroke pill.
/// Skipped on CI, where there is no window server.
@Suite(.disabled(if: onCI, "No window server on CI"), .serialized)
struct UICoverageTests {
    @MainActor
    private func spinRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    @Test @MainActor func liveTimerTickFiresOnRunLoop() {
        let state = makeState()
        state.applyText("30")
        state.startCountdown()
        let id = state.items[0].id
        spinRunLoop(1.3)
        let remaining = state.countdowns[id] ?? 30
        #expect(remaining < 30)
    }

    @Test @MainActor func managerAppliesStyledStates() {
        let state = makeState()
        let manager = OverlayManager(state: state)

        // Style branches: box, shadow, opacity, click-through, alignment.
        state.updateSelected {
            $0.boxEnabled = true
            $0.boxColorHex = "#00000080"
            $0.shadowEnabled = true
            $0.opacity = 0.5
            $0.alignment = .left
            $0.borderWidth = 4
        }
        state.clickThrough = true
        manager.reconcile()

        // Countdown active: widest-digit measurement + paused badge.
        state.applyText("Break - 0:30")
        state.startCountdown()
        manager.reconcile()
        state.togglePauseCountdown()
        manager.reconcile()
        state.togglePauseCountdown()
        manager.reconcile()

        // Hide everything (fade-out branch), then show again (fade-in).
        state.masterVisible = false
        manager.reconcile()
        state.masterVisible = true
        manager.reconcile()
        spinRunLoop(0.6)

        // Per-item hide.
        state.updateSelected { $0.visible = false }
        manager.reconcile()
        spinRunLoop(0.6)

        // Out-of-range screen index clamps instead of crashing.
        state.updateSelected {
            $0.visible = true
            $0.screenIndex = 99
        }
        manager.reconcile()

        // Off-screen origin gets pulled back onto the screen.
        state.updateSelected {
            $0.originX = -100_000
            $0.originY = -100_000
        }
        manager.reconcile()
        if let x = state.selectedItem?.originX {
            #expect(x > -100_000)
        }
    }

    @Test @MainActor func managerAutoHideFadesOutAndBack() {
        let state = makeState()
        let manager = OverlayManager(state: state)
        state.updateSelected { $0.autoHideSeconds = 0.2 }
        manager.showSelectedTemporarily()
        spinRunLoop(1.2)
        #expect(state.items[0].visible == false)

        // Start fades it back in.
        state.applyText("5")
        state.startCountdown()
        manager.reconcile()
        #expect(state.items[0].visible == true)
    }

    @Test @MainActor func managerActionsWithoutSelectionAreNoOps() {
        let state = makeState()
        let manager = OverlayManager(state: state)
        state.selectedID = nil
        manager.snapSelected(to: .bottomThird)
        manager.nudgeSelected(dx: 5, dy: 5)
        manager.showSelectedTemporarily()
        manager.resetSelectedPosition()
        #expect(state.items.count == 1)
    }

    @Test @MainActor func settingsWindowControllerLifecycle() {
        let controller = SettingsWindowController(
            rootView: Text("hello").frame(width: 200, height: 100))

        // A detached status button has no window: toggle takes the guard path.
        let detached = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        controller.toggle(below: detached)

        // Hosted in a real window, toggle shows then hides the panel.
        let host = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 30, height: 22),
            styleMask: [.borderless], backing: .buffered, defer: false)
        host.contentView?.addSubview(detached)
        controller.toggle(below: detached)
        spinRunLoop(0.3)
        controller.toggle(below: detached)
        host.orderOut(nil)
    }

    @Test @MainActor func keystrokePillShowsAndFormats() {
        let controller = KeystrokeDisplayController()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .option, .control, .shift], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k",
            charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        controller.show(event)
        controller.show(event)  // second show cancels the pending fade
        #expect(controller.setEnabled(false))
    }

    @Test @MainActor func settingsViewRendersInHostingView() {
        let state = makeState()
        let manager = OverlayManager(state: state)
        let keystrokes = KeystrokeDisplayController()
        let view = SettingsView(
            state: state, manager: manager, keystrokes: keystrokes)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 700)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width > 0)
    }
}
