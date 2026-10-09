# Clothesline workflow upgrade

## Goal and scope

Make Clothesline a daily workspace for collecting, finding, preparing, and exporting project materials. Preserve its illustrated identity, native macOS behavior, and protection of original files. This release implements the six improvements recommended at the end of the product assessment: visible controls, compact mode, search, native sharing, screenshot preparation, and three reusable export recipes.

Cloud hosting, subscriptions, licensing, clipboard monitoring, cross-device sync, smart folder rules, a general automation builder, and video editing are separate future projects. This branch does not change distribution credentials or publish the app.

## 1. Visible controls and collections

Add a small native control bar with a line selector, New Line, Search, selected-item count, Preview, Copy, Share, Prepare Image, and Export. Actions enable according to the current selection. Buttons have labels or tooltips and accessibility names. Existing context menus and shortcuts remain available.

Show the total item count and clear overflow controls. Add an expandable collection browser with a thumbnail grid and readable labels; its selection feeds the same actions as the rope. Add an editable note window so editing a note updates its stored content rather than exporting an unrelated temporary text file. File aliases can be edited without renaming originals.

Use native views for interactive controls and retain Core Animation for the rope and cards. Keep automatic screenshot peeks from taking focus. Native sharing uses the macOS sharing picker for files, URLs, and note text, including multiple items. Preparing or sharing an unavailable file shows an actionable error rather than silently omitting it.

## 2. Compact appearance

Add Illustrated and Compact settings, persisted with backward-compatible defaults. Illustrated remains the default. Compact uses less vertical space, reduced decoration, upright cards, readable labels, and the same selection, drag-and-drop, and keyboard behavior. Size and hit testing derive from the chosen layout rather than scaling the entire interface. Changing appearance repositions an open panel below the menu bar or notch. Respect Reduce Motion and retain themes.

## 3. Search

Command-F focuses a search field. Search covers all lines and matches item names, note text, URLs, file names, and recognized image text without case or diacritic sensitivity. Results show their source line. Empty search restores the active line; Escape first exits search, then follows existing selection/hide behavior. Search never changes board order or moves items. Actions operate on selected results by item ID.

Use background, on-device Vision OCR for supported images. Cache results against item ID and file modification information, invalidate after image changes, and cancel obsolete work. OCR failures do not block the line. Index only content intentionally added to Clothesline. Do not crawl users' folders or send content to a service.

## 4. Screenshot preparation

Prepare Image opens a native editor for one available screenshot or image. Include preview, crop, arrows, numbered markers, solid opaque redaction rectangles, resize, and PNG/JPEG export. Provide undo within the editor. Flatten edits into exported pixels, strip metadata from the rendered derivative, and never overwrite the source. Copy Result places the edited image on the clipboard; Save Result creates a new file; Hang Result adds an app-owned derivative.

Image decoding, processing, and OCR run outside the main thread. Validate image dimensions and export settings, respect orientation, preserve aspect ratio when resizing, and report unreadable inputs or write failures. A target-size JPEG option reports the achieved size and refuses to claim success if it cannot meet the limit. Rendered output is flattened before sharing so hidden pixels cannot be recovered from the original image layer.

## 5. Export recipes

Provide three presets with editable settings, saved destinations, and a preview of the output names and transformations:

- **Client Handoff:** selected images become JPEG copies with a maximum long edge of 1600 pixels, sequential filenames, and user-selected quality. Include other selected files as copies; render notes and links into a manifest; produce a ZIP package.
- **Bug Report:** preserve selected attachments as copies, include prepared images, and generate a Markdown report with title, reproduction steps, expected result, actual result, notes, and links. Export a folder or ZIP and offer Copy Report.
- **Product Listing:** process selected images into sequential JPEG copies with configurable dimensions, optional center cropping to a selected aspect ratio, and compression. Export to a chosen destination.

Processing never changes originals or existing destination files. Stage the full export in a temporary directory, publish into a new uniquely named destination only after success, and clean up failed staging. If a selected input is unavailable, stop with a list of affected items. Sanitize names and prohibit path traversal. Resolve collisions deterministically. ZIP invocation uses explicit executable arguments, never a shell built from filenames. Show progress, support cancellation, and keep incomplete exports out of the destination.

## 6. First-run guidance

Add a dismissible onboarding card explaining collection, preview, drag-out copy behavior, and the two global shortcuts. Explain screenshot-folder access before starting the watcher on a fresh installation. Existing users keep their settings and collections. Add a menu action to reopen the guide.

## Architecture

Keep Board and AppModel as the source of truth. Put platform-independent search matching, recipe configuration, filename planning, and validation in ClotheslineCore. Put Vision OCR, image rendering, sharing, the collection browser, editor, and export orchestration in focused macOS files. Views send intent through AppModel and action services; they do not own a second board.

Use additive Codable fields with tolerant defaults. Preserve existing item IDs, lines, bookmarks, ownership semantics, retention, undo, and persisted state. Export and OCR services resolve bookmarks through the existing file access layer. Do not serialize resolved cross-machine file assumptions or network credentials.

Maintain macOS 13 support and Swift 5.9 package compatibility. Use Apple frameworks and system tools; introduce no third-party package dependency.

## Verification and acceptance

Add meaningful tests before implementing search, settings migration, filename planning, recipe validation, image transformations, and export safety. Test search across lines, empty queries, Unicode, source changes, and stale OCR. Test old settings decode, compact layout boundaries, mixed selections, duplicate names, traversal-like names, missing files, cancellation, and destination collisions.

Verify rendered image dimensions, orientation, opaque redaction pixels, and that originals are byte-for-byte unchanged. Verify exported ZIP contents, report attachment references, target-size results, and cleanup after failed exports. Exercise clipboard output and native sharing on this Mac.

Run the full core suite, macOS service tests/self-tests, a fresh Xcode build, and the existing self-test. Inspect Illustrated and Compact layouts and the expanded browser. Manually check search focus, editor controls, exports, hotkeys, Quick Look, drag in/out, automatic peeks, persistence after relaunch, and Reduce Motion. Record what cannot be verified on this machine, such as additional display hardware.

Completion means the six features work from visible controls, existing collections migrate intact, validation passes, and the updated app runs from Xcode on this branch. This design does not promise validated willingness to pay; that requires subsequent user trials.
