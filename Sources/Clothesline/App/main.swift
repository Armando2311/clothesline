import AppKit

// Entry point. Clothesline is an accessory app (LSUIElement): no Dock icon and
// no menu bar of its own, so the app you are working in stays in front.
MainActor.assumeIsolated {
    let app = NSApplication.shared

    // Developer/CI hook: render the line with sample items to a PNG and exit.
    if let i = CommandLine.arguments.firstIndex(of: "--render-preview"), i + 1 < CommandLine.arguments.count {
        PreviewRenderer.run(output: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }

    if CommandLine.arguments.contains("--self-test") {
        exit(SelfTest.run())
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
