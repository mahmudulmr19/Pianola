import Foundation
import Observation
import PianolaCore

struct SavedSheet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var text: String
    var bpm: Double = 100
    var speed: Double = 1
    /// A reminder only. The Roblox piano has its own transpose control, and
    /// Pianola types the letters exactly as written.
    var transpose: Int = 0
    /// Hold each key until just before the next note, so chords flow on.
    var sustain: Bool = true
    var timing: TimingStyle = .classic
    /// Classic only: `q-w`, `q - w` and `q --` hold the note instead of pausing.
    var dashHolds: Bool = false
    var created = Date()
    var modified = Date()

    var rules: SheetRules { SheetRules(style: timing, dashHolds: dashHolds) }

    init(name: String, text: String, bpm: Double = 100, transpose: Int = 0,
         sustain: Bool = true, timing: TimingStyle = .classic, dashHolds: Bool = false) {
        self.name = name
        self.text = text
        self.bpm = bpm
        self.transpose = transpose
        self.sustain = sustain
        self.timing = timing
        self.dashHolds = dashHolds
    }

    // Older library files lack some fields; fill them with the defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Sheet"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 100
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        transpose = try c.decodeIfPresent(Int.self, forKey: .transpose) ?? 0
        sustain = try c.decodeIfPresent(Bool.self, forKey: .sustain) ?? true
        timing = try c.decodeIfPresent(TimingStyle.self, forKey: .timing) ?? .classic
        dashHolds = try c.decodeIfPresent(Bool.self, forKey: .dashHolds) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }
}

/// The saved sheets, kept in a JSON file in Application Support.
@Observable @MainActor
final class Library {
    private(set) var sheets: [SavedSheet] = []
    var selection: SavedSheet.ID?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var parseCache: [SavedSheet.ID: (text: String, rules: SheetRules, sheet: ParsedSheet)] = [:]

    init() {
        if let override = ProcessInfo.processInfo.environment["PIANOLA_LIBRARY"] {
            fileURL = URL(fileURLWithPath: override)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            fileURL = support.appendingPathComponent("Pianola", isDirectory: true)
                .appendingPathComponent("library.json")
        }
        load()
        if sheets.isEmpty && !FileManager.default.fileExists(atPath: fileURL.path) {
            sheets = Self.starterSheets
            saveNow()
        }
        selection = sheets.first?.id
    }

    var libraryFolder: URL { fileURL.deletingLastPathComponent() }

    func sheet(_ id: SavedSheet.ID?) -> SavedSheet? {
        guard let id else { return nil }
        return sheets.first { $0.id == id }
    }

    /// The parsed form of a sheet, cached until its text changes.
    func parsed(_ sheet: SavedSheet) -> ParsedSheet {
        if let cached = parseCache[sheet.id], cached.text == sheet.text, cached.rules == sheet.rules { return cached.sheet }
        let parsed = SheetParser.parse(sheet.text, rules: sheet.rules)
        parseCache[sheet.id] = (sheet.text, sheet.rules, parsed)
        return parsed
    }

    func update(_ id: SavedSheet.ID, _ change: (inout SavedSheet) -> Void) {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return }
        var sheet = sheets[index]
        change(&sheet)
        guard sheet != sheets[index] else { return }
        sheet.modified = Date()
        sheets[index] = sheet
        scheduleSave()
    }

    @discardableResult
    func add(name: String = "Untitled Sheet", text: String = "", bpm: Double = 100) -> SavedSheet.ID {
        let sheet = SavedSheet(name: uniqueName(name), text: text, bpm: bpm)
        sheets.insert(sheet, at: 0)
        selection = sheet.id
        scheduleSave()
        return sheet.id
    }

    func duplicate(_ id: SavedSheet.ID) {
        guard let original = sheet(id) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = uniqueName(original.name + " copy")
        copy.created = Date()
        copy.modified = Date()
        let index = sheets.firstIndex { $0.id == id } ?? 0
        sheets.insert(copy, at: index + 1)
        selection = copy.id
        scheduleSave()
    }

    func delete(_ id: SavedSheet.ID) {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return }
        sheets.remove(at: index)
        parseCache[id] = nil
        if selection == id {
            selection = sheets.isEmpty ? nil : sheets[min(index, sheets.count - 1)].id
        }
        scheduleSave()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(sheets.map { $0.name.lowercased() })
        if !names.contains(base.lowercased()) { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sheets = (try? decoder.decode([SavedSheet].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
            try encoder.encode(sheets).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Pianola could not save its library: \(error.localizedDescription)")
        }
    }

    // MARK: Hammerspoon

    /// Sheets saved by the old Hammerspoon "Piano autoplay" window that are not here yet.
    func hammerspoonSheets() -> [SavedSheet] {
        guard let defaults = UserDefaults(suiteName: "org.hammerspoon.Hammerspoon"),
              let items = defaults.array(forKey: "piano.savedSheets1") as? [[String: Any]] else { return [] }
        let existing = Set(sheets.map { $0.name.lowercased() })
        let sustain = (defaults.dictionary(forKey: "piano.cfg7")?["sustain"] as? Bool) ?? true
        return items.compactMap { item in
            guard let name = item["name"] as? String, let text = item["sheet"] as? String,
                  !existing.contains(name.lowercased()) else { return nil }
            // The old tempo is the same number as a PianoBlox BPM for single notes.
            let tempo = (item["tempo"] as? NSNumber)?.doubleValue ?? 150
            let transpose = (item["transpose"] as? NSNumber)?.intValue ?? 0
            return SavedSheet(name: name, text: text,
                              bpm: min(Tempo.maxBPM, max(Tempo.minBPM, tempo)),
                              transpose: max(-12, min(12, transpose)),
                              sustain: sustain, timing: .classic,
                              dashHolds: (item["dashHolds"] as? Bool) ?? false)
        }
    }

    @discardableResult
    func importFromHammerspoon() -> Int {
        let found = hammerspoonSheets()
        guard !found.isEmpty else { return 0 }
        sheets.append(contentsOf: found)
        sheets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selection = found.first?.id
        scheduleSave()
        return found.count
    }

    // MARK: Starter sheets

    static let starterSheets: [SavedSheet] = [
        SavedSheet(name: "Warm-up", text: "a s d f - [ad] - {sdf} -- f d s a", bpm: 84),
        SavedSheet(name: "Ode to Joy", text: """
            u u i o o i u y
            t t y u u - y y --
            u u i o o i u y
            t t y u y - t t --
            y y u t y {ui} u t y {ui} u y t y w --
            u u i o o i u y
            t t y u y - t t --
            """, bpm: 120),
    ]
}
