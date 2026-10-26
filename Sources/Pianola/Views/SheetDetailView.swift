import AppKit
import PianolaCore
import SwiftUI

struct SheetDetailView: View {
    enum Mode: String, Hashable { case sheet, edit }

    let sheetID: SavedSheet.ID
    @Environment(Library.self) private var library
    @Environment(Performance.self) private var performance
    @Environment(Permissions.self) private var permissions
    @State private var mode: Mode
    @State private var showGuide = false

    init(sheetID: SavedSheet.ID, startEditing: Bool) {
        self.sheetID = sheetID
        _mode = State(initialValue: startEditing ? .edit : .sheet)
    }

    var body: some View {
        if let sheet = library.sheet(sheetID) {
            let parsed = library.parsed(sheet)
            let running = performance.sheetID == sheetID && performance.phase.isRunning
            VStack(spacing: 0) {
                SheetHeader(sheet: sheet, parsed: parsed)
                if !permissions.canPressKeys { PermissionBanner() }
                if let notice = performance.notice { NoticeBanner(notice: notice) }
                Group {
                    if mode == .edit {
                        SheetTextView(text: Binding(
                            get: { sheet.text },
                            set: { value in library.update(sheetID) { $0.text = value } }))
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.black.opacity(0.28)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07)))
                            .overlay(alignment: .topLeading) {
                                if sheet.text.isEmpty { EditorPlaceholder() }
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 12)
                    } else if parsed.events.isEmpty {
                        EmptySheetView { mode = .edit }
                    } else {
                        SheetCanvas(sheet: sheet, parsed: parsed)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ControlDeck(sheet: sheet, parsed: parsed)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        Label("Sheet", systemImage: "music.note.list").tag(Mode.sheet)
                        Label("Edit", systemImage: "square.and.pencil").tag(Mode.edit)
                    }
                    .pickerStyle(.segmented)
                    .disabled(running)
                    .help(running ? "Stop playing to edit" : "Switch between the note view and the text")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { permissions.showingKeyTest = true } label: {
                        Label("Test Keys", systemImage: "keyboard.badge.ellipsis")
                    }
                    .help("Check that Pianola can press keys, without opening Roblox")
                    TargetAppMenu()
                    Button { showGuide.toggle() } label: {
                        Label("How to read sheets", systemImage: "questionmark.circle")
                    }
                    .help("How to read sheets")
                    .popover(isPresented: $showGuide, arrowEdge: .bottom) { NotationGuideView() }
                }
            }
            .onChange(of: sheet) { _, updated in performance.settingsChanged(for: updated) }
            .onChange(of: running) { _, isRunning in if isRunning { mode = .sheet } }
        }
    }
}

struct SheetHeader: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Untitled Sheet", text: Binding(
                get: { sheet.name },
                set: { value in library.update(sheet.id) { $0.name = value } }))
                .textFieldStyle(.plain)
                .font(Theme.titleFont(30))
                .foregroundStyle(Theme.ivory)

            HStack(spacing: 8) {
                let seconds = parsed.seconds(bpm: sheet.bpm, speed: sheet.speed)
                InfoPill(systemImage: "music.note", text: "\(parsed.noteCount) notes")
                InfoPill(systemImage: "clock", text: seconds.clockText)
                InfoPill(systemImage: "metronome", text: "\(Int(sheet.bpm)) BPM" + (sheet.speed == 1 ? "" : " · \(SpeedMenu.label(sheet.speed))"))
                if parsed.maxChord > 1 {
                    InfoPill(systemImage: "square.stack.3d.up", text: "Chords up to \(parsed.maxChord)", tint: Theme.chord)
                }
                if sheet.transpose != 0 {
                    InfoPill(systemImage: "arrow.up.arrow.down",
                             text: "Set piano transpose to \(sheet.transpose > 0 ? "+" : "")\(sheet.transpose)",
                             tint: Theme.accent)
                }
                if !parsed.silentCharacters.isEmpty {
                    InfoPill(systemImage: "pause.circle",
                             text: "\(parsed.silentCharacters.map { String($0) }.joined(separator: " ")) count as pauses",
                             tint: .secondary)
                        .help("Not piano keys. In Classic timing each one is a note-length of silence, as in the Hammerspoon version.")
                }
                if !parsed.ignoredCharacters.isEmpty {
                    InfoPill(systemImage: "exclamationmark.triangle",
                             text: "Skipped \(parsed.ignoredCharacters.map { String($0) }.joined(separator: " "))",
                             tint: .orange)
                        .help("These characters are not piano keys, so they play nothing and take no time.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

struct EditorPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste a sheet here")
            Text("a s d f - [ad] - {sdf} -- f d s a")
                .foregroundStyle(Theme.accent.opacity(0.6))
        }
        .font(.system(size: 15, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 19)
        .padding(.vertical, 16)
        .allowsHitTesting(false)
    }
}

struct EmptySheetView: View {
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
            Text("This sheet is empty").font(Theme.titleFont(22))
            Text("Paste the notes from PianoBlox or any Roblox sheet site.")
                .foregroundStyle(.secondary)
            Button("Paste a Sheet", action: onEdit)
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.ebony)
        }
    }
}

struct PermissionBanner: View {
    @Environment(Permissions.self) private var permissions

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pianola can't press keys yet").font(.headline)
                Text("Click Open Settings and switch Pianola on under Accessibility. If it already looks switched on, select it, remove it with −, then click Open Settings here again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings") {
                permissions.request()
                permissions.openSettings()
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.ebony)
        }
        .padding(14)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.12)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }
}

struct NoticeBanner: View {
    let notice: Performance.Notice
    @Environment(Performance.self) private var performance
    @Environment(Permissions.self) private var permissions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.headline)
                Text(notice.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if notice.needsPermission {
                Button("Open Settings") {
                    permissions.request()
                    permissions.openSettings()
                }
                .buttonStyle(.glass)
            }
            Button { performance.notice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(RoundIconButtonStyle(diameter: 26))
            .help("Dismiss")
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.orange.opacity(0.10)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Toolbar menu that picks which app receives the keys.
struct TargetAppMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Menu {
            Picker("Send keys to", selection: $settings.targetApp) {
                ForEach(appNames(), id: \.self) { name in
                    Text(name).tag(name)
                }
                Divider()
                Text("Whichever app is in front").tag("")
            }
            .pickerStyle(.inline)
        } label: {
            Label(settings.targetName.isEmpty ? "Front app" : settings.targetName, systemImage: "scope")
                .labelStyle(.titleAndIcon)
        }
        .help("Which app receives the key presses")
    }

    private func appNames() -> [String] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap(\.localizedName)
        var names = Set(running)
        names.insert("Roblox")
        if !settings.targetName.isEmpty { names.insert(settings.targetName) }
        return names.sorted { a, b in
            if a == "Roblox" { return true }
            if b == "Roblox" { return false }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}
