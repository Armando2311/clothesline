# Testing

This file separates what has been **verified automatically**, what was **inspected
visually** from rendered output, and what **still needs a person at a Mac**. The app was
originally developed in a Linux container; the current workflow upgrade also has local macOS verification.

## Current local verification — 2026-10-08

The workflow upgrade and redesign were built on a real Mac using Xcode 26.3 and macOS 26.5. Historical CI measurements below describe the original baseline, not the current build's memory or performance.

- `swift test`: 85 tests, including core, images/exports, OCR, collection navigation and native line regressions. Current result recorded after the final review pass.
- App `--self-test`: 27 checks.
- Xcode Debug build succeeds with DerivedData under `/tmp` (the Documents file provider adds Finder metadata that can prevent signing generated bundles).
- Rendered preview includes four illustrated themes, two Compact themes, selection, empty state and actual AppKit-cached SwiftUI toolbar controls. Portrait proportions and 2x bitmap dimensions also have regression coverage.
- Independent review findings addressed: source image overwrite/aliases, native modal ordering, and stale OCR after modifying an image while search stays active.
- Interrupted onboarding remains pending until Get Started. Screenshot e2e script explicitly completes onboarding through the launch argument domain for its test process rather than changing the user's saved completion preference.

Native pointer checks confirmed vertical grip movement and saved position, survival after clicking Xcode, explicit bottom-button close, image number/redaction gestures, accepted derivative Replace, and visible Save/Open panels above the persistent line. The QA app used a separate bundle identifier and sample state.

Native controller/responder tests cover vertical motion, losing key focus, explicit close, search filtering without deletion animation, arrow navigation, Delete/undo, select-all and text-editing isolation. Pointer-driven file dragging, additional display/Dock configurations, signed release/notarization and VoiceOver remain hardware verification items. The line now stays open after screenshots, outside clicks and drops until explicitly toggled or closed; older auto-hide checklist expectations below are superseded.

## 1. Automated (runs on every push) — all passing

Historical baseline green run: GitHub Actions `Build & Test` #10, commit `f3bc0c7`, `macos-15` runner + `ubuntu-latest`.

| Check | Where | Result |
|---|---|---|
| 42 core unit tests: board operations, dedupe, ordering, lines, retention, expiry scheduling, persistence round trip, corrupt-file recovery, owned-file deletion confinement (incl. path traversal), settings decoding, screenshot classification, link detection, rope geometry, layout, panel placement for notched/plain/external displays | Linux + macOS | ✅ 42/42 |
| App compiles: debug, and universal release (arm64 + x86_64) | macOS | ✅ (1 Swift 6-mode warning fixed; 0 warnings remaining in the last log) |
| Bundle: `plutil -lint`, `lipo -info` (x86_64 arm64), `codesign --verify --deep --strict` | macOS | ✅ |
| Launch smoke test: app starts and stays up; idle CPU after 16 s **0.0 %**, RSS **≈32 MB** | macOS | ✅ |
| `--self-test` (27 checks with real files, pasteboards and bookmarks): file drop hung by reference with no copy; duplicate drop ignored; pasted image becomes an owned copy inside Clothesline's folder; URL string → link, text → note; drag-out writers give the real file URL, note text + file promise, link `public.url`; removing never touches referenced files; owned copy kept while undoable, deleted once final; undo restores; bookmark follows a rename; deleted file → MISSING and stays on the line; state restored after relaunch in order; Copy To never overwrites; screen-capture attribute read correctly | macOS | ✅ 27/27 |
| Screenshot end-to-end (real app binary, simulated `screencapture` writes): single shot hung; burst of 5 hung without duplicates; impostor image named "Screenshot …" and unrelated image ignored; re-touching doesn't duplicate; `defaults write com.apple.screencapture location` followed live without restart | macOS | ✅ 5/5 |
| Render test: real `LineView` with sample items in 4 themes + empty state + selection | macOS | ✅ inspected visually |
| XcodeGen project generates and builds | macOS | ✅ |

### Bug found by these tests
The end-to-end test caught a real defect: FSEvents reports canonical paths
(`/private/var/…`) while the watched folder was compared in its symlinked form
(`/var/…`), so screenshots in symlinked folders were silently ignored. Fixed by comparing
`realpath()`s (commit `2fd3653`).

### What automation cannot cover
Mouse-driven drag sessions between apps, the actual ⇧⌘3 keystroke path, global hotkey
delivery, focus behaviour with other apps, notch placement on real hardware, animation feel
and Quick Look all need a person — see §2. The simulated screenshot test reproduces exactly
what `screencapture` writes to disk (hidden temp file → attribute → rename), but not the
keystroke itself.

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
- [ ] Take a screenshot, sleep the Mac, wake → watcher still works; a screenshot taken right before sleep appears exactly once.
- [ ] Screenshot folder on an external drive, unplug and replug → status shows unavailable, then recovers.
- [ ] Screen recording with "Include screen recordings" on/off.

### Drag and drop in
- [ ] Finder: one file, several files, a folder, an app bundle (hangs as file).
- [ ] Desktop file; file on external drive; file on a network share.
- [ ] Safari: drag an image (owned copy), drag a link (link tag), drag selected text (note).
- [ ] Chrome / Firefox: image and link.
- [ ] Photos: drag a photo (file promise → owned copy).
- [ ] Mail: drag an attachment.
- [ ] Drag a file to the very top edge of the screen with the line hidden → it peeks; drop → item hangs; drag away without dropping → it stays until explicitly closed.
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
