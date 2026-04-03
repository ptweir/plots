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
        if let currentID = store.currentGroupID, currentID != group.id,
           let currentGroup = store.groups.first(where: { $0.id == currentID }) {

            // Refresh frames for windows already in the group. Never add windows that
            // aren't already tracked — that's what "Update" is for.
            let allLive = WindowCapture.captureAll()
            let refreshed = refreshedWindows(from: currentGroup.windows, live: allLive)
            store.update(id: currentID, windows: refreshed)

            // Minimize outgoing windows: those in the current group with no match in target.
            // Use the refreshed snapshots so frame matching in minimizeWindows gets live frames.
            let outgoing = refreshed.filter { current in
                !group.windows.contains { target in
                    target.appBundleID == current.appBundleID && titlesMatch(current, target)
                }
            }
            WindowRestorer.minimizeWindows(outgoing)
        }
        WindowRestorer.restore(group: group)
        store.setCurrentGroup(id: group.id)
    }

    /// For each saved window, find its current live position and return an updated snapshot.
    /// Preserves group composition — never adds windows that aren't already in the group.
    private func refreshedWindows(from saved: [WindowSnapshot], live: [WindowSnapshot]) -> [WindowSnapshot] {
        return saved.map { snap in
            let candidates = live.filter { $0.appBundleID == snap.appBundleID }

            // 1. Exact title match
            if let title = snap.windowTitle, !title.isEmpty,
               let match = candidates.first(where: { $0.windowTitle == title }) {
                return match
            }
            // 2. Only one candidate for this app — unambiguous
            if candidates.count == 1 { return candidates[0] }
            // 3. Frame match (reliable when window hasn't moved since last save)
            if snap.frame != .zero,
               let match = candidates.first(where: { framesApproxEqual($0.frame, snap.frame) }) {
                return match
            }
            // 4. Index fallback
            if let match = candidates.first(where: { $0.windowIndex == snap.windowIndex }) {
                return match
            }
            // 5. Window not found — keep saved snapshot (window may have been closed)
            return snap
        }
    }

    private func framesApproxEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.origin.x - b.origin.x) < 1 &&
               abs(a.origin.y - b.origin.y) < 1 &&
               abs(a.size.width - b.size.width) < 1 &&
               abs(a.size.height - b.size.height) < 1
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

    /// Two snapshots match if they share a non-empty title; falls back to same index.
    private func titlesMatch(_ a: WindowSnapshot, _ b: WindowSnapshot) -> Bool {
        if let ta = a.windowTitle, let tb = b.windowTitle, !ta.isEmpty, !tb.isEmpty {
            return ta == tb
        }
        return a.windowIndex == b.windowIndex
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
