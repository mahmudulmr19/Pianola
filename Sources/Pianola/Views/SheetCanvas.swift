import PianolaCore
import SwiftUI

/// The sheet drawn as notes: plain keys, chords, fast runs and pauses, each in
/// its own colour. Follows along while playing; click a note to start there.
struct SheetCanvas: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    @Environment(Performance.self) private var performance

    var body: some View {
        let live = performance.sheetID == sheet.id && performance.phase != .idle
        let current = live ? performance.currentEvent : nil
        let playedThrough = !live ? -1 : (performance.phase == .finished ? parsed.events.count : (current ?? -1))
        let marker = performance.startMarker?.sheet == sheet.id ? performance.startMarker?.event : nil
        let currentLine = current.flatMap { parsed.events.indices.contains($0) ? parsed.events[$0].line : nil }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(parsed.lines) { line in
                        SheetLineView(
                            line: line,
                            events: Array(parsed.events[line.events]),
                            current: current.flatMap { line.events.contains($0) ? $0 : nil },
                            playedThrough: min(max(playedThrough, line.events.lowerBound), line.events.upperBound),
                            marker: marker.flatMap { line.events.contains($0) ? $0 : nil },
                            onTap: { performance.jump(toEvent: $0, in: sheet) })
                            .equatable()
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .onChange(of: currentLine) { _, line in
                guard let line else { return }
                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }
}

struct SheetLineView: View, Equatable {
    let line: SheetLine
    let events: [SheetEvent]
    let current: Int?
    let playedThrough: Int
    let marker: Int?
    let onTap: (Int) -> Void

    nonisolated static func == (a: SheetLineView, b: SheetLineView) -> Bool {
        a.line == b.line && a.events == b.events && a.current == b.current
            && a.playedThrough == b.playedThrough && a.marker == b.marker
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(line.number)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(current != nil ? Theme.accent.opacity(0.9) : Color.secondary.opacity(0.55))
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 9)
            FlowLayout(rowSpacing: 8, defaultGap: 3) {
                ForEach(events) { event in
                    TokenChip(event: event, state: state(of: event))
                        .flowGap(event.spacedBefore ? 9 : 3)
                        .onTapGesture { onTap(event.id) }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(current != nil ? Theme.accent.opacity(0.055) : .clear))
        .animation(.easeOut(duration: 0.25), value: current != nil)
    }

    private func state(of event: SheetEvent) -> TokenChip.Status {
        if event.id == current { return .current }
        if event.id < playedThrough { return .played }
        if event.id == marker { return .marked }
        return .upcoming
    }
}

struct TokenChip: View {
    enum Status { case upcoming, played, current, marked }

    let event: SheetEvent
    let status: Status
    @State private var hovering = false

    init(event: SheetEvent, state: Status) {
        self.event = event
        self.status = state
    }

    private var tint: Color {
        switch event.kind {
        case .chord: Theme.chord
        case .fast: Theme.fast
        case .note, .rest: .white
        }
    }

    private var isBlackNote: Bool { event.kind == .note && event.keys.first?.isBlack == true }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: event.kind == .note ? 8 : 10, style: .continuous)
        content
            .padding(.horizontal, event.kind == .note ? 0 : 7)
            .frame(minWidth: event.kind == .rest ? 14 : 26, minHeight: 30)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: status == .marked ? 1.5 : 1,
                                                                    dash: status == .marked ? [3, 2.5] : [])))
            .shadow(color: status == .current ? Theme.accent.opacity(0.6) : .clear, radius: 10)
            .scaleEffect(status == .current ? 1.1 : (hovering ? 1.05 : 1))
            .opacity(status == .played ? 0.38 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: status)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .help(helpText)
    }

    @ViewBuilder private var content: some View {
        if event.kind == .rest {
            restGlyph
        } else {
            HStack(spacing: event.kind == .note ? 0 : 2) {
                ForEach(Array(event.keys.enumerated()), id: \.offset) { _, key in
                    Text(String(key.label))
                        .font(Theme.noteFont)
                        .foregroundStyle(textColor(black: key.isBlack))
                }
                if event.heldThrough {
                    // Held through the dashes after it.
                    Capsule()
                        .fill(textColor(black: false).opacity(0.7))
                        .frame(width: 12, height: 2.5)
                        .padding(.leading, 3)
                }
            }
            .padding(.horizontal, event.heldThrough && event.kind == .note ? 6 : 0)
        }
    }

    @ViewBuilder private var restGlyph: some View {
        let color = status == .current ? Theme.accent : Color.white.opacity(event.durationBeats == 0 ? 0.18 : 0.32)
        if event.raw.contains(where: { $0 != "-" && $0 != "|" }) {
            // A character that is not a key, counted as a pause.
            Text(event.raw)
                .font(Theme.noteFont)
                .foregroundStyle(color)
                .padding(.horizontal, 4)
        } else if event.raw.first == "|" {
            HStack(spacing: 3) {
                ForEach(0..<event.raw.count, id: \.self) { _ in
                    Capsule().fill(color).frame(width: 2, height: 18)
                }
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 3) {
                ForEach(0..<event.raw.count, id: \.self) { _ in
                    Capsule().fill(color).frame(width: 9, height: 3)
                }
            }
            .padding(.horizontal, 3)
        }
    }

    private func textColor(black: Bool) -> Color {
        if status == .current { return Theme.ebony }
        if status == .marked { return Theme.accent }
        switch event.kind {
        case .chord: return Color(red: 0.86, green: 0.83, blue: 1.0)
        case .fast: return Color(red: 0.72, green: 0.98, blue: 0.93)
        default: return black ? .white : Theme.ivory
        }
    }

    private var fill: Color {
        if status == .current { return event.kind == .rest ? Theme.accent.opacity(0.18) : Theme.accent }
        switch event.kind {
        case .rest: return .clear
        case .note: return isBlackNote ? Color.black.opacity(0.55) : Color.white.opacity(0.075)
        case .chord, .fast: return tint.opacity(0.15)
        }
    }

    private var stroke: Color {
        if status == .marked { return Theme.accent }
        if status == .current { return event.kind == .rest ? .clear : Theme.accent }
        switch event.kind {
        case .rest: return .clear
        case .note: return isBlackNote ? Color.white.opacity(0.16) : Color.white.opacity(0.05)
        case .chord, .fast: return tint.opacity(hovering ? 0.65 : 0.38)
        }
    }

    private var helpText: String {
        let names = event.keys.map(\.noteName).joined(separator: " ")
        let length = Self.beatsText(event.durationBeats)
        switch event.kind {
        case .note: return "\(names) · \(length) — click to play from here"
        case .chord: return "Chord \(names) · \(length) — click to play from here"
        case .fast: return "Fast run \(names) · \(length) — click to play from here"
        case .rest: return event.durationBeats == 0 ? "Phrase mark · takes no time" : "Pause · \(length)"
        }
    }

    static func beatsText(_ beats: Double) -> String {
        let whole = Int(beats)
        let fraction = beats - Double(whole)
        let symbol: String
        switch fraction {
        case 0.24...0.26: symbol = "¼"
        case 0.49...0.51: symbol = "½"
        case 0.74...0.76: symbol = "¾"
        case 0.79...0.81: symbol = "⅘"
        case 0: symbol = ""
        default: return String(format: "%.2f beats", beats)
        }
        let number = (whole > 0 ? "\(whole)" : "") + symbol
        return number + (beats > 1 ? " beats" : " beat")
    }
}
