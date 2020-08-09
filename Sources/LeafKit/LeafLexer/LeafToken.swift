// MARK: Subject to change prior to 1.0.0 release
// MARK: -

// MARK: `LeafToken` Summary

/// `LeafToken` represents the first stage of parsing Leaf templates - a raw file/bytestream `String`
/// will be read by `LeafLexer` and interpreted into `[LeafToken]` representing a stream of tokens.
///
/// # STABLE TOKEN DEFINITIONS
/// - `.raw`: A variable-length string of data that will eventually be output directly without processing
/// - `.tagIndicator`: The signal at top-level that a Leaf syntax object will follow. Default is `#` and
///                   while it can be configured to be something else, only rare uses cases may want
///                   to do so. `.tagindicator` can be escaped in source templates with a
///                   backslash and will automatically be consumed by `.raw` if so. May decay to
///                   `.raw` at the token parsing stage if a non-tag/syntax object follows.
/// - `.tag(String?)`: The expected tag name - in `#for(index in array)`, equivalent token is
///                   `.tag("for")`. Nil value represents the insterstitial point of an anonymous
///                   tag - eg, the void between # and ( in `#()`
/// - `.blockIndicator`: Indicates the start of a body-bearing tag - `:`
/// - `.parametersStart`: Indicates the start of a tag's parameters - `(`
/// - `.parameterDelimiter`: Indicates a delimter between parameters - `,`
/// - `.parameter`: Associated value enum storing a valid tag parameter.
/// - `.parametersEnd`: Indicates the end of a tag's parameters - `)`
///
/// # POTENTIALLY UNSTABLE TOKENS
/// - `.space`: Only generated when inside parameters. Unclear why maintaining it is useful iside params;
///            However it probably should be evaluted while in `raw` state for indenting control
///
/// # TODO
/// - LeafTokens would ideally also store the range of their location in the original source template
internal enum LeafToken: LKPrintable, Hashable  {
    /// Holds a variable-length string of data that will be passed through with no processing
    case raw(String)
    
    /// `#` (or as configured) - Top-level signal that indicates a Leaf tag/syntax object will follow.
    case tagIndicator
    /// Holds the name of an expected tag or syntax object (eg, `for`) in `#for(index in array)`
    ///
    /// - Nil: Anonymous tag (top level expression)
    /// - Non-nil:  A named function or block, or an endblock tag
    case tag(String?)
    /// `:` - Indicates the start of a scoped body-bearing block
    case scopeIndicator

    /// `(` -  Indicates the start of a tag's parameters
    case parametersStart
    /// `,` -  Indicates separation of a tag's parameters
    case parameterDelimiter
    /// Holds a `ParameterToken` enum
    case parameter(LeafTokenParameter)
    /// `)` -  Indicates the end of a tag's parameters
    case parametersEnd
    
    /// Returns `"tokenCase"` or `"tokenCase(valueAsString)"` if associated value
    var description: String {
        switch self {
            case .raw(let r)         : return "\(short)(\(r.debugDescription))"
            case .tagIndicator       : return short
            case .tag(.none)         : return short
            case .tag(.some(let t))  : return "\(short)(\(t.debugDescription))"
            case .scopeIndicator     : return short
            case .parametersStart    : return short
            case .parametersEnd      : return short
            case .parameterDelimiter : return short
            case .parameter(let p)   : return "\(short)(\(p.description))"
        }
    }
    
    /// Token case
    var short: String {
        switch self {
            case .raw                : return "raw"
            case .tagIndicator       : return "tagIndicator"
            case .tag(.none)         : return "expression"
            case .tag(.some)         : return "function"
            case .scopeIndicator     : return "blockIndicator"
            case .parametersStart    : return "parametersStart"
            case .parametersEnd      : return "parametersEnd"
            case .parameterDelimiter : return "parameterDelimiter"
            case .parameter          : return "param"
        }
    }
    
    /// A token that represents the valid objects that will be lexed inside parameters
    enum LeafTokenParameter: LKPrintable, Hashable {
        /// Any tokenized literal value with a native Swift type
        ///
        /// ```
        /// case int(Int)       // A Swift `Int`
        /// case double(Double) // A Swift `Double`
        /// case string(String) // A Swift `String`
        case literal(Literal)
        /// Any Leaf keyword with no restrictions
        case keyword(LeafKeyword)
        /// Any Leaf operator - must be `.isLexable`
        case `operator`(LeafOperator)
        /// A single part of a variable scope - must be non-empty
        case variable(String)
        /// An identifier signifying a function or method name - must be non-empty
        case function(String)
        
        /// Returns `parameterCase(parameterValue)`
        var description: String {
            switch self {
                case .literal(let c)  : return "literal(\(c.description))"
                case .variable(let v) : return "variable(part: \(v))"
                case .keyword(let k)  : return "keyword(.\(k.short))"
                case .operator(let o) : return "operator(\(o.description))"
                case .function(let f) : return "function(id: \"\(f)\")"
            }
        }
        
        /// Returns `parameterValue` or `"parameterValue"` as appropriate for type
        var short: String {
            switch self {
                case .literal(let c)  : return "lit(\(c.short))"
                case .variable(let v) : return "var(\(v))"
                case .keyword(let k)  : return "kw(.\(k.short))"
                case .operator(let o) : return "op(\(o.short))"
                case .function(let f) : return "func(\(f))"
            }
        }
        
        /// An integer, double, or string constant value parameter (eg `1_000`, `-42.0`, `"string"`)
        enum Literal: LKPrintable, LeafDataRepresentable, Hashable {
            /// A Swift `Int`
            case int(Int)
            /// A Swift `Double`
            case double(Double)
            /// A Swift `String`
            case string(String)
            /// A Swift `Array` - only used to provide empty array literal currently
            case emptyArray

            var description: String {
                switch self {
                    case .double(let d) : return "Double: \(d.description)"
                    case .emptyArray    : return "Array: empty"
                    case .int(let i)    : return "Int: \(i.description)"
                    case .string(let s) : return "String: \"\(s)\""
                }
            }
            var short: String {
                switch self {
                    case .int(let i)    : return i.description
                    case .double(let d) : return d.description
                    case .string(let s) : return "\"\(s)\""
                    case .emptyArray    : return "[]"
                }
            }
            
            var leafData: LeafData {
                switch self {
                    case .int(let i)    : return .int(i)
                    case .double(let d) : return .double(d)
                    case .string(let s) : return .string(s)
                    case .emptyArray    : return .array([])
                }
            }
        }
    }
}
