import Foundation
public enum ReleaseVersion {
    private static func components(_ text:String)->[Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        return values + Array(repeating:0,count:3-values.count)
    }
    public static func isNewer(_ candidate:String,than current:String)->Bool {
        guard let a = components(candidate),let b = components(current) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }
    public static func isTrustedReleaseURL(_ url:URL)->Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.port == nil && url.path.hasPrefix("/Armando2311/clothesline/releases/")
    }
}
