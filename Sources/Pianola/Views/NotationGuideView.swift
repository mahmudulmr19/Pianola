import PianolaCore
import SwiftUI

/// The PianoBlox notation rules, as Pianola plays them.
struct NotationGuideView: View {
    private struct Rule: Identifiable {
        let id = UUID()
        let symbol: String
        let meaning: String
        let classic: String
        let pianoBlox: String
        let color: Color
    }

    private let rules: [Rule] = [
        Rule(symbol: "a s d", meaning: "Notes, left to right", classic: "½ each", pianoBlox: "½ each", color: Theme.ivory),
        Rule(symbol: "[asd]", meaning: "Chord, keys together", classic: "½", pianoBlox: "⅘", color: Theme.chord),
        Rule(symbol: "{asdf}", meaning: "Fast run, in order", classic: "½ in all", pianoBlox: "¼ per key", color: Theme.fast),
        Rule(symbol: "-", meaning: "Pause", classic: "½", pianoBlox: "½", color: .secondary),
        Rule(symbol: "--", meaning: "Longer pause", classic: "1", pianoBlox: "1", color: .secondary),
        Rule(symbol: "|", meaning: "Phrase break", classic: "none", pianoBlox: "1", color: .secondary),
        Rule(symbol: "S  !  @", meaning: "Black keys (Shift)", classic: "½ each", pianoBlox: "½ each", color: Theme.ivory),
        Rule(symbol: "space  ⏎", meaning: "Layout only", classic: "none", pianoBlox: "none", color: .secondary),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading a sheet").font(Theme.titleFont(20))
                Text("Each character is a key on the 61-key piano. Lengths are in beats; choose the timing per sheet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    Text("")
                    Text("")
                    Text("Classic").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("PianoBlox").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    GridRow {
                        Text(rule.symbol)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(rule.color)
                            .frame(minWidth: 82, alignment: .leading)
                        Text(rule.meaning)
                        Text(rule.classic)
                            .foregroundStyle(rule.classic == rule.pianoBlox ? Color.secondary : Theme.accent)
                            .monospacedDigit()
                        Text(rule.pianoBlox)
                            .foregroundStyle(rule.classic == rule.pianoBlox ? Color.secondary : Theme.fast)
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("At 100 BPM a beat lasts 0.6 s, so a single note is 0.3 s. Classic is the Hammerspoon version's timing: chords take the same time as notes, so they flow straight on. With Dash Holds on, q-w, q - w and q -- hold q for 2, 3 and 4 note-lengths.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Rules from the PianoBlox guide", destination: URL(string: "https://pianoblox.com/guides/how-to-read-roblox-piano-sheets")!)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 470)
    }
}
