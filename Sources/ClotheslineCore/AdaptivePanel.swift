import Foundation

/// Shared sizing policy for the panel and its responsive controls.
public enum AdaptivePanel {
    public static func cardScale(_ value: Double) -> Double {
        value.isFinite ? min(1.2, max(0.8, value)) : 1
    }
    public static func width(available: Double, itemCount: Int, cardWidth: Double, fitted: Bool) -> Double {
        guard fitted else { return available }
        return min(available, max(640, Double(max(1, itemCount)) * (cardWidth + 18) + 96))
    }
    public static func compactToolbar(width: Double) -> Bool { width < 1060 }
}
