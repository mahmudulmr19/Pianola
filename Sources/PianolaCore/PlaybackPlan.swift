import Foundation

/// One key press, placed on the beat grid.
public struct KeyStrike: Sendable, Hashable {
    public let beat: Double
    public let key: PianoKey
    public let eventIndex: Int
    /// How long the key stays down with sustain off, in beats. Zero means a
    /// short tap (`SheetPlayer.minimumHold`).
    public let holdBeats: Double
    /// How long the key stays down with sustain on, in beats.
    public let sustainHoldBeats: Double

    public func hold(sustain: Bool) -> Double { sustain ? sustainHoldBeats : holdBeats }
}

/// Every key press of a sheet in playing order. Everything is in beats, so
/// tempo can change while playing.
///
/// Classic (the original engine): with sustain on, every key is held for 95%
/// of its length, so it is let go just before the next note and chords flow
/// into what follows. With sustain off, keys are tapped. A dash hold keeps the
/// key down for 95% of the held length either way.
///
/// PianoBlox: a note is held for 48% of its length (90% with sustain), a chord
/// for 55% (95% with sustain), and each key of a fast run for up to 0.55 beat,
/// starting a quarter beat after the one before it.
public struct PlaybackPlan: Sendable {
    public let strikes: [KeyStrike]
    public let totalBeats: Double

    public init(_ sheet: ParsedSheet) {
        var ordered: [(order: Int, strike: KeyStrike)] = []
        for event in sheet.events where event.kind != .rest {
            // A chord presses each key once; a fast run may repeat a key on purpose.
            var seen = Set<Character>()
            let keys = event.kind == .chord ? event.keys.filter { seen.insert($0.label).inserted } : event.keys
            for (position, key) in keys.enumerated() {
                let (delay, dry, wet) = sheet.rules.style == .classic
                    ? Self.classic(event, keys.count, position)
                    : Self.pianoBlox(event, position)
                let strike = KeyStrike(beat: event.startBeat + delay, key: key, eventIndex: event.id,
                                       holdBeats: dry, sustainHoldBeats: wet)
                ordered.append((ordered.count, strike))
            }
        }
        ordered.sort { ($0.strike.beat, $0.order) < ($1.strike.beat, $1.order) }
        strikes = ordered.map(\.strike)
        totalBeats = sheet.totalBeats
    }

    private static func classic(_ event: SheetEvent, _ count: Int, _ position: Int) -> (Double, Double, Double) {
        var delay = 0.0
        var length = event.durationBeats
        var held = event.heldThrough
        if event.kind == .fast {
            let slot = SheetTiming.classicUnit / Double(count)
            delay = slot * Double(position)
            let isLast = position == count - 1
            length = isLast ? event.durationBeats - slot * Double(count - 1) : slot
            held = held && isLast
        }
        let sustained = length * 0.95
        return (delay, held ? sustained : 0, sustained)
    }

    private static func pianoBlox(_ event: SheetEvent, _ position: Int) -> (Double, Double, Double) {
        let length = event.durationBeats
        switch event.kind {
        case .fast:
            let hold = min(length, 0.55)
            return (SheetTiming.fastKeyBeats * Double(position), hold, hold)
        case .chord:
            return (0, length * 0.55, length * 0.95)
        default:
            return (0, length * 0.48, length * 0.9)
        }
    }

    /// Index of the first strike at or after `beat`.
    public func firstStrike(atOrAfter beat: Double) -> Int {
        var low = 0, high = strikes.count
        while low < high {
            let mid = (low + high) / 2
            if strikes[mid].beat < beat - 1e-9 { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
