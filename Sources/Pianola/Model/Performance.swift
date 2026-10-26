import AppKit
import Observation
import PianolaCore

/// Runs a performance: count-in, focusing the game, the player itself, pausing
/// when the game loses focus, and mirroring the player's position for the UI.
@Observable @MainActor
final class Performance {
    enum Phase: Equatable {
        case idle
        case countingIn(Int)
        case playing
        case paused(String?)
        case finished

        var isRunning: Bool {
            switch self {
            case .countingIn, .playing, .paused: true
            case .idle, .finished: false
            }
        }

        var isPaused: Bool { if case .paused = self { true } else { false } }
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String
        var needsPermission = false
    }

    struct StartMarker: Equatable {
        var sheet: SavedSheet.ID
        var event: Int
    }

    private(set) var phase: Phase = .idle
    private(set) var sheetID: SavedSheet.ID?
    private(set) var title = ""
    private(set) var parsed = ParsedSheet.empty
    private(set) var beat = 0.0
    private(set) var currentEvent: Int?
    private(set) var heldKeys: Set<Int> = []
    private(set) var bpm = 100.0
    private(set) var speed = 1.0
    private(set) var transpose = 0
    private(set) var targetName = ""
    /// Keys go straight to the target app, which can stay in the background.
    private(set) var inBackground = false
    /// Where playback starts when a note is clicked while stopped.
    private(set) var startMarker: StartMarker?
    var notice: Notice?
    /// A short message for the mini player, such as "105 BPM".
    private(set) var toast: String?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private let keyboard: SystemKeyboard
    @ObservationIgnored private let player: SheetPlayer
    @ObservationIgnored private var plan: PlaybackPlan?
    @ObservationIgnored private var startBeat = 0.0
    @ObservationIgnored private var sustain = false
    @ObservationIgnored private var targetPID: pid_t?
    @ObservationIgnored private var poller: Timer?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var miniPlayer: MiniPlayerWindow?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var isPreview = false

    init(settings: AppSettings) {
        self.settings = settings
        keyboard = SystemKeyboard()
        player = SheetPlayer(output: keyboard)
        player.onStateChange { [weak self] state in
            Task { @MainActor in if state == .finished { self?.finish() } }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.frontAppChanged(to: pid) }
        }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appQuit(pid) }
        }
    }

    var secondsPerBeat: Double { Tempo.secondsPerBeat(bpm: bpm, speed: speed) }
    var elapsed: Double { beat * secondsPerBeat }
    var duration: Double { parsed.totalBeats * secondsPerBeat }
    var progress: Double { parsed.totalBeats > 0 ? min(1, beat / parsed.totalBeats) : 0 }

    func isShowing(_ id: SavedSheet.ID) -> Bool { sheetID == id && phase != .idle }

    // MARK: Transport

    func play(_ sheet: SavedSheet, from event: Int? = nil) {
        stop(hidePanel: false)
        notice = nil
        Diagnostics.log("Play pressed: \"\(sheet.name)\", \(Int(sheet.bpm)) BPM, \(sheet.timing) timing, sustain \(sheet.sustain), target \"\(settings.targetName)\", front app \(Diagnostics.frontAppName())")
        guard CGPreflightPostEventAccess() else {
            Diagnostics.log("Not playing: no permission to press keys")
            notice = Notice(title: "Pianola needs permission to press keys",
                            detail: "Turn on Pianola in System Settings → Privacy & Security → Accessibility.",
                            needsPermission: true)
            return
        }
        let parsed = SheetParser.parse(sheet.text, rules: sheet.rules)
        guard parsed.noteCount > 0 else {
            Diagnostics.log("Not playing: the sheet has no notes")
            notice = Notice(title: "Nothing to play yet", detail: "Switch to Edit and paste a sheet.")
            return
        }

        let name = settings.targetName
        var target: NSRunningApplication?
        if !name.isEmpty {
            guard let app = Self.runningApp(named: name) else {
                let running = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
                Diagnostics.log("Not playing: no running app called \"\(name)\". Running: \(running.joined(separator: ", "))")
                notice = Notice(title: "\(name) isn't open",
                                detail: "Open \(name) and sit at a piano, or choose another app in the toolbar.")
                return
            }
            target = app
        }

        sheetID = sheet.id
        title = sheet.name
        self.parsed = parsed
        plan = PlaybackPlan(parsed)
        bpm = sheet.bpm
        speed = sheet.speed
        sustain = sheet.sustain
        transpose = sheet.transpose
        targetName = target?.localizedName ?? ""
        targetPID = target?.processIdentifier

        let from = event ?? (startMarker?.sheet == sheet.id ? startMarker?.event : nil)
        if let from, parsed.events.indices.contains(from) {
            startBeat = parsed.events[from].startBeat
            currentEvent = from
        } else {
            startBeat = 0
            currentEvent = nil
        }
        beat = startBeat

        keyboard.refreshLayout()
        inBackground = target != nil && settings.playInBackground
        keyboard.setTarget(inBackground ? target?.processIdentifier : nil)
        if let target, inBackground {
            Diagnostics.log("Sending keys straight to \(targetName) (pid \(target.processIdentifier)), in the background")
        } else if let target {
            NSApp.yieldActivation(to: target)
            let activated = target.activate()
            Diagnostics.log("Bringing \(targetName) (pid \(target.processIdentifier)) to the front: \(activated ? "ok" : "refused")")
        }
        showMiniPlayer()

        let seconds = max(0, settings.countIn)
        phase = .countingIn(seconds)
        countdown = Task { [weak self] in
            var left = seconds
            while left > 0 {
                self?.phase = .countingIn(left)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                left -= 1
            }
            // Give the game a moment to come to the front.
            if seconds == 0 { try? await Task.sleep(for: .milliseconds(350)) }
            if Task.isCancelled { return }
            self?.beginPlaying()
        }
    }

    private func beginPlaying() {
        guard let plan else { return }
        countdown = nil
        // Never type into the wrong app: the game must be in front, and with no
        // game chosen, Pianola itself must not be (it would type into its own window).
        let front = NSWorkspace.shared.frontmostApplication
        if let target = targetPID, !inBackground, front?.processIdentifier != target {
            Diagnostics.log("Not playing: \(targetName) is not in front (front app: \(front?.localizedName ?? "none"))")
            stop()
            notice = Notice(title: "\(targetName) didn't come to the front",
                            detail: "Click into \(targetName), then press ⌃⌥P to start.")
            return
        }
        if targetPID == nil, front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            Diagnostics.log("Not playing: Pianola itself is in front and no target app is set")
            stop()
            notice = Notice(title: "Switch to your game first",
                            detail: "With no target app chosen, keys go to the front app. Switch to it during the count-in, or press ⌃⌥P from inside it.")
            return
        }
        player.play(plan, fromBeat: startBeat, bpm: bpm, speed: speed, sustain: sustain)
        phase = .playing
        startPolling()
        Diagnostics.log(inBackground
            ? "Playing into \(targetName) in the background from beat \(startBeat)"
            : "Playing into \(front?.localizedName ?? "none") from beat \(startBeat)")
    }

    func togglePlayPause(_ sheet: SavedSheet?) {
        switch phase {
        case .playing: pause()
        case .paused: resume()
        case .countingIn: stop()
        case .idle, .finished: if let sheet { play(sheet) }
        }
    }

    func pause(reason: String? = nil) {
        switch phase {
        case .countingIn:
            stop()
        case .playing:
            player.pause()
            Diagnostics.log("Paused\(reason.map { ": \($0)" } ?? "") (\(keyboard.sentCount) key events sent so far)")
            phase = .paused(reason)
            poll()
            stopPolling()
        default:
            break
        }
    }

    func resume() {
        guard phase.isPaused else { return }
        if let pid = targetPID {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                stop()
                notice = Notice(title: "\(targetName) closed", detail: "Open it again to keep playing.")
                return
            }
            if !inBackground {
                NSApp.yieldActivation(to: app)
                app.activate()
            }
        }
        phase = .paused("Resuming…")
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.phase.isPaused else { return }
            self.player.resume()
            self.phase = .playing
            self.startPolling()
        }
    }

    func stop(hidePanel: Bool = true) {
        if phase.isRunning { Diagnostics.log("Stopped (\(keyboard.sentCount) key events sent so far)") }
        countdown?.cancel()
        countdown = nil
        resumeTask?.cancel()
        resumeTask = nil
        player.stop()
        stopPolling()
        phase = .idle
        heldKeys = []
        currentEvent = nil
        beat = 0
        if hidePanel { hideMiniPlayer() }
    }

    private func finish() {
        guard phase == .playing else { return }
        Diagnostics.log("Finished (\(keyboard.sentCount) key events sent so far)")
        stopPolling()
        heldKeys = []
        beat = parsed.totalBeats
        currentEvent = nil
        phase = .finished
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, self.phase == .finished else { return }
            self.hideMiniPlayer()
        }
    }

    /// Releases every key. Called when the app quits.
    func shutdown() {
        stop()
        player.shutdown()
    }

    // MARK: Position

    /// Clicking a note: jump there while playing, or mark where to start.
    func jump(toEvent index: Int, in sheet: SavedSheet) {
        if sheetID == sheet.id, phase == .playing || phase.isPaused {
            guard parsed.events.indices.contains(index) else { return }
            let target = parsed.events[index].startBeat
            player.seek(toBeat: target)
            if phase.isPaused {
                beat = target
                currentEvent = index
            }
        } else {
            startMarker = startMarker == StartMarker(sheet: sheet.id, event: index)
                ? nil : StartMarker(sheet: sheet.id, event: index)
        }
    }

    /// Dragging the progress bar.
    func scrub(to fraction: Double, in sheet: SavedSheet, parsed sheetEvents: ParsedSheet) {
        let target = max(0, min(1, fraction)) * sheetEvents.totalBeats
        if sheetID == sheet.id, phase == .playing || phase.isPaused {
            player.seek(toBeat: target)
            if phase.isPaused {
                beat = target
                currentEvent = parsed.eventIndex(atBeat: target)
            }
        } else if let index = sheetEvents.eventIndex(atBeat: target) {
            startMarker = index == 0 ? nil : StartMarker(sheet: sheet.id, event: index)
        }
    }

    func clearStartMarker() { startMarker = nil }

    // MARK: Live changes

    func settingsChanged(for sheet: SavedSheet) {
        guard sheet.id == sheetID else { return }
        transpose = sheet.transpose
        title = sheet.name
        if sheet.bpm != bpm || sheet.speed != speed {
            bpm = sheet.bpm
            speed = sheet.speed
            player.setTempo(bpm: bpm, speed: speed)
        }
        if sheet.sustain != sustain {
            sustain = sheet.sustain
            player.setSustain(sustain)
        }
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Shows a sheet as if it were playing, without pressing any keys.
    /// Used to take screenshots of the design.
    func preview(_ sheet: SavedSheet, atEvent index: Int) {
        isPreview = true
        sheetID = sheet.id
        title = sheet.name
        parsed = SheetParser.parse(sheet.text, rules: sheet.rules)
        bpm = sheet.bpm
        speed = sheet.speed
        targetName = settings.targetName
        guard parsed.events.indices.contains(index) else { return }
        let event = parsed.events[index]
        currentEvent = index
        beat = event.startBeat + event.durationBeats * 0.3
        heldKeys = Set(event.keys.map(\.midi))
        phase = .playing
    }

    // MARK: Plumbing

    private func startPolling() {
        poller?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    private func stopPolling() {
        poller?.invalidate()
        poller = nil
    }

    private func poll() {
        let snapshot = player.snapshot()
        if snapshot.beat != beat { beat = snapshot.beat }
        let event = parsed.eventIndex(atBeat: snapshot.beat)
        if event != currentEvent { currentEvent = event }
        if snapshot.heldKeys != heldKeys { heldKeys = snapshot.heldKeys }
        if snapshot.state == .finished && phase == .playing { finish() }
        // Backstop for a missed app-switch notification.
        if phase == .playing, settings.autoPause, !inBackground, let target = targetPID,
           let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != target {
            frontAppChanged(to: front.processIdentifier)
        }
    }

    /// The target app quit: nothing left to send keys to.
    private func appQuit(_ pid: pid_t?) {
        guard let pid, pid == targetPID, phase.isRunning else { return }
        Diagnostics.log("\(targetName) quit while \(phase)")
        stop()
        notice = Notice(title: "\(targetName) closed", detail: "Open it again to keep playing.")
    }

    private func frontAppChanged(to pid: pid_t?) {
        // In the background the target never needs to be in front.
        guard settings.autoPause, !isPreview, !inBackground else { return }
        if phase.isRunning {
            let name = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "unknown"
            Diagnostics.log("Front app changed to \(name) while \(phase)")
        }
        switch phase {
        case .countingIn:
            if let target = targetPID, pid != target {
                stop()
                notice = Notice(title: "Count-in cancelled", detail: "\(targetName) stopped being the front app.")
            }
        case .playing:
            if let target = targetPID {
                if pid != target { pause(reason: "\(targetName) isn't in front") }
            } else {
                pause(reason: "You switched apps")
            }
        default:
            break
        }
    }

    private func showMiniPlayer() {
        hideTask?.cancel()
        guard settings.showMiniPlayer else { return }
        if miniPlayer == nil { miniPlayer = MiniPlayerWindow(performance: self) }
        miniPlayer?.show()
    }

    private func hideMiniPlayer() {
        miniPlayer?.hide()
    }

    static func runningApp(named name: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return apps.first { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            ?? apps.first { $0.bundleIdentifier?.caseInsensitiveCompare(name) == .orderedSame }
            ?? apps.first { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }
    }
}
