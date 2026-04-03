// pepis/MenuController.swift
import AppKit

final class MenuController: NSObject {
    private let store: GroupStore
    private weak var statusItem: NSStatusItem?

    init(store: GroupStore, statusItem: NSStatusItem) {
        self.store = store
        self.statusItem = statusItem
        super.init()
        store.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    func rebuild() {
        let menu = NSMenu()

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
        let sub = NSMenu()

        let restore = NSMenuItem(title: "Restore", action: #selector(restoreGroup(_:)), keyEquivalent: "")
        restore.representedObject = group.id.uuidString
        restore.target = self
        sub.addItem(restore)

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
        WindowRestorer.restore(group: group)
    }

    @objc private func editContext(_ sender: NSMenuItem) {
        guard let group = group(for: sender) else { return }
        let url = store.contextFileURL(for: group)
        // Re-create if somehow missing
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
    }
}
