# Clothesline Workflow Upgrade Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline, task by task.

**Goal:** Deliver the approved six-feature workflow upgrade on codex/clothesline-workflow-upgrade.
**Architecture:** Keep Board/AppModel authoritative. Add pure search, image/export configuration and safe naming in Core; add native service and window units for OCR, editing, sharing and exports. Layer native controls above the rope and connect the collection browser to its selection.
**Tech Stack:** Swift 5.9, macOS 13, AppKit, SwiftUI, Vision, ImageIO, Core Graphics, system ditto.
**Spec:** docs/superpowers/specs/2026-10-07-workflow-upgrade-design.md

## Global Constraints
- macOS 13 support and Swift 5.9 package compatibility.
- No third-party package dependency.
- Original files and existing destination files must never be overwritten.
- Preserve item IDs, bookmarks, lines, retention, undo and tolerant settings decoding.
- No cloud service, clipboard monitoring, payment system or publishing.

## Review Focus
- Search selection must not reorder or drag items between lines accidentally.
- Owned derivatives must survive removal of their originals.
- Cancellation and missing inputs must leave no partial destination export.
- Image orientation, crop and redaction coordinates must agree with preview.
- Explicit interactive windows must remain usable despite accessory-panel auto-hide.

## Task 1: Core workflow contracts
Files: Sources/ClotheslineCore/Workflow.swift, Board.swift, Settings.swift; Tests/ClotheslineCoreTests/WorkflowTests.swift.
Interfaces: ItemSearch.results(board:query:recognizedText:), ExportRecipe/RecipeOptions, ExportNames.safe/unique, Board.editNote, AppearanceStyle.
- [ ] Write tests for accent-insensitive cross-line search, whitespace query, OCR text, note identity, legacy settings, filename traversal/collisions and recipe validation.
- [ ] Run `swift test --filter WorkflowTests`; expect missing-contract failures before adding implementation.
- [ ] Implement deterministic matching, safe filename planning, additive settings and edit-note mutation.
- [ ] Run full `swift test`; expect zero failures; commit.

## Task 2: Image and export services
Files: Sources/Clothesline/Workflow/{ImageProcessor,ExportService,OCRIndex}.swift; Tests/ClotheslineTests/WorkflowServiceTests.swift; Package.swift.
Interfaces: ImageProcessor.render/encode/load; ExportService.export(inputs:options:destination:progress:); OCRIndex.text for visible search.
- [ ] Add app-service test target. Write real-image tests for resize, crop, opaque redaction, size limit and source preservation; export tests for duplicate names, ZIP manifest, missing files, collisions and cancellation.
- [ ] Run service tests; expect missing-contract failures.
- [ ] Implement oriented ImageIO decode, flattened graphics rendering, JPEG size search, staged exports with cooperative cancellation and OCR caching on background tasks.
- [ ] Run full suite; expect all pass; commit.

## Task 3: Controls, collections and compact mode
Files: LineView.swift, PanelController.swift, AppModel.swift, SettingsWindow.swift; Workflow/{LineControls,CollectionWindow,NoteEditor}.swift.
Interfaces: AppModel.query/visibleItems/selectedIDs; model selection updates flow to rope and grid. PanelController refreshLayout() derives style height.
- [ ] Test filtered selection and query reset against model where meaningful, using AppKit service tests.
- [ ] Implement visible line/search/action controls, overflow buttons, expanded grid, item aliases and native note editor. Block internal reorder during cross-line search.
- [ ] Implement compact layout with upright cards, shared keyboard behavior and persisted appearance.
- [ ] Build and inspect both layout modes and browser; verify IDs and board order unchanged; commit.

## Task 4: Preparation, recipes, sharing and onboarding
Files: Workflow/{ImageEditor,RecipeWindow,WorkflowActions,WelcomeWindow}.swift; AppDelegate.swift; ItemActions.swift.
Interfaces: WorkflowActions presents reusable windows and actions; render/save/hang output consumes ImageProcessor; recipes use immutable ExportInput snapshots resolved from model.
- [ ] Implement image-editor crop, arrows, numbered markers, opaque redaction, undo, resize and export controls with progress and errors.
- [ ] Implement three configurable recipe presets, output-name preview, saved destinations, bug-report fields, cancellation and completion actions.
- [ ] Wire native sharing and context actions; make note opening edit stored note.
- [ ] Explain screenshot permission before watcher starts on fresh installs and allow reopening welcome guide.
- [ ] Run full suite and app self-tests; build; inspect editors and export a real package; commit.

## Task 5: End-to-end verification and review
Files: README.md, docs/TESTING.md and user-facing delivery report.
- [ ] Build with Xcode, run existing self-test and render preview, inspect UI, exercise search, compact mode, editor, recipe ZIP and native share picker.
- [ ] Request one independent whole-branch review; fix important findings with regression tests and a green full suite.
- [ ] Document precise test evidence and remaining hardware limitations; commit and leave branch open in Xcode.
