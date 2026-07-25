# TextAdder

[![CI](https://github.com/ismayc/text-adder/actions/workflows/ci.yml/badge.svg)](https://github.com/ismayc/text-adder/actions/workflows/ci.yml)
[Project site](https://ismayc.github.io/text-adder/)

A macOS menu bar app that floats persistent, styled text overlays on top of
every window — for labeling things while screen sharing (e.g. text on top of
Chrome). Designed to complement DemoPro: DemoPro is ephemeral hand-drawn
annotation; TextAdder is pre-composed text that stays put — lower-thirds,
session titles, break timers, quick phrases.

## Run

Download `TextAdder.dmg` from the
[latest release](https://github.com/ismayc/text-adder/releases/latest), open
it, and drag TextAdder to Applications (first launch: right-click → Open, since
the app is ad-hoc signed). Or build from source:

```sh
swift run            # quick run from the terminal
./make-app.sh        # build TextAdder.app (move to /Applications, double-click)
./make-dmg.sh        # package TextAdder.app into a drag-to-install DMG
```

Tagging `v*` on GitHub builds the DMG on CI and attaches it to a release.

## Test

```sh
swift test           # with Xcode installed (this is what CI runs)
./run-tests.sh       # with Command Line Tools only — adds the CLT's bundled
                     # Swift Testing framework to SwiftPM's search paths
```

## Features

Click the text-box icon in the menu bar; the panel has four tabs.

**Labels** — multiple independent overlays, each with its own text
(multi-line, live-updating as you type), name, alignment, display (multi-
monitor), snap-to-position grid + lower-third button, countdown timer
(set the text to `10` = 10 s, `10:00` = 10 min, or `1:30:00` = h:mm:ss,
then press Start), and a
"Show for Ns then fade out" button.

**Style** — per label: font, bold, size (12–200 pt), text color, letter-
outline border width/color, drop shadow, background box (color + opacity),
overall opacity. Save named style presets and apply them to any label.

**Phrases** — a quick-phrase library: click to swap into the selected label,
plus your 10 most recent texts. The "next phrase" hotkey cycles the selected
label through the library from anywhere.

**Extras** — master show/hide, click-through lock, recordable hotkeys
(defaults: ⌃⌥T show/hide, ⌃⌥P next phrase, ⌃⌥ arrows nudge 10 px),
launch at login, and a KeyCastr-style keystroke display (requires
Accessibility permission; macOS prompts on first enable, then relaunch).

**On the overlay itself** — drag anywhere to move; drag the small corner
grip to resize the text; press and hold for 2 seconds to pause/resume a
countdown; positions and all settings persist across launches.
Overlays float above full-screen apps and follow you across Spaces without
stealing focus.
