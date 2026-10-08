# Clothesline

A small macOS utility that hangs a clothesline under the top of your screen. Screenshots,
files, folders, links and notes hang from it on wooden clothespins until you drag them where
they need to go.

**Capture → Hang → Grab → Drop.**

* Take a screenshot (⇧⌘3 / ⇧⌘4 / ⇧⌘5) and it clips itself onto the line as a small photo print.
* Press **⌃⌥C** to show or hide the line. It opens under the menu bar, hanging from the notch
  on MacBooks that have one.
* Drag things onto the line from Finder, the Desktop, browsers, Mail, Photos…
* Drag items off the line into Finder, Mail, Messages or any app that accepts files. Several
  at once if you like.
* Press **⌃⌥V** to hang whatever is on the clipboard.

Everything stays on your Mac. No accounts, no analytics, no network access.

## Requirements

* macOS 13 Ventura or later, Apple silicon or Intel.
* To build: Xcode 15 or later (Swift 5.9+). Tested in CI with Xcode on macOS 15.

## Build and run

```bash
# Build Clothesline.app into ./build (ad hoc signed)
Scripts/build-app.sh             # this Mac's architecture
Scripts/build-app.sh --universal # Apple silicon + Intel

open build/Clothesline.app
```

For development you can also run straight from the package. An Info.plist is embedded in
the executable, so it gets its bundle identifier and accessory-app behavior:

```bash
swift run Clothesline
```

To use Xcode, either open `Package.swift` directly, or generate a project:

```bash
brew install xcodegen
xcodegen generate
open Clothesline.xcodeproj
```

*Launch at login* only works from the `.app` bundle (it uses `SMAppService`).

### Tests

```bash
swift test   # 40 unit tests for the core logic; also run on Linux in CI
```

CI (`.github/workflows/build.yml`) runs on every push. It runs the core tests on Linux and
macOS, builds the universal app bundle, verifies the signature, launches the app and checks
that it stays running and idle, renders the line with sample items to an image, and builds
the XcodeGen project.

`Clothesline --render-preview out.png` draws the real line view with sample content
(all four themes plus the empty state) without opening a window.

## Using Clothesline

| | |
|---|---|
| Show / hide | ⌃⌥C (configurable), the menu bar icon, or open the app again |
| Hang clipboard | ⌃⌥V (configurable) or ⌘V while the line is open |
| Select | Click, ⌘-click, ⇧-click, ← →, ⌘A |
| Preview | Space or ⌘Y (Quick Look). Hover for name and size |
| Open | Double-click or ↩ |
| Remove from line | ⌫. The file is **not** touched. ⌘Z brings it back |
| Pin | P. A painted clothespin means the item survives cleanups |
| Rearrange | Drag an item along the line |
| Lines | ⇥ / ⌘1–9 switch lines. Right-click the rope for New Line, Arrange By, Clear… |
| Hide | Esc, ⌘W, the shortcut again, or click anywhere else |

### What happens to your files

* **Hanging a file never moves or copies it.** Clothesline stores a reference (a bookmark)
  that keeps working if you rename or move the file on the same disk.
* **Removing an item only removes it from the line.**
* **Dragging out copies.** Hold ⌘ while dragging to move instead, the same as in Finder.
* **Moving a file or putting it in the Trash** are separate, clearly labelled menu commands
  that always ask first. Trash can be undone from the Trash.
* Images dropped from a browser, file promises and pasted images have no original file, so
  Clothesline keeps its own copy. That copy is discarded when the item leaves the line.
* If a file is deleted the item shows **MISSING** (use *Locate File…*). If its drive is
  unplugged it shows **OFFLINE** and comes back when the drive does.

## Permissions

* **Desktop folder access.** macOS asks the first time Clothesline reads your screenshot
  folder (the Desktop by default). This is needed to detect new screenshots.
* No Accessibility, Input Monitoring or Screen Recording permission is needed. The global
  shortcuts use the Carbon hot key API, and the drag-to-top-edge reveal uses a global mouse
  monitor; neither needs a permission.

## Limitations

* **Screenshots copied to the clipboard** (⌃⇧⌘3/4, or *Save to: Clipboard*) are not files, so
  they can't be detected without watching the clipboard, which Clothesline deliberately
  doesn't do. Press ⌃⌥V afterwards to hang it. Settings shows a notice when macOS is set to
  save screenshots to the clipboard.
* Screenshots sent straight to Preview, Mail or Messages from the Screenshot app are never
  written to the screenshot folder, so they aren't hung.
* The sandboxed Mac App Store variant (see `Resources/Clothesline-AppStore.entitlements`)
  can't read the system screenshot location; there you choose the folder once in Settings.
* The default build is ad hoc signed. To distribute it, sign with a Developer ID
  (`CODESIGN_IDENTITY=… Scripts/build-app.sh`) and notarize it.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions and
[docs/TESTING.md](docs/TESTING.md) for what has been verified and what still needs manual
testing.
