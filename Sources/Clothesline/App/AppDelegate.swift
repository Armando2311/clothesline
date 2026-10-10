import AppKit
import ClotheslineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model: AppModel
    private(set) lazy var panel = PanelController(model: model)
    private let watcher = ScreenshotWatcher()
    private lazy var folderRules = FolderRuleWatcher(model:model)
    private var statusItem: NSStatusItem?
    private var customFolderAccess: URL?

    /// Test/automation overrides (not persisted):
    ///   --state-dir <dir>          keep state somewhere other than Application Support
    ///   --screenshot-folder <dir>  watch this folder instead of the macOS setting
    ///   --show-line                open the line right after launch (idle measurements)
    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    override init() {
        if let dir = Self.argument("--state-dir") {
            model = AppModel(store: BoardStore(directory: URL(fileURLWithPath: dir, isDirectory: true)))
        } else {
            model = AppModel()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.requestPeek = { [weak self] in self?.panel.show(.peek) }
        model.settingsDidChange = { [weak self] old in self?.settingsChanged(from: old) }
        panel.screenshotRefresh = { [weak self] in self?.watcher.refresh() }

        HotKeyCenter.shared.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleLine: self.panel.toggle()
            case .hangClipboard: self.hangClipboard()
            }
        }
        registerHotKeys()

        watcher.onScreenshot = { [weak self] url in self?.model.screenshotDetected(url) }
        watcher.onStatusChange = { [weak self] status in self?.model.screenshotStatus = status }
        if !UserDefaults.standard.bool(forKey: "didCompleteWorkflowWelcome") {
            WelcomeWindow.shared.show { [weak self] in self?.applyWatcherConfig(); self?.panel.show(.explicit) }
        } else { applyWatcherConfig() }

        updateStatusItem()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)

        model.revalidate()
        folderRules.start()
        if ProcessInfo.processInfo.arguments.contains("--show-line") {
            after(0.5) { [weak self] in self?.panel.show(.explicit) }
        }

        // Record first launch only after the guide completes.
        let firstLaunchKey = "didShowWelcome"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey), UserDefaults.standard.bool(forKey: "didCompleteWorkflowWelcome") {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            if UserDefaults.standard.bool(forKey: "didCompleteWorkflowWelcome") { after(0.6) { [weak self] in self?.panel.show(.explicit) } }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        folderRules.stop()
        model.prepareForTermination()
        customFolderAccess?.stopAccessingSecurityScopedResource()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching the app again (Finder, Spotlight) shows the line.
        panel.show(.explicit)
        return false
    }

    // MARK: - Settings application

    private func settingsChanged(from old: AppSettings) {
        let s = model.settings
        if s.toggleShortcut != old.toggleShortcut || s.hangClipboardShortcut != old.hangClipboardShortcut { registerHotKeys() }
        if s.collectScreenshots != old.collectScreenshots || s.includeScreenRecordings != old.includeScreenRecordings
            || s.customScreenshotFolder != old.customScreenshotFolder { applyWatcherConfig() }
        if s.showMenuBarIcon != old.showMenuBarIcon { updateStatusItem() }
        if s.appearanceStyle != old.appearanceStyle || s.cardScale != old.cardScale || s.panelLayout != old.panelLayout || s.noThemeClickThrough != old.noThemeClickThrough { panel.refreshLayout() }
        if s.theme != old.theme { panel.refreshLayout() }
        if s.gentleBreeze != old.gentleBreeze || s.ambientEffects != old.ambientEffects {
            panel.lineView.applyTheme()
            panel.lineView.updateBreeze()
        }
        if s.retention != old.retention { model.applyRetention() }
    }

    private func registerHotKeys() {
        let center = HotKeyCenter.shared
        model.hotKeyResults = [
            .toggleLine: center.register(model.settings.toggleShortcut, for: .toggleLine),
            .hangClipboard: center.register(model.settings.hangClipboardShortcut, for: .hangClipboard),
        ]
    }

    private func applyWatcherConfig() {
        guard UserDefaults.standard.bool(forKey: "didCompleteWorkflowWelcome") else { return }
        customFolderAccess?.stopAccessingSecurityScopedResource()
        customFolderAccess = nil
        var custom: URL?
        if let override = Self.argument("--screenshot-folder") {
            custom = URL(fileURLWithPath: override, isDirectory: true)
        } else if let path = model.settings.customScreenshotFolder {
            custom = URL(fileURLWithPath: path, isDirectory: true)
            if let data = model.settings.customScreenshotFolderBookmark {
                var stale = false
                var options: URL.BookmarkResolutionOptions = [.withoutUI]
                if FileAccess.isSandboxed { options.insert(.withSecurityScope) }
                if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) {
                    custom = url
                    if FileAccess.isSandboxed, url.startAccessingSecurityScopedResource() { customFolderAccess = url }
                }
            }
        }
        watcher.apply(.init(enabled: model.settings.collectScreenshots, includeRecordings: model.settings.includeScreenRecordings, customFolder: custom))
    }

    @objc private func systemDidWake() {
        watcher.refresh()
        model.revalidate()
        model.applyRetention()
    }

    @objc private func volumesChanged() {
        watcher.refresh()
        model.revalidate()
    }

    // MARK: - Actions

    func hangClipboard() {
        let ids = PasteboardImporter.importContents(of: .general, into: model, source: .clipboard)
        if ids.isEmpty {
            NSSound.beep()
        } else if !panel.isVisible {
            panel.show(.peek)
        }
    }

    // MARK: - Menu bar

    private func updateStatusItem() {
        if model.settings.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Artwork.menuBarIcon()
            item.button?.setAccessibilityLabel("Clothesline")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggleTitle = panel.isVisible ? "Hide Clothesline" : "Show Clothesline"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(menuToggle), keyEquivalent: "")
        if let s = model.settings.toggleShortcut { toggle.title += "    \(s.displayString)" }
        menu.addItem(toggle)
        let clip = NSMenuItem(title: "Hang Clipboard", action: #selector(menuHangClipboard), keyEquivalent: "")
        if let s = model.settings.hangClipboardShortcut { clip.title += "    \(s.displayString)" }
        menu.addItem(clip)
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Note…", action: #selector(menuNewNote), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add Files…", action: #selector(menuAddFiles), keyEquivalent: ""))
        menu.addItem(.separator())
        let lines = NSMenuItem(title: "Lines", action: nil, keyEquivalent: "")
        lines.submenu = panel.lineView.actions.linesMenu()
        menu.addItem(lines)
        let clear = NSMenuItem(title: "Clear Line (keeps pinned)", action: model.activeItems.contains { !$0.pinned } ? #selector(menuClear) : nil, keyEquivalent: "")
        menu.addItem(clear)
        if model.canUndoRemoval {
            menu.addItem(NSMenuItem(title: "Undo Remove", action: #selector(menuUndo), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if let status = model.screenshotStatus, model.settings.collectScreenshots {
            let text: String
            if let problem = status.problem {
                text = "⚠︎ " + (problem.count > 60 ? String(problem.prefix(58)) + "…" : problem)
            } else {
                text = "Collecting screenshots from \(status.folder?.lastPathComponent ?? "—")"
            }
            let info = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Browse Collection…", action: #selector(menuBrowse), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Welcome Guide…", action: #selector(menuWelcome), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Clothesline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    @objc private func menuToggle() { panel.toggle() }
    @objc private func menuHangClipboard() { hangClipboard() }
    @objc private func menuNewNote() { panel.lineView.actions.newNote() }
    @objc private func menuAddFiles() { panel.lineView.actions.addFiles() }
    @objc private func menuClear() { model.clearActiveLine() }
    @objc private func menuUndo() { model.undoLastRemoval() }
    @objc private func menuBrowse() { panel.lineView.workflow.browse() }
    @objc private func menuWelcome() { WelcomeWindow.shared.show() }
    @objc private func menuSettings() { SettingsWindowController.shared.show(model: model) }
    @objc private func menuCheckUpdates() { UpdateChecker.shared.check() }

}
