import SwiftUI
struct SearchHighlight:View {
    var text:String
    var query:String
    var body:some View { highlighted(text,remaining:64) }
    private func highlighted(_ value:String,remaining:Int)->Text {
        guard remaining > 0 else { return Text(value) }
        let matches = query.split(whereSeparator:\.isWhitespace).compactMap { value.range(of:String($0),options:[.caseInsensitive,.diacriticInsensitive]) }
        guard let match = matches.min(by:{ $0.lowerBound < $1.lowerBound }) else { return Text(value) }
        return Text(String(value[..<match.lowerBound])) + Text(String(value[match])).bold().foregroundColor(.accentColor) + highlighted(String(value[match.upperBound...]),remaining:remaining-1)
    }
}
