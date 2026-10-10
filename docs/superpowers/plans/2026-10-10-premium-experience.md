# Clothesline Premium Experience Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or independent parallel agents for the explicitly separated file ownership below.

**Goal:** Deliver all ten approved improvements on a new branch without altering main.
**Architecture:** Preserve Board/AppModel as mutation authority. Add independently persisted workspace/history/preset metadata, pure search/geometry helpers, and native UI services. Integrate once independent service contracts exist.
**Tech Stack:** Swift, Foundation, AppKit, SwiftUI, Core Animation, XcodeGen.
**Spec:** docs/superpowers/specs/2026-10-10-premium-experience.md

## Global constraints
- macOS 13 minimum; existing Swift package retains Linux core tests.
- Original files are referenced, never rewritten by preparation or collection.
- Work occurs exclusively on codex/clothesline-premium-experience.
- No paid gate or cloud upload; real release notarization needs existing credentials.

## Review focus
- Corrupt or older state must retain recoverable data and decode new settings safely.
- Owned removed items must survive relaunch when history retains them.
- Rules must not collect a partially written file or repeatedly import after restart.
- Small screens must keep close/pin/settings reachable with large cards and selection.
- Cancelled exports must never publish partial output or alter originals.

## Tasks
- [x] Adaptive UI: own LineView, PanelController, LineControls, SettingsWindow and geometry helper. Write geometry/toolbar/drag tests, observe failures, implement fitted/full-width and scaled-card layout, contextual toolbar, safe clickthrough, grouping and line routing indicators. Run filtered native tests then review integration.
- [x] Export presets: own Workflow.swift, RecipeWindow, ExportService and preset persistence. Test legacy recipe decode, unique multi-format names, exact byte limits, cancellation and preset roundtrip before implementing. Preserve original source and security-scoped destination lifetime. UI consumes model.workspaceForActiveLine and model.activity.recordExport.
- [x] Workspace services: own new WorkspaceConfiguration/CollectionRule/ActivityEntry/WorkspaceStore, views and FolderRuleWatcher. Test matching, bounded history, persistence, invalid destinations and stable watched writes. Expose configuration(for lineID), routing, retainedItems, start/stop; use model.restoreActivity for board mutation.
- [x] Model integration and search: add SearchFilters(kind,source,lineID,period), GroupStore, transient notice, atomic save/recovery preservation, activity hooks and workspace methods. Write regression tests for date filtering, selection reconciliation, duplicate notice and owned-file history relaunch.
- [x] Native finish: onboarding steps, update release verification/check UI, Reduce Transparency and source context actions. Add release signing/notarization workflow and test validators without external publication.
- [x] Integration: run complete swift test, XcodeGen/Xcode build, render and inspect representative layouts, live QA in separate state. Resolve all failures and independent review findings. Record actual evidence and remaining external requirements.
- [ ] Commit and push only new branch, create reviewable PR against main; verify remote main remains at starting SHA.

Verification: 129 passing tests, 28 passing app self-test checks, successful Xcode Debug build, inspected theme/Compact preview and isolated native workspace/preset/export QA. Distribution credentials remain an external requirement; no notarization or publication was performed.
