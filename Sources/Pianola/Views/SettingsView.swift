import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Permissions.self) private var permissions
    @Environment(Library.self) private var library
    @State private var importable = 0
    @State private var imported: Int?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Playing") {
                TextField("Send keys to", text: $settings.targetApp, prompt: Text("Whichever app is in front"))
                Stepper(value: $settings.countIn, in: 0...10) {
                    LabeledContent("Count-in", value: settings.countIn == 0 ? "None" : "\(settings.countIn) seconds")
                }
                Toggle("Pause when the game isn't the front app", isOn: $settings.autoPause)
                Toggle("Play in the background", isOn: $settings.playInBackground)
                    .help("Send keys straight to the chosen app, so it doesn't need to be in front. Turn off for apps that ignore keys while in the background.")
                Toggle("Show the floating mini player", isOn: $settings.showMiniPlayer)
            }

            Section {
                ForEach(HotKeys.Action.allCases, id: \.rawValue) { action in
                    LabeledContent(action.title) {
                        Text(action.symbol).font(.system(.body, design: .monospaced))
                    }
                }
                if !AppModel.shared.hotKeys.failed.isEmpty {
                    Text("Some shortcuts are taken by another app: \(AppModel.shared.hotKeys.failed.map(\.symbol).joined(separator: ", ")).")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("These work in any app, including Roblox.")
            }

            Section("Permission") {
                LabeledContent("Press keys in other apps") {
                    Label(permissions.canPressKeys ? "Allowed" : "Not allowed",
                          systemImage: permissions.canPressKeys ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(permissions.canPressKeys ? .green : .orange)
                }
                Button("Open Accessibility Settings") {
                    permissions.request()
                    permissions.openSettings()
                }
                Button("Test Key Presses…") { permissions.showingKeyTest = true }
            }

            Section("Updates") {
                let updates = AppModel.shared.updates
                LabeledContent("Version", value: Updates.versionText)
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updates.checksAutomatically },
                        set: { updates.checksAutomatically = $0 }))
                    Button("Check Now") { updates.checkNow() }
                        .disabled(!updates.canCheck)
                } else {
                    Text("Updates are off in this build.").foregroundStyle(.secondary)
                }
            }

            Section("Library") {
                LabeledContent("Hammerspoon sheets") {
                    if let imported {
                        Text("Imported \(imported)").foregroundStyle(.secondary)
                    } else {
                        Button(importable > 0 ? "Import \(importable)" : "None to import") {
                            imported = library.importFromHammerspoon()
                            importable = 0
                        }
                        .disabled(importable == 0)
                    }
                }
                Button("Show Library in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([library.libraryFolder.appendingPathComponent("library.json")])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { importable = library.hammerspoonSheets().count }
    }
}
