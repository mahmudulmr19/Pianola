# Pianola

A Mac app that plays Roblox piano sheets for you. Paste a sheet, set the BPM,
press Play, and Pianola types the notes into Roblox, with the timing of the
original Hammerspoon engine or of the [PianoBlox guide](https://pianoblox.com/guides/how-to-read-roblox-piano-sheets).

## Build and run

```bash
Scripts/build-app.sh
open build/Pianola.app
```

Needs macOS 26 or later and the Xcode Command Line Tools. The first time you
press Play, macOS asks you to allow Pianola under **System Settings → Privacy &
Security → Accessibility**. Pianola needs that to press keys in Roblox.

The app is signed ad hoc, by its bundle identifier, so the Accessibility
permission stays granted across rebuilds. **Test Keys** in the toolbar checks
that key presses arrive, without Roblox. Pianola writes what it does to
`~/Library/Logs/Pianola/pianola.log`.

## Using it

1. Copy a sheet from PianoBlox (or any Roblox sheet site) and paste it in **Edit**.
2. Type the BPM shown on the song's page.
3. Open Roblox and sit at a piano, then press Play. Pianola brings Roblox to the
   front, counts down from 3 and plays.

Click any note in the sheet to start from there. If you click away from Roblox,
playback pauses so keys never land in another app.

| Shortcut | Works in any app |
| --- | --- |
| `⌃⌥P` | Play / pause |
| `⌃⌥S` | Stop |
| `⌃⌥[` `⌃⌥]` | 5 BPM slower / faster |

Inside the app: `⌘N` new sheet, `⌘⇧V` new sheet from the clipboard, `⌘↩`
play, `⌘.` stop.

The old Hammerspoon piano script uses the same `⌃⌥` shortcuts. Turn it off so
the two don't both react. **File → Import from Hammerspoon** copies its saved
sheets into Pianola.

## How sheets are timed

Each sheet has a **Timing** setting in the control panel. A beat lasts
`60 / (BPM × speed)` seconds.

**Classic** (default) is the Hammerspoon version's engine. Chords take the same
time as a note, so they flow straight into the next one. It matches the old
engine key for key on all 20 imported sheets.

**PianoBlox** follows the [PianoBlox guide](https://pianoblox.com/guides/how-to-read-roblox-piano-sheets)
and their player.

| Written | Meaning | Classic | PianoBlox |
| --- | --- | --- | --- |
| `a s d` or `asd` | notes, left to right | ½ beat each | ½ beat each |
| `[asd]` | chord, pressed together | ½ beat | ⅘ beat |
| `{asdf}` | fast run, in order | ½ beat in all | ¼ beat per key |
| `-` | pause | ½ beat | ½ beat |
| `--` | pause | 1 beat | 1 beat |
| `\|` | phrase break | none | 1 beat |
| spaces, line breaks | layout only | none | none |
| `?` `–` `.` and other symbols | not keys | ½ beat of silence | skipped |

With **Dash Holds** on (Classic only), `q-w` holds `q` for 2 note-lengths,
`q - w` for 3 and `q --` for 4, instead of pausing.

Capital letters and `!@$%^*(` are black keys, typed with Shift. A capital
letter with no black key (such as `A`) plays the white key.

**Sustain** (on by default) holds each key until just before the next note,
which is what makes chords connect. With it off, keys are tapped (Classic) or
held for about half their length (PianoBlox).

**Transpose** is a reminder you keep with each sheet. Set the same value on the
Roblox piano. Pianola always types the letters as written.

## Project layout

- `Sources/PianolaCore`: the engine, with no UI code.
  - `KeyMap.swift`: the 61-key layout (C2–C7) and which keys need Shift.
  - `SheetParser.swift`: reads a sheet into notes, chords, fast runs and pauses, each placed on a beat.
  - `PlaybackPlan.swift`: turns those into key presses with hold lengths.
  - `SheetPlayer.swift`: the real-time player. It runs one clock on a real-time
    thread, keeps positions in beats so tempo can change mid-song, and treats
    a system freeze as a pause.
- `Sources/Pianola`: the SwiftUI app. It sends keyboard events, handles the
  library, global shortcuts, the floating mini player and the Accessibility
  check.
- `Sources/PianolaCLI`: `pianola-cli` prints what the engine makes of a sheet:
  `swift run pianola-cli events < sheet.txt`.
- `Tests/PianolaCoreTests`: parser, timing and real-time player tests.

```bash
Scripts/test.sh
```

The player tests run sheets in real time and check that every key press and
release lands within 2 ms of its target. On a normal run the worst case is
about 0.1 ms.
