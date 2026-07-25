import AppKit
import Combine

/// Borderless, non-activating panel that floats above every other window
/// (including full-screen apps) and never steals focus.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Container view: the (optional) background box, drag surface, and long-press
/// target. Pausing a countdown takes a deliberate press-and-hold on the text —
/// a plain click does nothing, so ordinary dragging and resizing never toggle it.
private final class ItemContainerView: NSView {
    var onLongPress: (() -> Void)?
    /// How long the pointer must stay down before the countdown toggles.
    static let holdSeconds: TimeInterval = 2.0
    /// Pointer slop allowed before a press turns into a window drag.
    private static let dragSlop: CGFloat = 4

    private var holdTimer: Timer?
    private var pressOrigin: NSPoint = .zero
    private var isDragging = false
    private let holdIndicator = CALayer()

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        holdIndicator.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
        holdIndicator.cornerRadius = 1.5
        holdIndicator.isHidden = true
        layer?.addSublayer(holdIndicator)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Swallow events aimed at the label so drag/press land here; the resize
    /// handle keeps its own events.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view is ResizeHandle { return view }
        return view == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        pressOrigin = event.locationInWindow
        startHold()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging else { return }
        // Small movements keep the hold alive; a real drag moves the window.
        let point = event.locationInWindow
        let dx = point.x - pressOrigin.x
        let dy = point.y - pressOrigin.y
        guard dx * dx + dy * dy > Self.dragSlop * Self.dragSlop else { return }
        isDragging = true
        cancelHold()
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        cancelHold()
    }

    private func startHold() {
        cancelHold()
        showHoldIndicator()
        let timer = Timer(timeInterval: Self.holdSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.cancelHold()
            self.onLongPress?()
        }
        // .common so the hold keeps ticking while the mouse is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdIndicator.removeAllAnimations()
        holdIndicator.isHidden = true
    }

    /// Thin bar along the bottom edge that fills over the hold duration, so the
    /// gesture is discoverable and an accidental press visibly does nothing.
    private func showHoldIndicator() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holdIndicator.isHidden = false
        holdIndicator.frame = NSRect(x: 6, y: 3, width: 0, height: 3)
        CATransaction.commit()

        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = 0
        grow.toValue = max(0, bounds.width - 12)
        grow.duration = Self.holdSeconds
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        holdIndicator.anchorPoint = NSPoint(x: 0, y: 0.5)
        holdIndicator.position = NSPoint(x: 6, y: 4.5)
        holdIndicator.add(grow, forKey: "hold")
    }
}

/// Small corner grip: dragging it changes the label's font size.
private final class ResizeHandle: NSView {
    var onResize: ((CGFloat) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    /// Claim the whole press so it never falls through to the container's
    /// press-and-hold (which would pause the countdown after a resize).
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        onResize?(event.deltaX)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        for offset in stride(from: 4.0, through: 12.0, by: 4.0) {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 1))
            path.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + offset))
        }
        NSColor.white.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

/// One floating window per overlay item, kept in sync with AppState.
final class OverlayManager {
    private let state: AppState
    private var panels: [UUID: OverlayPanel] = [:]
    private var labels: [UUID: NSTextField] = [:]
    private var handles: [UUID: ResizeHandle] = [:]
    private var pausedBadges: [UUID: OverlayPanel] = [:]
    /// Items whose panel is mid fade-in/out; guards against reconcile passes
    /// (e.g. countdown ticks) stomping the animation.
    private var fading: Set<UUID> = []
    private var autoHideTimers: [UUID: Timer] = [:]
    private var cancellable: AnyCancellable?
    private var isApplying = false
    private let basePadding: CGFloat = 16

    init(state: AppState) {
        self.state = state
        cancellable = state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // objectWillChange fires before values land; apply after.
                DispatchQueue.main.async { self?.reconcile() }
            }
        reconcile()
    }

    private func screen(for item: OverlayItem) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens[min(item.screenIndex, screens.count - 1)]
    }

    func reconcile() {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        for (id, panel) in panels where !state.items.contains(where: { $0.id == id }) {
            panel.orderOut(nil)
            panels[id] = nil
            labels[id] = nil
            handles[id] = nil
            pausedBadges[id]?.orderOut(nil)
            pausedBadges[id] = nil
            autoHideTimers[id]?.invalidate()
            autoHideTimers[id] = nil
        }
        for item in state.items {
            apply(item)
        }
    }

    private func makePanel(for item: OverlayItem) -> OverlayPanel {
        let panel = OverlayPanel()
        let container = ItemContainerView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        let label = NSTextField(wrappingLabelWithString: "")
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        container.addSubview(label)

        let handle = ResizeHandle(frame: .zero)
        let id = item.id
        container.onLongPress = { [weak self] in
            // Press and hold on the text pauses/resumes this label's countdown.
            self?.state.togglePauseCountdown(id)
        }
        handle.onResize = { [weak self] delta in
            guard let self,
                let idx = self.state.items.firstIndex(where: { $0.id == id })
            else { return }
            let newSize = min(400, max(8, self.state.items[idx].fontSize + Double(delta) * 0.5))
            self.state.items[idx].fontSize = newSize
        }
        container.addSubview(handle)
        panel.contentView = container

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isApplying,
                let idx = self.state.items.firstIndex(where: { $0.id == id })
            else { return }
            let origin = panel.frame.origin
            if self.state.items[idx].originX != origin.x
                || self.state.items[idx].originY != origin.y
            {
                self.state.items[idx].originX = origin.x
                self.state.items[idx].originY = origin.y
            }
        }

        panels[item.id] = panel
        labels[item.id] = label
        handles[item.id] = handle
        return panel
    }

    private func apply(_ item: OverlayItem) {
        let panel = panels[item.id] ?? makePanel(for: item)
        guard let label = labels[item.id], let handle = handles[item.id],
            let container = panel.contentView
        else { return }

        let displayText = state.displayText(for: item)
        label.attributedStringValue = item.attributed(displayText)

        // While counting down, measure with the widest digit so the window
        // doesn't change width every second.
        let measureText =
            state.countdowns[item.id] != nil
            ? String(displayText.map { $0.isNumber ? "8" : $0 })
            : displayText
        let bounds = item.attributed(measureText).boundingRect(
            with: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let pad = basePadding + CGFloat(item.borderWidth)
        // NSTextField needs ~4 px per side beyond boundingRect, or it wraps
        // the last character out of view (measured empirically).
        let size = NSSize(
            width: ceil(bounds.width) + pad * 2 + 10,
            height: ceil(bounds.height) + pad * 2 + 4
        )

        var origin: NSPoint
        if let x = item.originX, let y = item.originY {
            origin = NSPoint(x: x, y: y)
        } else if let screen = screen(for: item) {
            origin = SnapPosition.middleCenter.origin(for: size, in: screen.visibleFrame)
            setOrigin(of: item.id, to: origin)
        } else {
            origin = .zero
        }
        // If the item was moved to another display, pull it onto that screen.
        if let screen = screen(for: item),
            !screen.frame.intersects(NSRect(origin: origin, size: size))
        {
            origin = SnapPosition.middleCenter.origin(for: size, in: screen.visibleFrame)
            setOrigin(of: item.id, to: origin)
        }

        let target = NSRect(origin: origin, size: size)
        if !panel.frame.isNearlyEqual(to: target) {
            panel.setFrame(target, display: true)
        }
        label.frame = container.bounds.insetBy(dx: pad, dy: pad)
        label.autoresizingMask = [.width, .height]
        handle.frame = NSRect(
            x: container.bounds.maxX - 16, y: 2, width: 14, height: 14)
        handle.autoresizingMask = [.minXMargin, .maxYMargin]

        container.layer?.backgroundColor =
            item.boxEnabled
            ? (NSColor(hexString: item.boxColorHex) ?? .black).cgColor
            : NSColor.black.withAlphaComponent(0.01).cgColor

        panel.ignoresMouseEvents = state.clickThrough

        let id = item.id
        let shouldShow = state.masterVisible && item.visible
        if shouldShow && !panel.isVisible {
            fading.insert(id)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = item.opacity
            } completionHandler: { [weak self] in
                self?.fading.remove(id)
            }
        } else if !shouldShow && panel.isVisible {
            if !fading.contains(id) {
                fading.insert(id)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    guard let self else { return }
                    self.fading.remove(id)
                    guard
                        let current = self.state.items.first(where: { $0.id == id }),
                        self.state.masterVisible && current.visible
                    else {
                        panel.orderOut(nil)
                        return
                    }
                    // Re-shown while fading out — snap back to full opacity.
                    panel.alphaValue = current.opacity
                }
            }
        } else if shouldShow && !fading.contains(id) {
            panel.alphaValue = item.opacity
        }

        updatePausedBadge(for: item, next: panel)
    }

    /// Small "Paused" pill shown beside a label whose countdown is paused.
    private func updatePausedBadge(for item: OverlayItem, next panel: OverlayPanel) {
        let showing =
            state.pausedCountdowns.contains(item.id) && state.masterVisible
            && item.visible
        guard showing else {
            pausedBadges[item.id]?.orderOut(nil)
            return
        }

        let badge: OverlayPanel
        if let existing = pausedBadges[item.id] {
            badge = existing
        } else {
            badge = OverlayPanel()
            badge.ignoresMouseEvents = true
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            container.wantsLayer = true
            container.layer?.backgroundColor =
                NSColor.black.withAlphaComponent(0.75).cgColor
            container.layer?.cornerRadius = 8
            let text = NSTextField(labelWithString: "Paused")
            text.font = .systemFont(ofSize: 14, weight: .semibold)
            text.textColor = .white
            text.sizeToFit()
            text.frame.origin = NSPoint(x: 10, y: 5)
            container.addSubview(text)
            badge.contentView = container
            badge.setContentSize(
                NSSize(width: text.frame.width + 20, height: text.frame.height + 10))
            pausedBadges[item.id] = badge
        }

        let size = badge.frame.size
        badge.setFrameOrigin(
            NSPoint(
                x: panel.frame.maxX + 6,
                y: panel.frame.midY - size.height / 2))
        badge.orderFrontRegardless()
    }

    private func setOrigin(of id: UUID, to origin: NSPoint) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[idx].originX = origin.x
        state.items[idx].originY = origin.y
    }

    // MARK: - Actions used by the settings panel / hotkeys

    func snapSelected(to position: SnapPosition) {
        guard let item = state.selectedItem, let panel = panels[item.id],
            let screen = screen(for: item)
        else { return }
        let origin = position.origin(for: panel.frame.size, in: screen.visibleFrame)
        setOrigin(of: item.id, to: origin)
    }

    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let item = state.selectedItem, let panel = panels[item.id] else { return }
        let o = panel.frame.origin
        setOrigin(of: item.id, to: NSPoint(x: o.x + dx, y: o.y + dy))
    }

    func resetSelectedPosition() {
        guard let item = state.selectedItem else { return }
        snapSelected(to: .middleCenter)
        _ = item
    }

    /// Show the selected label now, then fade it out after its auto-hide delay.
    func showSelectedTemporarily() {
        guard let item = state.selectedItem else { return }
        let id = item.id
        autoHideTimers[id]?.invalidate()

        state.updateSelected { $0.visible = true }
        if !state.masterVisible { state.masterVisible = true }

        autoHideTimers[id] = Timer.scheduledTimer(
            withTimeInterval: item.autoHideSeconds, repeats: false
        ) { [weak self] _ in
            // Setting visible=false fades the panel out via apply().
            guard let self,
                let idx = self.state.items.firstIndex(where: { $0.id == id })
            else { return }
            self.state.items[idx].visible = false
        }
    }
}

extension NSRect {
    fileprivate func isNearlyEqual(to other: NSRect) -> Bool {
        abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5
            && abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
