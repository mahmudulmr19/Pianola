import Foundation
import Observation
import Sparkle

/// Automatic updates through Sparkle.
///
/// Pianola checks the feed in Info.plist (`SUFeedURL`, the appcast attached to
/// the latest GitHub release) once a day, and on demand from the app menu.
/// Updates must be signed with the key whose public half is `SUPublicEDKey`.
@Observable @MainActor
final class Updates {
    /// False in development builds that have no feed or key, and in screenshot
    /// and self-test runs, so Sparkle never complains there.
    let isAvailable: Bool
    private(set) var canCheck = false
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private let testDelegate: InstallRightAway?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = ProcessInfo.processInfo.environment
        isAvailable = info["SUFeedURL"] != nil && info["SUPublicEDKey"] != nil
            && environment["PIANOLA_SNAPSHOT"] == nil && environment["PIANOLA_SELFTEST"] == nil

        guard isAvailable else {
            controller = nil
            testDelegate = nil
            checksAutomatically = false
            return
        }
        // Scripts/test-update.sh: check in the background and install as soon as
        // the update is downloaded, so the whole path can be tested unattended.
        let testing = environment["PIANOLA_UPDATE_TEST"] != nil
        testDelegate = testing ? InstallRightAway() : nil
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: testDelegate, userDriverDelegate: nil)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        // Sparkle changes this on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
        Diagnostics.log("Updates: on, checking \(info["SUFeedURL"] ?? "")")
        if testing {
            controller.updater.automaticallyDownloadsUpdates = true
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func checkNow() {
        Diagnostics.log("Updates: checking now")
        controller?.checkForUpdates(nil)
    }

    /// Test only: installs a downloaded update straight away instead of at quit.
    private final class InstallRightAway: NSObject, SPUUpdaterDelegate {
        func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                     immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
            Diagnostics.log("Update test: \(item.displayVersionString) downloaded, installing now")
            immediateInstallHandler()
            return true
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
            Diagnostics.log("Update test: stopped: \(error.localizedDescription)")
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            Diagnostics.log("Update test: found \(item.displayVersionString)")
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
            Diagnostics.log("Update test: no update: \(error.localizedDescription)")
        }

        func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
            Diagnostics.log("Update test: downloaded \(item.displayVersionString)")
        }

        func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
            Diagnostics.log("Update test: download failed: \(error.localizedDescription)")
        }
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
