# Pepis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that snapshots named groups of application windows (positions + sizes) and restores them on demand, with per-group markdown files for AI agent context.

**Architecture:** `AppDelegate` owns a `GroupStore` (JSON persistence) and a `MenuController` (NSMenu builder). `WindowCapture` reads window frames via the macOS Accessibility API; `WindowRestorer` launches apps and repositions windows using the same API. Groups and their context files live in `~/Library/Application Support/pepis/`.

**Tech Stack:** Swift 5.9, AppKit, ApplicationServices (AX API), XCTest, xcodegen (for project generation)

---

## File Map

| File | Responsibility |
|---|---|
| `project.yml` | xcodegen project definition |
| `pepis/Info.plist` | Bundle metadata; `LSUIElement=YES` suppresses Dock icon |
| `pepis/Models.swift` | `WindowSnapshot` and `Group` structs — `Codable`, no dependencies |
| `pepis/GroupStore.swift` | Load/save `groups.json`; create/delete context `.md` files; `onChange` callback |
| `pepis/WindowCapture.swift` | Read all running app windows via AX API → `[WindowSnapshot]` |
| `pepis/WindowRestorer.swift` | Launch missing apps, reposition windows via AX API |
| `pepis/MenuController.swift` | Build and own `NSMenu`; wire store actions; handle save dialog |
| `pepis/AppDelegate.swift` | App entry point; own all top-level objects; request AX permission |
| `pepis-tests/ModelsTests.swift` | Codable round-trip tests for `WindowSnapshot` and `Group` |
| `pepis-tests/GroupStoreTests.swift` | Save/load/delete groups; context file creation; malformed JSON recovery |

---

## Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `pepis/Info.plist`
- Create: `pepis-tests/` (empty directory placeholder)

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
```

Expected: `xcodegen version X.Y.Z` on completion.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: pepis
options:
  bundleIdPrefix: com.pepis
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
schemes:
  pepis:
    build:
      targets:
        pepis: all
        pepis-tests: testing
    run:
      config: Debug
    test:
      targets:
        - name: pepis-tests
          randomExecutionOrder: false
targets:
  pepis:
    type: application
    platform: macOS
    sources:
      - pepis
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pepis.app
        INFOPLIST_FILE: pepis/Info.plist
        SWIFT_VERSION: "5.9"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
        CODE_SIGNING_ALLOWED: "NO"
  pepis-tests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - pepis-tests
    dependencies:
      - target: pepis
    settings:
      base:
        SWIFT_VERSION: "5.9"
        TEST_HOST: ""
        BUNDLE_LOADER: ""
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
        CODE_SIGNING_ALLOWED: "NO"
```

- [ ] **Step 3: Write `pepis/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>pepis</string>
    <key>CFBundleIdentifier</key>
    <string>com.pepis.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Pepis needs Accessibility access to read and restore window positions.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create source and test directories**

```bash
mkdir -p pepis pepis-tests
```

- [ ] **Step 5: Generate the Xcode project**

```bash
xcodegen generate
```

Expected output: `✔ Generated: pepis.xcodeproj`

- [ ] **Step 6: Verify project builds (no sources yet — expect "no Swift files" warning but no error)**

```bash
xcodebuild -scheme pepis -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add project.yml pepis/Info.plist pepis.xcodeproj
git commit -m "chore: scaffold xcodegen project"
```

---

## Task 2: Models

**Files:**
- Create: `pepis/Models.swift`
- Create: `pepis-tests/ModelsTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// pepis-tests/ModelsTests.swift
import XCTest
@testable import pepis

final class ModelsTests: XCTestCase {

    func testWindowSnapshotCodableRoundTrip() throws {
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            windowIndex: 0,
            frame: CGRect(x: 100, y: 200, width: 1200, height: 800)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WindowSnapshot.self, from: data)
        XCTAssertEqual(decoded.appBundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.appName, "Safari")
        XCTAssertEqual(decoded.windowIndex, 0)
        XCTAssertEqual(decoded.frame, CGRect(x: 100, y: 200, width: 1200, height: 800))
    }

    func testGroupCodableRoundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000000)
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Terminal",
            appName: "Terminal",
            windowIndex: 1,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let group = Group(id: id, name: "Morning setup", createdAt: date, windows: [snapshot])
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(Group.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Morning setup")
        XCTAssertEqual(decoded.createdAt, date)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows[0].appBundleID, "com.apple.Terminal")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail (Models.swift doesn't exist yet)**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: build error — `cannot find type 'WindowSnapshot'`

- [ ] **Step 3: Write `pepis/Models.swift`**

```swift
// pepis/Models.swift
import Foundation
import CoreGraphics

struct WindowSnapshot: Codable {
    var appBundleID: String
    var appName: String
    var windowIndex: Int
    // CGRect is not Codable — store components as Doubles
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
}

extension WindowSnapshot {
    var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    init(appBundleID: String, appName: String, windowIndex: Int, frame: CGRect) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowIndex = windowIndex
        self.frameX = frame.origin.x
        self.frameY = frame.origin.y
        self.frameWidth = frame.size.width
        self.frameHeight = frame.size.height
    }
}

struct Group: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var windows: [WindowSnapshot]
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|Test.*failed|FAILED|SUCCEEDED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add pepis/Models.swift pepis-tests/ModelsTests.swift
git commit -m "feat: add WindowSnapshot and Group models with Codable"
```

---

## Task 3: GroupStore

**Files:**
- Create: `pepis/GroupStore.swift`
- Create: `pepis-tests/GroupStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// pepis-tests/GroupStoreTests.swift
import XCTest
@testable import pepis

final class GroupStoreTests: XCTestCase {

    var tempDir: URL!
    var store: GroupStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        store = GroupStore(supportDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStartsEmpty() {
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testSaveAndReload() throws {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertEqual(reloaded.groups.count, 1)
        XCTAssertEqual(reloaded.groups[0].name, "Work")
    }

    func testDeleteGroup() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.delete(id: group.id)
        XCTAssertTrue(store.groups.isEmpty)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertTrue(reloaded.groups.isEmpty)
    }

    func testSaveCreatesContextFile() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        let contextURL = store.contextFileURL(for: group)
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextURL.path))
    }

    func testContextFileURLMatchesGroupID() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        let url = store.contextFileURL(for: group)
        XCTAssertEqual(url.lastPathComponent, "\(group.id.uuidString).md")
    }

    func testMalformedJSONStartsEmpty() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let corruptData = "not json".data(using: .utf8)!
        let groupsFile = tempDir.appendingPathComponent("groups.json")
        try corruptData.write(to: groupsFile)

        let store = GroupStore(supportDir: tempDir)
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testOnChangeCalledOnSave() {
        var callCount = 0
        store.onChange = { callCount += 1 }
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        XCTAssertEqual(callCount, 1)
    }

    func testOnChangeCalledOnDelete() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        var callCount = 0
        store.onChange = { callCount += 1 }
        store.delete(id: group.id)
        XCTAssertEqual(callCount, 1)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|cannot find"
```

Expected: build error — `cannot find type 'GroupStore'`

- [ ] **Step 3: Write `pepis/GroupStore.swift`**

```swift
// pepis/GroupStore.swift
import Foundation

final class GroupStore {
    private(set) var groups: [Group] = []
    var onChange: (() -> Void)?

    private let supportDir: URL
    private let groupsFile: URL
    private let contextDir: URL

    init(supportDir: URL = GroupStore.defaultSupportDir()) {
        self.supportDir = supportDir
        self.groupsFile = supportDir.appendingPathComponent("groups.json")
        self.contextDir = supportDir.appendingPathComponent("context")
        createDirectoriesIfNeeded()
        load()
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

    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        persist()
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

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsFile, options: .atomic)
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

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|Test.*failed|FAILED|SUCCEEDED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add pepis/GroupStore.swift pepis-tests/GroupStoreTests.swift
git commit -m "feat: add GroupStore with JSON persistence and context file management"
```

---

## Task 4: WindowCapture

**Files:**
- Create: `pepis/WindowCapture.swift`

> Note: `WindowCapture` calls the macOS Accessibility API, which requires a running app with permission granted. It cannot be meaningfully unit tested. Verification is manual (Task 9).

- [ ] **Step 1: Write `pepis/WindowCapture.swift`**

```swift
// pepis/WindowCapture.swift
import AppKit
import ApplicationServices

enum WindowCapture {
    /// Returns a snapshot of all visible windows across all regular (non-background) apps.
    /// Requires Accessibility permission — returns empty array if not granted.
    static func captureAll() -> [WindowSnapshot] {
        guard AXIsProcessTrusted() else { return [] }

        var snapshots: [WindowSnapshot] = []
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for (index, window) in windows.enumerated() {
                guard let frame = axFrame(of: window) else { continue }
                snapshots.append(WindowSnapshot(
                    appBundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowIndex: index,
                    frame: frame
                ))
            }
        }
        return snapshots
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
```

- [ ] **Step 2: Verify project still builds**

```bash
xcodebuild -scheme pepis -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add pepis/WindowCapture.swift
git commit -m "feat: add WindowCapture using Accessibility API"
```

---

## Task 5: WindowRestorer

**Files:**
- Create: `pepis/WindowRestorer.swift`

> Note: `WindowRestorer` also calls the AX API. Manual verification in Task 9.

- [ ] **Step 1: Write `pepis/WindowRestorer.swift`**

```swift
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
```

- [ ] **Step 2: Verify project still builds**

```bash
xcodebuild -scheme pepis -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add pepis/WindowRestorer.swift
git commit -m "feat: add WindowRestorer — launch apps and reposition windows via AX API"
```

---

## Task 6: MenuController

**Files:**
- Create: `pepis/MenuController.swift`

- [ ] **Step 1: Write `pepis/MenuController.swift`**

```swift
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
```

- [ ] **Step 2: Verify project still builds**

```bash
xcodebuild -scheme pepis -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add pepis/MenuController.swift
git commit -m "feat: add MenuController — NSMenu wired to GroupStore"
```

---

## Task 7: AppDelegate and Entry Point

**Files:**
- Create: `pepis/AppDelegate.swift`

- [ ] **Step 1: Write `pepis/AppDelegate.swift`**

```swift
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
        AXIsProcessTrustedWithOptions(options)
    }
}
```

- [ ] **Step 2: Build and run tests**

```bash
xcodebuild test -scheme pepis -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|Test.*failed|FAILED|SUCCEEDED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add pepis/AppDelegate.swift
git commit -m "feat: add AppDelegate — wires store, status item, and menu controller"
```

---

## Task 8: Accessibility Error State in Menu

When Accessibility permission has not been granted, `WindowCapture.captureAll()` returns `[]` silently. The menu should also surface a visible warning.

**Files:**
- Modify: `pepis/MenuController.swift`

- [ ] **Step 1: Add permission check to `rebuild()` in `MenuController.swift`**

Replace the top of `rebuild()` — find the line `let menu = NSMenu()` and add the warning block after it:

```swift
func rebuild() {
    let menu = NSMenu()

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

    // ... rest of method unchanged
```

Also add the selector at the bottom of `MenuController`:

```swift
    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
```

Add `import ApplicationServices` at the top of `MenuController.swift`.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme pepis -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add pepis/MenuController.swift
git commit -m "feat: show accessibility warning in menu when permission not granted"
```

---

## Task 9: Gitignore and Manual Smoke Test

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Xcode
*.xcuserstate
xcuserdata/
DerivedData/
*.xcworkspace
!default.xcworkspace

# Superpowers brainstorm sessions
.superpowers/

# macOS
.DS_Store
```

- [ ] **Step 2: Commit .gitignore**

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```

- [ ] **Step 3: Build a runnable app**

```bash
xcodebuild -scheme pepis -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CONFIGURATION_BUILD_DIR=./build build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` and `build/pepis.app` exists.

- [ ] **Step 4: Manual smoke test — run the app**

```bash
open build/pepis.app
```

Expected behavior to verify:
1. No Dock icon appears
2. `⊞` appears in the menu bar — click it
3. If Accessibility not granted: `⚠ Accessibility access required` appears; clicking it opens System Settings
4. After granting permission in System Settings, quit and re-open the app
5. Click `⊞` → `Save current windows as…` → type `Test group` → Save
6. The menu now shows `Test group` with Restore / Edit context / Delete submenu
7. Click `Edit context` → a `.md` file opens in your default editor
8. Quit the app, re-open — `Test group` is still in the menu (persisted)
9. Click `Restore` — open apps reposition to saved frames; closed apps launch and reposition

- [ ] **Step 5: Verify persistence file locations**

```bash
ls ~/Library/Application\ Support/pepis/
ls ~/Library/Application\ Support/pepis/context/
```

Expected: `groups.json` and one `*.md` file per saved group.

- [ ] **Step 6: Final commit**

```bash
git add build/ 2>/dev/null || true   # only if build artifacts were staged accidentally
git status
# stage anything unstaged that should be tracked
git commit -m "feat: pepis v1.0 — window group manager with AI context files" --allow-empty
```

---

## Self-Review Notes

- `CGRect` codability handled by storing flat `frameX/Y/Width/Height` in `WindowSnapshot` — consistent across Models, GroupStore tests, and usage in Capture/Restorer.
- `onChange` callback pattern used throughout — defined in GroupStore, assigned in MenuController init.
- Context file URL is always derived from `store.contextFileURL(for:)` — never computed independently.
- `AXIsProcessTrusted()` (no options) used for silent checks; `AXIsProcessTrustedWithOptions` (with prompt) used only at launch.
- `WindowCapture` and `WindowRestorer` both guard on `AXIsProcessTrusted()` — no AX calls without permission.
- `delete(id:)` takes a `UUID` (not a `Group`) — matches what `MenuController` stores in `representedObject`.
