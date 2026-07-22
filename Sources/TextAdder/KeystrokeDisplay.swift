import AppKit
import ApplicationServices

/// Shows the keys you press in a pill at the bottom of the main screen,
/// KeyCastr-style. Uses a global event monitor, which requires the app to be
/// granted Accessibility permission (macOS prompts on first enable).
final class KeystrokeDisplayController {
    private let panel = OverlayPanel()
    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var fadeWork: DispatchWorkItem?

    init() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        container.wantsLayer = true
        container.layer?.backgroundColor =
            NSColor.black.withAlphaComponent(0.72).cgColor
        container.layer?.cornerRadius = 14
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        container.addSubview(label)
        panel.contentView = container
        panel.ignoresMouseEvents = true
    }

    /// Returns false if Accessibility permission is missing (macOS will have
    /// shown its grant prompt; the app must be relaunched after granting).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if !enabled {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            panel.orderOut(nil)
            return true
        }
        guard monitor == nil else { return true }
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.show(event)
        }
        return true
    }

    func show(_ event: NSEvent) {
        var text = ""
        let f = event.modifierFlags
        if f.contains(.control) { text += "⌃" }
        if f.contains(.option) { text += "⌥" }
        if f.contains(.shift) { text += "⇧" }
        if f.contains(.command) { text += "⌘" }
        text += HotKeyCenter.keyName(for: event)

        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(
            width: label.frame.width + 44, height: label.frame.height + 20)
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: sf.midX - size.width / 2, y: sf.minY + 100,
                width: size.width, height: size.height),
            display: true
        )
        label.frame = NSRect(
            x: 22, y: 10, width: label.frame.width, height: label.frame.height)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        fadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self.panel.animator().alphaValue = 0
            } completionHandler: {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
