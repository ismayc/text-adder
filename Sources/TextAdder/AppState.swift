import AppKit
import Combine

/// All app state: overlay items, phrase library, presets, hotkeys, countdowns.
/// Persisted to UserDefaults as JSON (debounced).
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var items: [OverlayItem]
    @Published var selectedID: UUID?
    @Published var masterVisible = true
    @Published var clickThrough = false
    @Published var phrases: [String]
    @Published var recents: [String]
    @Published var presets: [StylePreset]
    @Published var toggleHotKey: HotKeyCombo
    @Published var phraseHotKey: HotKeyCombo
    @Published var keystrokesEnabled = false

    /// Remaining seconds per item with an active countdown (runtime only).
    @Published var countdowns: [UUID: Int] = [:]
    @Published var pausedCountdowns: Set<UUID> = []
    /// For countdowns embedded in longer text ("Break - 10:00"): the item's
    /// text with the time token swapped for a placeholder to re-fill each tick.
    private var countdownTemplates: [UUID: String] = [:]
    private static let timePlaceholder = "\u{FFFC}"

    private var tickTimer: Timer?
    private var saveCancellable: AnyCancellable?
    private var lastRecordedText: [UUID: String] = [:]
    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can use an isolated suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = defaults.data(forKey: key),
                let value = try? JSONDecoder().decode(T.self, from: data)
            else { return fallback }
            return value
        }
        items = load("items", [OverlayItem(name: "Label 1")])
        phrases = load("phrases", ["Q&A time", "Be right back", "Break until :15"])
        recents = load("recents", [String]())
        presets = load("presets", [StylePreset]())
        toggleHotKey = load(
            "toggleHotKey",
            HotKeyCombo(keyCode: 17, modifiers: 4096 | 2048, display: "⌃⌥T"))
        phraseHotKey = load(
            "phraseHotKey",
            HotKeyCombo(keyCode: 35, modifiers: 4096 | 2048, display: "⌃⌥P"))
        masterVisible = defaults.object(forKey: "masterVisible") as? Bool ?? true
        clickThrough = defaults.object(forKey: "clickThrough") as? Bool ?? false
        keystrokesEnabled = defaults.object(forKey: "keystrokesEnabled") as? Bool ?? false
        selectedID = items.first?.id
        lastRecordedText = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.text) })

        saveCancellable = objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    func save() {
        func store<T: Encodable>(_ value: T, _ key: String) {
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: key)
            }
        }
        recordRecents()
        store(items, "items")
        store(phrases, "phrases")
        store(recents, "recents")
        store(presets, "presets")
        store(toggleHotKey, "toggleHotKey")
        store(phraseHotKey, "phraseHotKey")
        defaults.set(masterVisible, forKey: "masterVisible")
        defaults.set(clickThrough, forKey: "clickThrough")
        defaults.set(keystrokesEnabled, forKey: "keystrokesEnabled")
    }

    /// Once a label's text settles (save is edit-debounced), remember it.
    private func recordRecents() {
        for item in items {
            let t = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, lastRecordedText[item.id] != item.text else { continue }
            lastRecordedText[item.id] = item.text
            recents.removeAll { $0 == t }
            recents.insert(t, at: 0)
            if recents.count > 10 { recents.removeLast(recents.count - 10) }
        }
    }

    // MARK: - Selection / items

    var selectedIndex: Int? {
        items.firstIndex { $0.id == selectedID }
    }

    var selectedItem: OverlayItem? {
        selectedIndex.map { items[$0] }
    }

    func addItem() {
        var item = OverlayItem(name: "Label \(items.count + 1)")
        if let current = selectedItem {  // new labels inherit the current style
            StylePreset(name: "", from: current).apply(to: &item)
        }
        items.append(item)
        selectedID = item.id
    }

    func removeSelected() {
        guard let idx = selectedIndex else { return }
        let id = items[idx].id
        countdowns[id] = nil
        countdownTemplates[id] = nil
        pausedCountdowns.remove(id)
        items.remove(at: idx)
        selectedID = items.first?.id
    }

    func updateSelected(_ mutate: (inout OverlayItem) -> Void) {
        guard let idx = selectedIndex else { return }
        mutate(&items[idx])
    }

    func updateItem(_ id: UUID, _ mutate: (inout OverlayItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    // MARK: - Phrases

    func applyText(_ text: String) {
        updateSelected { $0.text = text }
    }

    /// Cycle the selected label through the phrase list (global hotkey).
    func nextPhrase() {
        guard !phrases.isEmpty, let idx = selectedIndex else { return }
        let current = items[idx].text
        let next: String
        if let pos = phrases.firstIndex(of: current) {
            next = phrases[(pos + 1) % phrases.count]
        } else {
            next = phrases[0]
        }
        items[idx].text = next
    }

    // MARK: - Countdown

    /// Parse "10" (seconds), "10:00" (m:ss), or "1:30:00" (h:mm:ss) as seconds.
    static func parseDuration(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":").map(String.init)
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
        switch numbers.count {
        case 1: return numbers[0]
        case 2: return numbers[0] * 60 + numbers[1]
        case 3: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: return nil
        }
    }

    static func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(
                format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60,
                seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// What the overlay actually shows: live countdown if active, else the text.
    func displayText(for item: OverlayItem) -> String {
        guard let remaining = countdowns[item.id] else { return item.text }
        let time = Self.formatDuration(remaining)
        if let template = countdownTemplates[item.id] {
            return template.replacingOccurrences(
                of: Self.timePlaceholder, with: time)
        }
        return time
    }

    /// Start a countdown from the selected label's text. The text may be just
    /// a duration ("10", "10:00"), or contain one ("Break remaining - 10:00"),
    /// in which case only the time part ticks and the rest stays.
    func startCountdown() {
        guard let item = selectedItem else {
            NSSound.beep()
            return
        }
        let text = item.text
        if let range = text.ranges(of: #/(\d+:)?\d{1,2}:\d{2}/#).last,
            let seconds = Self.parseDuration(String(text[range]))
        {
            let rest = text.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            countdownTemplates[item.id] =
                rest.isEmpty
                ? nil
                : text.replacingCharacters(in: range, with: Self.timePlaceholder)
            countdowns[item.id] = seconds
        } else if let seconds = Self.parseDuration(text) {
            countdownTemplates[item.id] = nil
            countdowns[item.id] = seconds
        } else {
            NSSound.beep()
            return
        }
        pausedCountdowns.remove(item.id)
        // Starting a timer brings the label back on screen (it fades in),
        // e.g. after a "Show for Ns" fade-out.
        updateSelected { $0.visible = true }
        if !masterVisible { masterVisible = true }
    }

    func togglePauseCountdown(_ itemID: UUID? = nil) {
        guard let id = itemID ?? selectedItem?.id, countdowns[id] != nil else {
            return
        }
        if pausedCountdowns.contains(id) {
            pausedCountdowns.remove(id)
        } else {
            pausedCountdowns.insert(id)
        }
    }

    func resetCountdown() {
        guard let id = selectedItem?.id else { return }
        countdowns[id] = nil
        countdownTemplates[id] = nil
        pausedCountdowns.remove(id)
    }

    func tick() {
        guard !countdowns.isEmpty else { return }
        var changed = false
        for (id, remaining) in countdowns
        where remaining > 0 && !pausedCountdowns.contains(id) {
            countdowns[id] = remaining - 1
            changed = true
        }
        if changed { objectWillChange.send() }
    }

    // MARK: - Presets

    func savePreset(named name: String) {
        guard let item = selectedItem, !name.isEmpty else { return }
        presets.removeAll { $0.name == name }
        presets.append(StylePreset(name: name, from: item))
    }

    func applyPreset(_ preset: StylePreset) {
        updateSelected { preset.apply(to: &$0) }
    }
}
