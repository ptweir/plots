// pepis/WindowRestorer.swift
import AppKit
import ApplicationServices

enum WindowRestorer {
    static func restore(group: Group) {
        for snapshot in group.windows {
            if let app = runningApp(bundleID: snapshot.appBundleID) {
                setFrame(snapshot.frame, windowIndex: snapshot.windowIndex, of: app)
            } else {
                launch(bundleID: snapshot.appBundleID) { app in
                    self.setFrame(snapshot.frame, windowIndex: snapshot.windowIndex, of: app)
                }
            }
        }
    }

    // MARK: - Private

    private static func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
    }

    private static func setFrame(_ frame: CGRect, windowIndex: Int, of app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              windowIndex < windows.count else { return }

        let window = windows[windowIndex]
        var origin = frame.origin
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private static func launch(bundleID: String, completion: @escaping (NSRunningApplication) -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, _ in
            guard let app = app else { return }
            // Give the app 2 seconds to create its windows before repositioning
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                completion(app)
            }
        }
    }
}
