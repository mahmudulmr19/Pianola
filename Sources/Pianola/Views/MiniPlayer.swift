import AppKit
import PianolaCore
import SwiftUI

/// A small floating glass player shown over the game while playing.
/// It never takes keyboard focus, so the game keeps receiving the keys.
@MainActor
final class MiniPlayerWindow {
    private let panel: FloatingPanel
    private var placed = false

    init(performance: Performance) {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: MiniPlayerView.size.width, height: MiniPlayerView.size.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: MiniPlayerView(performance: performance))
    }

    func show() {
        if !placed {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - MiniPlayerView.size.width / 2,
                                             y: frame.maxY - MiniPlayerView.size.height - 18))
            }
            placed = true
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    var window: NSWindow { panel }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct MiniPlayerView: View {
    static let size = CGSize(width: 560, height: 96)
    let performance: Performance

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(performance.title.isEmpty ? "Pianola" : performance.title)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                UpcomingNotes(performance: performance)
                MiniProgress(performance: performance)
            }
            Button { performance.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(RoundIconButtonStyle(diameter: 32))
            .help("Stop (⌃⌥S)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: Self.size.width - 16, height: Self.size.height - 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.32)))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .top) {
            if let toast = performance.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.ebony)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent))
                    .offset(y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: performance.toast)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder private var leading: some View {
        switch performance.phase {
        case .countingIn(let n):
            ZStack {
                Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(n) / CGFloat(max(1, performance.settings.countIn)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: n)
                Text(n > 0 ? "\(n)" : "•")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 46, height: 46)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
        default:
            Button { performance.togglePlayPause(nil) } label: {
                Image(systemName: performance.phase == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ebony)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(Theme.accent)
            .help(performance.phase == .playing ? "Pause (⌃⌥P)" : "Resume (⌃⌥P)")
        }
    }

    private var status: String {
        switch performance.phase {
        case .countingIn:
            if performance.transpose != 0 {
                return "Set piano transpose to \(performance.transpose > 0 ? "+" : "")\(performance.transpose)"
            }
            return performance.targetName.isEmpty ? "Switch to your game" : "Get ready in \(performance.targetName)"
        case .playing: return "\(Int(performance.bpm)) BPM\(performance.speed == 1 ? "" : " · \(SpeedMenu.label(performance.speed))")  ·  ⌃⌥P pause  ·  ⌃⌥S stop"
        case .paused(let reason): return reason ?? "Paused"
        case .finished: return "Finished"
        case .idle: return ""
        }
    }

    private var statusColor: Color {
        switch performance.phase {
        case .countingIn: performance.transpose != 0 ? Theme.accent : .secondary
        case .paused: .orange
        default: .secondary
        }
    }
}

/// The current note and the next few, so you can see what is coming.
private struct UpcomingNotes: View {
    let performance: Performance

    var body: some View {
        let events = performance.parsed.events
        let start = performance.currentEvent ?? 0
        let window = events.isEmpty ? [] : Array(events[min(start, events.count - 1)..<min(events.count, start + 12)])
        HStack(spacing: 4) {
            ForEach(window) { event in
                Text(event.kind == .rest ? event.raw : event.keys.map { String($0.label) }.joined())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(event.id == performance.currentEvent ? Theme.ebony : color(for: event))
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(event.id == performance.currentEvent ? Theme.accent : color(for: event).opacity(0.13)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .clipped()
        .animation(.easeOut(duration: 0.12), value: performance.currentEvent)
    }

    private func color(for event: SheetEvent) -> Color {
        switch event.kind {
        case .chord: Theme.chord
        case .fast: Theme.fast
        case .rest: .secondary
        case .note: Theme.ivory
        }
    }
}

private struct MiniProgress: View {
    let performance: Performance

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Theme.accent).frame(width: max(4, geo.size.width * performance.progress))
                }
            }
            .frame(height: 4)
            Text("\(performance.elapsed.clockText) / \(performance.duration.clockText)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
