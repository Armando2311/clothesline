# Testing

This file separates what has been **verified automatically**, what was **inspected
visually** from rendered output, and what **still needs a person at a Mac**. The app was
developed in a Linux container without a display; all macOS verification ran on GitHub
Actions `macos-15` runners.

## 1. Automated (runs on every push)

| Check | Where | Result |
|---|---|---|
| Core unit tests: board operations, dedupe, ordering, lines, retention, expiry scheduling, persistence round trip, corrupt-file recovery, owned-file deletion confinement (incl. path traversal), settings decoding, screenshot classification, link detection, rope geometry, layout, panel placement for notched/plain/external displays | Linux + macOS | see CI |
| App compiles (debug + universal release, arm64 + x86_64) | macOS | see CI |
| Bundle: Info.plist lint, `lipo` architectures, `codesign --verify --strict` | macOS | see CI |
| Launch smoke test: app starts, stays alive 16 s, reports CPU/RSS while idle | macOS | see CI |
| Render test: real `LineView` with sample items in 4 themes + empty state → PNG | macOS | see CI |
| XcodeGen project generates and builds | macOS | see CI |

## 2. Manual verification checklist

Run on real hardware. Record macOS version and Mac model for each run.

### Screenshots
- [ ] ⇧⌘3 → print appears within ~0.5 s, line peeks without taking focus (typing in the front app keeps working).
- [ ] ⇧⌘4 region, ⇧⌘4 then Space (window) → each appears once.
- [ ] Five screenshots in rapid succession → five prints, no duplicates, in order.
- [ ] ⇧⌘5 › Options › Save to › Documents → next screenshot is hung from Documents (no restart).
- [ ] ⇧⌘5 › Options › Clipboard → Settings › Screenshots shows the clipboard notice; ⌃⌥V hangs it.
- [ ] Copy an old screenshot into the Desktop → **not** hung.
- [ ] Save a regular image named "Screenshot …png" to the Desktop from another app → not hung (no screen-capture attribute).
- [ ] Take a screenshot, sleep the Mac, wake → watcher still works; screenshots taken while asleep… (n/a) / taken right before sleep appear once.
- [ ] Screenshot folder on an external drive, unplug and replug → status shows unavailable, then recovers.
- [ ] Screen recording with "Include screen recordings" on/off.

### Drag and drop in
- [ ] Finder: one file, several files, a folder, an app bundle (hangs as file).
- [ ] Desktop file; file on external drive; file on a network share.
- [ ] Safari: drag an image (owned copy), drag a link (link tag), drag selected text (note).
- [ ] Chrome / Firefox: image and link.
- [ ] Photos: drag a photo (file promise → owned copy).
- [ ] Mail: drag an attachment.
- [ ] Drag a file to the very top edge of the screen with the line hidden → it peeks; drop → item hangs; drag away without dropping → it hides.
- [ ] Insertion gap opens where the item will land.

### Drag and drop out
- [ ] Drag one print to a Finder folder on the **same** volume → **copy** made, original stays.
- [ ] Same with ⌘ held → moved; item leaves the line.
- [ ] Select three prints (⌘-click), drag together to a folder → three copies.
- [ ] Drag to Mail compose, Messages, Notes, Pages/TextEdit → file attached / inserted.
- [ ] Drag a note to TextEdit (text inserted) and to Finder (.txt created).
- [ ] Drag a link to Finder (.webloc) and to a browser tab (opens).
- [ ] Drag onto the Dock Trash → refused (no delete operation offered).
- [ ] Drag an item along the line → reorders.

### File safety & robustness
- [ ] Remove from line → file untouched; ⌘Z restores it.
- [ ] Move File to Trash… → confirmation; file is in Trash; Put Back works.
- [ ] Rename a hung file in Finder → item follows it (title updates on next open).
- [ ] Move it to another folder on the same disk → still works.
- [ ] Delete it → MISSING stamp; Locate File… repairs it.
- [ ] Unplug its drive → OFFLINE; replug → available again.
- [ ] Quit and relaunch → all items, lines, pins and order restored.
- [ ] Corrupt `~/Library/Application Support/Clothesline/state.json` → app starts empty and keeps the bad file as `state.corrupt-*.json`.

### Window, displays, focus
- [ ] Notched MacBook: line hangs from just below the notch, centre hook under the notch.
- [ ] Non-notched MacBook / external display: line under the menu bar, single swag.
- [ ] Two displays: line opens on the display with the pointer; moving displays while open repositions.
- [ ] Menu bar set to auto-hide; full-screen app (Safari full screen, Keynote) → line appears above it.
- [ ] Mission Control and ⌘` don't show the panel.
- [ ] Opening with ⌃⌥C keeps the previous app frontmost (its menu bar stays).
- [ ] Click into another app → line hides. Esc hides.
- [ ] Space opens Quick Look above the line; ← → move through items.
- [ ] Light/Dark switch with theme Automatic → Summer ↔ Midnight.
- [ ] Reduce Motion on → no drops/swings/particles, simple fades.
- [ ] VoiceOver: items are announced with kind and name; VO-Space opens Quick Look.

### Settings
- [ ] Record a new shortcut; re-record the current one; a conflicting one shows the warning.
- [ ] Launch at login toggles (from the .app); appears in System Settings › General › Login Items.
- [ ] Retention: limit 10 screenshots → oldest unpinned leave first; pinned survive.
- [ ] Temporary line clears after its period (set a short period by editing to verify).

### Performance
- [ ] Activity Monitor: idle CPU 0.0 % with line hidden; Energy Impact "Low".
- [ ] Line open with breeze + particles: CPU of Clothesline process ~0 % (animation in WindowServer).
- [ ] 100 items on a line: opens without visible delay; scrolling smooth.
- [ ] Leave running 24 h with screenshots: memory stays flat (Instruments › Leaks).
