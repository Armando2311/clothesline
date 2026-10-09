import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry of the clothesline, in panel-local coordinates with the origin at
/// the top-left and y growing downwards (the app's line view is flipped).
///
/// The rope is strung between hooks. On a display with a camera housing
/// (notch), a third hook sits right under the notch so the line hangs in two
/// swags, as if the rope were tied to the notch itself. Each swag is a
/// parabola, which is visually indistinguishable from a catenary at these
/// sags and has a closed-form slope.
public struct LineGeometry: Equatable, Sendable {
    public struct Hook: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Segment: Equatable, Sendable {
        public var start: Hook
        public var end: Hook
        public var sag: Double

        public var span: Double { end.x - start.x }

        public func y(atX x: Double) -> Double {
            let u = min(max((x - start.x) / span, 0), 1)
            return start.y + (end.y - start.y) * u + 4 * sag * u * (1 - u)
        }

        /// Slope dy/dx at x.
        public func slope(atX x: Double) -> Double {
            let u = min(max((x - start.x) / span, 0), 1)
            return (end.y - start.y) / span + 4 * sag * (1 - 2 * u) / span
        }

        /// Control point of the quadratic Bézier that traces exactly this parabola.
        public var controlPoint: Hook {
            Hook(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + 2 * sag)
        }
    }

    public var width: Double
    public var hooks: [Hook]
    public var segments: [Segment]
    /// Horizontal distance kept clear around interior hooks and at the ends.
    public var hookClearance: Double

    /// - Parameters:
    ///   - width: panel width.
    ///   - centerHookX: x of a hook under the notch, if the display has one.
    ///   - sagScale: multiplier for the rope sag (used for the attach "dip").
    public init(width: Double, centerHookX: Double?, hookInset: Double = 30, hookY: Double = 16, sagScale: Double = 1) {
        self.width = width
        self.hookClearance = 44
        var hooks = [Hook(x: hookInset, y: hookY)]
        if let cx = centerHookX, cx > hookInset + 120, cx < width - hookInset - 120 {
            hooks.append(Hook(x: cx, y: hookY - 6))
        }
        hooks.append(Hook(x: width - hookInset, y: hookY))
        self.hooks = hooks
        var segments: [Segment] = []
        for (a, b) in zip(hooks, hooks.dropFirst()) {
            let span = b.x - a.x
            let sag = min(max(span * 0.035, 12), 38) * sagScale
            segments.append(Segment(start: a, end: b, sag: sag))
        }
        self.segments = segments
    }

    public func segment(atX x: Double) -> Segment {
        segments.first { x <= $0.end.x } ?? segments[segments.count - 1]
    }

    public func ropeY(atX x: Double) -> Double { segment(atX: x).y(atX: x) }
    public func ropeAngle(atX x: Double) -> Double { atan(segment(atX: x).slope(atX: x)) }

    /// Usable intervals along the rope where items may hang.
    public var usableIntervals: [ClosedRange<Double>] {
        segments.compactMap { s in
            let lo = s.start.x + hookClearance
            let hi = s.end.x - hookClearance
            return lo < hi ? lo...hi : nil
        }
    }

    public var usableLength: Double {
        usableIntervals.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    /// Maps a distance along the concatenated usable intervals to an x position.
    public func x(alongUsable d: Double) -> Double {
        var remaining = d
        let intervals = usableIntervals
        guard let first = intervals.first, let last = intervals.last else { return width / 2 }
        if remaining <= 0 { return first.lowerBound + remaining }
        for interval in intervals {
            let len = interval.upperBound - interval.lowerBound
            if remaining <= len { return interval.lowerBound + remaining }
            remaining -= len
        }
        return last.upperBound + remaining
    }

    /// Inverse of `x(alongUsable:)` for points inside usable intervals; points in
    /// a gap snap to the nearest boundary.
    public func usableDistance(atX x: Double) -> Double {
        var acc = 0.0
        for interval in usableIntervals {
            if x < interval.lowerBound { return acc }
            if x <= interval.upperBound { return acc + (x - interval.lowerBound) }
            acc += interval.upperBound - interval.lowerBound
        }
        return acc
    }
}

/// Where each item hangs.
public struct LineLayout: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        /// Pin position (top-centre of the item) on the rope.
        public var x: Double
        public var y: Double
        /// Rotation in radians, positive = clockwise in a y-down space.
        public var rotation: Double
        /// Whether the slot is within the visible part of the line.
        public var visible: Bool
    }

    public var slots: [Slot]
    public var pitch: Double
    /// Total content length minus usable length; > 0 means the line scrolls.
    public var overflow: Double

    /// Lays out `jitters` (one per item, values in [-1, 1]) along the line.
    ///
    /// Items are spaced naturally when there is room, crowd together (overlapping
    /// like real laundry) when space runs out, and finally the line becomes
    /// horizontally scrollable by `scroll` points.
    public init(geometry: LineGeometry, itemWidth: Double, jitters: [Double], scroll: Double = 0, reduceMotion: Bool = false) {
        let n = jitters.count
        let natural = itemWidth + 18
        let minimum = itemWidth * 0.55
        let length = geometry.usableLength
        var pitch = natural
        if n > 1 {
            pitch = min(natural, max(minimum, length / Double(n - 1)))
        }
        let groupLength = pitch * Double(max(n - 1, 0))
        self.pitch = pitch
        self.overflow = max(0, groupLength - length)
        let maxScroll = overflow
        let clampedScroll = min(max(scroll, 0), maxScroll)
        let start = overflow > 0 ? -clampedScroll : (length - groupLength) / 2

        var slots: [Slot] = []
        slots.reserveCapacity(n)
        for (i, j) in jitters.enumerated() {
            // Organic spacing: nudge each item a little, less when crowded.
            let nudge = j * min(6, pitch * 0.08)
            let d = start + Double(i) * pitch + nudge
            let x = geometry.x(alongUsable: d)
            let ropeAngle = geometry.ropeAngle(atX: x)
            let tilt = reduceMotion ? j * 0.02 : j * 0.055
            let visible = d >= -itemWidth * 0.25 && d <= length + itemWidth * 0.25
            slots.append(Slot(x: x, y: geometry.ropeY(atX: x), rotation: ropeAngle * 0.55 + tilt, visible: visible))
        }
        self.slots = slots
    }

    /// The insertion index for a drop at x (used for drag-to-reorder).
    public static func insertionIndex(forX x: Double, in slots: [Slot]) -> Int {
        for (i, slot) in slots.enumerated() where x < slot.x { return i }
        return slots.count
    }
}

/// Placement of the panel on a display. All rectangles use the AppKit screen
/// coordinate system (origin bottom-left), so the app can pass NSScreen values
/// straight in.
public struct PanelPlacement: Equatable, Sendable {
    public var frame: CGRect
    /// x of the notch centre in panel-local coordinates, if the panel sits under a notch.
    public var notchCenterX: Double?
    public var hasNotch: Bool

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - visibleFrame: `NSScreen.visibleFrame` (excludes the menu bar and Dock).
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (non-zero on notched displays).
    ///   - notchRect: the camera-housing rect between `auxiliaryTopLeftArea` and
    ///     `auxiliaryTopRightArea`, if available.
    public init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: Double, notchRect: CGRect?, height: Double, sideMargin: Double = 8, verticalOffset: Double = 0) {
        // Hang below the menu bar. If the menu bar is hidden (auto-hide or a
        // full-screen space) visibleFrame reaches the top, but on a notched
        // display we still have to stay below the camera housing.
        var top = Double(visibleFrame.maxY)
        if safeAreaTop > 0 { top = min(top, Double(screenFrame.maxY) - safeAreaTop) }
        top = min(top, Double(screenFrame.maxY))
        let width = Double(screenFrame.width) - sideMargin * 2
        let h = min(height, max(140, top - Double(screenFrame.minY)))
        let maximumOffset = max(0, top - h - Double(visibleFrame.minY))
        let offset = verticalOffset.isFinite ? min(maximumOffset, max(0, verticalOffset)) : 0
        let origin = CGPoint(x: Double(screenFrame.minX) + sideMargin, y: top - h - offset)
        self.frame = CGRect(x: origin.x, y: origin.y, width: width, height: h)
        if let notch = notchRect, notch.width > 0, offset == 0 {
            self.hasNotch = true
            self.notchCenterX = Double(notch.midX) - Double(origin.x)
        } else {
            self.hasNotch = false
            self.notchCenterX = nil
        }
    }
}
