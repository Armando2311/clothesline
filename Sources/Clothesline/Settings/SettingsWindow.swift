import AppKit
import SwiftUI
import ServiceManagement
import ClotheslineCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "Clothesline Settings"
            w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Accessory apps return focus to the previous app automatically.
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScreenshotSettings(model: model)
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            AppearanceSettings(model: model)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            CleanupSettings(model: model)
                .tabItem { Label("Cleanup", systemImage: "leaf") }
            AboutSettings(model: model)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        // Grouped forms are scrollable and have no intrinsic height.
        // Give the tab content a stable viewport instead of a collapsed strip.
        .frame(width: 540, height: 520)
        .padding(20)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                ShortcutRow(title: "Show or hide the line", shortcut: $model.settings.toggleShortcut,
                            defaultShortcut: .defaultToggle, result: model.hotKeyResults[.toggleLine])
                ShortcutRow(title: "Hang clipboard contents", shortcut: $model.settings.hangClipboardShortcut,
                            defaultShortcut: .defaultHangClipboard, result: model.hotKeyResults[.hangClipboard])
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("While the line is open: ← → select · Space Quick Look · ⌫ remove from line · ⌘Z undo · P pin · ⌘C copy · ⌘V hang · ⇥ next line · Esc hide")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Text("The line stays open until you use its shortcut, Escape or EXIT button.").font(.caption)
                Toggle("Reveal the line when dragging something to the top of the screen", isOn: $model.settings.revealOnDragToTopEdge)
                Picker("After dragging an item out", selection: $model.settings.afterDragOut) {
                    ForEach(AfterDragOut.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("Dragging out copies the file. Hold ⌘ while dragging to move it instead, as in Finder.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open Clothesline at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        loginError = LoginItem.set(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show icon in the menu bar", isOn: $model.settings.showMenuBarIcon)
                if !model.settings.showMenuBarIcon {
                    Text("Without the icon, use the shortcut to open the line, or open Clothesline again from Finder to show it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: Shortcut?
    let defaultShortcut: Shortcut
    let result: HotKeyCenter.RegistrationResult?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if result == .unavailable {
                    Text("This shortcut is used by another app or macOS. Choose another.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            ShortcutRecorder(shortcut: $shortcut)
                .frame(width: 130, height: 24)
            Button {
                shortcut = defaultShortcut
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Restore \(defaultShortcut.displayString)")
        }
    }
}

// MARK: - Screenshots

private struct ScreenshotSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Hang new screenshots automatically", isOn: $model.settings.collectScreenshots)
                Toggle("Peek at the line when a screenshot arrives", isOn: $model.settings.revealOnScreenshot)
                    .disabled(!model.settings.collectScreenshots)
                Toggle("Include screen recordings", isOn: $model.settings.includeScreenRecordings)
                    .disabled(!model.settings.collectScreenshots)
                Picker("Hang screenshots on", selection: $model.settings.screenshotLineID) {
                    Text("The current line").tag(UUID?.none)
                    ForEach(model.board.lines) { line in Text(line.name).tag(UUID?.some(line.id)) }
                }
                .disabled(!model.settings.collectScreenshots)
            } footer: {
                Text("Works with ⇧⌘3, ⇧⌘4, ⇧⌘5 and the Screenshot app. Clothesline only reads new screenshot files; it never moves, renames or uploads them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Folder") {
                LabeledContent("Watching") {
                    Text(folderDescription).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if let problem = model.screenshotStatus?.problem, model.settings.collectScreenshots {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                HStack {
                    Button("Choose Folder…") { chooseFolder() }
                    if model.settings.customScreenshotFolder != nil {
                        Button("Use macOS Setting") {
                            model.settings.customScreenshotFolder = nil
                            model.settings.customScreenshotFolderBookmark = nil
                        }
                    }
                }
                Text("By default Clothesline follows the location set in the Screenshot app (⇧⌘5 › Options › Save to) and notices when you change it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var folderDescription: String {
        if let custom = model.settings.customScreenshotFolder { return (custom as NSString).abbreviatingWithTildeInPath + " (custom)" }
        guard let folder = model.screenshotStatus?.folder else { return "—" }
        return (folder.path as NSString).abbreviatingWithTildeInPath + " (macOS setting)"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.level = WorkflowPresentation.modalLevel
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Watch This Folder"
        panel.message = "Choose the folder where your screenshots are saved."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var options: URL.BookmarkCreationOptions = []
        if FileAccess.isSandboxed { options.insert(.withSecurityScope) }
        model.settings.customScreenshotFolderBookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        model.settings.customScreenshotFolder = url.path
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Appearance", selection: $model.settings.appearanceStyle) {
                    ForEach(AppearanceStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("Compact keeps the rope and uses upright cards with less decoration.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Themes") {
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(ThemeChoice.allCases, id: \.self) { choice in
                        HStack {
                            ThemeSwatch(choice: choice)
                            Text(choice.displayName)
                        }
                        .tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Liquid Glass uses native glass on macOS 26, with frosted translucency on earlier versions.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Gentle breeze (items sway slightly while the line is open)", isOn: $model.settings.gentleBreeze)
                Toggle("Ambient effects (light motes, rain, fireflies)", isOn: $model.settings.ambientEffects)
                Toggle("Soft sounds when items are clipped on or off", isOn: $model.settings.playSounds)
            } header: {
                Text("Motion & Sound")
            } footer: {
                Text("When “Reduce motion” is on in System Settings › Accessibility › Display, Clothesline uses simple fades and turns off swaying and particles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let choice: ThemeChoice

    var body: some View {
        let themes: [Theme] = choice == .automatic ? [.summerAfternoon, .midnight] : [Theme.resolve(choice, appearance: NSAppearance(named: .aqua)!)]
        HStack(spacing: 0) {
            ForEach(Array(themes.enumerated()), id: \.offset) { _, t in
                LinearGradient(colors: [Color(nsColor: t.skyTop), Color(nsColor: t.skyMiddle), Color(nsColor: t.skyBottom)], startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: 34, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.1)))
    }
}

// MARK: - Cleanup

private struct CleanupSettings: View {
    @ObservedObject var model: AppModel

    private let screenshotLimits: [Int?] = [10, 20, 30, 50, 100, nil]
    private let expiries: [Double?] = [nil, 1, 8, 24, 72, 168]

    var body: some View {
        Form {
            Section {
                Picker("Keep at most", selection: $model.settings.retention.maxScreenshotsPerLine) {
                    ForEach(screenshotLimits, id: \.self) { n in
                        Text(n.map { "\($0) screenshots per line" } ?? "Unlimited screenshots").tag(n)
                    }
                }
                Picker("Take items off the line after", selection: $model.settings.retention.expireAfterHours) {
                    ForEach(expiries, id: \.self) { h in
                        Text(h.map { ItemActions.hoursText($0) } ?? "Never").tag(h)
                    }
                }
                Toggle("Take unpinned items off the line when quitting", isOn: $model.settings.retention.clearUnpinnedOnQuit)
            } header: {
                Text("Automatic Cleanup")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup only takes items off the line. Your files are never deleted, moved or changed.")
                    Text("Pinned items (painted clothespins) are always kept. Pin with P or from the item’s menu.")
                    Text("Images you dropped from a browser or pasted are stored by Clothesline; their copy is discarded when the item leaves the line.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About & troubleshooting

private struct AboutSettings: View {
    @ObservedObject var model: AppModel
    @State private var folderReadable: Bool?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text("Clothesline").font(.title2.bold())
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("A quiet place to hang screenshots, files, links and notes for a little while.")
            }
            Section("Privacy") {
                Text("Everything stays on your Mac. Clothesline has no analytics, no network access and no accounts. Screenshots and files are never uploaded.")
                    .font(.callout)
            }
            Section("Troubleshooting") {
                LabeledContent("Screenshot folder access") {
                    switch folderReadable {
                    case .some(true): Text("OK").foregroundStyle(.green)
                    case .some(false): Text("Not allowed").foregroundStyle(.red)
                    case .none: Text("Checking…").foregroundStyle(.secondary)
                    }
                }
                if folderReadable == false {
                    Text("Allow Clothesline in System Settings › Privacy & Security › Files and Folders (Desktop Folder), or choose a different folder under Screenshots.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                LabeledContent("Data folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.directory])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: checkFolder)
    }

    private func checkFolder() {
        guard let folder = model.screenshotStatus?.folder else { folderReadable = nil; return }
        folderReadable = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }
}

// MARK: - Shortcut recorder

/// A click-to-record shortcut field. Esc cancels, ⌫ clears.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onChange = { shortcut = $0 }
        b.shortcut = shortcut
        return b
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onChange = { shortcut = $0 }
        if !nsView.isRecording { nsView.shortcut = shortcut }
    }

    final class RecorderButton: NSButton {
        var onChange: ((Shortcut?) -> Void)?
        private(set) var isRecording = false { didSet { refresh() } }
        var shortcut: Shortcut? { didSet { refresh() } }
        private var monitor: Any?

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(clicked)
            refresh()
        }

        required init?(coder: NSCoder) { fatalError("not supported") }

        private func refresh() {
            title = isRecording ? "Type shortcut…" : (shortcut?.displayString ?? "None")
        }

        @objc private func clicked() {
            isRecording ? stop() : start()
        }

        private func start() {
            isRecording = true
            // Suspend global hotkeys so the current one can be re-recorded.
            HotKeyCenter.shared.suspend()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else { return event }
                // Extract plain values first; NSEvent itself is not Sendable.
                let keyCode = event.keyCode
                let candidate = Shortcut(event: event)
                let consumed = MainActor.assumeIsolated { self.handle(keyCode: keyCode, candidate: candidate) }
                return consumed ? nil : event
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if isRecording { HotKeyCenter.shared.resume() }
            isRecording = false
        }

        private func handle(keyCode: UInt16, candidate: Shortcut?) -> Bool {
            switch Int(keyCode) {
            case 53: stop(); return true // Esc
            case 51, 117:
                shortcut = nil
                onChange?(nil)
                stop()
                return true
            default:
                guard let s = candidate, s.isValidGlobalShortcut else {
                    NSSound.beep()
                    return true
                }
                shortcut = s
                onChange?(s)
                stop()
                return true
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { stop() }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            if Bundle.main.bundleURL.pathExtension != "app" {
                return "Launch at login needs the app bundle. Build it with Scripts/build-app.sh and run Clothesline.app."
            }
            return error.localizedDescription
        }
    }
}
