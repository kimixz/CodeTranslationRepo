
import Foundation

final class StringUtils {
    
    private init() {
        // prevent class from being constructed
    }
    
    static func searchAndColor(text: String?, searchText: String?, color: Int) -> String {
        guard let text = text else {
            return ""
        }
        
        if text.isEmpty || searchText == nil || searchText!.isEmpty {
            return text
        }
        
        let pattern = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: searchText!), options: [.caseInsensitive])
        let range = NSRange(location: 0, length: text.utf16.count)
        let mutableString = NSMutableString(string: text)
        
        pattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                let matchedString = (text as NSString).substring(with: matchRange)
                let replacement = String(format: "<font color='%d'><b>%@</b></font>", color, matchedString)
                mutableString.replaceCharacters(in: matchRange, with: replacement)
            }
        }
        
        return mutableString as String
    }
    
    static func removePrefix(_ s: String, _ prefix: String) -> String {
        if s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count))
        }
        return s
    }
}
