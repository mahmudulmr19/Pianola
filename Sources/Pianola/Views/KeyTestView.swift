import AppKit
import Observation
import PianolaCore
import SwiftUI

/// Plays a short sheet into a text box inside Pianola and checks what arrives.
/// Tests permission, keyboard layout and Shift for black keys, without Roblox.
@Observable @MainActor
final class KeyTest {
    enum Status: Equatable {
        case ready, running, passed, failed(String)
    }

    var status = Status.ready
    var typed = ""
    @ObservationIgnored private let keyboard = SystemKeyboard()
    @ObservationIgnored private lazy var player = SheetPlayer(output: keyboard)

    func run() {
        typed = ""
        guard CGPreflightPostEventAccess() else {
            status = .failed("macOS isn't letting Pianola press keys yet. Turn Pianola on in System Settings → Privacy & Security → Accessibility, then test again.")
            Diagnostics.log("Key test: no permission")
            return
        }
        status = .running
        keyboard.refreshLayout()
        Task {
            // Let the text box take focus first.
            try? await Task.sleep(for: .milliseconds(400))
            guard NSApp.isActive else {
                status = .failed("Pianola has to be the front app for the test. Click this window and try again.")
                return
            }
            player.play(PlaybackPlan(SheetParser.parse(SelfTest.sheet)), bpm: 120, speed: 1, sustain: false)
            try? await Task.sleep(for: .seconds(3.0))
            evaluate()
        }
    }

    private func evaluate() {
        let got = typed.filter { !$0.isWhitespace }
        let expected = SelfTest.expected
        if got == expected {
            status = .passed
        } else if got.isEmpty {
            status = .failed("No keys arrived. macOS may still be blocking Pianola: in Privacy & Security → Accessibility, select Pianola, remove it with −, then press Open Settings in Pianola and turn it on again.")
        } else if got.lowercased() == expected.lowercased().replacingOccurrences(of: "!", with: "1") || got.lowercased() == expected.lowercased() {
            status = .failed("Letters arrive, but black keys came through without Shift (got \(got)).")
        } else {
            status = .failed("Some keys arrived, but not the right ones (got \(got), expected \(expected)). Is your keyboard layout set to something other than U.S.?")
        }
        Diagnostics.log("Key test typed \"\(typed)\" (expected \"\(expected)\"): \(status)")
    }
}

struct KeyTestView: View {
    @State private var test = KeyTest()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Test key presses").font(Theme.titleFont(22))
                Text("Pianola will type a short sheet into the box below, the same way it plays into Roblox. Don't type while it runs.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SheetTextView(text: $test.typed)
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))

            HStack(spacing: 6) {
                Text("Should type").foregroundStyle(.secondary)
                Text(SelfTest.expected).font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .font(.callout)

            result
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.2), value: test.status)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(test.status == .ready ? "Run Test" : "Run Again") { test.run() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.ebony)
                    .disabled(test.status == .running)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder private var result: some View {
        switch test.status {
        case .ready:
            EmptyView()
        case .running:
            Label("Typing…", systemImage: "keyboard").foregroundStyle(Theme.accent)
        case .passed:
            Label("Keys work, black keys included. You're ready to play in Roblox.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
