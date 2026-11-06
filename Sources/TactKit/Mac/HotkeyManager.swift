import Carbon.HIToolbox
import Foundation

/// Global shortcuts through Carbon, which needs no permissions and works in every app.
@MainActor
final class HotkeyManager {
    var onAction: ((HotkeyAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x54414354 // "TACT"
    nonisolated(unsafe) fileprivate static weak var current: HotkeyManager?

    init() {
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 1, &spec, nil, &handler)
    }

    /// Returns the actions whose shortcut could not be claimed, usually because another app holds it.
    @discardableResult
    func register(_ combos: [String: HotkeyCombo]) -> [HotkeyAction] {
        unregisterAll()
        var failed: [HotkeyAction] = []
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let combo = combos[action.rawValue] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actionsByID[id] = action
            } else {
                failed.append(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actionsByID = [:]
    }

    fileprivate func fire(id: UInt32) {
        if let action = actionsByID[id] { onAction?(action) }
    }
}

private func hotkeyCallback(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
    if status == noErr {
        let id = hotkeyID.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HotkeyManager.current?.fire(id: id) }
        }
    }
    return noErr
}
