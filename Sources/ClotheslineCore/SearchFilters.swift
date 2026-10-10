import Foundation

public enum SearchPeriod: String, Codable, CaseIterable, Sendable {
    case anytime, today, week
    public var displayName: String {
        switch self { case .anytime: return "Any time"; case .today: return "Today"; case .week: return "Last 7 days" }
    }
}
public struct SearchFilters: Equatable, Sendable {
    public var kind: ItemKind?
    public var source: ItemSource?
    public var lineID: UUID?
    public var period: SearchPeriod = .anytime
    public init() {}
    public var isActive: Bool { kind != nil || source != nil || lineID != nil || period != .anytime }
    public func results(board: Board, query: String, recognizedText: [UUID:String] = [:], now: Date = Date(), calendar: Calendar = .current) -> [HangingItem] {
        let terms = query.trimmingCharacters(in:.whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        let candidates = terms.isEmpty && !isActive ? board.activeItems : board.items
        let cutoff: Date?
        switch period { case .anytime: cutoff = nil; case .today: cutoff = calendar.startOfDay(for:now); case .week: cutoff = now.addingTimeInterval(-7*86400) }
        return candidates.filter { item in
            guard kind == nil || kind == item.kind, source == nil || source == item.source,
                  lineID == nil || lineID == item.lineID, cutoff == nil || item.dateAdded >= cutoff! else { return false }
            let text = [item.title,item.text ?? "",item.link ?? "",item.file?.fileName ?? "",item.kind.displayName,board.line(item.lineID)?.name ?? "",recognizedText[item.id] ?? ""].joined(separator:" ")
            return terms.allSatisfy { text.range(of:$0,options:[.caseInsensitive,.diacriticInsensitive]) != nil }
        }
    }
    public static func excerpt(_ text: String, query: String) -> String? {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return nil }
        return text.components(separatedBy:.newlines).first { line in terms.contains { line.range(of:String($0),options:[.caseInsensitive,.diacriticInsensitive]) != nil } }.map { String($0.prefix(160)) }
    }
}
public enum PanelLayout: String, Codable, CaseIterable, Sendable {
    case fullWidth, fitted
    public var displayName: String { self == .fullWidth ? "Full width" : "Fit contents" }
}
public struct ItemGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var lineID: UUID
    public var itemIDs: Set<UUID>
    public init(name:String,lineID:UUID,itemIDs:Set<UUID>) { self.name = name; self.lineID = lineID; self.itemIDs = itemIDs }
}
