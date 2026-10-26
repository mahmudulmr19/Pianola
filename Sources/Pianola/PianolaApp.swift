import AppKit
import PianolaCore
import SwiftUI

@main
struct PianolaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Pianola", id: "main") {
            RootView()
                .environment(model.library)
                .environment(model.performance)
                .environment(model.permissions)
                .environment(model.settings)
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1220, height: 820)
        .windowToolbarStyle(.unified)
        .commands { PianolaCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model.library)
                .environment(model.permissions)
                .environment(model.settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Owns the app's long-lived objects.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let library = Library()
    let permissions = Permissions()
    let hotKeys = HotKeys()
    let performance: Performance

    private init() {
        performance = Performance(settings: settings)
    }

    var selectedSheet: SavedSheet? { library.sheet(library.selection) }

    func handle(_ action: HotKeys.Action) {
        Diagnostics.log("Shortcut \(action.symbol) (\(performance.phase))")
        switch action {
        case .playPause:
            if performance.phase.isRunning {
                performance.togglePlayPause(nil)
            } else if let sheet = selectedSheet {
                performance.play(sheet)
            }
        case .stop:
            performance.stop()
        case .slower:
            nudgeTempo(by: -5)
        case .faster:
            nudgeTempo(by: 5)
        }
    }

    func nudgeTempo(by delta: Double) {
        guard let sheet = library.sheet(performance.sheetID) ?? selectedSheet else { return }
        let bpm = min(Tempo.maxBPM, max(Tempo.minBPM, sheet.bpm + delta))
        library.update(sheet.id) { $0.bpm = bpm }
        if let updated = library.sheet(sheet.id) { performance.settingsChanged(for: updated) }
        performance.flash("\(Int(bpm)) BPM")
    }

    func newSheetFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmed ?? ""
        library.add(name: text.isEmpty ? "Untitled Sheet" : "Pasted Sheet", text: text)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
        Diagnostics.log("Pianola launched (build \(version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)). Permission to press keys: \(CGPreflightPostEventAccess())")
        if ProcessInfo.processInfo.environment["PIANOLA_SELFTEST"] != nil {
            SelfTest.runIfRequested()
            return
        }
        let model = AppModel.shared
        model.hotKeys.register { model.handle($0) }
        if !model.permissions.canPressKeys && ProcessInfo.processInfo.environment["PIANOLA_SNAPSHOT"] == nil {
            // Ask straight away: shows the macOS prompt that leads to the Accessibility list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.permissions.request() }
        }
        Snapshot.runIfRequested(model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.performance.shutdown()
        AppModel.shared.library.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct PianolaCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Sheet") { model.library.add() }
                .keyboardShortcut("n")
            Button("New Sheet from Clipboard") { model.newSheetFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Import from Hammerspoon") { model.library.importFromHammerspoon() }
        }
        CommandMenu("Playback") {
            Button(model.performance.phase == .playing ? "Pause" : "Play") { model.handle(.playPause) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Stop") { model.performance.stop() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Faster (+5 BPM)") { model.nudgeTempo(by: 5) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Slower (−5 BPM)") { model.nudgeTempo(by: -5) }
                .keyboardShortcut("[", modifiers: .command)
            Divider()
            Button("Clear Start Marker") { model.performance.clearStartMarker() }
                .disabled(model.performance.startMarker == nil)
            Divider()
            Button("Test Key Presses…") { model.permissions.showingKeyTest = true }
        }
    }
}

/// Developer aid: `PIANOLA_SNAPSHOT=/path/shot.png` saves a picture of the
/// window a moment after launch and quits. `PIANOLA_SNAPSHOT_EVENT=12` shows
/// the selected sheet as if note 12 were playing (no keys are pressed), and
/// `PIANOLA_SNAPSHOT_MINI=1` also saves the mini player next to it.
@MainActor
enum Snapshot {
    static func runIfRequested(_ model: AppModel) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PIANOLA_SNAPSHOT"] else { return }
        if let name = environment["PIANOLA_SNAPSHOT_SHEET"],
           let sheet = model.library.sheets.first(where: { $0.name == name }) {
            model.library.selection = sheet.id
        }
        if let index = environment["PIANOLA_SNAPSHOT_EVENT"].flatMap(Int.init), let sheet = model.selectedSheet {
            model.performance.preview(sheet, atEvent: index)
        }
        if environment["PIANOLA_SNAPSHOT_RENDER"] != nil, let sheet = model.selectedSheet {
            // Off-screen render of Pianola's own views, for when screen capture is not allowed.
            // System controls (text fields, menus, switches) are drawn as placeholders.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let parsed = model.library.parsed(sheet)
                let page = ZStack {
                    StageBackground()
                    VStack(spacing: 0) {
                        SheetHeader(sheet: sheet, parsed: parsed)
                        VStack(alignment: .leading, spacing: 4) {
                            let current = model.performance.currentEvent
                            ForEach(parsed.lines) { line in
                                SheetLineView(line: line, events: Array(parsed.events[line.events]),
                                              current: current.flatMap { line.events.contains($0) ? $0 : nil },
                                              playedThrough: min(max(current ?? -1, line.events.lowerBound), line.events.upperBound),
                                              marker: nil, onTap: { _ in })
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        ControlDeck(sheet: sheet, parsed: parsed)
                    }
                }
                .environment(model.library)
                .environment(model.performance)
                .environment(model.permissions)
                .environment(model.settings)
                .environment(\.colorScheme, .dark)
                .frame(width: 980, height: 760)
                let renderer = ImageRenderer(content: page)
                renderer.scale = 1.5
                if let image = renderer.cgImage {
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
                let hud = MiniPlayerView(performance: model.performance).environment(\.colorScheme, .dark)
                    .background(Color(white: 0.3))
                let hudRenderer = ImageRenderer(content: hud)
                hudRenderer.scale = 2
                if let image = hudRenderer.cgImage {
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-mini.png")))
                }
                exit(0)
            }
            return
        }
        var mini: MiniPlayerWindow?
        if environment["PIANOLA_SNAPSHOT_MINI"] != nil {
            mini = MiniPlayerWindow(performance: model.performance)
            mini?.show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Pianola" }) {
                save(window, to: path)
            }
            if let mini {
                save(mini.window, to: path.replacingOccurrences(of: ".png", with: "-mini.png"))
            }
            exit(0)
        }
    }

    /// SwiftUI draws on the GPU, so ask the window server for the picture.
    private static func save(_ window: NSWindow, to path: String) {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try? capture.run()
        capture.waitUntilExit()
    }
}
