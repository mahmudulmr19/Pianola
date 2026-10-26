import Foundation

/// Which timing rules a sheet is read with.
public enum TimingStyle: String, Codable, Sendable, CaseIterable, Hashable {
    /// The original Hammerspoon engine: every note, chord and fast run lasts one
    /// note-length, so chords flow straight into the next note. `|` is layout only.
    case classic
    /// The PianoBlox player: chords last ⅘ beat, fast runs ¼ beat per key,
    /// and `|` is a one-beat pause.
    case pianoBlox
}

public struct SheetRules: Sendable, Hashable {
    public var style: TimingStyle
    /// Classic only: `q-w`, `q - w` and `q --` hold `q` instead of pausing.
    public var dashHolds: Bool

    public init(style: TimingStyle, dashHolds: Bool = false) {
        self.style = style
        self.dashHolds = dashHolds
    }

    public static let classic = SheetRules(style: .classic)
    public static let pianoBlox = SheetRules(style: .pianoBlox)
}

/// How long each symbol lasts, in beats.
public enum SheetTiming {
    // PianoBlox player values.
    /// A single key such as `a`.
    public static let noteBeats = 0.5
    /// A chord such as `[asd]`.
    public static let chordBeats = 0.8
    /// Each key of a fast run such as `{asdf}`; the run lasts this times its key count.
    public static let fastKeyBeats = 0.25
    /// Each `-`.
    public static let dashBeats = 0.5
    /// Each `|`.
    public static let barBeats = 1.0
    /// Spaces and line breaks are layout only.
    public static let spaceBeats = 0.0

    /// Classic: one note-length. Everything is a whole number of these, except
    /// the keys of a fast run, which share one.
    public static let classicUnit = 0.5
}

public enum EventKind: String, Sendable, Hashable {
    case note, chord, fast, rest
}

/// One thing that happens in a sheet: a note, a chord, a fast run or a rest.
public struct SheetEvent: Sendable, Identifiable, Hashable {
    public let id: Int
    public let kind: EventKind
    /// Keys it plays, in written order. Empty for rests.
    public let keys: [PianoKey]
    /// The text it came from, for example `[a s d]` or `--`.
    public let raw: String
    /// Source line, counting from 0.
    public let line: Int
    /// Position in the sheet, as character offsets.
    public let range: Range<Int>
    public internal(set) var startBeat: Double
    public internal(set) var durationBeats: Double
    /// Whether a space or the start of a line comes right before it.
    public let spacedBefore: Bool
    /// Classic with dash holds: the note is held through dashes after it, even with sustain off.
    public internal(set) var heldThrough = false

    public var endBeat: Double { startBeat + durationBeats }
}

/// A line of the sheet that has at least one event.
public struct SheetLine: Sendable, Identifiable, Hashable {
    /// Source line, counting from 0.
    public let id: Int
    /// Position among non-empty lines, counting from 1.
    public let number: Int
    /// Indices into `ParsedSheet.events`.
    public let events: Range<Int>
}

public struct ParsedSheet: Sendable {
    public let rules: SheetRules
    public let events: [SheetEvent]
    public let lines: [SheetLine]
    public let totalBeats: Double
    /// Characters that were skipped because they play nothing, such as `#` or a lone `[`.
    public let ignoredCharacters: [Character]
    /// Classic only: characters that are not keys but still take a note-length
    /// of silence, as they did in the original engine (`?`, `–`, `.`).
    public let silentCharacters: [Character]

    public static let empty = SheetParser.parse("")

    /// Number of key presses in the sheet.
    public var noteCount: Int { events.reduce(0) { $0 + $1.keys.count } }

    /// Largest number of keys pressed together.
    public var maxChord: Int {
        events.filter { $0.kind == .chord }.map(\.keys.count).max() ?? (noteCount > 0 ? 1 : 0)
    }

    public func seconds(bpm: Double, speed: Double = 1) -> Double {
        totalBeats * Tempo.secondsPerBeat(bpm: bpm, speed: speed)
    }

    /// The event sounding at `beat`: the last one that started at or before it.
    public func eventIndex(atBeat beat: Double) -> Int? {
        guard !events.isEmpty, beat >= events[0].startBeat else { return nil }
        var low = 0, high = events.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if events[mid].startBeat <= beat + 1e-9 { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

public enum Tempo {
    public static let minBPM = 20.0
    public static let maxBPM = 400.0
    public static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    public static func secondsPerBeat(bpm: Double, speed: Double = 1) -> Double {
        60 / (max(1, bpm) * max(0.05, speed))
    }
}

public enum SheetParser {
    public static func parse(_ text: String, rules: SheetRules = .pianoBlox) -> ParsedSheet {
        var builder = Builder(chars: Array(text))
        switch rules.style {
        case .pianoBlox: builder.readPianoBlox()
        case .classic: builder.readClassic(dashHolds: rules.dashHolds)
        }
        return builder.finish(rules: rules)
    }

    private struct Builder {
        let chars: [Character]
        var events: [SheetEvent] = []
        var beat = 0.0
        var line = 0
        var index = 0
        var spaced = true
        var ignored: [Character] = []
        var silent: [Character] = []

        init(chars: [Character]) { self.chars = chars }

        mutating func ignore(_ ch: Character) {
            if !ignored.contains(ch) { ignored.append(ch) }
        }

        func isNewline(_ ch: Character) -> Bool { ch == "\n" || ch == "\r" || ch == "\r\n" }

        func closing(_ close: Character, after start: Int) -> Int? {
            var j = start + 1
            while j < chars.count {
                if chars[j] == close { return j }
                j += 1
            }
            return nil
        }

        /// Adds an event. Notes, chords and runs with no playable key are dropped.
        @discardableResult
        mutating func emit(_ kind: EventKind, _ start: Int, _ end: Int, _ written: [Character],
                           duration: (Int) -> Double) -> Int? {
            var keys: [PianoKey] = []
            for ch in written {
                if let key = KeyMap.key(for: ch) { keys.append(key) } else { ignore(ch) }
            }
            if kind != .rest && keys.isEmpty { return nil }
            let length = duration(keys.count)
            events.append(SheetEvent(
                id: events.count, kind: kind, keys: keys,
                raw: String(chars[start..<end]), line: line, range: start..<end,
                startBeat: beat, durationBeats: length, spacedBefore: spaced))
            beat += length
            spaced = false
            return events.count - 1
        }

        /// Shared handling of line breaks and spaces. Returns true if it used the character.
        mutating func layout(_ ch: Character) -> Bool {
            if isNewline(ch) {
                line += 1
                spaced = true
                index += 1
                return true
            }
            if ch == " " || ch == "\t" {
                spaced = true
                index += 1
                return true
            }
            return false
        }

        // MARK: PianoBlox

        /// - Letters, digits and `!@$%^*(` are single notes, read left to right.
        /// - `[asd]` is a chord. Spaces inside it are only for reading.
        /// - `{asdf}` is a fast run: same order, a quarter beat between keys.
        /// - `-` waits half a beat and `--` a whole beat. `|` waits one beat.
        /// - Spaces, tabs and line breaks take no time.
        /// - A `[` or `{` with no closing bracket is skipped and what follows reads as notes.
        mutating func readPianoBlox() {
            while index < chars.count {
                let ch = chars[index]
                if layout(ch) { continue }
                if ch == "[" || ch == "{", let close = closing(ch == "[" ? "]" : "}", after: index) {
                    let inside = chars[(index + 1)..<close].filter(KeyMap.isSheetCharacter)
                    if ch == "[" {
                        emit(.chord, index, close + 1, Array(inside)) { _ in SheetTiming.chordBeats }
                    } else {
                        emit(.fast, index, close + 1, Array(inside)) { max(SheetTiming.fastKeyBeats, Double($0) * SheetTiming.fastKeyBeats) }
                    }
                    index = close + 1
                    continue
                }
                if ch == "-" || ch == "|" {
                    let end = run(of: ch)
                    let count = Double(end - index)
                    let each = ch == "-" ? SheetTiming.dashBeats : SheetTiming.barBeats
                    emit(.rest, index, end, []) { _ in count * each }
                    index = end
                    continue
                }
                if KeyMap.isSheetCharacter(ch) {
                    emit(.note, index, index + 1, [ch]) { _ in SheetTiming.noteBeats }
                    index += 1
                    continue
                }
                if !ch.isWhitespace { ignore(ch) }
                index += 1
            }
        }

        // MARK: Classic

        /// The rules of the original Hammerspoon engine:
        /// - Every note, chord `[asd]` and fast run `{asd}` lasts one note-length
        ///   (half a beat). A fast run's keys share that length.
        /// - Each `-` is a note-length pause. With dash holds on, `q-w` holds `q`
        ///   for 2 lengths, `q - w` for 3 and `q --` for 4.
        /// - `|`, spaces and line breaks take no time.
        /// - Any other character is a note-length of silence.
        mutating func readClassic(dashHolds: Bool) {
            let unit = SheetTiming.classicUnit
            var lastNote: Int?
            var spacedDash = false

            while index < chars.count {
                let ch = chars[index]
                if isNewline(ch) || ch == " " || ch == "\t" {
                    // A dash after a space is the dotted hold form.
                    var j = index
                    while j < chars.count && (isNewline(chars[j]) || chars[j].isWhitespace) {
                        if isNewline(chars[j]) { line += 1 }
                        j += 1
                    }
                    if j < chars.count && chars[j] == "-" { spacedDash = true }
                    spaced = true
                    index = j
                    continue
                }
                if ch == "[" || ch == "{", let close = closing(ch == "[" ? "]" : "}", after: index) {
                    let inside = chars[(index + 1)..<close].filter { !$0.isWhitespace && $0 != "|" }
                    if ch == "[" {
                        if let added = emit(.chord, index, close + 1, Array(inside), duration: { _ in unit }) {
                            lastNote = added
                        } else if !inside.isEmpty {
                            // Brackets around non-keys still took a note-length.
                            lastNote = emit(.rest, index, close + 1, []) { _ in unit }
                        }
                    } else if let added = emit(.fast, index, close + 1, Array(inside), duration: { _ in unit }) {
                        lastNote = added
                    }
                    spacedDash = false
                    index = close + 1
                    continue
                }
                if ch == "-" {
                    let end = run(of: "-")
                    let count = end - index
                    if !dashHolds {
                        emit(.rest, index, end, []) { _ in Double(count) * unit }
                        lastNote = nil
                    } else {
                        var look = end
                        while look < chars.count && (chars[look].isWhitespace || chars[look] == "|") { look += 1 }
                        let noteFollows = look < chars.count && chars[look] != "-"
                        if let held = lastNote, !spacedDash || count >= 2 || noteFollows {
                            let units = count >= 2 ? 4.0 : (spacedDash ? 3.0 : 2.0)
                            hold(held, toUnits: units)
                        } else {
                            emit(.rest, index, end, []) { _ in unit }
                            lastNote = nil
                        }
                    }
                    spacedDash = false
                    index = end
                    continue
                }
                if ch == "|" {
                    // Phrase mark: shown, but takes no time.
                    emit(.rest, index, index + 1, []) { _ in 0 }
                    spaced = true
                    index += 1
                    continue
                }
                if let added = emit(.note, index, index + 1, [ch], duration: { _ in unit }) {
                    lastNote = added
                } else if !ch.isWhitespace {
                    if !silent.contains(ch) { silent.append(ch) }
                    ignored.removeAll { $0 == ch }
                    lastNote = emit(.rest, index, index + 1, []) { _ in unit }
                }
                spacedDash = false
                index += 1
            }
        }

        /// Classic dash hold: the note in front now lasts `units` note-lengths.
        /// For a fast run, only its last key grows.
        mutating func hold(_ position: Int, toUnits units: Double) {
            let unit = SheetTiming.classicUnit
            var event = events[position]
            let newLength: Double
            if event.kind == .fast && event.keys.count > 1 {
                let slot = unit / Double(event.keys.count)
                newLength = slot * Double(event.keys.count - 1) + units * unit
            } else {
                newLength = units * unit
            }
            let delta = newLength - event.durationBeats
            event.durationBeats = newLength
            event.heldThrough = true
            events[position] = event
            // Only zero-length phrase marks can come after it; move them along.
            for later in (position + 1)..<events.count { events[later].startBeat += delta }
            beat += delta
        }

        func run(of ch: Character) -> Int {
            var j = index
            while j < chars.count && chars[j] == ch { j += 1 }
            return j
        }

        func finish(rules: SheetRules) -> ParsedSheet {
            var lines: [SheetLine] = []
            var start = 0
            while start < events.count {
                var end = start
                while end < events.count && events[end].line == events[start].line { end += 1 }
                lines.append(SheetLine(id: events[start].line, number: lines.count + 1, events: start..<end))
                start = end
            }
            return ParsedSheet(rules: rules, events: events, lines: lines, totalBeats: beat,
                               ignoredCharacters: ignored, silentCharacters: silent)
        }
    }
}
