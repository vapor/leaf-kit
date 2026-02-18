extension String {
    /// Escapes HTML entities in a `String`.
    public func htmlEscaped() -> String {
        self.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(scalar)
            }
        }
    }
}
