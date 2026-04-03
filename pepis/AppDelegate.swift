// pepis/AppDelegate.swift
import AppKit
import ApplicationServices

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Held as a static so the delegate isn't released when main() returns to the run loop
    private static var _instance: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        _instance = delegate
        app.delegate = delegate
        app.run()
    }

    var statusItem: NSStatusItem!
    var store: GroupStore!
    var menuController: MenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()

        store = GroupStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⊞"
        statusItem.button?.font = NSFont.systemFont(ofSize: 14)
        menuController = MenuController(store: store, statusItem: statusItem)
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
