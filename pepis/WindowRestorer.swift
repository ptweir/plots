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

    /// Minimizes the specific windows described by the given snapshots.
    static func minimizeWindows(_ snapshots: [WindowSnapshot]) {
        let byApp = Dictionary(grouping: snapshots, by: { $0.appBundleID })
        for (bundleID, windowSnapshots) in byApp {
            guard let app = runningApp(bundleID: bundleID) else { continue }
            let axWindows = axWindowList(for: app)
            for snapshot in windowSnapshots {
                guard let window = matchWindow(snapshot, in: axWindows) else { continue }
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    // MARK: - Private

    private static func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
    }

    private static func axWindowList(for app: NSRunningApplication) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }
        return windows
    }

    /// Finds the AX window matching a snapshot: title first, index as fallback.
    private static func matchWindow(_ snapshot: WindowSnapshot, in windows: [AXUIElement]) -> AXUIElement? {
        if let title = snapshot.windowTitle, !title.isEmpty {
            return windows.first { axTitle(of: $0) == title }
                ?? (snapshot.windowIndex < windows.count ? windows[snapshot.windowIndex] : nil)
        }
        return snapshot.windowIndex < windows.count ? windows[snapshot.windowIndex] : nil
    }

    private static func applySnapshot(_ snapshot: WindowSnapshot, isMinimized: Bool, to app: NSRunningApplication) {
        let windows = axWindowList(for: app)
        guard let window = matchWindow(snapshot, in: windows) else { return }

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
