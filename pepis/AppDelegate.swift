// pepis/AppDelegate.swift
import AppKit
import ApplicationServices

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        // Shows the system permission dialog on first launch if not yet granted
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
