import Foundation
import PianolaCore

// pianola-cli: prints what the engine makes of a sheet.
//
//   pianola-cli info  < sheet.txt          summary and timing
//   pianola-cli events < sheet.txt         every event
//   pianola-cli json  < sheets.json        parse a JSON array of sheets, print JSON
//   pianola-cli plan [bpm] < sheet.txt     every key press with times in seconds
//
// Timing is Classic unless "pianoblox" is given; add "holds" for dash holds.

let arguments = CommandLine.arguments.dropFirst()
let command = arguments.first ?? "info"
// Add "pianoblox" for PianoBlox timing and "holds" for Classic dash holds.
let rules = SheetRules(style: arguments.contains("pianoblox") ? .pianoBlox : .classic,
                       dashHolds: arguments.contains("holds"))
let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)

func format(_ value: Double) -> String { String(format: "%.3f", value) }

switch command {
case "json":
    let sheets = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String] ?? []
    let output: [[String: Any]] = sheets.map { text in
        let sheet = SheetParser.parse(text, rules: rules)
        return [
            "totalBeats": sheet.totalBeats,
            "strikes": PlaybackPlan(sheet).strikes.map { [String($0.key.label), $0.beat] as [Any] },
            "events": sheet.events.map { event -> [String: Any] in
                ["kind": event.kind.rawValue,
                 "keys": event.keys.map { String($0.label) },
                 "startBeat": event.startBeat,
                 "durationBeats": event.durationBeats]
            },
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))

case "events":
    for event in SheetParser.parse(input, rules: rules).events {
        let keys = event.keys.map { String($0.label) }.joined()
        print("\(format(event.startBeat))  +\(format(event.durationBeats))  \(event.kind.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))  \(event.raw)  → \(keys)")
    }

case "plan":
    let bpm = arguments.compactMap(Double.init).first ?? 100
    let spb = Tempo.secondsPerBeat(bpm: bpm)
    for strike in PlaybackPlan(SheetParser.parse(input, rules: rules)).strikes {
        let shift = strike.key.needsShift ? "⇧" : " "
        print("\(format(strike.beat * spb))s  \(shift)\(strike.key.baseKey)  hold \(format(strike.holdBeats * spb))s  (\(strike.key.noteName))")
    }

default:
    let sheet = SheetParser.parse(input, rules: rules)
    print("events      \(sheet.events.count)")
    print("notes       \(sheet.noteCount)")
    print("max chord   \(sheet.maxChord)")
    print("lines       \(sheet.lines.count)")
    print("beats       \(format(sheet.totalBeats))")
    for bpm in [72.0, 100, 120] {
        let seconds = sheet.seconds(bpm: bpm)
        print("at \(Int(bpm)) bpm   \(Int(seconds) / 60)m \(String(format: "%02d", Int(seconds) % 60))s")
    }
    if !sheet.ignoredCharacters.isEmpty {
        print("ignored     \(String(sheet.ignoredCharacters))")
    }
}
