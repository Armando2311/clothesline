import Foundation

/// The complete persisted state: every line and every item on it.
///
/// Items are stored in one array; their relative order *within a line* is the
/// left-to-right order on that line. `Board` is a value type with pure mutating
/// operations so all of the line logic can be unit-tested without UI.
public struct Board: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var lines: [Line]
    public var items: [HangingItem]
    public var activeLineID: UUID

    public init(lines: [Line], items: [HangingItem] = [], activeLineID: UUID? = nil) {
        precondition(!lines.isEmpty, "A board needs at least one line")
        self.schemaVersion = Board.currentSchemaVersion
        self.lines = lines
        self.items = items
        self.activeLineID = activeLineID ?? lines[0].id
    }

    /// The default board for first launch.
    public static func makeDefault() -> Board {
        let main = Line(name: "Clothesline")
        return Board(lines: [main], activeLineID: main.id)
    }

    // MARK: - Queries

    public var activeLine: Line {
        lines.first { $0.id == activeLineID } ?? lines[0]
    }

    public func items(on lineID: UUID) -> [HangingItem] {
        items.filter { $0.lineID == lineID }
    }

    /// Include a destination if at least one selected item would actually move.
    public func moveDestinations(for selected: [HangingItem]) -> [Line] {
        guard !selected.isEmpty else { return [] }
        return lines.filter { line in selected.contains { $0.lineID != line.id } }
    }

    public var activeItems: [HangingItem] { items(on: activeLineID) }

    public func item(_ id: UUID) -> HangingItem? {
        items.first { $0.id == id }
    }

    public func line(_ id: UUID) -> Line? {
        lines.first { $0.id == id }
    }

    // MARK: - Adding

    public enum AddOutcome: Equatable, Sendable {
        case added(HangingItem)
        /// An equivalent item was already on the line; it was moved to the end
        /// (most recent) instead of being duplicated.
        case alreadyPresent(HangingItem)
    }

    /// Hangs an item on its line. Items are appended to the right end unless an
    /// explicit position is given. Duplicates (same file path, link or text on
    /// the same line) are not added twice.
    @discardableResult
    public mutating func add(_ item: HangingItem, atLinePosition position: Int? = nil) -> AddOutcome {
        if let existing = items.first(where: { $0.lineID == item.lineID && $0.dedupeKey == item.dedupeKey }) {
            return .alreadyPresent(existing)
        }
        let lineItems = items(on: item.lineID)
        guard let position, position < lineItems.count else {
            items.append(item)
            return .added(item)
        }
        let clamped = max(0, position)
        let anchorID = lineItems[clamped].id
        let globalIndex = items.firstIndex { $0.id == anchorID } ?? items.count
        items.insert(item, at: globalIndex)
        return .added(item)
    }

    // MARK: - Removing

    /// Removes items from the board (never touches files). Returns the removed
    /// items so the caller can clean up any Clothesline-owned copies.
    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> [HangingItem] {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Clears a line. Pinned items stay unless `includingPinned` is true.
    @discardableResult
    public mutating func clear(lineID: UUID, includingPinned: Bool = false) -> [HangingItem] {
        let ids = Set(items.filter { $0.lineID == lineID && (includingPinned || !$0.pinned) }.map(\.id))
        return remove(ids)
    }

    // MARK: - Editing

    public mutating func setPinned(_ ids: Set<UUID>, _ pinned: Bool) {
        for i in items.indices where ids.contains(items[i].id) {
            items[i].pinned = pinned
        }
    }

    public mutating func rename(_ id: UUID, to title: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[i].title = trimmed
    }

    public mutating func editNote(_ id: UUID, text: String) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.kind == .text }),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items[i].text = text
        items[i].title = ItemClassifier.title(forText: text)
    }

    public mutating func updateFile(_ id: UUID, _ file: FileReference) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].file = file
    }

    /// Moves the given items (keeping their relative order) so that they sit at
    /// `position` among the remaining items of their line. Used for manual
    /// arrangement by dragging along the line.
    public mutating func move(_ ids: Set<UUID>, toLinePosition position: Int, lineID: UUID) {
        let moving = items.filter { ids.contains($0.id) && $0.lineID == lineID }
        guard !moving.isEmpty else { return }
        let movingIDs = Set(moving.map(\.id))
        items.removeAll { movingIDs.contains($0.id) }
        let remaining = items(on: lineID)
        let globalIndex: Int
        if position >= remaining.count {
            if let last = remaining.last, let idx = items.firstIndex(where: { $0.id == last.id }) {
                globalIndex = idx + 1
            } else {
                globalIndex = items.count
            }
        } else {
            let anchor = remaining[max(0, position)].id
            globalIndex = items.firstIndex { $0.id == anchor } ?? items.count
        }
        items.insert(contentsOf: moving, at: globalIndex)
    }

    /// Moves items to another line, appending them at its right end.
    public mutating func move(_ ids: Set<UUID>, toLine lineID: UUID) {
        guard line(lineID) != nil else { return }
        let moving = items.filter { ids.contains($0.id) && $0.lineID != lineID }
        var movedIDs = Set<UUID>()
        for var item in moving {
            item.lineID = lineID
            // Skip if the destination already holds the same thing.
            if items.contains(where: { $0.lineID == lineID && $0.dedupeKey == item.dedupeKey }) { continue }
            movedIDs.insert(item.id)
        }
        let moved = items.filter { movedIDs.contains($0.id) }.map { item -> HangingItem in
            var copy = item
            copy.lineID = lineID
            return copy
        }
        items.removeAll { movedIDs.contains($0.id) }
        items.append(contentsOf: moved)
    }

    // MARK: - Organisation

    public enum SortOrder: String, CaseIterable, Codable, Sendable {
        case dateAdded
        case kind
        case name
        case source

        public var displayName: String {
            switch self {
            case .dateAdded: return "Date Added"
            case .kind: return "Kind"
            case .name: return "Name"
            case .source: return "Source"
            }
        }
    }

    /// Re-orders a line once. Manual arrangement afterwards is preserved.
    /// Pinned items always gather at the left end.
    public mutating func sort(lineID: UUID, by order: SortOrder) {
        let lineItems = items(on: lineID)
        let sorted = lineItems.enumerated().sorted { a, b in
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            let lhs = a.element, rhs = b.element
            switch order {
            case .dateAdded:
                if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
            case .kind:
                let li = ItemKind.allCases.firstIndex(of: lhs.kind)!
                let ri = ItemKind.allCases.firstIndex(of: rhs.kind)!
                if li != ri { return li < ri }
            case .name:
                let c = lhs.title.localizedStandardCompare(rhs.title)
                if c != .orderedSame { return c == .orderedAscending }
            case .source:
                if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
            }
            return a.offset < b.offset // stable
        }.map(\.element)
        items.removeAll { $0.lineID == lineID }
        items.append(contentsOf: sorted)
    }

    // MARK: - Lines

    @discardableResult
    public mutating func addLine(named name: String, expiryHours: Double? = nil) -> Line {
        let line = Line(name: uniqueLineName(name), expiryHours: expiryHours)
        lines.append(line)
        return line
    }

    public mutating func renameLine(_ id: UUID, to name: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines[i].name = trimmed
    }

    public mutating func setExpiry(_ id: UUID, hours: Double?) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].expiryHours = hours
    }

    /// Deletes a line. Its items move to a neighbouring line rather than being
    /// discarded. The last remaining line cannot be deleted.
    public mutating func deleteLine(_ id: UUID) {
        guard lines.count > 1, let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let target = index > 0 ? lines[index - 1].id : lines[index + 1].id
        move(Set(items(on: id).map(\.id)), toLine: target)
        // Anything left (duplicates of items already on the target) goes away.
        items.removeAll { $0.lineID == id }
        lines.remove(at: index)
        if activeLineID == id { activeLineID = target }
    }

    public mutating func activate(lineID: UUID) {
        if line(lineID) != nil { activeLineID = lineID }
    }

    private func uniqueLineName(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Line" : trimmed
        let existing = Set(lines.map(\.name))
        if !existing.contains(name) { return name }
        var n = 2
        while existing.contains("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }

    // MARK: - Integrity

    /// Repairs a decoded board: reassigns orphaned items, fixes the active line
    /// and drops duplicate ids. Called after loading from disk.
    public mutating func repair() {
        if lines.isEmpty { lines = [Line(name: "Clothesline")] }
        let lineIDs = Set(lines.map(\.id))
        if !lineIDs.contains(activeLineID) { activeLineID = lines[0].id }
        var seen = Set<UUID>()
        items = items.compactMap { item in
            guard seen.insert(item.id).inserted else { return nil }
            var item = item
            if !lineIDs.contains(item.lineID) { item.lineID = lines[0].id }
            return item
        }
    }
}
