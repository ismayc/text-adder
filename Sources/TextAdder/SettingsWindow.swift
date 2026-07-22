import AppKit
import SwiftUI

/// Borderless panel that can take keyboard focus (for the text editor)
/// without activating the app and stealing focus from the frontmost window.
private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hands the SwiftUI content's measured size to the panel controller.
private final class SizeRelay {
    var handler: ((CGSize) -> Void)?
}

/// Popover replacement: a panel positioned explicitly below the status item,
/// sized to fit its SwiftUI content (no scrolling), closed when it loses key
/// status (i.e. you click anywhere else).
final class SettingsWindowController {
    private let panel: SettingsPanel
    private var lastHide: TimeInterval = 0
    private let relay = SizeRelay()

    init<V: View>(rootView: V) {
        let relay = self.relay
        let measured = rootView.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { relay.handler?(geo.size) }
                    .onChange(of: geo.size) { relay.handler?($0) }
            }
        )
        let hosting = NSHostingController(rootView: measured)
        hosting.view.layoutSubtreeIfNeeded()
        var size = hosting.view.fittingSize
        if size.width < 10 || size.height < 10 {
            size = NSSize(width: 380, height: 480)
        }

        panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // One notch above the overlays so they can't cover the controls.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        hosting.view.frame = effect.bounds
        hosting.view.autoresizingMask = [.width, .height]
        effect.addSubview(hosting.view)
        panel.contentView = effect

        // Content height changes with the selected tab / item count; keep the
        // panel exactly content-sized, top edge pinned under the menu bar.
        relay.handler = { [weak self] size in
            DispatchQueue.main.async { self?.resize(to: size) }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.hide() }
    }

    private func resize(to size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        let maxHeight =
            (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? size.height
        let height = min(size.height, maxHeight - 12)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 || abs(frame.width - size.width) > 0.5
        else { return }
        frame.origin.y = frame.maxY - height
        frame.size = NSSize(width: size.width, height: height)
        panel.setFrame(frame, display: true)
    }

    func toggle(below button: NSStatusBarButton) {
        // Clicking the status item makes the panel resign key, which hides it
        // just before this action fires — don't immediately reopen it.
        if panel.isVisible || ProcessInfo.processInfo.systemUptime - lastHide < 0.3 {
            hide()
        } else {
            show(below: button)
        }
    }

    private func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let screen = buttonWindow.screen ?? NSScreen.main
        let buttonFrame = buttonWindow.frame
        let size = panel.frame.size

        var x = buttonFrame.midX - size.width / 2
        let y = buttonFrame.minY - 6 - size.height
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        guard panel.isVisible else { return }
        lastHide = ProcessInfo.processInfo.systemUptime
        panel.orderOut(nil)
    }
}
