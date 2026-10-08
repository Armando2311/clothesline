import AppKit

/// Runs `block` on the main actor after `delay` seconds. Returns a handle that
/// can cancel the pending work. Used instead of repeating timers so the app is
/// fully idle when nothing is happening.
@MainActor
final class Delayed {
    private var task: Task<Void, Never>?

    func schedule(after delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            block()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    var isPending: Bool { task != nil && task?.isCancelled == false }
}

@MainActor
func after(_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        block()
    }
}

extension NSColor {
    /// Creates a colour from a 0xRRGGBB literal.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

enum Motion {
    /// Whether the user asked macOS to reduce motion.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
}

enum Log {
    /// Lightweight logging to the unified log (visible in Console.app under
    /// subsystem app.clothesline). Never logs file contents.
    static func info(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[Clothesline] %@", message())
        #endif
    }

    static func error(_ message: @autoclosure () -> String) {
        NSLog("[Clothesline] ERROR %@", message())
    }
}
