# Current Group & Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "current group" concept that persists across restarts, auto-saves the current group's windows when switching groups, and lets users update any group's windows in-place via a new "Update" submenu item.

**Architecture:** `GroupStore` gains `currentGroupID`, `update(id:windows:)`, and `setCurrentGroup(id:)`. The current group ID is persisted to `current.json` alongside `groups.json`. `MenuController` gains a ✓ checkmark on the active group item, an "Update" submenu action, auto-save logic in the restore action, and calls `setCurrentGroup` after saving a new group.

**Tech Stack:** Swift 6.3, AppKit, XCTest

---

## File Map

| File | Change |
|---|---|
| `pepis/GroupStore.swift` | Add `currentGroupID`, `update(id:windows:)`, `setCurrentGroup(id:)`, `current.json` persistence |
| `pepis/MenuController.swift` | Add ✓ state on current group, "Update" submenu item + action, auto-save in `restoreGroup`, `setCurrentGroup` call in `promptSave` |
| `pepis-tests/GroupStoreTests.swift` | Add 10 new tests for all new GroupStore behaviour |

---

## Task 1: GroupStore — currentGroupID, update, setCurrentGroup

**Files:**
- Modify: `pepis/GroupStore.swift`
- Modify: `pepis-tests/GroupStoreTests.swift`

### Existing GroupStore interface (for reference)

```swift
final class GroupStore {
    private(set) var groups: [Group] = []
    var onChange: (() -> Void)?
    init(supportDir: URL = GroupStore.defaultSupportDir())
    static func defaultSupportDir() -> URL
    func save(group: Group)
    func delete(id: UUID)
    func contextFileURL(for group: Group) -> URL
}
```

- [ ] **Step 1: Write the failing tests**

Add these 10 tests to the bottom of `GroupStoreTests` class in `pepis-tests/GroupStoreTests.swift` (before the closing `}`):

```swift
    func testCurrentGroupIDStartsNil() {
        XCTAssertNil(store.currentGroupID)
    }

    func testSetCurrentGroupPersists() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.setCurrentGroup(id: group.id)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertEqual(reloaded.currentGroupID, group.id)
    }

    func testSetCurrentGroupNilClearsPersistence() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.setCurrentGroup(id: group.id)
        store.setCurrentGroup(id: nil)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertNil(reloaded.currentGroupID)
    }

    func testStaleCurrentGroupIDBecomesNil() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.setCurrentGroup(id: group.id)
        // Simulate stale reference by persisting a UUID that no longer exists
        // Delete the group, reload — currentGroupID should be nil
        store.delete(id: group.id)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertNil(reloaded.currentGroupID)
    }

    func testDeleteCurrentGroupClearsCurrentGroupID() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.setCurrentGroup(id: group.id)
        store.delete(id: group.id)
        XCTAssertNil(store.currentGroupID)
    }

    func testUpdateReplacesWindows() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            windowIndex: 0,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        store.update(id: group.id, windows: [snapshot])
        XCTAssertEqual(store.groups[0].windows.count, 1)
        XCTAssertEqual(store.groups[0].windows[0].appBundleID, "com.apple.Safari")
    }

    func testUpdatePersists() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            windowIndex: 0,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        store.update(id: group.id, windows: [snapshot])

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertEqual(reloaded.groups[0].windows.count, 1)
    }

    func testUpdateWithUnknownIDIsNoOp() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.update(id: UUID(), windows: [])
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].windows.count, 0)
    }

    func testUpdateCallsOnChange() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        var callCount = 0
        store.onChange = { callCount += 1 }
        store.update(id: group.id, windows: [])
        XCTAssertEqual(callCount, 1)
    }

    func testSetCurrentGroupCallsOnChange() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        var callCount = 0
        store.onChange = { callCount += 1 }
        store.setCurrentGroup(id: group.id)
        XCTAssertEqual(callCount, 1)
    }
```

- [ ] **Step 2: Run tests to confirm new tests fail**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|cannot find|FAILED|SUCCEEDED"
```

Expected: build error — `value of type 'GroupStore' has no member 'setCurrentGroup'`

- [ ] **Step 3: Replace `pepis/GroupStore.swift` with the updated implementation**

```swift
// pepis/GroupStore.swift
import Foundation

final class GroupStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: UUID?
    var onChange: (() -> Void)?

    private let supportDir: URL
    private let groupsFile: URL
    private let contextDir: URL
    private let currentFile: URL

    init(supportDir: URL = GroupStore.defaultSupportDir()) {
        self.supportDir = supportDir
        self.groupsFile = supportDir.appendingPathComponent("groups.json")
        self.contextDir = supportDir.appendingPathComponent("context")
        self.currentFile = supportDir.appendingPathComponent("current.json")
        createDirectoriesIfNeeded()
        load()
        loadCurrentGroup()
    }

    static func defaultSupportDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("pepis")
    }

    func save(group: Group) {
        groups.append(group)
        persist()
        createContextFileIfNeeded(for: group)
        onChange?()
    }

    func update(id: UUID, windows: [WindowSnapshot]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].windows = windows
        persist()
        onChange?()
    }

    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        if currentGroupID == id {
            currentGroupID = nil
            persistCurrentGroup()
        }
        persist()
        onChange?()
    }

    func setCurrentGroup(id: UUID?) {
        currentGroupID = id
        persistCurrentGroup()
        onChange?()
    }

    func contextFileURL(for group: Group) -> URL {
        contextDir.appendingPathComponent("\(group.id.uuidString).md")
    }

    // MARK: - Private

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: groupsFile) else { return }
        groups = (try? JSONDecoder().decode([Group].self, from: data)) ?? []
    }

    private func loadCurrentGroup() {
        guard let data = try? Data(contentsOf: currentFile),
              let uuidString = try? JSONDecoder().decode(String.self, from: data),
              let id = UUID(uuidString: uuidString),
              groups.contains(where: { $0.id == id }) else {
            currentGroupID = nil
            return
        }
        currentGroupID = id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsFile, options: .atomic)
        }
    }

    private func persistCurrentGroup() {
        if let id = currentGroupID {
            if let data = try? JSONEncoder().encode(id.uuidString) {
                try? data.write(to: currentFile, options: .atomic)
            }
        } else {
            try? FileManager.default.removeItem(at: currentFile)
        }
    }

    private func createContextFileIfNeeded(for group: Group) {
        let url = contextFileURL(for: group)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm all 20 pass**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|Test.*failed|SUCCEEDED|FAILED"
```

Expected: `** TEST SUCCEEDED **` with 20 tests passing.

- [ ] **Step 5: Commit**

```bash
git add pepis/GroupStore.swift pepis-tests/GroupStoreTests.swift
git commit -m "feat: add currentGroupID, update, and setCurrentGroup to GroupStore"
```

---

## Task 2: MenuController — ✓ state, Update action, auto-save on restore

**Files:**
- Modify: `pepis/MenuController.swift`

Replace the entire contents of `pepis/MenuController.swift` with:

```swift
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
        // Auto-save current group state before switching (skip if restoring same group)
        if let currentID = store.currentGroupID, currentID != group.id {
            store.update(id: currentID, windows: WindowCapture.captureAll())
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
```

- [ ] **Step 1: Replace `pepis/MenuController.swift` with the code above**

- [ ] **Step 2: Build and run tests**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|SUCCEEDED|FAILED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Rebuild the app bundle**

```bash
xcodebuild -scheme pepis -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CONFIGURATION_BUILD_DIR=./build build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add pepis/MenuController.swift
git commit -m "feat: add Update action, current group checkmark, auto-save on restore"
```

---

## Task 3: Manual smoke test

- [ ] **Step 1: Relaunch the app**

```bash
pkill pepis 2>/dev/null; sleep 0.3; open build/pepis.app
```

- [ ] **Step 2: Verify the following**

1. Save a group named "A" — it should appear with ✓ in the menu
2. Rearrange some windows, save a group named "B" — ✓ moves to B
3. Click B → Restore — nothing visible happens (already on B); ✓ stays on B
4. Rearrange some windows, click A → Restore:
   - Current windows should be auto-saved to B
   - Windows restore to A's saved state
   - ✓ moves to A
5. Click B → Restore — windows should match what you had when you left B in step 4
6. Click A → Update — ✓ moves to A, A's windows updated with current state
7. Quit and relaunch — ✓ is still on the last active group

- [ ] **Step 3: Final commit**

```bash
git commit -m "feat: current group v1 — Update, auto-save on restore, persisted current group" --allow-empty
```
