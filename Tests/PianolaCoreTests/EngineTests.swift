import Foundation
import Testing
@testable import PianolaCore

// Rules come from https://pianoblox.com/guides/how-to-read-roblox-piano-sheets
// and the PianoBlox player that the guide's demos run on.

@Suite struct KeyMapTests {
    @Test func layoutHasSixtyOneKeys() {
        #expect(KeyMap.allKeys.count == 61)
        #expect(KeyMap.allKeys.filter(\.isBlack).count == 25)
        #expect(KeyMap.allKeys.first?.label == "1")
        #expect(KeyMap.allKeys.first?.noteName == "C2")
        #expect(KeyMap.allKeys.last?.label == "m")
        #expect(KeyMap.allKeys.last?.noteName == "C7")
        #expect(KeyMap.key(for: "t")?.noteName == "C4")
    }

    @Test func blackKeysAreShiftedWhiteKeys() throws {
        let s = try #require(KeyMap.key(for: "S"))
        #expect(s.isBlack && s.needsShift && s.baseKey == "s")
        #expect(KeyMap.key(for: "!")?.baseKey == "1")
        #expect(KeyMap.key(for: "(")?.baseKey == "9")
        #expect(KeyMap.key(for: "s")?.needsShift == false)
        // A sharp sits one semitone above its white key.
        #expect(KeyMap.key(for: "S")!.midi == KeyMap.key(for: "s")!.midi + 1)
    }

    @Test func charactersOffThePianoFollowThePianoBloxLookup() {
        // Upper-case letters without a black key play the white key.
        #expect(KeyMap.key(for: "A")?.label == "a")
        #expect(KeyMap.key(for: "M")?.label == "m")
        // These pass the sheet character check but are not keys.
        #expect(KeyMap.isSheetCharacter("#") && KeyMap.key(for: "#") == nil)
        #expect(KeyMap.isSheetCharacter("&") && KeyMap.key(for: "&") == nil)
        #expect(KeyMap.key(for: "é") == nil)
    }
}

@Suite struct ParserTests {
    func kinds(_ text: String) -> [EventKind] { SheetParser.parse(text).events.map(\.kind) }
    func durations(_ text: String) -> [Double] { SheetParser.parse(text).events.map(\.durationBeats) }

    @Test func singleNotesAreHalfABeatAndSpacesTakeNoTime() {
        #expect(durations("a s d") == [0.5, 0.5, 0.5])
        #expect(durations("asd") == [0.5, 0.5, 0.5])
        #expect(SheetParser.parse("a   s\td").totalBeats == 1.5)
    }

    @Test func bracketsMakeAChord() {
        let sheet = SheetParser.parse("[asd] [a s d]")
        #expect(sheet.events.count == 2)
        #expect(sheet.events.allSatisfy { $0.kind == .chord && $0.durationBeats == 0.8 })
        #expect(sheet.events[1].keys.map(\.label) == ["a", "s", "d"])
        #expect(sheet.events[1].startBeat == 0.8)
    }

    @Test func bracesMakeAFastRunAQuarterBeatPerKey() {
        #expect(SheetParser.parse("{asdf}").events.first?.durationBeats == 1.0)
        #expect(SheetParser.parse("{a s d}").events.first?.durationBeats == 0.75)
        #expect(SheetParser.parse("{a}").events.first?.durationBeats == 0.25)
    }

    @Test func dashesAndBarsArePauses() {
        #expect(durations("-") == [0.5])
        #expect(durations("--") == [1.0])
        #expect(durations("---") == [1.5])
        #expect(durations("|") == [1.0])
        #expect(durations("||") == [2.0])
        #expect(kinds("-|-") == [.rest, .rest, .rest])
        #expect(SheetParser.parse("a - s -- d").totalBeats == 3.0)
    }

    @Test func theGuidesMiniSheet() {
        let sheet = SheetParser.parse("a s d f - [ad] - {sdf} -- f d s a")
        // "This original 13-note exercise"
        #expect(sheet.noteCount == 13)
        #expect(sheet.events.count == 13)
        #expect(abs(sheet.totalBeats - 7.55) < 1e-9)
        #expect(sheet.events[5].kind == .chord && sheet.events[5].startBeat == 2.5)
        #expect(abs(sheet.events[7].startBeat - 3.8) < 1e-9)
        #expect(sheet.events[7].kind == .fast)
    }

    @Test func emptyAndInvalidGroupsAreSkipped() {
        #expect(SheetParser.parse("[]").events.isEmpty)
        #expect(SheetParser.parse("{}").totalBeats == 0)
        #expect(SheetParser.parse("[#&]").events.isEmpty)
        #expect(SheetParser.parse("# &").events.isEmpty)
        #expect(SheetParser.parse("[a#s]").events.first?.keys.map(\.label) == ["a", "s"])
    }

    @Test func unclosedBracketsReadAsNotes() {
        let sheet = SheetParser.parse("[asd")
        #expect(kinds("[asd") == [.note, .note, .note])
        #expect(sheet.ignoredCharacters == ["["])
        #expect(kinds("{qw") == [.note, .note])
        #expect(kinds("a]s}d") == [.note, .note, .note])
    }

    @Test func linesAndPositions() {
        let sheet = SheetParser.parse("ab\r\n\n[cd] e\nf")
        #expect(sheet.lines.map(\.number) == [1, 2, 3])
        #expect(sheet.lines.map(\.id) == [0, 2, 3])
        #expect(sheet.lines[1].events == 2..<4)
        #expect(sheet.events[2].raw == "[cd]")
        #expect(sheet.events[2].spacedBefore)
        #expect(!sheet.events[1].spacedBefore)
        #expect(sheet.events[3].spacedBefore)
        // A chord can span a line break; the line count does not move inside it.
        let spanning = SheetParser.parse("[a\nb] c")
        #expect(spanning.events.count == 2)
        #expect(spanning.events[1].line == 0)
    }

    @Test func findsTheEventAtABeat() {
        let sheet = SheetParser.parse("a [sd] - f")
        #expect(sheet.eventIndex(atBeat: 0) == 0)
        #expect(sheet.eventIndex(atBeat: 0.49) == 0)
        #expect(sheet.eventIndex(atBeat: 0.5) == 1)
        #expect(sheet.eventIndex(atBeat: 1.4) == 2)
        #expect(sheet.eventIndex(atBeat: 99) == 3)
        #expect(SheetParser.parse("").eventIndex(atBeat: 0) == nil)
    }
}

@Suite struct PlanTests {
    @Test func holdLengthsFollowThePianoBloxPlayer() {
        let plan = PlaybackPlan(SheetParser.parse("a [sd] {fgh}"))
        let a = plan.strikes[0]
        #expect(abs(a.holdBeats - 0.24) < 1e-9)          // 0.5 × 0.48
        #expect(abs(a.sustainHoldBeats - 0.45) < 1e-9)   // 0.5 × 0.9
        let chord = plan.strikes[1]
        #expect(abs(chord.holdBeats - 0.44) < 1e-9)      // 0.8 × 0.55
        #expect(abs(chord.sustainHoldBeats - 0.76) < 1e-9)
        let run = plan.strikes.filter { $0.eventIndex == 2 }
        #expect(run.map(\.beat) == [1.3, 1.55, 1.8])
        #expect(run.allSatisfy { abs($0.holdBeats - 0.55) < 1e-9 && $0.sustainHoldBeats == $0.holdBeats })
    }

    @Test func chordKeysPressTogetherOnce() {
        let plan = PlaybackPlan(SheetParser.parse("[aas]"))
        #expect(plan.strikes.map(\.key.label) == ["a", "s"])
        #expect(plan.strikes.allSatisfy { $0.beat == 0 })
    }

    @Test func findsTheFirstStrikeAtABeat() {
        let plan = PlaybackPlan(SheetParser.parse("a - s d"))
        #expect(plan.firstStrike(atOrAfter: 0) == 0)
        #expect(plan.firstStrike(atOrAfter: 0.6) == 1)
        #expect(plan.firstStrike(atOrAfter: 1.0) == 1)
        #expect(plan.firstStrike(atOrAfter: 9) == 3)
    }
}

/// Records key actions with the time they arrived.
final class Recorder: KeyOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(time: Double, action: KeyAction)] = []

    func send(_ actions: [KeyAction]) {
        let now = SheetPlayer.now()
        lock.withLock { log.append(contentsOf: actions.map { (now, $0) }) }
    }

    var entries: [(time: Double, action: KeyAction)] { lock.withLock { log } }

    var downs: [(time: Double, label: Character)] {
        entries.compactMap { if case .down(let key) = $0.action { ($0.time, key.label) } else { nil } }
    }

    var heldAtEnd: Set<Character> {
        var down = Set<Character>()
        for entry in entries {
            switch entry.action {
            case .down(let key): down.insert(key.baseKey)
            case .up(let key): down.remove(key.baseKey)
            }
        }
        return down
    }
}

func wait(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

@Suite(.serialized) struct PlayerTests {
    @Test func playsOnTime() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        // 120 bpm: a beat is 0.5 s, a note 0.25 s.
        player.play(PlaybackPlan(SheetParser.parse("a s d f [gh]")), bpm: 120, speed: 1, sustain: false)
        await wait(1.8)

        let downs = recorder.downs
        #expect(downs.map(\.label) == ["a", "s", "d", "f", "g", "h"])
        let start = downs[0].time
        let expected = [0.0, 0.25, 0.5, 0.75, 1.0, 1.0]
        var worst = 0.0
        for (down, target) in zip(downs, expected) { worst = max(worst, abs(down.time - start - target)) }
        print("worst timing error: \(String(format: "%.2f", worst * 1000)) ms")
        #expect(worst < 0.002)
        #expect(player.snapshot().state == .finished)
        #expect(recorder.heldAtEnd.isEmpty)
    }

    @Test func releasesAfterTheHoldTime() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("a")), bpm: 120, speed: 1, sustain: false)
        await wait(0.5)
        let entries = recorder.entries
        #expect(entries.count == 2)
        // 0.5 beat × 0.48 × 0.5 s
        #expect(abs(entries[1].time - entries[0].time - 0.12) < 0.002)
    }

    @Test func pressesAndReleasesStayOnTheClock() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("a s d f g h j k")), bpm: 120, speed: 1, sustain: false)
        await wait(2.3)
        let entries = recorder.entries
        #expect(entries.count == 16)
        let start = entries[0].time
        var worst = 0.0
        for (n, entry) in entries.enumerated() {
            // Presses every 0.25 s, each released 0.12 s later.
            let target = Double(n / 2) * 0.25 + (n.isMultiple(of: 2) ? 0 : 0.12)
            worst = max(worst, abs(entry.time - start - target))
        }
        print("worst press/release error: \(String(format: "%.2f", worst * 1000)) ms")
        #expect(worst < 0.002)
    }

    @Test func aRepeatedKeyIsReleasedBeforeItIsPressedAgain() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        // In a fast run each key is held 0.55 beat but the next comes 0.25 beat later.
        player.play(PlaybackPlan(SheetParser.parse("{aaS}")), bpm: 240, speed: 1, sustain: false)
        await wait(0.8)
        let actions = recorder.entries.map(\.action)
        let a = KeyMap.key(for: "a")!, s = KeyMap.key(for: "S")!
        #expect(actions.prefix(4) == [.down(a), .up(a), .down(a), .down(s)])
        #expect(recorder.heldAtEnd.isEmpty)
    }

    @Test func pauseReleasesKeysAndResumeCarriesOn() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("[asdf] g h")), bpm: 60, speed: 1, sustain: true)
        await wait(0.2)
        player.pause()
        await wait(0.05)
        #expect(player.snapshot().state == .paused)
        #expect(player.snapshot().heldKeys.isEmpty)
        #expect(recorder.heldAtEnd.isEmpty)
        let pausedBeat = player.snapshot().beat
        await wait(0.5)
        #expect(player.snapshot().beat == pausedBeat)
        #expect(recorder.downs.count == 4)
        player.resume()
        await wait(1.9)
        #expect(recorder.downs.map(\.label) == ["a", "s", "d", "f", "g", "h"])
        #expect(player.snapshot().state == .finished)
    }

    @Test func tempoCanChangeMidSong() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("a s d f")), bpm: 60, speed: 1, sustain: false)
        await wait(0.6)          // past "s", which lands at 0.5 s
        let changedAt = SheetPlayer.now()
        let beatAtChange = player.snapshot().beat
        player.setTempo(bpm: 60, speed: 2)
        await wait(0.8)
        let downs = recorder.downs
        #expect(downs.count == 4)
        // "d" sits on beat 1. At double speed the rest of the way takes half as long.
        let expected = changedAt + (1.0 - beatAtChange) * 0.5
        #expect(abs(downs[2].time - expected) < 0.005)
        #expect(abs(downs[3].time - downs[2].time - 0.25) < 0.005)
    }

    @Test func seekJumpsToABeat() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("a s d f g h")), bpm: 60, speed: 1, sustain: false)
        await wait(0.1)
        player.seek(toBeat: 1.5)   // notes sit on beats 0, 0.5, 1, 1.5, … so this is "f"
        await wait(1.7)
        #expect(recorder.downs.map(\.label) == ["a", "f", "g", "h"])
    }

    @Test func stopReleasesEverything() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        player.play(PlaybackPlan(SheetParser.parse("[qwerty]")), bpm: 30, speed: 1, sustain: true)
        await wait(0.1)
        #expect(player.snapshot().heldKeys.count == 6)
        player.stop()
        #expect(player.snapshot().heldKeys.isEmpty)
        #expect(recorder.heldAtEnd.isEmpty)
        #expect(player.snapshot().state == .idle)
    }

    @Test func startsPartWayThrough() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        let sheet = SheetParser.parse("a s {df} g")
        player.play(PlaybackPlan(sheet), fromBeat: sheet.events[2].startBeat, bpm: 120, speed: 1, sustain: false)
        await wait(0.7)
        #expect(recorder.downs.map(\.label) == ["d", "f", "g"])
    }
}
