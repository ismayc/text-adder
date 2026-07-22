import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    let manager: OverlayManager
    let keystrokes: KeystrokeDisplayController

    @State private var tab = 0

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text("Labels").tag(0)
                Text("Style").tag(1)
                Text("Phrases").tag(2)
                Text("Extras").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case 0: LabelsTab(state: state, manager: manager)
                case 1: StyleTab(state: state)
                case 2: PhrasesTab(state: state)
                default: ExtrasTab(state: state, keystrokes: keystrokes)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(14)
        .frame(width: 380)
    }
}

// MARK: - Labels

private struct LabelsTab: View {
    @ObservedObject var state: AppState
    let manager: OverlayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.items) { item in
                HStack {
                    Button {
                        state.updateItem(item.id) { $0.visible.toggle() }
                    } label: {
                        Image(systemName: item.visible ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.plain)
                    Text(item.name)
                    if state.countdowns[item.id] != nil {
                        Text("⏱ \(AppState.formatDuration(state.countdowns[item.id] ?? 0))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(item.text.prefix(18)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            item.id == state.selectedID
                                ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .onTapGesture { state.selectedID = item.id }
            }

            HStack {
                Button("Add Label") { state.addItem() }
                if state.items.count > 1 {
                    Button("Remove Selected", role: .destructive) {
                        state.removeSelected()
                    }
                }
            }

            if let idx = state.selectedIndex {
                let item = $state.items[idx]
                Divider()

                HStack {
                    Text("Name")
                    TextField("Name", text: item.name)
                        .textFieldStyle(.roundedBorder)
                }

                TextEditor(text: item.text)
                    .font(.system(size: 14))
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4))
                    )

                Picker("Align", selection: item.alignment) {
                    ForEach(TextAlign.allCases) { a in
                        Text(a.rawValue.capitalized).tag(a)
                    }
                }
                .pickerStyle(.segmented)

                if NSScreen.screens.count > 1 {
                    Picker("Display", selection: item.screenIndex) {
                        ForEach(0..<NSScreen.screens.count, id: \.self) { i in
                            Text(screenName(i)).tag(i)
                        }
                    }
                }

                Divider()
                Text("Position").font(.headline)
                snapGrid
                Text("Drag the text to place it, or use ⌃⌥ arrow keys to nudge. Drag the corner grip to resize.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                countdownSection(itemID: state.items[idx].id)

                Divider()
                HStack {
                    Button("Show for \(Int(state.items[idx].autoHideSeconds))s") {
                        manager.showSelectedTemporarily()
                    }
                    Stepper(
                        "", value: item.autoHideSeconds, in: 1...120, step: 1
                    )
                    .labelsHidden()
                    Text("then fade out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var snapGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        let pos = SnapPosition.allCases[row * 3 + col]
                        Button {
                            manager.snapSelected(to: pos)
                        } label: {
                            Circle()
                                .frame(width: 7, height: 7)
                                .frame(maxWidth: .infinity, minHeight: 18)
                        }
                    }
                }
            }
            Button("Bottom Third (lower-third)") {
                manager.snapSelected(to: .bottomThird)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func countdownSection(itemID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Countdown").font(.headline)
            Text("Put a duration in the text, then Start: \"10\" = 10 seconds, \"10:00\" = 10 minutes, \"1:30:00\" = h:mm:ss. Surrounding text stays — e.g. \"Break time remaining - 10:00\" ticks just the time. Click the overlay to pause/resume.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Start") { state.startCountdown() }
                if state.countdowns[itemID] != nil {
                    Button(
                        state.pausedCountdowns.contains(itemID) ? "Resume" : "Pause"
                    ) {
                        state.togglePauseCountdown()
                    }
                    Button("Reset") { state.resetCountdown() }
                }
            }
        }
    }

    private func screenName(_ i: Int) -> String {
        guard i < NSScreen.screens.count else { return "Display \(i + 1)" }
        return NSScreen.screens[i].localizedName
    }
}

// MARK: - Style

private struct StyleTab: View {
    @ObservedObject var state: AppState
    @State private var presetName = ""

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let idx = state.selectedIndex {
                let item = $state.items[idx]

                Picker("Font", selection: item.fontFamily) {
                    ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Bold", isOn: item.isBold)

                HStack {
                    Text("Size")
                    Slider(value: item.fontSize, in: 12...200)
                    Text("\(Int(state.items[idx].fontSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                        .monospacedDigit()
                }

                ColorPicker(
                    "Text color", selection: colorBinding(item.textColorHex))

                HStack {
                    Text("Border")
                    Slider(value: item.borderWidth, in: 0...15)
                    Text(String(format: "%.1f", state.items[idx].borderWidth))
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
                ColorPicker(
                    "Border color", selection: colorBinding(item.borderColorHex))

                Toggle("Drop shadow", isOn: item.shadowEnabled)

                Divider()
                Toggle("Background box", isOn: item.boxEnabled)
                if state.items[idx].boxEnabled {
                    ColorPicker(
                        "Box color (alpha = opacity)",
                        selection: colorBinding(item.boxColorHex),
                        supportsOpacity: true)
                }

                HStack {
                    Text("Opacity")
                    Slider(value: item.opacity, in: 0.1...1)
                    Text("\(Int(state.items[idx].opacity * 100))%")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }

                Divider()
                Text("Presets").font(.headline)
                HStack {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        state.savePreset(named: presetName)
                        presetName = ""
                    }
                    .disabled(presetName.isEmpty)
                }
                ForEach(state.presets) { preset in
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Button("Apply") { state.applyPreset(preset) }
                        Button {
                            state.presets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Select a label first.").foregroundStyle(.secondary)
            }
        }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hexString: hex.wrappedValue) ?? .white) },
            set: { hex.wrappedValue = NSColor($0).hexString }
        )
    }
}

// MARK: - Phrases

private struct PhrasesTab: View {
    @ObservedObject var state: AppState
    @State private var newPhrase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click a phrase to put it in the selected label. \(state.phraseHotKey.display) cycles through them from anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("New phrase", text: $newPhrase)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPhrase)
                Button("Add", action: addPhrase).disabled(newPhrase.isEmpty)
            }
            Button("Add current label text") {
                if let t = state.selectedItem?.text, !t.isEmpty,
                    !state.phrases.contains(t)
                {
                    state.phrases.append(t)
                }
            }

            ForEach(state.phrases, id: \.self) { phrase in
                HStack {
                    Button(phrase) { state.applyText(phrase) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        state.phrases.removeAll { $0 == phrase }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !state.recents.isEmpty {
                Divider()
                Text("Recent texts").font(.headline)
                ForEach(state.recents, id: \.self) { recent in
                    Button(recent) { state.applyText(recent) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                }
            }
        }
    }

    private func addPhrase() {
        let t = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !state.phrases.contains(t) { state.phrases.append(t) }
        newPhrase = ""
    }
}

// MARK: - Extras

private struct ExtrasTab: View {
    @ObservedObject var state: AppState
    let keystrokes: KeystrokeDisplayController

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var keystrokePermissionMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show all overlays", isOn: $state.masterVisible)
            Toggle("Click-through (lock positions)", isOn: $state.clickThrough)
                .help("Clicks pass through all overlay text. Turn off to drag or resize.")

            Divider()
            Text("Hotkeys").font(.headline)
            HotKeyRecorderRow(title: "Show/hide overlays", combo: $state.toggleHotKey)
            HotKeyRecorderRow(title: "Next phrase", combo: $state.phraseHotKey)
            Text("⌃⌥ arrow keys nudge the selected label by 10 px.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginItemError {
                Text(loginItemError).font(.caption).foregroundStyle(.red)
            }

            Divider()
            Toggle("Show keystrokes (KeyCastr-style)", isOn: $state.keystrokesEnabled)
                .onChange(of: state.keystrokesEnabled) { on in
                    keystrokePermissionMissing = !keystrokes.setEnabled(on)
                }
            if keystrokePermissionMissing {
                Text("Grant Accessibility permission to TextAdder in System Settings → Privacy & Security → Accessibility, then relaunch the app and re-enable.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()
            HStack {
                Spacer()
                Button("Quit TextAdder") { NSApp.terminate(nil) }
            }
        }
    }
}

/// Click the button, press a combo (needs ⌘, ⌃, or ⌥), Esc cancels.
private struct HotKeyRecorderRow: View {
    let title: String
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press keys…" : combo.display) {
                recording ? stop() : start()
            }
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc cancels
                stop()
                return nil
            }
            if let new = HotKeyCenter.combo(from: event) {
                combo = new
                stop()
                return nil
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
