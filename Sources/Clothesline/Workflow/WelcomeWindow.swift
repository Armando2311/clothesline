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
    @State private var step = 0
    private let titles = ["Collect anything. Send it together.","Prepare once. Reuse every day.","Keep your projects close."]
    var body: some View {
        VStack(alignment: .leading,spacing:18) {
            Text(titles[step]).font(.title.bold())
            Text("Step \(step+1) of 3").font(.caption).foregroundStyle(.secondary)
            if step == 0 {
                Label("Drag files, links and notes onto the rope.",systemImage:"pin")
                Label("Dragging out copies files. Your originals stay safe.",systemImage:"doc.on.doc")
                Text("Control–Option–C shows the line; Escape or EXIT closes it. Pin the toolbar to keep controls visible.")
                Text("Screenshot collection reads your screenshot folder. macOS may ask for Desktop access; you can disable it or choose another folder in Settings.").font(.caption).foregroundStyle(.secondary)
            } else if step == 1 {
                Label("Preview, crop, redact and prepare selected images.",systemImage:"slider.horizontal.3")
                Label("Save export presets with formats, size limits and destinations.",systemImage:"square.and.arrow.up")
                Text("Export creates separate copies. Use Activity History to find an export, repeat it, or restore removed items.")
            } else {
                Label("Named lines remember workspace destinations and presets.",systemImage:"square.stack")
                Label("Optional collection rules route new files into the right line.",systemImage:"line.3.horizontal.decrease.circle")
                Text("Command–F searches text inside images. More contains workspace, rules and history. Settings controls fitted width, card size and No Theme.")
            }
            Spacer(minLength:0)
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step == 2 ? "Get Started" : "Next") { if step == 2 { done() } else { step += 1 } }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width:500,height:370)
    }
}
