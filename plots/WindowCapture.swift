// plots/WindowCapture.swift
import AppKit
import ApplicationServices

enum WindowCapture {
    /// Returns a snapshot of all visible windows across all regular (non-background) apps.
    /// Requires Accessibility permission — returns empty array if not granted.
    static func captureAll() -> [WindowSnapshot] {
        guard AXIsProcessTrusted() else { return [] }

        var snapshots: [WindowSnapshot] = []
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for (index, window) in windows.enumerated() {
                let minimized = axBool(kAXMinimizedAttribute, of: window) ?? false
                // Minimized windows may not expose a frame via AX; use .zero as placeholder
                // (frame is irrelevant when restoring as minimized).
                let frame = axFrame(of: window) ?? .zero
                snapshots.append(WindowSnapshot(
                    appBundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowIndex: index,
                    windowTitle: axTitle(of: window),
                    isMinimized: minimized,
                    frame: frame
                ))
            }
        }
        return snapshots
    }

    private static func axBool(_ attribute: String, of element: AXUIElement) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref as? Bool else { return nil }
        return value
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String, !title.isEmpty else { return nil }
        return title
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef as! AXValue?,
              let sizeValue = sizeRef as! AXValue?
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
