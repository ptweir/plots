// pepis/WindowRestorer.swift
import AppKit
import ApplicationServices

enum WindowRestorer {
    static func restore(group: Group) {
        for snapshot in group.windows {
            let minimized = snapshot.isMinimized ?? false
            if let app = runningApp(bundleID: snapshot.appBundleID) {
                applySnapshot(snapshot, isMinimized: minimized, to: app)
            } else if !minimized {
                // Don't launch an app just to immediately minimize it
                launch(bundleID: snapshot.appBundleID) { app in
                    self.applySnapshot(snapshot, isMinimized: false, to: app)
                }
            }
        }
    }

    /// Minimizes all windows for each app in the given set of bundle IDs.
    static func minimizeApps(_ bundleIDs: Set<String>) {
        for bundleID in bundleIDs {
            guard let app = runningApp(bundleID: bundleID) else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }
            for window in windows {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    // MARK: - Private

    private static func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
    }

    private static func applySnapshot(_ snapshot: WindowSnapshot, isMinimized: Bool, to app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        // Prefer matching by title (stable across reordering); fall back to index.
        let window: AXUIElement?
        if let title = snapshot.windowTitle, !title.isEmpty {
            window = windows.first { axTitle(of: $0) == title } ?? (snapshot.windowIndex < windows.count ? windows[snapshot.windowIndex] : nil)
        } else {
            window = snapshot.windowIndex < windows.count ? windows[snapshot.windowIndex] : nil
        }
        guard let window else { return }

        if isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        } else {
            // Unminimize first so position/size changes take effect
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            var origin = snapshot.frame.origin
            var size = snapshot.frame.size
            if let posValue = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
        }
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String, !title.isEmpty else { return nil }
        return title
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
