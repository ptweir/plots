# Pepis — Window Groups App Design

**Date:** 2026-04-03
**Platform:** macOS (Apple Silicon + Intel laptops)
**Tech stack:** Swift, SwiftUI, AppKit

---

## Overview

A macOS menu bar app that lets you snapshot all open application windows (positions and sizes) into named groups, and restore them later. Groups persist across restarts.

---

## Architecture

### Components

| Component | Responsibility |
|---|---|
| `AppDelegate` | Entry point; creates `NSStatusItem`, owns `MenuController` and `GroupStore` |
| `GroupStore` | Loads/saves groups to disk; single source of truth; notifies observers on change |
| `WindowCapture` | Reads all running app windows via Accessibility API; returns array of `WindowSnapshot` |
| `WindowRestorer` | Given a `Group`, launches missing apps and repositions all windows via Accessibility API |
| `MenuController` | Rebuilds `NSMenu` from current `GroupStore` state whenever groups change |

### Data Model

```swift
struct WindowSnapshot: Codable {
    var appBundleID: String
    var appName: String
    var windowIndex: Int    // 0 = first window, 1 = second, etc.
    var frame: CGRect
}

struct Group: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var windows: [WindowSnapshot]
}
```

### Persistence

Groups are stored as JSON at:
```
~/Library/Application Support/pepis/groups.json
```

`GroupStore` reads on launch and writes on every mutation (create, delete).

---

## Menu Structure

```
[⊞ menu bar icon]
  ── Groups ──
  Morning setup  ▶  [Restore] [Delete]
  Deep work      ▶  [Restore] [Delete]
  Code review    ▶  [Restore] [Delete]
  ─────────────────
  + Save current windows as…
  ─────────────────
  Quit
```

- Clicking a group name opens a submenu with **Restore** and **Delete**
- "Save current windows as…" opens a small input dialog for the group name
- The app has no Dock icon (`LSUIElement = YES` in `Info.plist`)

---

## Window Capture

Uses `NSWorkspace.shared.runningApplications` to enumerate apps, then `AXUIElementCreateApplication` + `kAXWindowsAttribute` to get each app's windows and their `kAXPositionAttribute` / `kAXSizeAttribute`.

Windows are indexed in the order returned by the Accessibility API. Index is used to match windows on restore (1st window of app X → restore to saved frame for window index 0).

---

## Window Restore

1. For each `WindowSnapshot` in the group:
   - If the app is already running: find its window by index, set position + size via AX API
   - If the app is not running: launch via `NSWorkspace.shared.open(bundleID:)`, wait up to 2 seconds for it to appear, then reposition
2. Window matching is by bundle ID + window index. If an app has fewer windows than saved, extra snapshots are skipped silently.

---

## Permissions

The Accessibility API requires user permission granted once in:
**System Settings → Privacy & Security → Accessibility**

On first launch, the app calls `AXIsProcessTrustedWithOptions` with the prompt option, which shows the system dialog automatically.

---

## Error Handling

- **Permission denied:** Show a menu item "⚠ Accessibility access required" that opens System Settings when clicked
- **App fails to launch:** Skip that window, continue restoring others
- **No groups saved yet:** Show placeholder text "No groups yet" in menu
- **Malformed JSON on disk:** Start fresh with empty groups, log the error

---

## Project Structure

```
pepis/
  pepis.xcodeproj
  pepis/
    AppDelegate.swift
    GroupStore.swift
    WindowCapture.swift
    WindowRestorer.swift
    MenuController.swift
    Models.swift          // WindowSnapshot, Group
    Info.plist
    Assets.xcassets
  docs/
    superpowers/specs/
      2026-04-03-window-groups-design.md
```

---

## Out of Scope

- Multiple display support (positions are in global screen coordinates, so multi-monitor will work incidentally but won't be explicitly managed)
- Renaming groups
- Reordering groups
- Per-window app launch arguments or document paths
- iCloud sync
