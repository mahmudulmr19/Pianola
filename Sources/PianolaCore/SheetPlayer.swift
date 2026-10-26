import Foundation

public enum KeyAction: Sendable, Equatable {
    case down(PianoKey)
    case up(PianoKey)
}

/// Where key presses go. The app turns them into keyboard events; tests record them.
public protocol KeyOutput: AnyObject, Sendable {
    /// Presses and releases that are due at the same moment, in order.
    /// Called on the player's thread.
    func send(_ actions: [KeyAction])
}

public enum PlayerState: Sendable, Equatable {
    case idle, playing, paused, finished
}

public struct PlayerSnapshot: Sendable, Equatable {
    public var state: PlayerState
    public var beat: Double
    /// MIDI numbers of the keys that are down right now.
    public var heldKeys: Set<Int>
    public var bpm: Double
    public var speed: Double
}

/// Plays a `PlaybackPlan` in real time on its own thread.
///
/// Positions are kept in beats and turned into seconds with the current tempo,
/// so tempo and speed can change mid-song. Key releases share the same clock as
/// presses, so a key is always released before it is pressed again. A long
/// stall (the Mac froze, the lid closed) is treated as a pause rather than time
/// the song owes, so the player never machine-guns notes to catch up.
public final class SheetPlayer: @unchecked Sendable {
    /// Roblox reads input once a frame, so a key held for less than this can be
    /// missed. Also the length of a tap with sustain off, as in the original engine.
    public static let minimumHold = 0.030
    /// Lateness beyond this is a freeze, not a late note.
    public static let stallThreshold = 0.15
    /// Small lead before the first note so it lands on time.
    static let startLead = 0.02

    private let output: KeyOutput
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var thread: Thread?

    // Everything below is guarded by `lock`.
    private var plan: PlaybackPlan?
    private var state: PlayerState = .idle
    private var nextStrike = 0
    private var originBeat = 0.0
    private var originTime = 0.0
    private var pausedBeat = 0.0
    private var bpm = 100.0
    private var speed = 1.0
    private var secondsPerBeat = 0.6
    private var sustain = false
    private var held: [Character: (key: PianoKey, releaseAt: Double)] = [:]
    private var shuttingDown = false
    private var stateHandler: (@Sendable (PlayerState) -> Void)?

    public init(output: KeyOutput) {
        self.output = output
    }

    deinit { shutdown() }

    /// Called on the player's thread when playback finishes by itself.
    public func onStateChange(_ handler: @escaping @Sendable (PlayerState) -> Void) {
        lock.withLock { stateHandler = handler }
    }

    public static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    // MARK: Commands

    public func play(_ plan: PlaybackPlan, fromBeat beat: Double = 0, bpm: Double, speed: Double, sustain: Bool) {
        lock.withLock {
            releaseAllLocked()
            self.plan = plan
            self.bpm = bpm
            self.speed = speed
            self.sustain = sustain
            secondsPerBeat = Tempo.secondsPerBeat(bpm: bpm, speed: speed)
            let start = min(max(0, beat), plan.totalBeats)
            nextStrike = plan.firstStrike(atOrAfter: start)
            originBeat = start
            originTime = Self.now() + Self.startLead
            state = .playing
        }
        ensureThread()
        wake.signal()
    }

    public func pause() {
        lock.withLock {
            guard state == .playing else { return }
            pausedBeat = beatLocked(at: Self.now())
            state = .paused
            releaseAllLocked()
        }
        wake.signal()
    }

    public func resume() {
        lock.withLock {
            guard state == .paused, let plan else { return }
            nextStrike = plan.firstStrike(atOrAfter: pausedBeat)
            originBeat = pausedBeat
            originTime = Self.now() + Self.startLead
            state = .playing
        }
        wake.signal()
    }

    public func stop() {
        lock.withLock {
            releaseAllLocked()
            state = .idle
            pausedBeat = 0
        }
        wake.signal()
    }

    /// Jump to a beat. Keeps playing (or stays paused) from there.
    public func seek(toBeat beat: Double) {
        lock.withLock {
            guard let plan, state == .playing || state == .paused else { return }
            releaseAllLocked()
            let target = min(max(0, beat), plan.totalBeats)
            nextStrike = plan.firstStrike(atOrAfter: target)
            if state == .playing {
                originBeat = target
                originTime = Self.now() + Self.startLead
            } else {
                pausedBeat = target
            }
        }
        wake.signal()
    }

    public func setTempo(bpm: Double, speed: Double) {
        lock.withLock {
            let now = Self.now()
            if state == .playing && now > originTime {
                originBeat = beatLocked(at: now)
                originTime = now
            }
            self.bpm = bpm
            self.speed = speed
            secondsPerBeat = Tempo.secondsPerBeat(bpm: bpm, speed: speed)
        }
        wake.signal()
    }

    public func setSustain(_ on: Bool) {
        lock.withLock { sustain = on }
    }

    public func snapshot() -> PlayerSnapshot {
        lock.withLock {
            PlayerSnapshot(state: state, beat: beatLocked(at: Self.now()),
                           heldKeys: Set(held.values.map(\.key.midi)), bpm: bpm, speed: speed)
        }
    }

    /// Releases every key and ends the player thread.
    public func shutdown() {
        lock.withLock {
            releaseAllLocked()
            state = .idle
            shuttingDown = true
        }
        wake.signal()
    }

    // MARK: Engine

    private func beatLocked(at now: Double) -> Double {
        switch state {
        case .playing:
            guard now > originTime else { return originBeat }
            return originBeat + (now - originTime) / secondsPerBeat
        case .paused: return pausedBeat
        case .finished: return plan?.totalBeats ?? 0
        case .idle: return pausedBeat
        }
    }

    private func timeLocked(ofBeat beat: Double) -> Double {
        originTime + (beat - originBeat) * secondsPerBeat
    }

    private func releaseAllLocked() {
        guard !held.isEmpty else { return }
        let keys = held.values.map(\.key).sorted { $0.midi < $1.midi }
        held.removeAll()
        output.send(keys.map { .up($0) })
    }

    private func ensureThread() {
        lock.withLock {
            guard thread == nil else { return }
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "Pianola player"
            thread.qualityOfService = .userInteractive
            thread.stackSize = 1 << 20
            self.thread = thread
            thread.start()
        }
    }

    /// Asks the scheduler to treat this thread like an audio thread. Ordinary
    /// threads get a few milliseconds of timer slack; real-time ones are woken
    /// on the dot. The work per wake-up is tiny, so the budget is small.
    private static func makeCurrentThreadRealtime() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        func ticks(_ nanoseconds: Double) -> UInt32 {
            UInt32(nanoseconds * Double(timebase.denom) / Double(timebase.numer))
        }
        var policy = thread_time_constraint_policy_data_t(
            period: ticks(5_000_000),
            computation: ticks(500_000),
            constraint: ticks(1_000_000),
            preemptible: 1)
        let count = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                  thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, count)
            }
        }
    }

    private func run() {
        Self.makeCurrentThreadRealtime()
        while true {
            var deadline: Double?
            var finished: (@Sendable (PlayerState) -> Void)?

            lock.lock()
            if shuttingDown {
                thread = nil
                lock.unlock()
                return
            }
            let now = Self.now()
            var actions: [KeyAction] = []

            for (base, entry) in held where entry.releaseAt <= now + 0.0005 {
                actions.append(.up(entry.key))
                held[base] = nil
            }

            if state == .playing, let plan {
                if nextStrike < plan.strikes.count {
                    let lateness = now - timeLocked(ofBeat: plan.strikes[nextStrike].beat)
                    if lateness > Self.stallThreshold { originTime += lateness }
                }
                while nextStrike < plan.strikes.count {
                    let strike = plan.strikes[nextStrike]
                    if timeLocked(ofBeat: strike.beat) > now + 0.0005 { break }
                    let base = strike.key.baseKey
                    if let previous = held[base] { actions.append(.up(previous.key)) }
                    actions.append(.down(strike.key))
                    let hold = max(Self.minimumHold, strike.hold(sustain: sustain) * secondsPerBeat)
                    held[base] = (strike.key, now + hold)
                    nextStrike += 1
                }
                if nextStrike < plan.strikes.count {
                    deadline = timeLocked(ofBeat: plan.strikes[nextStrike].beat)
                } else if beatLocked(at: now) >= plan.totalBeats - 1e-6 {
                    state = .finished
                    finished = stateHandler
                } else {
                    deadline = timeLocked(ofBeat: plan.totalBeats)
                }
            }

            if let soonest = held.values.map(\.releaseAt).min() {
                deadline = min(deadline ?? soonest, soonest)
            }
            if !actions.isEmpty { output.send(actions) }
            lock.unlock()

            finished?(.finished)

            if let deadline {
                let nanos = UInt64(max(0, deadline) * 1_000_000_000)
                _ = wake.wait(timeout: DispatchTime(uptimeNanoseconds: nanos))
            } else {
                wake.wait()
            }
        }
    }
}
