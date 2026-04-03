// pepis/WindowCapture.swift
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
                guard let frame = axFrame(of: window) else { continue }
                snapshots.append(WindowSnapshot(
                    appBundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowIndex: index,
                    frame: frame
                ))
            }
        }
        return snapshots
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
