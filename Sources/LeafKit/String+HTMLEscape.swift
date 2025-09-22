import Foundation

extension String {
    /// Escapes HTML entities in a `String`.
    public func htmlEscaped() -> String {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            self
                .replacing("&", with: "&amp;")
                .replacing("\"", with: "&quot;")
                .replacing("'", with: "&#39;")
                .replacing("<", with: "&lt;")
                .replacing(">", with: "&gt;")
        } else {
            self
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
    }
}
