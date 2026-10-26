import PianolaCore
import SwiftUI

/// The 61-key Roblox piano, drawn with its keyboard letters. Held keys glow.
struct PianoKeyboardView: View {
    var held: Set<Int>

    private static let whites = KeyMap.allKeys.filter { !$0.isBlack }
    private static let whiteIndex: [Int: Int] = Dictionary(
        uniqueKeysWithValues: whites.enumerated().map { ($1.midi, $0) })

    var body: some View {
        Canvas { context, size in
            let feltHeight: CGFloat = 5
            let keyTop = feltHeight
            let keyHeight = size.height - feltHeight
            let whiteWidth = size.width / CGFloat(Self.whites.count)
            let blackWidth = whiteWidth * 0.6
            let blackHeight = keyHeight * 0.62
            let labelSize = min(11, max(8, whiteWidth * 0.46))

            for (index, key) in Self.whites.enumerated() {
                let rect = CGRect(x: CGFloat(index) * whiteWidth + 0.5, y: keyTop,
                                  width: whiteWidth - 1, height: keyHeight)
                let shape = Path(roundedRect: rect, cornerRadii: .init(
                    topLeading: 0, bottomLeading: 4, bottomTrailing: 4, topTrailing: 0))
                let down = held.contains(key.midi)
                if down {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Theme.accent.opacity(0.9), radius: 9))
                        layer.fill(shape, with: .linearGradient(
                            Gradient(colors: [Theme.accent.opacity(0.85), Theme.accent]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                    }
                } else {
                    context.fill(shape, with: .linearGradient(
                        Gradient(stops: [.init(color: Theme.ivoryShade, location: 0),
                                         .init(color: Theme.ivory, location: 0.18),
                                         .init(color: Theme.ivory, location: 0.92),
                                         .init(color: Theme.ivoryShade, location: 1)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
                let label = Text(String(key.label))
                    .font(.system(size: labelSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(down ? Theme.ebony : Color.black.opacity(0.42))
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - labelSize * 0.9))
                if key.midi % 12 == 0 {
                    // A small mark on every C, like the dots on a fretboard.
                    let dot = CGRect(x: rect.midX - 1.5, y: rect.maxY - labelSize * 2.2, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(down ? Theme.ebony.opacity(0.6) : Color.black.opacity(0.18)))
                }
            }

            for key in KeyMap.allKeys where key.isBlack {
                guard let left = Self.whiteIndex[key.midi - 1] else { continue }
                let rect = CGRect(x: CGFloat(left + 1) * whiteWidth - blackWidth / 2, y: keyTop,
                                  width: blackWidth, height: blackHeight)
                let shape = Path(roundedRect: rect, cornerRadii: .init(
                    topLeading: 0, bottomLeading: 3, bottomTrailing: 3, topTrailing: 0))
                let down = held.contains(key.midi)
                if down {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Theme.accent.opacity(0.9), radius: 8))
                        layer.fill(shape, with: .color(Theme.accent))
                    }
                } else {
                    context.fill(shape, with: .linearGradient(
                        Gradient(colors: [Theme.ebony, Theme.ebonyShine.opacity(0.9), Theme.ebony]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                    // Bevel at the front edge of the key.
                    let bevel = CGRect(x: rect.minX + 1.5, y: rect.maxY - 6, width: rect.width - 3, height: 4)
                    context.fill(Path(roundedRect: bevel, cornerRadius: 1.5), with: .color(.white.opacity(0.10)))
                }
                if blackWidth > 9 {
                    let label = Text(String(key.label))
                        .font(.system(size: labelSize * 0.82, weight: .semibold, design: .monospaced))
                        .foregroundStyle(down ? Theme.ebony : Color.white.opacity(0.5))
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - labelSize * 1.25))
                }
            }

            // Red felt strip along the back of the keys.
            let felt = CGRect(x: 0, y: 0, width: size.width, height: feltHeight)
            context.fill(Path(felt), with: .linearGradient(
                Gradient(colors: [Color(red: 0.42, green: 0.08, blue: 0.12), Color(red: 0.26, green: 0.04, blue: 0.07)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: feltHeight)))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .accessibilityElement()
        .accessibilityLabel("Piano keyboard")
    }
}
