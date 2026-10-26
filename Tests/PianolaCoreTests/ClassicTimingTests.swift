import Foundation
import Testing
@testable import PianolaCore

// Classic timing is the original Hammerspoon engine. These cases come from its
// regression test (roblox-piano/test_root_sheet_rules.js). One note-length is
// half a beat, so at the same BPM a note lasts as long as it used to.

@Suite struct ClassicTimingTests {
    func parse(_ text: String, holds: Bool = false) -> ParsedSheet {
        SheetParser.parse(text, rules: SheetRules(style: .classic, dashHolds: holds))
    }

    func timeline(_ sheet: ParsedSheet) -> [String] {
        sheet.events.filter { $0.durationBeats > 0 }.map { event in
            let what = event.kind == .rest ? "rest" : event.keys.map { String($0.label) }.joined()
            return "\(what)@\(event.startBeat)/\(event.durationBeats)" + (event.heldThrough ? "h" : "")
        }
    }

    @Test func chordsLastOneNoteSoTheNextNoteFollowsStraightOn() {
        let sheet = parse("[tuo] p [ad] s")
        #expect(timeline(sheet) == ["tuo@0.0/0.5", "p@0.5/0.5", "ad@1.0/0.5", "s@1.5/0.5"])
    }

    @Test func spacesLineBreaksAndBarsAreLayoutOnly() {
        let sheet = parse("qw q |\n e")
        #expect(timeline(sheet) == ["q@0.0/0.5", "w@0.5/0.5", "q@1.0/0.5", "e@1.5/0.5"])
        #expect(sheet.totalBeats == 2.0)
        // The bar is still shown, as a zero-length mark.
        #expect(sheet.events.contains { $0.raw == "|" && $0.durationBeats == 0 })
    }

    @Test func withoutDashHoldsEveryDashIsANoteLengthPause() {
        let sheet = parse("q-w q - w q --")
        #expect(timeline(sheet) == ["q@0.0/0.5", "rest@0.5/0.5", "w@1.0/0.5", "q@1.5/0.5",
                                    "rest@2.0/0.5", "w@2.5/0.5", "q@3.0/0.5", "rest@3.5/1.0"])
    }

    @Test func dashHoldsHoldTheNoteInFront() {
        let sheet = parse("q-w q - w q --", holds: true)
        #expect(timeline(sheet) == ["q@0.0/1.0h", "w@1.0/0.5", "q@1.5/1.5h", "w@3.0/0.5", "q@3.5/2.0h"])
        #expect(timeline(parse("[qw]-e", holds: true)) == ["qw@0.0/1.0h", "e@1.0/0.5"])
        // A dash with no note in front is a single note-length rest.
        #expect(timeline(parse("--q", holds: true)) == ["rest@0.0/0.5", "q@0.5/0.5"])
        // Holds reach across a bar, and the bar moves with them.
        let barred = parse("q|-w", holds: true)
        #expect(timeline(barred) == ["q@0.0/1.0h", "w@1.0/0.5"])
        #expect(barred.events[1].raw == "|" && barred.events[1].startBeat == 1.0)
    }

    @Test func groupsKeepTheirOriginalLengths() {
        let sheet = parse("[qwer] [q w e r] {qwer} -")
        #expect(timeline(sheet) == ["qwer@0.0/0.5", "qwer@0.5/0.5", "qwer@1.0/0.5", "rest@1.5/0.5"])
        let run = PlaybackPlan(sheet).strikes.filter { $0.eventIndex == 2 }
        #expect(run.map(\.beat) == [1.0, 1.125, 1.25, 1.375])
    }

    @Test func otherCharactersAreANoteLengthOfSilence() {
        let sheet = parse("a?b–c")
        #expect(timeline(sheet) == ["a@0.0/0.5", "rest@0.5/0.5", "b@1.0/0.5", "rest@1.5/0.5", "c@2.0/0.5"])
        #expect(sheet.silentCharacters == ["?", "–"])
        #expect(sheet.ignoredCharacters.isEmpty)
    }

    @Test func withSustainKeysAreHeldUntilJustBeforeTheNextNote() {
        let plan = PlaybackPlan(parse("[tuo] p"))
        // Held for 95% of a note-length; tapped with sustain off.
        #expect(plan.strikes.map(\.sustainHoldBeats).allSatisfy { abs($0 - 0.475) < 1e-9 })
        #expect(plan.strikes.map(\.holdBeats).allSatisfy { $0 == 0 })
        let held = PlaybackPlan(parse("q-w", holds: true)).strikes[0]
        #expect(abs(held.holdBeats - 0.95) < 1e-9)
    }
}

@Suite(.serialized) struct ClassicPlayerTests {
    @Test func aChordHandsStraightOverToTheNextNote() async {
        let recorder = Recorder()
        let player = SheetPlayer(output: recorder)
        defer { player.shutdown() }
        // 120 BPM: a note-length is 0.25 s.
        let sheet = SheetParser.parse("[tuo] p [ad] s", rules: .classic)
        player.play(PlaybackPlan(sheet), bpm: 120, speed: 1, sustain: true)
        await wait(1.3)
        let downs = recorder.downs
        let start = downs[0].time
        let chordStarts = [0.0, 0.0, 0.0, 0.25, 0.5, 0.5, 0.75]
        #expect(downs.map(\.label) == ["t", "u", "o", "p", "a", "d", "s"])
        for (down, target) in zip(downs, chordStarts) { #expect(abs(down.time - start - target) < 0.002) }
        // The chord's keys are let go 0.2375 s in, 12.5 ms before "p".
        let ups = recorder.entries.filter { if case .up = $0.action { true } else { false } }
        #expect(abs(ups[0].time - start - 0.2375) < 0.002)
        #expect(recorder.heldAtEnd.isEmpty)
    }
}
