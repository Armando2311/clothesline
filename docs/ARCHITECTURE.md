# Clothesline — Architecture

## Module layout

```
Sources/
  ClotheslineCore/        Pure Foundation. No AppKit. Unit-tested on macOS and Linux.
    HangingItem.swift     Item, Line, FileReference, ownership model
    Board.swift           All line/item operations (add, dedupe, remove, move, sort, lines)
    Retention.swift       Cleanup policy (never touches files)
    Persistence.swift     Atomic JSON store, corrupt-file recovery, owned-file sandboxing
    ScreenshotClassifier  Screenshot detection rules + macOS screenshot preference parsing
    ItemClassifier.swift  File kind, link detection, titles, export names
    LineGeometry.swift    Rope curve, item slots, panel placement under the notch
    Settings.swift        AppSettings / Shortcut, tolerant decoding
  Clothesline/            The macOS app
    App/                  main.swift, AppDelegate (lifecycle, menu bar), AppModel (state)
    Window/               ClotheslinePanel (NSPanel), PanelController (show/hide/peek/placement)
    Line/                 LineView (interaction, layout, animation), ItemLayer, SkyLayer
    Theme/                Theme palettes, Artwork (all illustrations, drawn in code)
    Screenshots/          ScreenshotWatcher (FSEvents)
    Files/                FileAccess (bookmarks), ThumbnailCache (Quick Look thumbnails)
    DragDrop/             PasteboardImporter (in), DragWriters (out)
    Items/                ItemActions (menus, file operations, confirmations)
    Hotkeys/              HotKeyCenter (Carbon RegisterEventHotKey)
    Settings/             SwiftUI settings window, shortcut recorder, login item
    Support/              Small utilities, PreviewRenderer (CI image of the line)
```

Data flow is one-directional: user intent → `AppModel` mutation → `@Published board`
→ `LineView` diffs item ids and animates additions/removals. The view owns no data.

## Key decisions

### Window: a non-activating `NSPanel`
`.borderless + .nonactivatingPanel`, level `.statusBar`,
`[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.

* It can become **key without activating the app**, so keyboard navigation and Quick
  Look work while the app you were using stays frontmost with its menu bar.
* Automatic reveals (screenshot arrives, drag reaches the top edge) only order the panel
  front — they never take key focus. Only the shortcut, the menu, or a click on the line
  makes it key.
* It appears on every Space and over full-screen apps, and stays out of Mission Control
  and ⌘\` cycling.
* Clicks in other apps are seen by a global mouse monitor (no permission needed) and
  hide the line.

### Placement under the notch
`PanelPlacement` (core, unit-tested) takes `NSScreen.frame`, `visibleFrame`,
`safeAreaInsets.top` and the camera-housing rect derived from
`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. The panel hangs directly below the menu
bar; on a notched display it never rises above the notch even with an auto-hidden menu
bar. The line opens on the display under the pointer. On notched displays a third hook
sits under the notch so the rope hangs in two swags, as if tied to the notch; nothing is
assumed about notch size or position.

### Rendering: Core Animation, not SwiftUI
Items are `CALayer`s inside one flipped `NSView`. This gives exact hit-testing on rotated
items, real multi-item `NSDraggingSession`s, and animations that run in the render server.
All artwork (sky, clouds, rooftops, rope, hooks, wooden clothespins, photo prints, paper,
folders, notes, tags, app icon) is drawn with Core Graphics into bitmaps that are cached
and reused. There is no per-frame drawing; the optional breeze and particles are
render-server animations that are removed when the line hides or Reduce Motion is on.

### Screenshot detection: FSEvents + the screen-capture attribute
* `com.apple.screencapture` preferences (`location`, `target`, `name`) give the folder.
  A second FSEvents stream on `~/Library/Preferences` notices when the user changes the
  location in the Screenshot app, without polling.
* File-level FSEvents on that folder (≈80 ms latency). `screencapture` writes a hidden
  temp file then renames it; only visible names are considered, and a size-stability check
  covers slower writers.
* A file is a screenshot if it carries the `com.apple.metadata:kMDItemIsScreenCapture`
  extended attribute that macOS stamps on screenshots. This works with any filename, any
  language and without a Spotlight index. Filename heuristics are only a fallback when
  extended attributes are unavailable, and then only for files created in the last two
  minutes.
* After wake, volume mount/unmount, or an FSEvents "events dropped" flag, the folder is
  reconciled once for screenshots created since the last check.
* Reported paths are remembered, and the board de-duplicates by path, so nothing hangs
  twice.

### File safety model
| Action | What happens to the file |
|---|---|
| Drop a file on the line / Add Files… | Nothing. A bookmark (reference) is stored. |
| Drop image data, a file promise, paste an image | Clothesline saves **its own copy** in `~/Library/Application Support/Clothesline/Items`. |
| Remove from Line (⌫) | Nothing for referenced files. Owned copies are deleted only once the removal can no longer be undone (⌘Z keeps the last 20 removals). |
| Drag out (default) | Receiver gets a **copy**. The drag only offers `.copy`, so Finder cannot move the file even on the same volume. |
| Drag out holding ⌘ | Explicit move (Finder convention). The item leaves the line because the file now lives elsewhere. |
| Copy File To… | Copy, never overwrites (`name 2.ext`). |
| Move File To… | Confirmation alert, then move; the item follows the file. |
| Move File to Trash… | Warning alert, then `NSWorkspace.recycle` (recoverable from the Trash). |
| Automatic cleanup | Removes items from the line only. |

`BoardStore.deleteOwnedFile` refuses any path outside the owned folder (tested against
path traversal), so no bug elsewhere can delete a user's file.

### Persistence
`state.json` (atomic writes, debounced 0.4 s, flushed at quit). An unreadable file is moved
aside instead of overwritten. Files are stored as bookmark data plus last known path;
bookmarks follow renames/moves on the same volume. Resolution runs off the main thread with
`.withoutUI, .withoutMounting`, so a disconnected drive marks items **OFFLINE** instead of
blocking, and a deleted file marks them **MISSING** (with *Locate File…*).

### Global shortcuts
Carbon `RegisterEventHotKey`: needs no Accessibility/Input Monitoring permission and works
sandboxed. Defaults ⌃⌥C (toggle) and ⌃⌥V (hang clipboard). Conflicts are reported in
Settings. Hotkeys are suspended while a new shortcut is being recorded.

### Drag-to-top-edge reveal
A global `leftMouseDragged` monitor (no permission needed). It only fires when the drag
pasteboard changed since the mouse went down — i.e. a real drag with content — and the
pointer touches the top 4 pt of a display. The line peeks without focus and hides again if
the drag leaves without dropping.

### Sandboxing
The default build is not sandboxed (Developer ID distribution): it can read the macOS
screenshot setting and reference files anywhere. All code paths are sandbox-aware
(security-scoped bookmarks, `startAccessingSecurityScopedResource`), and
`Resources/Clothesline-AppStore.entitlements` is the starting point for a Mac App Store
build; in the sandbox the screenshot folder must be chosen once in Settings.

## Performance budget
* Idle: no timers. Retention uses a single one-shot timer at the next expiry. Pointer-exit
  checks run only while a peeked line is visible.
* Hidden: panel ordered out, particles and breeze removed.
* Thumbnails: Quick Look, bounded `NSCache` (200 items / 64 MB).
