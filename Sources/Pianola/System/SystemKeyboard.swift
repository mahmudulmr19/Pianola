import AppKit
import Carbon.HIToolbox
import PianolaCore

/// Sends the player's key presses to macOS as real keyboard events.
///
/// With no target, events go to the login session, so the front app gets them,
/// as in the Hammerspoon version. With a target, they go straight to that app's
/// process, so it does not need to be in front. A black key is its white key
/// with the Shift flag on the event (no separate Shift press, which Roblox games
/// often bind to Shift-lock). Keys are found by character on the current layout.
final class SystemKeyboard: KeyOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var codes: [Character: CGKeyCode]
    private var sent = 0
    private var targetPID: pid_t?
    private let source = CGEventSource(stateID: .combinedSessionState)

    @MainActor init() {
        codes = Self.layoutCodes()
    }

    /// Re-reads the keyboard layout. Call before playing in case it changed.
    @MainActor func refreshLayout() {
        let fresh = Self.layoutCodes()
        lock.withLock { codes = fresh }
    }

    /// Send to this app even when it is in the background, or nil for the front app.
    func setTarget(_ pid: pid_t?) {
        lock.withLock { targetPID = pid }
    }

    /// Number of key events posted so far.
    var sentCount: Int { lock.withLock { sent } }

    func send(_ actions: [KeyAction]) {
        let codes = lock.withLock { self.codes }
        // Releases first, so a key pressed again is always let go before.
        for case .up(let key) in actions { post(codes[key.baseKey], down: false, shift: key.needsShift) }
        for case .down(let key) in actions { post(codes[key.baseKey], down: true, shift: key.needsShift) }
    }

    private func post(_ code: CGKeyCode?, down: Bool, shift: Bool) {
        guard let code, let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        event.flags = shift ? .maskShift : []
        if let pid = lock.withLock({ targetPID }) {
            event.postToPid(pid)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
        lock.withLock { sent += 1 }
    }

    // MARK: Layout

    /// US keyboard positions, used for anything the current layout does not type.
    private static let usPositions: [Character: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
    ]

    @MainActor private static func layoutCodes() -> [Character: CGKeyCode] {
        var map = usPositions
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return map }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var found: [Character: CGKeyCode] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            // Ascending order finds the main-row digits before the keypad ones.
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) else { continue }
                let ch = Character(scalar)
                if found[ch] == nil { found[ch] = CGKeyCode(code) }
            }
        }
        for key in map.keys { if let code = found[key] { map[key] = code } }
        return map
    }
}
