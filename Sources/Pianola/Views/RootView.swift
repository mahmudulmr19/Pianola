import AppKit
import PianolaCore
import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Permissions.self) private var permissions

    var body: some View {
        @Bindable var permissions = permissions
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            ZStack {
                StageBackground()
                if let id = library.selection, let sheet = library.sheet(id) {
                    SheetDetailView(sheetID: id, startEditing: sheet.text.isEmpty)
                        .id(id)
                } else if library.sheets.isEmpty {
                    WelcomeView()
                } else {
                    Text("Choose a sheet")
                        .font(Theme.titleFont(22))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $permissions.showingKeyTest) { KeyTestView() }
    }
}

struct SidebarView: View {
    @Environment(Library.self) private var library
    @Environment(Performance.self) private var performance
    @State private var search = ""
    @State private var importable = 0
    @State private var pendingDelete: SavedSheet?

    var body: some View {
        @Bindable var library = library
        List(selection: $library.selection) {
            Section("Sheets") {
                ForEach(filtered) { sheet in
                    SheetRow(sheet: sheet, parsed: library.parsed(sheet),
                             isLive: performance.sheetID == sheet.id && performance.phase.isRunning)
                        .tag(sheet.id)
                        .contextMenu {
                            Button("Duplicate") { library.duplicate(sheet.id) }
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDelete = sheet }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search sheets")
        .onDeleteCommand {
            if let sheet = library.sheet(library.selection) { pendingDelete = sheet }
        }
        .confirmationDialog("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { sheet in
            Button("Delete", role: .destructive) {
                if performance.sheetID == sheet.id { performance.stop() }
                library.delete(sheet.id)
            }
        } message: { _ in
            Text("The sheet is removed from your library. This can't be undone.")
        }
        .safeAreaInset(edge: .bottom) {
            if importable > 0 {
                Button {
                    library.importFromHammerspoon()
                    importable = library.hammerspoonSheets().count
                } label: {
                    Label("Import \(importable) from Hammerspoon", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(12)
                .help("Copy the sheets saved in your old Hammerspoon piano window")
            }
        }
        .toolbar {
            ToolbarItem {
                Button { library.add() } label: { Label("New Sheet", systemImage: "plus") }
                    .help("New sheet (⌘N)")
            }
        }
        .task { importable = library.hammerspoonSheets().count }
    }

    private var filtered: [SavedSheet] {
        let query = search.trimmed
        guard !query.isEmpty else { return library.sheets }
        return library.sheets.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct SheetRow: View {
    let sheet: SavedSheet
    let parsed: ParsedSheet
    let isLive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: Self.colors(for: sheet.name), startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: isLive ? "waveform" : "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .symbolEffect(.variableColor.iterative, isActive: isLive)
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.name.isEmpty ? "Untitled Sheet" : sheet.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        guard parsed.noteCount > 0 else { return "Empty" }
        return "\(parsed.noteCount) notes · \(parsed.seconds(bpm: sheet.bpm, speed: sheet.speed).clockText) · \(Int(sheet.bpm)) BPM"
    }

    /// A gradient picked from the name, so each sheet keeps its own colour.
    static func colors(for name: String) -> [Color] {
        let seed = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        let hue = Double(seed % 360) / 360
        return [Color(hue: hue, saturation: 0.55, brightness: 0.78),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.48)]
    }
}

struct WelcomeView: View {
    @Environment(Library.self) private var library
    @State private var importable = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "pianokeys")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
            Text("Your piano, on autopilot")
                .font(Theme.titleFont(34))
                .foregroundStyle(Theme.ivory)
            Text("Paste a Roblox piano sheet and Pianola plays it for you, note for note, with PianoBlox timing.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Button("New Sheet") { library.add() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.ebony)
                Button("Paste from Clipboard") { AppModel.shared.newSheetFromClipboard() }
                    .buttonStyle(.glass)
                if importable > 0 {
                    Button("Import \(importable) from Hammerspoon") { library.importFromHammerspoon() }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
        .padding(40)
        .task { importable = library.hammerspoonSheets().count }
    }
}
