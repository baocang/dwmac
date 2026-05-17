import Carbon.HIToolbox
import Foundation

/// One hotkey binding owned by the manager.
struct HotkeyBinding {
    let id: UInt32
    let keyCode: UInt32
    let modifierMask: UInt32
    let handler: () -> Void
}

/// Singleton hotkey manager. Carbon's API is C-callback based, so the C trampoline
/// dispatches to this shared instance.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var nextID: UInt32 = 1
    private var bindings: [UInt32: HotkeyBinding] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var installed = false

    private init() {}

    /// Install the global Carbon event handler. Call once during boot.
    func installEventHandler() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind:  OSType(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         hotkeyCallback,
                                         1,
                                         &spec,
                                         nil,
                                         &handlerRef)
        if status == noErr {
            installed = true
            Log.debug("Carbon event handler installed")
        } else {
            Log.error("InstallEventHandler failed: \(status)")
        }
    }

    /// Register a hotkey. Returns true on success.
    @discardableResult
    func register(keyCode: UInt32, modifierMask: UInt32, _ handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: kDwmacHotKeySignature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode,
                                         modifierMask,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            Log.warn("RegisterEventHotKey failed (key=\(keyCode), mods=0x\(String(modifierMask, radix: 16))): \(status)")
            return false
        }
        bindings[id] = HotkeyBinding(id: id, keyCode: keyCode, modifierMask: modifierMask, handler: handler)
        refs[id] = ref
        return true
    }

    /// Unregister every binding.
    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        bindings.removeAll()
    }

    fileprivate func dispatch(id: UInt32) {
        guard let binding = bindings[id] else { return }
        binding.handler()
    }
}

/// C-callable trampoline. Extracts the EventHotKeyID and forwards to the manager.
private let hotkeyCallback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
    guard let eventRef else { return OSStatus(eventNotHandledErr) }
    var hkID = EventHotKeyID()
    let status = GetEventParameter(eventRef,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hkID)
    guard status == noErr else { return status }
    HotkeyManager.shared.dispatch(id: hkID.id)
    return noErr
}
