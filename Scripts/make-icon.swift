// Draws Pianola's app icon as a 1024×1024 PNG.
//   swiftc Scripts/make-icon.swift -o build/make-icon && build/make-icon build/icon-1024.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

guard let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

// Body: the standard macOS icon grid, 824 points with continuous corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.45))
context.addPath(bodyPath)
context.setFillColor(color(0x0E0D15))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(bodyPath)
context.clip()

// Night background with a warm glow rising from the keys.
context.drawLinearGradient(gradient([color(0x221D33), color(0x0D0C14)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
context.drawRadialGradient(gradient([color(0xFFB84D, 0.55), color(0xFFB84D, 0)]),
                           startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 430), endRadius: 470, options: [])
context.drawRadialGradient(gradient([color(0xA894FF, 0.28), color(0xA894FF, 0)]),
                           startCenter: CGPoint(x: 820, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 820, y: 860), endRadius: 420, options: [])

// Keyboard: seven white keys with five black keys.
let keysTop: CGFloat = 470
let keysBottom: CGFloat = 100
let keyCount = 7
let margin: CGFloat = 0
let whiteWidth = (body.width - margin * 2) / CGFloat(keyCount)
let glowing = 2  // the third white key is being played

// Felt strip.
context.setFillColor(color(0x6B1420))
context.fill(CGRect(x: body.minX, y: keysTop, width: body.width, height: 16))

for index in 0..<keyCount {
    let rect = CGRect(x: body.minX + margin + CGFloat(index) * whiteWidth + 4, y: keysBottom - 40,
                      width: whiteWidth - 8, height: keysTop - keysBottom + 40)
    let path = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    if index == glowing {
        context.drawLinearGradient(gradient([color(0xFFD27A), color(0xFFA531)]),
                                   start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    } else {
        context.drawLinearGradient(gradient([color(0xD9D3C6), color(0xF7F3EA), color(0xEFEAE0)], [0, 0.25, 1]),
                                   start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    }
    context.restoreGState()
}

let blackAfter = [0, 1, 3, 4, 5]
let blackWidth = whiteWidth * 0.58
for index in blackAfter {
    let x = body.minX + margin + CGFloat(index + 1) * whiteWidth - blackWidth / 2
    let rect = CGRect(x: x, y: keysTop - 220, width: blackWidth, height: 220)
    let path = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: color(0x000000, 0.5))
    context.addPath(path)
    context.setFillColor(color(0x15141A))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient([color(0x2B2A33), color(0x101015)]),
                               start: CGPoint(x: rect.minX, y: rect.midY), end: CGPoint(x: rect.maxX, y: rect.midY), options: [])
    context.setFillColor(color(0xFFFFFF, 0.10))
    context.fill(CGRect(x: rect.minX + 10, y: rect.minY + 12, width: rect.width - 20, height: 14))
    context.restoreGState()
}

// A glowing note above the played key.
if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 300, weight: .semibold)) {
    let noteSize = symbol.size
    let noteRect = CGRect(x: 512 - noteSize.width / 2 + 10, y: 560, width: noteSize.width, height: noteSize.height)
    if let cg = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 60, color: color(0xFFB84D, 0.9))
        context.clip(to: noteRect, mask: cg)
        context.drawLinearGradient(gradient([color(0xFFE2A3), color(0xFFAA3A)]),
                                   start: CGPoint(x: 0, y: noteRect.maxY), end: CGPoint(x: 0, y: noteRect.minY), options: [])
        context.restoreGState()
    }
}

// Soft highlight along the top edge.
context.drawLinearGradient(gradient([color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 760), options: [])
context.restoreGState()

// Thin rim.
context.addPath(bodyPath)
context.setStrokeColor(color(0xFFFFFF, 0.08))
context.setLineWidth(3)
context.strokePath()

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
