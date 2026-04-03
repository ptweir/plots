// pepis/MenuController.swift
import AppKit
import ApplicationServices

final class MenuController: NSObject, NSMenuDelegate {
    private let store: GroupStore
    private weak var statusItem: NSStatusItem?

    init(store: GroupStore, statusItem: NSStatusItem) {
        self.store = store
        self.statusItem = statusItem
        super.init()
        store.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    // Rebuild each time the menu is about to open so AX permission state is always fresh
    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        let menu = NSMenu()
        menu.delegate = self

        // Warn if Accessibility permission is not granted
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(
                title: "⚠ Accessibility access required",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        if store.groups.isEmpty {
            let empty = NSMenuItem(title: "No groups yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for group in store.groups {
                menu.addItem(groupMenuItem(for: group))
            }
        }

        menu.addItem(.separator())

        let save = NSMenuItem(title: "Save current windows as…", action: #selector(promptSave), keyEquivalent: "")
        save.target = self
        menu.addItem(save)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pepis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Private

    private func groupMenuItem(for group: Group) -> NSMenuItem {
        let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
        item.state = group.id == store.currentGroupID ? .on : .off

        let sub = NSMenu()

        let restore = NSMenuItem(title: "Restore", action: #selector(restoreGroup(_:)), keyEquivalent: "")
        restore.representedObject = group.id.uuidString
        restore.target = self
        sub.addItem(restore)

        let update = NSMenuItem(title: "Update", action: #selector(updateGroup(_:)), keyEquivalent: "")
        update.representedObject = group.id.uuidString
        update.target = self
        sub.addItem(update)

        let edit = NSMenuItem(title: "Edit context", action: #selector(editContext(_:)), keyEquivalent: "")
        edit.representedObject = group.id.uuidString
        edit.target = self
        sub.addItem(edit)

        sub.addItem(.separator())

        let delete = NSMenuItem(title: "Delete", action: #selector(deleteGroup(_:)), keyEquivalent: "")
        delete.representedObject = group.id.uuidString
        delete.target = self
        sub.addItem(delete)

        item.submenu = sub
        return item
    }

    private func group(for item: NSMenuItem) -> Group? {
        guard let idString = item.representedObject as? String,
              let id = UUID(uuidString: idString) else { return nil }
        return store.groups.first { $0.id == id }
    }

    @objc private func restoreGroup(_ sender: NSMenuItem) {
        guard let group = group(for: sender) else { return }
        // Auto-save current group state before switching (skip if restoring same group).
        // Only update positions for apps already tracked by the group — don't add new apps.
        // Then minimize apps belonging to the current group that have no place in the target group.
        if let currentID = store.currentGroupID, currentID != group.id,
           let currentGroup = store.groups.first(where: { $0.id == currentID }) {
            let trackedBundleIDs = Set(currentGroup.windows.map { $0.appBundleID })
            let windows = WindowCapture.captureAll().filter { trackedBundleIDs.contains($0.appBundleID) }
            store.update(id: currentID, windows: windows)

            let targetBundleIDs = Set(group.windows.map { $0.appBundleID })
            let outgoing = trackedBundleIDs.subtracting(targetBundleIDs)
            WindowRestorer.minimizeApps(outgoing)
        }
        WindowRestorer.restore(group: group)
        store.setCurrentGroup(id: group.id)
    }

    @objc private func updateGroup(_ sender: NSMenuItem) {
        guard let group = group(for: sender) else { return }
        store.update(id: group.id, windows: WindowCapture.captureAll())
        store.setCurrentGroup(id: group.id)
    }

    @objc private func editContext(_ sender: NSMenuItem) {
        guard let group = group(for: sender) else { return }
        let url = store.contextFileURL(for: group)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func deleteGroup(_ sender: NSMenuItem) {
        guard let group = group(for: sender) else { return }
        store.delete(id: group.id)
    }

    @objc private func promptSave() {
        let alert = NSAlert()
        alert.messageText = "Save window group"
        alert.informativeText = "Enter a name for this group of windows."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "e.g. Morning setup"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let group = Group(
            id: UUID(),
            name: name,
            createdAt: Date(),
            windows: WindowCapture.captureAll()
        )
        store.save(group: group)
        store.setCurrentGroup(id: group.id)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
