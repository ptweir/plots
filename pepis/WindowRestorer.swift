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
                AXUIElementPerformAction(window, "AXMinimize" as CFString as CFString)
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

    /// Finds the AX window matching a snapshot.
    /// Priority: exact title → saved frame → index.
    /// Frame matching is reliable when windows haven't moved since the snapshot was taken
    /// (which is guaranteed for auto-save, since positions are captured right before minimising).
    private static func matchWindow(_ snapshot: WindowSnapshot, in windows: [AXUIElement]) -> AXUIElement? {
        // 1. Exact title match
        if let title = snapshot.windowTitle, !title.isEmpty,
           let match = windows.first(where: { axTitle(of: $0) == title }) {
            return match
        }
        // 2. Frame match — handles apps like Chrome where tab titles change dynamically
        if snapshot.frame != .zero,
           let match = windows.first(where: { axFrame(of: $0) == snapshot.frame }) {
            return match
        }
        // 3. Index fallback
        return snapshot.windowIndex < windows.count ? windows[snapshot.windowIndex] : nil
    }

    private static func applySnapshot(_ snapshot: WindowSnapshot, isMinimized: Bool, to app: NSRunningApplication) {
        let windows = axWindowList(for: app)
        guard let window = matchWindow(snapshot, in: windows) else { return }

        if isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, "AXMinimize" as CFString as CFString)
        } else {
            // Use both attribute and raise action — some apps (e.g. Chrome) respond to one but not the other
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
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

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              posRef != nil, sizeRef != nil else { return nil }
        let posValue = posRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
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
