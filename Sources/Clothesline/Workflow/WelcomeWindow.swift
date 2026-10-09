import AppKit
import SwiftUI

@MainActor
final class WelcomeWindow {
    static let shared = WelcomeWindow()
    private var window: NSWindow?
    private var completion: (() -> Void)?
    func show(completion: (() -> Void)? = nil) {
        self.completion = completion
        let window = self.window ?? NSWindow(contentRect: CGRect(x: 0,y: 0,width: 500,height: 380),styleMask: [.titled],backing: .buffered,defer: false)
        window.title = "Welcome to Clothesline"; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WelcomeView { [weak self] in
            self?.window?.orderOut(nil)
            UserDefaults.standard.set(true,forKey: "didCompleteWorkflowWelcome")
            UserDefaults.standard.set(true,forKey: "didShowWelcome")
            let action = self?.completion; self?.completion = nil; action?()
        })
        window.center(); self.window = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
}
private struct WelcomeView: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading,spacing: 18) {
            Text("Collect anything. Send it together.").font(.title.bold())
            Label("Drag files, links and notes onto the rope.",systemImage: "pin")
            Label("Select an item, then Preview, Share or Export.",systemImage: "square.and.arrow.up")
            Label("Dragging out makes a copy. Your original stays safe.",systemImage: "doc.on.doc")
            Text("Control–Option–C shows the line. Control–Option–V hangs your clipboard. Command–F searches your collection.").font(.callout)
            Text("To collect new screenshots, Clothesline reads your screenshot folder. macOS may ask for Desktop access. You can turn collection off or choose another folder in Settings.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Get Started",action: done).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 500)
    }
}
