import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController!
    private var overlayManager: OverlayManager!
    private var keystrokes: KeystrokeDisplayController!
    private var hotKeys: HotKeyCenter!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        overlayManager = OverlayManager(state: state)
        keystrokes = KeystrokeDisplayController()
        hotKeys = HotKeyCenter()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "character.textbox",
                accessibilityDescription: "Text Adder"
            )
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        settingsWindow = SettingsWindowController(
            rootView: SettingsView(
                state: state, manager: overlayManager, keystrokes: keystrokes)
        )

        // (Re)register global hotkeys whenever the recorded combos change.
        state.$toggleHotKey.combineLatest(state.$phraseHotKey)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        if state.keystrokesEnabled {
            state.keystrokesEnabled = keystrokes.setEnabled(true)
        }
    }

    private func registerHotKeys() {
        let state = AppState.shared
        hotKeys.removeAll()
        hotKeys.register(state.toggleHotKey) {
            state.masterVisible.toggle()
        }
        hotKeys.register(state.phraseHotKey) {
            state.nextPhrase()
        }
        // Fixed ⌃⌥ arrows: nudge the selected label by 10 px.
        let ctrlOpt = UInt32(4096 | 2048)
        let nudges: [(UInt32, CGFloat, CGFloat)] = [
            (123, -10, 0), (124, 10, 0), (125, 0, -10), (126, 0, 10),
        ]
        for (keyCode, dx, dy) in nudges {
            hotKeys.register(
                HotKeyCombo(keyCode: keyCode, modifiers: ctrlOpt, display: "")
            ) { [weak self] in
                self?.overlayManager.nudgeSelected(dx: dx, dy: dy)
            }
        }
    }

    @objc private func statusItemClicked() {
        // Right-click: instantly hide/show all overlays (they fade).
        if NSApp.currentEvent?.type == .rightMouseUp {
            AppState.shared.masterVisible.toggle()
            return
        }
        guard let button = statusItem.button else { return }
        settingsWindow.toggle(below: button)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
