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

Files and recognized text stay on your Mac. No accounts or analytics. The explicit Check for Updates action contacts GitHub.

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
swift test   # core and native macOS regressions; core also runs on Linux in CI
```

CI (`.github/workflows/build.yml`) runs on every push. It runs the core tests on Linux and
macOS, builds the universal app bundle, verifies the signature, launches the app and checks
that it stays running and idle, runs `Clothesline --self-test` (real files, pasteboards and
bookmarks), runs `Scripts/e2e-screenshot-test.sh` against the real binary, renders the line
with sample items to an image, and builds the XcodeGen project.

`Clothesline --render-preview out.png` draws the real line view with sample content
(all themes, Compact layouts, toolbar and empty state) without opening a window.

## Workflow tools

The control bar exposes line switching, search, collection browsing, Preview, Copy,
Share, Prepare Image and Export. Search with **⌘F** across every line, including note
contents, URLs and text recognized locally in screenshots and images. OCR starts when
search is used; new matches appear as recognition completes.

Choose **Settings → Appearance → Compact** for upright cards with less decoration.
The expanded collection browser supports multiple selection (⌘-click), Quick Look,
copy-by-default multi-item dragging, editable notes and labels that leave filenames intact.

**Prepare Image** offers cropping, arrows, numbered steps, opaque redaction, undo,
resize, PNG/JPEG output, and an optional JPEG size limit. Copy, hang or save a flattened
result; the original is never overwritten. Cropping preserves existing annotations.

**Export** includes three configurable recipes:

* **Client Handoff:** resize and number JPEG copies, collect other attachments, include
  notes and links in `Report.md`, then create a ZIP or folder.
* **Bug Report:** preserve attachments and add reproduction steps, expected/actual results,
  notes and links to a Markdown report. Copy the report after exporting.
* **Product Listing:** resize, optionally center-crop and number image copies.

Recipe settings and the chosen destination are remembered locally. Exports use new names
instead of overwriting existing files. A selected folder cannot be exported into itself or
its descendants. Cancellation discards the staged package. Hosted sharing, sync, billing,
and automatic clipboard history are not included.

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
| Hide | Esc, ⌘W, the shortcut again, or EXIT in the hover toolbar |

### What happens to your files

* **Hanging a file never moves or copies it.** Clothesline stores a reference (a bookmark)
  that keeps working if you rename or move the file on the same disk.
* **Removing an item only removes it from the line.**
* **Dragging out copies.** Hold ⌘ while dragging to move instead, the same as in Finder.
* **Moving a file or putting it in the Trash** are separate, clearly labelled menu commands
  that always ask first. Trash can be undone from the Trash.
* Images dropped from a browser, file promises and pasted images have no original file, so
  Clothesline keeps its own copy. That copy is retained while undo or activity history can restore it, then eligible for cleanup.
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

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions,
[docs/TESTING.md](docs/TESTING.md) for what has been verified and what still needs manual
testing, and [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

### Smaller, persistent clothesline

The illustrated line is now 210 points high (Compact: 190), with larger dark card labels and a shallower rope. Clicks in Finder or another app leave it open while you pick up files. Close it with Escape, Control–Option–C (or your configured toggle shortcut), or EXIT at the right of the hover toolbar. Drag the up/down grip at the toolbar's left to uncover files behind it; the position is saved per display and constrained to the visible desktop.

Search uses gentle filtering without deletion effects. Compact thumbnails retain their aspect ratio at Retina scale. OCR is debounced, runs off the UI thread, and caches results locally across launches. JPEG exports explicitly composite transparency over white. Save Result allows replacing an existing derivative after native confirmation, while protecting the source image, symlinks and hardlinks. Collection browsing supports arrow keys, Space preview, Delete/undo and Command–A/C/F.

### Hover toolbar and new themes

The toolbar stays hidden until the pointer enters the line, then fades and slides into view in 180 ms. Click the **pin** button next to Settings to keep it visible when the pointer leaves; click again to restore hover behavior. The preference survives closing and relaunching. It stays available during keyboard search and open menus. Escape, the configured toggle, and the larger **EXIT** button close the line. The gear button opens Settings; Command–comma also opens Settings from the line.

Choose **Sakura Morning**, **Ocean Breeze**, **Lavender Twilight**, or **Liquid Glass** under Settings → Appearance → Themes. Liquid Glass uses a persistent native frosted backdrop with a clear glass finish on Xcode 26/macOS 26, and the same frosted foundation on older supported builds. Its active backdrop stays consistent when selecting files, revealing controls or moving focus to another app. Subtle edge lighting and a floating shadow add depth without obscuring the cards. Cards retain contrasting paper backgrounds. Reduce Motion replaces the slide with a simple fade.

Choose **No Theme** in Settings → Appearance to float only the rope and files over the desktop or any app, with no panel backdrop in either Illustrated or Compact mode. The toolbar floats on its own translucent surface.


## Premium workflow improvements

* **A fitted line:** automatically sizes to its contents, with full-width and card-size options. No Theme can optionally pass clicks through empty space; optional shake-to-reveal is available in Settings.
* **Contextual controls:** selection actions appear when useful, less frequent actions live in More, and Pin, Settings and EXIT remain reachable.
* **Organized dragging:** insertion feedback, batch counts, line drop targets and named collapsible groups. Option-drop creates a group; double-click a collapsed stack to expand it.
* **Reusable exports:** named presets remember destinations, PNG/JPEG outputs, image dimensions and byte limits. Preview reports encoded output size before ZIP compression; impossible limits block export.
* **Automatic collections:** source/kind rules route new items; folder rules collect stable writes from the selected folder. Preview a rule before enabling it, and pause it anytime.
* **Project workspaces:** each line remembers its project context, destination, export preset and sort order. Open Workspace from More.
* **Focused search:** filter by kind, source, line and date; matching text is highlighted in the collection browser. Copy recognized image text directly or locate an unavailable file.
* **Recovery and activity:** additions, removals and exports are recorded locally. Restore removed items, reveal export results, or run an export again from More → Activity history.
* **Native finish:** guided onboarding, Reduce Motion/Transparency support and an explicit update checker. Developer ID signing and notarization tooling is documented in [Distribution](docs/RELEASING.md).

New items are saved immediately, persistence failures remain visible, and history keeps app-owned copies recoverable across relaunches. Referenced originals are never modified by collection or preparation. Folder watches are nonrecursive; activity history keeps the latest 200 entries. Signing/notarization requires your Apple distribution credentials; update installation remains explicit.
