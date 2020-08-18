/// `LKToken` represents the first stage of parsing Leaf templates - a raw file/bytestream `String`
/// will be read by `LKLexer` and interpreted into `[LKToken]` representing a stream of tokens.
///
/// # TOKEN DEFINITIONS
/// - `.raw`: A variable-length string of data that will eventually be output directly without processing
/// - `.tagIndicator`: The signal at top-level that a Leaf syntax object will follow. Default is `#` and
///                   while it can be configured to be something else, only rare uses cases may want
///                   to do so. `.tagindicator` can be escaped in source templates with a
///                   backslash, which will automatically be consumed by `.raw` if so. Decays to
///                   `.raw` automatically at lexing when not followed by a valid function identifier
///                   or left parent indicating an anonymous expression
/// - `.tag(String?)`: The expected function/block name - in `#for(index in array)`, equivalent
///                   token is `.tag("for")`. Nil value represents the insterstitial point of an
///                   anonymous tag - eg, the void between `#` and `(` in `#()`
/// - `.scopeIndicator`: Indicates the start of a scoped block from a `LeafBlock` tag - `:`
/// - `.parametersStart`: Indicates the start of an expression/function/block's parameters - `(`
/// - `.labelIndicator`: Indicates that preceding identifier is a label for a following parameter- `:`
/// - `.parameterDelimiter`: Indicates a delimter between parameters - `,`
/// - `.parameter(Parameter)`: Associated value enum storing a valid tag parameter.
/// - `.parametersEnd`: Indicates the end of a tag's parameters - `)`
/// - `.whiteSpace(String)`: Currently only used inside parameters, and only preserved when needed
///                         to disambiguate things Lexer can't handle (eg, `[` as subscript (no
///                         whitespace) versus collection literal (can accept whitespace)
///
/// # TODO
/// - LKTokens would ideally also store the range of their location in the original source template
/// - Tracking `.whiteSpace` in .`raw` to handle regularly formatted indentation, drop extraneous \n etc
internal enum LKToken: LKPrintable, Hashable  {
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
    /// `:` - Indicates a delineation of `label : value` in parameters
    case labelIndicator
    /// `,` -  Indicates separation of a tag's parameters
    case parameterDelimiter
    /// Holds a `ParameterToken` enum
    case parameter(Parameter)
    /// `)` -  Indicates the end of a tag's parameters
    case parametersEnd

    /// A stream of consecutive white space (currently only used inside parameters)
    case whiteSpace(String)

    /// Returns `"tokenCase"` or `"tokenCase(valueAsString)"` if associated value
    var description: String {
        switch self {
            case .raw(let r)         : return "\(short)(\(r.debugDescription))"
            case .tag(.some(let t))  : return "\(short)(\"\(t)\")"
            case .parameter(let p)   : return "\(short)(\(p.description))"
            default                  : return short
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
            case .labelIndicator     : return "labelIndicator"
            case .parametersEnd      : return "parametersEnd"
            case .parameterDelimiter : return "parameterDelimiter"
            case .parameter          : return "param"
            case .whiteSpace         : return "whiteSpace"
        }
    }

    /// A token that represents the valid objects that will be lexed inside parameters
    enum Parameter: LKPrintable, Hashable {
        /// Any tokenized literal value with a native Swift type
        ///
        /// ```
        /// case int(Int)       // A Swift `Int`
        /// case double(Double) // A Swift `Double`
        /// case string(String) // A Swift `String`
        /// case emptyArray     // A Swift `[]`
        /// case emptyDict      // A Swift `[:]`
        case literal(Literal)
        /// Any Leaf keyword with no restrictions
        case keyword(LeafKeyword)
        /// Any Leaf operator
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

        /// Any tokenized literal value with a native Swift type
        ///
        /// ```
        /// case int(Int)       // A Swift `Int`
        /// case double(Double) // A Swift `Double`
        /// case string(String) // A Swift `String`
        /// case emptyArray     // A Swift `[]`
        /// case emptyDict      // A Swift `[:]`
        enum Literal: LKPrintable, LeafDataRepresentable, Hashable {
            /// A Swift `Int`
            case int(Int)
            /// A Swift `Double`
            case double(Double)
            /// A Swift `String`
            case string(String)
            /// A Swift `Array` - only used to disambiguate empty array literal
            case emptyArray
            /// A Swift `Dictionary` - only used to disambiguate empty array literal
            case emptyDict

            var description: String {
                switch self {
                    case .int(let i)    : return "Int: \(i.description)"
                    case .double(let d) : return "Double: \(d.description)"
                    case .string(let s) : return "String: \"\(s)\""
                    case .emptyArray    : return "Array (empty)"
                    case .emptyDict     : return "Dictionary (empty)"
                }
            }
            var short: String {
                switch self {
                    case .int(let i)    : return i.description
                    case .double(let d) : return d.description
                    case .string(let s) : return "\"\(s)\""
                    case .emptyArray    : return "[]"
                    case .emptyDict     : return "[:]"
                }
            }

            var leafData: LeafData {
                switch self {
                    case .int(let i)    : return .int(i)
                    case .double(let d) : return .double(d)
                    case .string(let s) : return .string(s)
                    case .emptyArray    : return .array([])
                    case .emptyDict     : return .dictionary([:])
                }
            }
        }
    }
}
