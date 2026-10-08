import AppKit
import Carbon.HIToolbox
import ClotheslineCore

/// System-wide keyboard shortcuts via Carbon's `RegisterEventHotKey`.
///
/// This is still the only public API for global hotkeys that needs no
/// Accessibility or Input Monitoring permission and works in a sandbox. The
/// key event is consumed only for the registered combination; every other
/// keystroke is untouched.
@MainActor
final class HotKeyCenter {
    enum Action: UInt32 {
        case toggleLine = 1
        case hangClipboard = 2
    }

    enum RegistrationResult: Equatable {
        case ok
        case unavailable // taken by another app or the system
        case notSet
    }

    static let shared = HotKeyCenter()

    var handler: ((Action) -> Void)?
    private var refs: [Action: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private(set) var results: [Action: RegistrationResult] = [:]
    private var shortcuts: [Action: Shortcut] = [:]
    private var suspended = false

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, let action = HotKeyCenter.Action(rawValue: hotKeyID.id) else { return status }
            // Carbon delivers this on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.handler?(action) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    /// Registers (or clears) the shortcut for an action. Returns whether macOS
    /// accepted it; a combination already claimed elsewhere is reported so the
    /// settings window can say so instead of failing silently.
    @discardableResult
    func register(_ shortcut: Shortcut?, for action: Action) -> RegistrationResult {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        shortcuts[action] = shortcut
        guard let shortcut, shortcut.isValidGlobalShortcut else {
            results[action] = .notSet
            return .notSet
        }
        if suspended {
            results[action] = .ok
            return .ok
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x434C_534E), id: action.rawValue) // 'CLSN'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        let result: RegistrationResult
        if status == noErr, let ref {
            refs[action] = ref
            result = .ok
        } else {
            result = .unavailable
        }
        results[action] = result
        return result
    }

    /// Releases all hotkeys while a shortcut is being recorded, so the current
    /// combination reaches the recorder instead of firing.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for (action, shortcut) in shortcuts { register(shortcut, for: action) }
    }
}

extension Shortcut {
    /// Builds a shortcut from a key-down event captured by the recorder.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= Shortcut.command }
        if flags.contains(.shift) { mods |= Shortcut.shift }
        if flags.contains(.option) { mods |= Shortcut.option }
        if flags.contains(.control) { mods |= Shortcut.control }
        let label = Shortcut.label(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, keyLabel: label)
    }

    static func label(forKeyCode code: UInt16, characters: String?) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Grave: return "`"
        default:
            let c = (characters ?? "").uppercased()
            return c.isEmpty ? "#\(code)" : c
        }
    }
}
