// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation
import Carbon.HIToolbox

/// Global hot key via Carbon's `RegisterEventHotKey`. Carbon is the correct tool here: it works
/// app-wide without Accessibility permission, unlike `NSEvent` global key monitors.
public final class HotKeyManager: @unchecked Sendable {
    public var onTrigger: (@MainActor () -> Void)?

    private let signature = OSType(0x4E43_4C50)  // 'NCLP'
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init() {
        installHandler()
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    public func register(_ combo: KeyCombo) -> Bool {
        unregister()
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            Log.error("RegisterEventHotKey failed (\(status)) for \(combo.displayString)")
            return false
        }
        hotKeyRef = reference
        Log.info("registered hot key \(combo.displayString)")
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            nanoClipHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            Log.error("InstallEventHandler failed (\(status))")
        }
    }
}

private func nanoClipHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    guard manager.onTrigger != nil else { return noErr }
    // Carbon delivers hot key events on the main thread through the app event target.
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            manager.onTrigger?()
        }
    } else {
        Log.error("hot key event arrived off the main thread; ignoring")
    }
    return noErr
}