import AppKit
import SwiftUI

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
    static func duration(reduced: Bool = Motion.reduced) -> TimeInterval { reduced ? 0.12 : 0.28 }
    static func travel(reduced: Bool = Motion.reduced) -> CGFloat { reduced ? 0 : 24 }
    static var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1) }
    static var swiftUI: Animation { reduced ? .easeInOut(duration: 0.12) : .interpolatingSpring(stiffness: 320, damping: 34) }

    /// Always start at the presentation value, so interrupted actions do not jump.
    static func animate(_ layer: CALayer, keyPath: String, to value: Any, duration: TimeInterval? = nil, from: Any? = nil) {
        let start = from ?? layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = start
        animation.toValue = value
        animation.duration = duration ?? Self.duration()
        animation.timingFunction = timing
        layer.add(animation, forKey: "motion.\(keyPath)")
    }

    @MainActor static func present(_ window: NSWindow) {
        window.animationBehavior = .documentWindow
        guard !window.isVisible else { window.makeKeyAndOrderFront(nil); return }
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        if !reduced, let content = window.contentView {
            content.wantsLayer = true
            if let layer = content.layer { animate(layer, keyPath: "transform.translation.y", to: 0, from: -8) }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration()
            context.timingFunction = timing
            window.animator().alphaValue = 1
        }
    }

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


/// SwiftUI observes accessibility changes live, including open workflow windows.
private struct PremiumAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    let value: Value
    func body(content: Content) -> some View {
        content.animation(reduced ? .easeInOut(duration: 0.12) : .interpolatingSpring(stiffness: 320, damping: 34), value: value)
    }
}
extension View {
    func premiumAnimation<Value: Equatable>(value: Value) -> some View { modifier(PremiumAnimation(value: value)) }
}
