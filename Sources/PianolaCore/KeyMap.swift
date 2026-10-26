import Foundation

/// One key of the 61-key Roblox piano (C2 to C7).
public struct PianoKey: Hashable, Sendable, Identifiable, CustomStringConvertible {
    /// The character a sheet uses for this key, for example "a", "S" or "!".
    public let label: Character
    public let midi: Int
    public let isBlack: Bool
    /// The physical keyboard key that plays it: "s" for "S", "1" for "!".
    public let baseKey: Character

    public var id: Int { midi }
    /// Black keys are typed with Shift held.
    public var needsShift: Bool { isBlack }
    public var description: String { String(label) }

    /// Note name such as "C4" or "F#3", useful for tooltips.
    public var noteName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[midi % 12] + String(midi / 12 - 1)
    }
}

/// The PianoBlox keyboard layout.
///
/// White keys run through `1234567890qwertyuiopasdfghjklzxcvbnm` from the lowest
/// note up, and black keys through `!@$%^*(QWETYIOPSDGHJLZCVB`. Lookups follow the
/// PianoBlox player: a character is used as written when it is on the piano,
/// otherwise its lower-case form is tried, so "A" plays "a". Anything else,
/// including "#" and "&", is not a key.
public enum KeyMap {
    public static let lowestMidi = 36
    public static let highestMidi = 96

    static let whiteLabels = Array("1234567890qwertyuiopasdfghjklzxcvbnm")
    static let blackLabels = Array("!@$%^*(QWETYIOPSDGHJLZCVB")
    static let shiftedDigits: [Character: Character] = [
        "!": "1", "@": "2", "$": "4", "%": "5", "^": "6", "*": "8", "(": "9",
    ]

    /// All 61 keys, lowest first.
    public static let allKeys: [PianoKey] = {
        var keys: [PianoKey] = []
        var white = 0, black = 0
        for midi in lowestMidi...highestMidi {
            let isBlack = [1, 3, 6, 8, 10].contains(midi % 12)
            let label: Character
            if isBlack { label = blackLabels[black]; black += 1 } else { label = whiteLabels[white]; white += 1 }
            let base: Character = isBlack
                ? (shiftedDigits[label] ?? Character(label.lowercased()))
                : label
            keys.append(PianoKey(label: label, midi: midi, isBlack: isBlack, baseKey: base))
        }
        return keys
    }()

    static let byLabel: [Character: PianoKey] =
        Dictionary(uniqueKeysWithValues: allKeys.map { ($0.label, $0) })

    /// The characters a sheet may use for notes, exactly as the PianoBlox
    /// parser reads them (`[a-zA-Z0-9!@#$%^&*()]`).
    public static func isSheetCharacter(_ ch: Character) -> Bool {
        guard let ascii = ch.asciiValue else { return false }
        switch ascii {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return "!@#$%^&*()".contains(ch)
        }
    }

    /// The piano key a sheet character plays, or nil if it plays nothing.
    public static func key(for ch: Character) -> PianoKey? {
        if let key = byLabel[ch] { return key }
        let lower = ch.lowercased()
        if lower.count == 1, let key = byLabel[Character(lower)] { return key }
        return nil
    }

    public static func key(midi: Int) -> PianoKey? {
        guard midi >= lowestMidi, midi <= highestMidi else { return nil }
        return allKeys[midi - lowestMidi]
    }
}
