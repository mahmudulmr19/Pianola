import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts that work while Roblox is in front. They need no permission.
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable {
        case playPause = 1, stop, slower, faster

        var keyCode: Int {
            switch self {
            case .playPause: kVK_ANSI_P
            case .stop: kVK_ANSI_S
            case .slower: kVK_ANSI_LeftBracket
            case .faster: kVK_ANSI_RightBracket
            }
        }

        var symbol: String {
            switch self {
            case .playPause: "⌃⌥P"
            case .stop: "⌃⌥S"
            case .slower: "⌃⌥["
            case .faster: "⌃⌥]"
            }
        }

        var title: String {
            switch self {
            case .playPause: "Play or pause"
            case .stop: "Stop"
            case .slower: "Slower (−5 BPM)"
            case .faster: "Faster (+5 BPM)"
            }
        }
    }

    static var perform: ((Action) -> Void)?
    private(set) var failed: [Action] = []
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func register(_ perform: @escaping (Action) -> Void) {
        Self.perform = perform
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, &handler)

        let modifiers = UInt32(controlKey | optionKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x504E_4C41), id: action.rawValue)  // "PNLA"
            let status = RegisterEventHotKey(UInt32(action.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(action)
                NSLog("Pianola: shortcut \(action.symbol) is taken by another app (\(status))")
            }
        }
    }
}

private let hotKeyCallback: EventHandlerUPP = { _, event, _ in
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    let raw = id.id
    MainActor.assumeIsolated {
        if let action = HotKeys.Action(rawValue: raw) { HotKeys.perform?(action) }
    }
    return noErr
}
