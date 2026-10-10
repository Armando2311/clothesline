import Foundation

/// Deliberate horizontal shake detection for an existing drag, ignoring small tremors.
public struct ShakeGesture: Sendable {
    private var anchorX: Double?
    private var startedAt: Double?
    private var direction = 0
    private var reversals = 0
    public init() {}
    public mutating func reset() { self = ShakeGesture() }
    public mutating func update(x: Double, time: Double) -> Bool {
        guard x.isFinite, time.isFinite else { reset(); return false }
        guard let anchorX, let startedAt, time >= startedAt, time - startedAt <= 0.65 else {
            reset(); self.anchorX = x; self.startedAt = time; return false
        }
        let delta = x - anchorX
        guard abs(delta) >= 25 else { return false }
        let nextDirection = delta > 0 ? 1 : -1
        if direction != 0 && direction != nextDirection { reversals += 1 }
        direction = nextDirection
        self.anchorX = x
        guard reversals >= 3 else { return false }
        reset()
        return true
    }
}
