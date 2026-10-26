import PianolaCore
import SwiftUI

/// The glass panel at the bottom: transport, progress, tempo and the keyboard.
struct ControlDeck: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    @Environment(Library.self) private var library
    @Environment(Performance.self) private var performance

    var body: some View {
        let live = performance.isShowing(sheet.id)
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                PlayButton(sheet: sheet, parsed: parsed)
                Button { performance.stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(RoundIconButtonStyle(diameter: 40))
                .disabled(!live)
                .help("Stop (⌃⌥S)")

                PlaybackProgress(sheet: sheet, parsed: parsed)
            }

            HStack(spacing: 12) {
                StepperField(title: "BPM", value: Binding(
                    get: { sheet.bpm },
                    set: { value in library.update(sheet.id) { $0.bpm = value } }),
                    range: Tempo.minBPM...Tempo.maxBPM, step: 1,
                    help: "Beats per minute. Use the BPM printed on the sheet's page. ⌃⌥[ and ⌃⌥] change it while playing.")

                SpeedMenu(speed: Binding(
                    get: { sheet.speed },
                    set: { value in library.update(sheet.id) { $0.speed = value } }))

                TimingMenu(sheet: sheet, locked: live && performance.phase.isRunning)

                StepperField(title: "Transpose", value: Binding(
                    get: { Double(sheet.transpose) },
                    set: { value in library.update(sheet.id) { $0.transpose = Int(value) } }),
                    range: -12...12, step: 1, signed: true, highlight: sheet.transpose != 0,
                    help: "A reminder for this song. Set the same transpose on the Roblox piano; Pianola types the letters as written.")

                Toggle(isOn: Binding(
                    get: { sheet.sustain },
                    set: { value in library.update(sheet.id) { $0.sustain = value } })) {
                    Text("Sustain").font(.callout.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Hold each key almost to the next note instead of tapping it.")

                Spacer(minLength: 0)
            }

            PianoKeyboardView(held: live ? performance.heldKeys : [])
                .frame(height: 86)
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

/// The big round play / pause button.
struct PlayButton: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    @Environment(Performance.self) private var performance

    var body: some View {
        let live = performance.sheetID == sheet.id
        let icon: String = switch (live, performance.phase) {
        case (true, .playing): "pause.fill"
        case (true, .countingIn): "xmark"
        default: "play.fill"
        }
        Button {
            if live && performance.phase.isRunning {
                performance.togglePlayPause(sheet)
            } else {
                performance.play(sheet)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ebony)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Theme.accent)
        .controlSize(.extraLarge)
        .disabled(parsed.noteCount == 0)
        .help(live && performance.phase == .playing ? "Pause (⌃⌥P)" : "Play into \(performance.settings.targetName.isEmpty ? "the front app" : performance.settings.targetName) (⌃⌥P)")
    }
}

/// Progress bar with times. Reads the position every frame, so it is kept on
/// its own to avoid redrawing the rest of the deck.
struct PlaybackProgress: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    @Environment(Performance.self) private var performance

    var body: some View {
        let live = performance.isShowing(sheet.id)
        let spb = Tempo.secondsPerBeat(bpm: sheet.bpm, speed: sheet.speed)
        let total = parsed.totalBeats * spb
        let markerBeat: Double? = performance.startMarker?.sheet == sheet.id
            ? performance.startMarker.flatMap { parsed.events.indices.contains($0.event) ? parsed.events[$0.event].startBeat : nil }
            : nil
        let progress = live ? performance.progress : (markerBeat.map { parsed.totalBeats > 0 ? $0 / parsed.totalBeats : 0 } ?? 0)
        let elapsed = live ? performance.elapsed : (markerBeat ?? 0) * spb

        VStack(spacing: 6) {
            Scrubber(progress: progress, isMarker: !live && markerBeat != nil) { fraction in
                performance.scrub(to: fraction, in: sheet, parsed: parsed)
            }
            HStack {
                Text(elapsed.clockText)
                Spacer()
                Text(statusText(live: live))
                    .foregroundStyle(statusColor(live: live))
                    .contentTransition(.opacity)
                Spacer()
                Text(total.clockText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func statusText(live: Bool) -> String {
        guard live else {
            if performance.startMarker?.sheet == sheet.id { return "Starts from the marked note" }
            return "Ready"
        }
        switch performance.phase {
        case .countingIn(let n): return n > 0 ? "Starting in \(n)…" : "Starting…"
        case .playing: return performance.targetName.isEmpty ? "Playing" : "Playing into \(performance.targetName)"
        case .paused(let reason): return reason.map { "Paused — \($0)" } ?? "Paused"
        case .finished: return "Finished"
        case .idle: return "Ready"
        }
    }

    private func statusColor(live: Bool) -> Color {
        guard live else { return .secondary }
        switch performance.phase {
        case .playing, .countingIn: return Theme.accent
        case .paused: return .orange
        default: return .secondary
        }
    }
}

struct Scrubber: View {
    var progress: Double
    var isMarker: Bool
    var onScrub: (Double) -> Void
    @State private var dragging: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let value = dragging ?? progress
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(isMarker ? 0.35 : 0.7),
                                                  Theme.accent.opacity(isMarker ? 0.5 : 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, width * value))
                Circle()
                    .fill(Theme.ivory)
                    .frame(width: hovering || dragging != nil ? 13 : 9)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: width * value - (hovering || dragging != nil ? 6.5 : 4.5))
            }
            .frame(height: hovering || dragging != nil ? 7 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragging = min(1, max(0, $0.location.x / max(1, width))) }
                .onEnded { value in
                    onScrub(min(1, max(0, value.location.x / max(1, width))))
                    dragging = nil
                })
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .frame(height: 16)
        .help("Drag to choose where to play from")
    }
}

/// "BPM − 100 +" style control. Hold a button to repeat.
struct StepperField: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var signed = false
    var highlight = false
    var help: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlight ? Theme.accent : .secondary)
                .padding(.trailing, 4)
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonRepeatBehavior(.enabled)
            TextField(title, value: Binding(
                get: { value },
                set: { value = min(range.upperBound, max(range.lowerBound, $0.rounded())) }),
                format: signed ? .number.sign(strategy: .always(includingZero: false)) : .number)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(highlight ? Theme.accent : .primary)
                .frame(width: signed ? 34 : 40)
            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonRepeatBehavior(.enabled)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(highlight ? 0.09 : 0.06)))
        .overlay(Capsule().strokeBorder(highlight ? Theme.accent.opacity(0.35) : Color.white.opacity(0.06)))
        .help(help)
    }
}

/// Classic (the original engine) or PianoBlox timing, plus dash holds.
struct TimingMenu: View {
    let sheet: SavedSheet
    var locked: Bool
    @Environment(Library.self) private var library

    var body: some View {
        Menu {
            Picker("Timing", selection: Binding(
                get: { sheet.timing },
                set: { value in library.update(sheet.id) { $0.timing = value } })) {
                Text("Classic: chords flow into the next note").tag(TimingStyle.classic)
                Text("PianoBlox: chords ⅘ beat, | pauses a beat").tag(TimingStyle.pianoBlox)
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Dashes hold the note before them", isOn: Binding(
                get: { sheet.dashHolds },
                set: { value in library.update(sheet.id) { $0.dashHolds = value } }))
                .disabled(sheet.timing != .classic)
        } label: {
            HStack(spacing: 6) {
                Text("Timing").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(sheet.timing == .classic ? "Classic" : "PianoBlox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(sheet.timing == .classic ? Color.primary : Theme.fast)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        .disabled(locked)
        .help(locked ? "Stop playing to change the timing"
              : "Classic: every note and chord lasts the same, like the Hammerspoon version. PianoBlox: the PianoBlox website's rules.")
    }
}

struct SpeedMenu: View {
    @Binding var speed: Double

    var body: some View {
        Menu {
            Picker("Speed", selection: $speed) {
                ForEach(Tempo.speeds, id: \.self) { value in
                    Text(Self.label(value)).tag(value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text("Speed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Self.label(speed))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(speed == 1 ? Color.primary : Theme.accent)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        .help("Practise slower, then build up: 0.5× → 0.75× → 1×")
    }

    static func label(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
