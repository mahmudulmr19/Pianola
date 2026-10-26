import AppKit
import Foundation
import PianolaCore

/// A plain-text log at ~/Library/Logs/Pianola/pianola.log, so problems such as
/// a missing permission or the game not coming to the front can be traced.
enum Diagnostics {
    static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Pianola/pianola.log")
    private static let queue = DispatchQueue(label: "com.mahmudul.pianola.log")

    static func log(_ message: String) {
        let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n"
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > 1_000_000 {
                try? manager.removeItem(at: fileURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }

    @MainActor static func frontAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
    }
}

/// `PIANOLA_SELFTEST=/path/result.json` opens a small window with a text box,
/// plays a short sheet into it and writes what arrived. It checks the whole
/// path (permission, keyboard layout, Shift for black keys) without Roblox.
@MainActor
enum SelfTest {
    static let sheet = "a s d [fg] {hj} - k S ! Q"
    static let expected = "asdfghjkS!Q"

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["PIANOLA_SELFTEST"] else { return }
        let keyboard = SystemKeyboard()
        let player = SheetPlayer(output: keyboard)
        let window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 520, height: 140),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 140))
        text.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        window.title = "Pianola key test — please don't type"
        window.contentView = text
        window.level = .floating

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(text)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            let front = Diagnostics.frontAppName()
            let permission = CGPreflightPostEventAccess()
            Diagnostics.log("Self-test starting. Permission: \(permission). Front app: \(front)")
            // Keys go to whatever is in front, so only type when the test box is.
            if NSApp.isActive && window.isKeyWindow {
                player.play(PlaybackPlan(SheetParser.parse(sheet)), bpm: 120, speed: 1, sustain: false)
            } else {
                Diagnostics.log("Self-test skipped typing: its window is not in front")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                let typed = text.string
                let result: [String: Any] = [
                    "permission": permission,
                    "frontAppAtStart": front,
                    "keyWindowWasTest": window.isKeyWindow,
                    "keyEventsSent": keyboard.sentCount,
                    "typed": typed,
                    "expected": expected,
                    "pass": typed == expected,
                ]
                Diagnostics.log("Self-test typed \"\(typed)\" (expected \"\(expected)\")")
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                player.shutdown()
                exit(0)
            }
        }
    }
}
