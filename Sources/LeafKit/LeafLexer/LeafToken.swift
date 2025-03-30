// MARK: `LeafToken` Summary

/// `LeafToken` represents the first stage of parsing Leaf templates - a raw file/bytestream `String`
/// will be read by `LeafLexer` and interpreted into `[LeafToken]` representing a stream of tokens.
///
/// # STABLE TOKEN DEFINITIONS
/// - `.raw`: A variable-length string of data that will eventually be output directly without processing
/// - `.tagIndicator`: The signal at top-level that a Leaf syntax object will follow. Default is `#` and
///     while it can be configured to be something else, only rare uses cases may want to do so.
///     `.tagindicator` can be escaped in source templates with a backslash and will automatically
///     be consumed by `.raw` if so. May decay to `.raw` at the token parsing stage if a non-
///     tag/syntax object follows.
/// - `.tag`: The expected tag name - in `#for(index in array)`, equivalent token is `.tag("for")`
/// - `.tagBodyIndicator`: Indicates the start of a body-bearing tag - ':'
/// - `.parametersStart`: Indicates the start of a tag's parameters - `(`
/// - `.parameterDelimiter`: Indicates a delimter between parameters - `,`
/// - `.parameter`: Associated value enum storing a valid tag parameter.
/// - `.parametersEnd`: Indicates the end of a tag's parameters - `)`
///
/// # POTENTIALLY UNSTABLE TOKENS
/// - `.stringLiteral`: Does not appear to be used anywhere?
/// - `.whitespace`: Only generated when not at top-level, and unclear why maintaining it is useful
///

internal enum LeafToken: CustomStringConvertible, Equatable, Sendable {
    /// Holds a variable-length string of data that will be passed through with no processing
    case raw(String)
    
    /// `#` (or as configured) - Top-level signal that indicates a Leaf tag/syntax object will follow.
    case tagIndicator
    /// Holds the name of an expected tag or syntax object (eg, `for`) in `#for(index in array)`
    case tag(name: String)
    /// `:` - Indicates the start of a body for a body-bearing tag
    case tagBodyIndicator

    /// `(` -  Indicates the start of a tag's parameters
    case parametersStart
    /// `,` -  Indicates separation of a tag's parameters
    case parameterDelimiter
    /// Holds a `Parameter` enum
    case parameter(Parameter)
    /// `)` -  Indicates the end of a tag's parameters
    case parametersEnd

    /// To be removed if possible - avoid using
    case stringLiteral(String)
    /// To be removed if possible - avoid using
    case whitespace(length: Int)
    
    /// Returns `"tokenCase"` or `"tokenCase(valueAsString)"` if holding a value
    var description: String {
        switch self {
            case .raw(let str):
                return "raw(\(str.debugDescription))"
            case .tagIndicator:
                return "tagIndicator"
            case .tag(let name):
                return "tag(name: \(name.debugDescription))"
            case .tagBodyIndicator:
                return "tagBodyIndicator"
            case .parametersStart:
                return "parametersStart"
            case .parametersEnd:
                return "parametersEnd"
            case .parameterDelimiter:
                return "parameterDelimiter"
            case .parameter(let param):
                return "param(\(param))"
            case .stringLiteral(let string):
                return "stringLiteral(\(string.debugDescription))"
            case .whitespace(let length):
                return "whitespace(\(length))"
        }
    }
}
