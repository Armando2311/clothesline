# Roadmap

## Done (in this version)

* Floating line under the menu bar / notch, all Spaces and full-screen apps, per-display placement.
* Global shortcuts (toggle ⌃⌥C, hang clipboard ⌃⌥V), configurable, with conflict reporting.
* Automatic screenshot collection (FSEvents + screen-capture attribute), follows the macOS
  save location live, reconciles after sleep/wake and volume changes.
* Drag in: files, folders, file promises, image data, links, text. Drag-to-top-edge reveal.
* Drag out: real file URLs, multi-item, copy by default, ⌘ to move, notes as text + .txt promise,
  links as URLs.
* Multiple selection, keyboard navigation, Quick Look, hover captions, context menus.
* Pinning, undo for removals, Copy/Move File To…, Move to Trash… with confirmations, Locate File….
* Multiple lines (incl. temporary lines that clear themselves), Arrange By.
* Retention: max screenshots per line, expiry, clear-on-quit; never deletes user files.
* Persistent state with bookmarks; MISSING/OFFLINE states.
* Four original themes (+ automatic light/dark), breeze, ambient particles, Reduce Motion support.
* Settings window, launch at login, menu bar item, VoiceOver labels.

## Workflow upgrade branch

Implemented: visible control bar, Compact mode, expanded collection browser, cross-line
search with on-device OCR, native sharing, native note editing and labels, image preparation
with flattened redaction, and Client Handoff / Bug Report / Product Listing recipes.

Public-release distribution work below remains outstanding.

## Next (before a public release)

1. **Developer ID signing + notarization** pipeline (needs an Apple Developer account — requires your
   credentials).
2. **Sparkle-style updates** or Mac App Store distribution (sandbox variant: screenshot folder chosen
   once; everything else already uses security-scoped bookmarks).
3. **Real-device QA pass** using `docs/TESTING.md` §2 on a notched MacBook, an Intel Mac and a
   multi-display setup; tune spring constants and peek timing with real hands.
4. **Localization** (strings are already short and centralized in a few files).
5. **Onboarding card** on first launch explaining Desktop permission before macOS asks.

## Later (candidate premium features)

* **Hosted collection sharing** beyond the implemented native Share menu.
* **Additional preparation actions** beyond the implemented PNG/JPEG output, resize, crop and annotations.
* **Copy recognized text** as a dedicated action, beyond the implemented searchable OCR.
* **Richer search filters** for dates, sources and item kinds.
* **Opt-in clipboard history** with explicit privacy controls (excluded apps, password-manager types,
  auto-expiry) — deliberately left out of v1.
* **Per-line folders**: optionally mirror a line to a real folder for syncing via iCloud Drive.
* **Shortcuts.app actions** (App Intents): "Hang file", "Clear line", "Get items on line".
* **Seasonal themes** and a custom-theme editor (colours only, same illustration system).
