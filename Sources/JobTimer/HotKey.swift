import Carbon

/// System-wide keyboard shortcut via Carbon (no Accessibility permission needed).
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    init(keyCode: Int, modifiers: Int, id: UInt32, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        Self.handlers[id] = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A54_4D52), id: id) // 'JTMR'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
