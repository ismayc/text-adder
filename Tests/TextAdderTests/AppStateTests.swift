import AppKit
import Testing

@testable import TextAdder

/// Fresh AppState backed by an isolated, empty UserDefaults suite.
func makeState() -> AppState {
    let suite = "TextAdderTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return AppState(defaults: defaults)
}

@Suite struct DurationTests {
    @Test func parseBareNumberIsSeconds() {
        #expect(AppState.parseDuration("10") == 10)
        #expect(AppState.parseDuration("90") == 90)
        #expect(AppState.parseDuration(" 5 ") == 5)
    }

    @Test func parseMinutesSeconds() {
        #expect(AppState.parseDuration("10:00") == 600)
        #expect(AppState.parseDuration("1:30") == 90)
    }

    @Test func parseHoursMinutesSeconds() {
        #expect(AppState.parseDuration("1:30:00") == 5400)
        #expect(AppState.parseDuration("0:00:05") == 5)
    }

    @Test func parseInvalid() {
        #expect(AppState.parseDuration("") == nil)
        #expect(AppState.parseDuration("hello") == nil)
        #expect(AppState.parseDuration("1:2:3:4") == nil)
        #expect(AppState.parseDuration("10:xx") == nil)
        #expect(AppState.parseDuration(":") == nil)
    }

    @Test func formatUnderAnHour() {
        #expect(AppState.formatDuration(0) == "0:00")
        #expect(AppState.formatDuration(10) == "0:10")
        #expect(AppState.formatDuration(600) == "10:00")
        #expect(AppState.formatDuration(3599) == "59:59")
    }

    @Test func formatAnHourAndOver() {
        #expect(AppState.formatDuration(3600) == "1:00:00")
        #expect(AppState.formatDuration(5400) == "1:30:00")
        #expect(AppState.formatDuration(3661) == "1:01:01")
    }
}

@Suite struct AppStateItemTests {
    @Test func freshStateHasOneSelectedItem() {
        let state = makeState()
        #expect(state.items.count == 1)
        #expect(state.selectedID == state.items[0].id)
        #expect(state.selectedItem != nil)
        #expect(state.selectedIndex == 0)
        #expect(!state.phrases.isEmpty)
    }

    @Test func addItemInheritsStyleAndSelects() {
        let state = makeState()
        state.updateSelected {
            $0.fontSize = 99
            $0.textColorHex = "#112233FF"
        }
        state.addItem()
        #expect(state.items.count == 2)
        #expect(state.selectedID == state.items[1].id)
        #expect(state.items[1].fontSize == 99)
        #expect(state.items[1].textColorHex == "#112233FF")
        #expect(state.items[1].name == "Label 2")
    }

    @Test func removeSelectedCleansCountdownAndReselects() {
        let state = makeState()
        state.addItem()
        state.applyText("10")
        state.startCountdown()
        let removedID = state.items[1].id
        #expect(state.countdowns[removedID] != nil)

        state.removeSelected()
        #expect(state.items.count == 1)
        #expect(state.selectedID == state.items[0].id)
        #expect(state.countdowns[removedID] == nil)
    }

    @Test func removeWithNoSelectionIsNoOp() {
        let state = makeState()
        state.selectedID = nil
        state.removeSelected()
        #expect(state.items.count == 1)
    }

    @Test func updateSelectedAndUpdateItem() {
        let state = makeState()
        state.updateSelected { $0.name = "Renamed" }
        #expect(state.items[0].name == "Renamed")

        state.updateItem(state.items[0].id) { $0.visible = false }
        #expect(!state.items[0].visible)

        state.updateItem(UUID()) { $0.name = "Ghost" }  // unknown id: no-op
        #expect(state.items[0].name == "Renamed")

        state.selectedID = nil
        state.updateSelected { $0.name = "Nope" }
        #expect(state.items[0].name == "Renamed")
    }
}

@Suite struct AppStatePhraseTests {
    @Test func applyText() {
        let state = makeState()
        state.applyText("On screen")
        #expect(state.selectedItem?.text == "On screen")
    }

    @Test func nextPhraseFromOutsideListStartsAtFirst() {
        let state = makeState()
        state.phrases = ["One", "Two", "Three"]
        state.applyText("not in list")
        state.nextPhrase()
        #expect(state.selectedItem?.text == "One")
    }

    @Test func nextPhraseCyclesAndWraps() {
        let state = makeState()
        state.phrases = ["One", "Two"]
        state.applyText("One")
        state.nextPhrase()
        #expect(state.selectedItem?.text == "Two")
        state.nextPhrase()
        #expect(state.selectedItem?.text == "One")
    }

    @Test func nextPhraseNoPhrasesOrNoSelectionIsNoOp() {
        let state = makeState()
        state.phrases = []
        state.applyText("keep me")
        state.nextPhrase()
        #expect(state.selectedItem?.text == "keep me")

        state.phrases = ["One"]
        state.selectedID = nil
        state.nextPhrase()
        #expect(state.items[0].text == "keep me")
    }
}

@Suite struct AppStateCountdownTests {
    @Test func bareSecondsCountdown() {
        let state = makeState()
        state.applyText("10")
        state.startCountdown()
        #expect(state.countdowns[state.items[0].id] == 10)
        #expect(state.displayText(for: state.items[0]) == "0:10")
    }

    @Test func wholeTextTimeCountdown() {
        let state = makeState()
        state.applyText("10:00")
        state.startCountdown()
        #expect(state.countdowns[state.items[0].id] == 600)
        #expect(state.displayText(for: state.items[0]) == "10:00")
    }

    @Test func embeddedCountdownKeepsSurroundingText() {
        let state = makeState()
        state.applyText("Break time remaining - 10:00")
        state.startCountdown()
        #expect(
            state.displayText(for: state.items[0])
                == "Break time remaining - 10:00")
        state.tick()
        #expect(
            state.displayText(for: state.items[0])
                == "Break time remaining - 9:59")
        // The stored text is never overwritten by the ticking display.
        #expect(state.items[0].text == "Break time remaining - 10:00")
    }

    @Test func embeddedCountdownUsesLastTimeToken() {
        let state = makeState()
        state.applyText("Back at 2:15 - 0:30")
        state.startCountdown()
        #expect(state.countdowns[state.items[0].id] == 30)
        state.tick()
        #expect(state.displayText(for: state.items[0]) == "Back at 2:15 - 0:29")
    }

    @Test func invalidTextDoesNotStart() {
        let state = makeState()
        state.applyText("hello world")
        state.startCountdown()
        #expect(state.countdowns.isEmpty)
    }

    @Test func noSelectionDoesNotStart() {
        let state = makeState()
        state.selectedID = nil
        state.startCountdown()
        #expect(state.countdowns.isEmpty)
    }

    @Test func startUnhidesLabelAndMaster() {
        let state = makeState()
        state.updateSelected { $0.visible = false }
        state.masterVisible = false
        state.applyText("5")
        state.startCountdown()
        #expect(state.items[0].visible)
        #expect(state.masterVisible)
    }

    @Test func startClearsExistingPause() {
        let state = makeState()
        state.applyText("5")
        state.startCountdown()
        state.togglePauseCountdown()
        #expect(!state.pausedCountdowns.isEmpty)
        state.startCountdown()
        #expect(state.pausedCountdowns.isEmpty)
    }

    @Test func tickDecrementsAndStopsAtZero() {
        let state = makeState()
        state.applyText("2")
        state.startCountdown()
        let id = state.items[0].id
        state.tick()
        #expect(state.countdowns[id] == 1)
        state.tick()
        #expect(state.countdowns[id] == 0)
        state.tick()
        #expect(state.countdowns[id] == 0)  // stays at zero
    }

    @Test func tickWithNoCountdownsIsNoOp() {
        let state = makeState()
        state.tick()
        #expect(state.countdowns.isEmpty)
    }

    @Test func pauseHaltsTicksAndResumeContinues() {
        let state = makeState()
        state.applyText("10")
        state.startCountdown()
        let id = state.items[0].id

        state.togglePauseCountdown()
        #expect(state.pausedCountdowns.contains(id))
        state.tick()
        #expect(state.countdowns[id] == 10)

        state.togglePauseCountdown()
        #expect(!state.pausedCountdowns.contains(id))
        state.tick()
        #expect(state.countdowns[id] == 9)
    }

    @Test func togglePauseByExplicitID() {
        let state = makeState()
        state.applyText("10")
        state.startCountdown()
        let id = state.items[0].id
        state.selectedID = nil  // explicit id must work without selection
        state.togglePauseCountdown(id)
        #expect(state.pausedCountdowns.contains(id))
    }

    @Test func togglePauseWithoutCountdownIsNoOp() {
        let state = makeState()
        state.togglePauseCountdown()
        #expect(state.pausedCountdowns.isEmpty)
    }

    @Test func resetRestoresOriginalText() {
        let state = makeState()
        state.applyText("Break - 0:30")
        state.startCountdown()
        state.togglePauseCountdown()
        state.resetCountdown()
        #expect(state.countdowns.isEmpty)
        #expect(state.pausedCountdowns.isEmpty)
        #expect(state.displayText(for: state.items[0]) == "Break - 0:30")
    }

    @Test func resetWithNoSelectionIsNoOp() {
        let state = makeState()
        state.selectedID = nil
        state.resetCountdown()
        #expect(state.countdowns.isEmpty)
    }
}

@Suite struct AppStatePresetTests {
    @Test func saveAndApplyPreset() {
        let state = makeState()
        state.updateSelected {
            $0.fontSize = 120
            $0.boxEnabled = true
            $0.shadowEnabled = true
        }
        state.savePreset(named: "Big")
        #expect(state.presets.count == 1)

        state.addItem()
        state.updateSelected { $0.fontSize = 20 }
        state.applyPreset(state.presets[0])
        #expect(state.selectedItem?.fontSize == 120)
        #expect(state.selectedItem?.boxEnabled == true)
        #expect(state.selectedItem?.shadowEnabled == true)
    }

    @Test func presetDoesNotChangeTextOrPosition() {
        let state = makeState()
        state.savePreset(named: "Style")
        state.applyText("my words")
        state.updateSelected { $0.originX = 42 }
        state.applyPreset(state.presets[0])
        #expect(state.selectedItem?.text == "my words")
        #expect(state.selectedItem?.originX == 42)
    }

    @Test func samePresetNameReplaces() {
        let state = makeState()
        state.updateSelected { $0.fontSize = 50 }
        state.savePreset(named: "A")
        state.updateSelected { $0.fontSize = 60 }
        state.savePreset(named: "A")
        #expect(state.presets.count == 1)
        #expect(state.presets[0].fontSize == 60)
    }

    @Test func emptyNameOrNoSelectionIsNoOp() {
        let state = makeState()
        state.savePreset(named: "")
        #expect(state.presets.isEmpty)
        state.selectedID = nil
        state.savePreset(named: "X")
        #expect(state.presets.isEmpty)
    }
}

@Suite struct AppStatePersistenceTests {
    @Test func roundTripThroughDefaults() {
        let suite = "TextAdderTests-roundtrip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let state = AppState(defaults: defaults)
        state.applyText("persisted text")
        state.phrases = ["p1", "p2"]
        state.presets = [StylePreset(name: "P", from: state.items[0])]
        state.masterVisible = false
        state.clickThrough = true
        state.keystrokesEnabled = true
        state.toggleHotKey = HotKeyCombo(keyCode: 1, modifiers: 256, display: "⌘S")
        state.phraseHotKey = HotKeyCombo(keyCode: 2, modifiers: 512, display: "⇧D")
        state.save()

        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.items[0].text == "persisted text")
        #expect(reloaded.phrases == ["p1", "p2"])
        #expect(reloaded.presets.map(\.name) == ["P"])
        #expect(!reloaded.masterVisible)
        #expect(reloaded.clickThrough)
        #expect(reloaded.keystrokesEnabled)
        #expect(reloaded.toggleHotKey.display == "⌘S")
        #expect(reloaded.phraseHotKey.display == "⇧D")
    }

    @Test func recentsRecordSettledTextsNewestFirst() {
        let state = makeState()
        state.applyText("first")
        state.save()
        state.applyText("second")
        state.save()
        #expect(Array(state.recents.prefix(2)) == ["second", "first"])
    }

    @Test func recentsDeduplicateAndCapAtTen() {
        let state = makeState()
        state.applyText("repeat")
        state.save()
        state.applyText("other")
        state.save()
        state.applyText("repeat")
        state.save()
        #expect(state.recents.filter { $0 == "repeat" }.count == 1)
        #expect(state.recents.first == "repeat")

        for i in 0..<12 {
            state.applyText("text \(i)")
            state.save()
        }
        #expect(state.recents.count == 10)
        #expect(state.recents.first == "text 11")
    }

    @Test func blankTextIsNotRecorded() {
        let state = makeState()
        state.applyText("   \n")
        state.save()
        #expect(!state.recents.contains { $0.isEmpty })
        #expect(!state.recents.contains("   \n"))
    }

    @Test func unchangedTextIsNotReRecorded() {
        let state = makeState()
        state.save()
        // Initial text was seeded as already-recorded; saving without edits
        // must not add it.
        #expect(state.recents.isEmpty)
    }
}
