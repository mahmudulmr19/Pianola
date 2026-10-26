import AppKit
import Observation

/// Whether Pianola may press keys in other apps (Privacy & Security → Accessibility).
@Observable @MainActor
final class Permissions {
    private(set) var canPressKeys = CGPreflightPostEventAccess()
    /// Shows the key test sheet in the main window.
    var showingKeyTest = false
    @ObservationIgnored private var timer: Timer?

    init() {
        // Keep checking while access is missing, so the app notices the moment it is granted.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let now = CGPreflightPostEventAccess()
        if now != canPressKeys {
            canPressKeys = now
            Diagnostics.log("Permission to press keys changed: \(now)")
        }
    }

    /// Shows the system prompt that adds Pianola to the Accessibility list.
    func request() {
        _ = CGRequestPostEventAccess()
        refresh()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
