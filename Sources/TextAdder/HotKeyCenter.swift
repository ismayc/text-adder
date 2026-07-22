import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon RegisterEventHotKey (no
/// Accessibility permission needed) and dispatches to closures by ID.
final class HotKeyCenter {
    private var handlerRef: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                Unmanaged<HotKeyCenter>.fromOpaque(userData!)
                    .takeUnretainedValue().actions[hkID.id]?()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func removeAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x5441_4444), id: nextID)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hkID,
            GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            actions[nextID] = action
        }
        nextID += 1
    }

    /// Build a combo from a keyDown event captured by the recorder UI.
    /// Requires at least one of ⌘⌃⌥ so plain typing can't become a hotkey.
    static func combo(from event: NSEvent) -> HotKeyCombo? {
        var mods: UInt32 = 0
        var display = ""
        let f = event.modifierFlags
        if f.contains(.control) {
            mods |= UInt32(controlKey)
            display += "⌃"
        }
        if f.contains(.option) {
            mods |= UInt32(optionKey)
            display += "⌥"
        }
        if f.contains(.shift) {
            mods |= UInt32(shiftKey)
            display += "⇧"
        }
        if f.contains(.command) {
            mods |= UInt32(cmdKey)
            display += "⌘"
        }
        guard mods != 0, mods != UInt32(shiftKey) else { return nil }
        display += keyName(for: event)
        return HotKeyCombo(
            keyCode: UInt32(event.keyCode), modifiers: mods, display: display)
    }

    static func keyName(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
