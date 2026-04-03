# Pepis — Current Group & Update Design

**Date:** 2026-04-03
**Builds on:** `2026-04-03-window-groups-design.md`

---

## Overview

Two new behaviors:

1. **Update existing group** — each group's submenu gains an "Update" item that replaces its saved windows with the current screen state.
2. **Auto-save on restore** — when restoring group X while group Y is current, automatically save the current windows to Y first. If restoring the current group, just revert (no auto-save). The current group persists across restarts.

---

## Data Model Changes

### `GroupStore` additions

```swift
private(set) var currentGroupID: UUID?

func update(id: UUID, windows: [WindowSnapshot])  // replace windows, persist, call onChange
func setCurrentGroup(id: UUID?)                    // set currentGroupID, persist, call onChange
```

### Persistence

`currentGroupID` is stored in a separate file:
```
~/Library/Application Support/pepis/current.json   ← {"currentGroupID": "uuid-string"}
```

Kept separate from `groups.json` so the groups format is unchanged. If the file is missing or the UUID references a deleted group, `currentGroupID` is treated as `nil`.

---

## Restore Flow

```
User clicks Restore on group X:
  if currentGroupID != nil AND currentGroupID != X.id:
    windows = WindowCapture.captureAll()
    update(id: currentGroupID!, windows: windows)
  WindowRestorer.restore(group: X)
  setCurrentGroup(id: X.id)
```

- Restoring the current group: skips auto-save (reverts to saved state)
- Restoring a different group: saves current screen to the old group first

---

## Update Flow

```
User clicks Update on group X:
  windows = WindowCapture.captureAll()
  update(id: X.id, windows: windows)
  setCurrentGroup(id: X.id)
```

Updating a group also makes it current (you're now working in that context).

---

## Save New Group Flow

```
User saves new group with name N:
  group = Group(id: UUID(), name: N, createdAt: now, windows: WindowCapture.captureAll())
  store.save(group: group)
  setCurrentGroup(id: group.id)   ← new: newly saved group becomes current
```

---

## Menu Changes

### Group submenu

```
Morning setup ✓ ▶  [Restore] [Update] [Edit context] [Delete]
Deep work        ▶  [Restore] [Update] [Edit context] [Delete]
```

- ✓ state (`NSMenuItem.state = .on`) on the top-level group item when `group.id == store.currentGroupID`
- "Update" item added between "Restore" and "Edit context"

---

## Files Changed

| File | Change |
|---|---|
| `pepis/GroupStore.swift` | Add `currentGroupID`, `update(id:windows:)`, `setCurrentGroup(id:)`, load/save `current.json` |
| `pepis/MenuController.swift` | ✓ state on current group item; "Update" submenu item + action; `setCurrentGroup` on save |
| `pepis-tests/GroupStoreTests.swift` | Tests for `update`, `setCurrentGroup`, persistence of `currentGroupID`, stale UUID handling |

---

## Error Handling

- **No current group (`currentGroupID` is nil):** first restore ever, or after a fresh install. Skip the auto-save step entirely — just restore and set the target as current.
- **No groups saved yet:** menu shows "No groups yet" as before; restore and update flows are unreachable. `currentGroupID` stays `nil`.
- **currentGroupID references a deleted group:** treat as `nil` on load (validate against groups array after loading)
- **WindowCapture returns empty (no AX permission):** `update` is called with `[]` — silently replaces windows with empty array. This is acceptable; the user will see the warning in the menu if they try to restore.
- **`update` called with unknown ID:** no-op, no error

---

## Out of Scope

- Showing a diff or confirmation before auto-saving on restore
- Undo for auto-save
- "Update" updating `createdAt` (creation date is preserved)
