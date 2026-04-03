// plots/HotkeyManager.swift
import AppKit
import ApplicationServices

/// Listens for Cmd+Esc globally and fires `onCycle`.
/// Uses a CGEventTap (requires Accessibility permission, which Plots already holds).
final class HotkeyManager {
    // Weak reference accessible from the @convention(c) callback, which cannot capture context.
    private static weak var current: HotkeyManager?

    private var eventTap: CFMachPort?
    var onCycle: (() -> Void)?

    init() {
        HotkeyManager.current = self
    }

    func start() {
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard type == .keyDown else { return Unmanaged.passRetained(event) }
            return HotkeyManager.current?.handle(event: event) ?? Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Escape keyCode = 53; must be held with Command
        guard event.getIntegerValueField(.keyboardEventKeycode) == 53,
              event.flags.contains(.maskCommand) else {
            return Unmanaged.passRetained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.onCycle?() }
        return nil // consume the event
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
