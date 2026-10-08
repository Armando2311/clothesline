import Foundation

/// Automatic cleanup rules. Cleanup only ever removes items *from the line*.
/// Referenced files are never touched; only Clothesline-owned copies are
/// deleted, by the caller, after the item is gone.
public struct RetentionPolicy: Codable, Equatable, Sendable {
    /// Keep at most this many unpinned screenshots per line (oldest go first).
    public var maxScreenshotsPerLine: Int?
    /// Remove unpinned items older than this many hours (applies to all lines,
    /// in addition to any per-line expiry).
    public var expireAfterHours: Double?
    /// Remove unpinned items when Clothesline quits.
    public var clearUnpinnedOnQuit: Bool

    public init(maxScreenshotsPerLine: Int? = 30, expireAfterHours: Double? = nil, clearUnpinnedOnQuit: Bool = false) {
        self.maxScreenshotsPerLine = maxScreenshotsPerLine
        self.expireAfterHours = expireAfterHours
        self.clearUnpinnedOnQuit = clearUnpinnedOnQuit
    }

    enum CodingKeys: String, CodingKey { case maxScreenshotsPerLine, expireAfterHours, clearUnpinnedOnQuit }

    // Explicit coding: `nil` limits are written as null so "unlimited" is not
    // mistaken for "missing" (which falls back to the default) on decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RetentionPolicy()
        maxScreenshotsPerLine = c.contains(.maxScreenshotsPerLine) ? (try? c.decodeIfPresent(Int.self, forKey: .maxScreenshotsPerLine)) ?? nil : d.maxScreenshotsPerLine
        expireAfterHours = c.contains(.expireAfterHours) ? (try? c.decodeIfPresent(Double.self, forKey: .expireAfterHours)) ?? nil : d.expireAfterHours
        clearUnpinnedOnQuit = (try? c.decodeIfPresent(Bool.self, forKey: .clearUnpinnedOnQuit)) ?? d.clearUnpinnedOnQuit
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxScreenshotsPerLine, forKey: .maxScreenshotsPerLine)
        try c.encode(expireAfterHours, forKey: .expireAfterHours)
        try c.encode(clearUnpinnedOnQuit, forKey: .clearUnpinnedOnQuit)
    }

    /// The effective expiry for a line: the stricter of the global and per-line settings.
    func expiryHours(for line: Line) -> Double? {
        switch (expireAfterHours, line.expiryHours) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    /// Items that the policy says should leave the line at `now`.
    public func itemsToRemove(from board: Board, now: Date) -> Set<UUID> {
        var result = Set<UUID>()
        for line in board.lines {
            let lineItems = board.items(on: line.id)
            if let hours = expiryHours(for: line) {
                let cutoff = now.addingTimeInterval(-hours * 3600)
                for item in lineItems where !item.pinned && item.dateAdded <= cutoff {
                    result.insert(item.id)
                }
            }
            if let maxShots = maxScreenshotsPerLine, maxShots >= 0 {
                let shots = lineItems
                    .filter { $0.kind == .screenshot && !$0.pinned && !result.contains($0.id) }
                    .sorted { $0.dateAdded < $1.dateAdded }
                if shots.count > maxShots {
                    for item in shots.prefix(shots.count - maxShots) { result.insert(item.id) }
                }
            }
        }
        return result
    }

    /// The next moment an item will expire, so the app can schedule a single
    /// one-shot timer instead of polling.
    public func nextExpiry(in board: Board, after now: Date) -> Date? {
        var next: Date?
        for line in board.lines {
            guard let hours = expiryHours(for: line) else { continue }
            for item in board.items(on: line.id) where !item.pinned {
                let due = item.dateAdded.addingTimeInterval(hours * 3600)
                if due > now, next == nil || due < next! { next = due }
            }
        }
        return next
    }
}
