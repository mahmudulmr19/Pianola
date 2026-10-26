import Foundation
import Observation

/// App-wide preferences, stored in UserDefaults.
@Observable @MainActor
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// The app that receives the key presses. Empty means whichever app is in front.
    var targetApp: String { didSet { defaults.set(targetApp, forKey: "targetApp") } }
    /// Seconds to count down before the first note.
    var countIn: Int { didSet { defaults.set(countIn, forKey: "countIn") } }
    /// Pause when the target app stops being the frontmost app, so keys never land elsewhere.
    var autoPause: Bool { didSet { defaults.set(autoPause, forKey: "autoPause") } }
    /// Show the floating mini player over the game while playing.
    var showMiniPlayer: Bool { didSet { defaults.set(showMiniPlayer, forKey: "showMiniPlayer") } }

    init() {
        defaults.register(defaults: [
            "targetApp": "Roblox", "countIn": 3, "autoPause": true, "showMiniPlayer": true,
        ])
        targetApp = defaults.string(forKey: "targetApp") ?? "Roblox"
        countIn = defaults.integer(forKey: "countIn")
        autoPause = defaults.bool(forKey: "autoPause")
        showMiniPlayer = defaults.bool(forKey: "showMiniPlayer")
    }

    var targetName: String { targetApp.trimmingCharacters(in: .whitespacesAndNewlines) }
}
