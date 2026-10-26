import SwiftUI

/// Colours and shared styling. Pianola always uses its dark "stage" look.
enum Theme {
    /// Warm amber for the note being played and for primary actions.
    static let accent = Color(red: 1.00, green: 0.72, blue: 0.30)
    /// Chords.
    static let chord = Color(red: 0.66, green: 0.58, blue: 1.00)
    /// Fast runs.
    static let fast = Color(red: 0.30, green: 0.86, blue: 0.78)
    /// Ivory and ebony for the keyboard.
    static let ivory = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let ivoryShade = Color(red: 0.83, green: 0.80, blue: 0.74)
    static let ebony = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let ebonyShine = Color(red: 0.24, green: 0.24, blue: 0.28)

    static let stageTop = Color(red: 0.075, green: 0.074, blue: 0.095)
    static let stageBottom = Color(red: 0.055, green: 0.050, blue: 0.075)

    static func titleFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static let noteFont = Font.system(size: 15, weight: .medium, design: .monospaced)
}

/// The window background: a deep gradient with a soft warm glow at the top.
struct StageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.stageTop, Theme.stageBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           center: .init(x: 0.5, y: -0.1), startRadius: 10, endRadius: 620)
            RadialGradient(colors: [Theme.chord.opacity(0.07), .clear],
                           center: .init(x: 1.0, y: 1.0), startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// A small rounded label used for sheet facts such as "325 notes".
struct InfoPill: View {
    var systemImage: String
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.10)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

/// A quiet round button for secondary actions such as Stop.
struct RoundIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        RoundIconButton(configuration: configuration, diameter: diameter)
    }

    private struct RoundIconButton: View {
        let configuration: ButtonStyleConfiguration
        let diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.ivory.opacity(isEnabled ? 0.92 : 0.35))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.20 : (hovering && isEnabled ? 0.14 : 0.09))))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

extension Double {
    /// "2:15" style time.
    var clockText: String {
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
