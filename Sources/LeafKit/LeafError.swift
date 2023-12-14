// MARK: `LeafError` Summary

/// `LeafError` reports errors during the template rendering process, wrapping more specific
/// errors if necessary during Lexing and Parsing stages.
///
public struct LeafError: Error {
    /// Possible cases of a LeafError.Reason, with applicable stored values where useful for the type
    public enum Reason: Sendable {
        // MARK: Errors related to loading raw templates
        /// Attempted to access a template blocked for security reasons
        case illegalAccess(String)
        
        // MARK: Errors related to LeafCache access
        /// Attempt to modify cache entries when caching is globally disabled
        case cachingDisabled
        /// Attempt to insert a cache entry when one exists and replacing is not set to true
        /// - Provide the template name update was attempted on
        case keyExists(String)
        /// Attempt to modify cache for a non-existant key
        /// - Provide template name
        /// - NOTE: NOT thrown when "reading" from cache - nil Optional returned then
        case noValueForKey(String)

        // MARK: Errors related to rendering a template
        /// Attempt to render a non-flat AST
        /// - Provide template name & array of unresolved references
        case unresolvedAST(String, [String])
        /// Attempt to render a non-existant template
        /// Provide template name
        case noTemplateExists(String)
        /// Attempt to render an AST with cyclical external references
        /// - Provide template name & ordered array of template names that causes the cycle path
        case cyclicalReference(String, [String])

        // MARK: Wrapped Errors related to Lexing or Parsing
        /// Errors due to malformed template syntax or grammar
        case lexerError(LexerError)
        
        // MARK: Errors lacking specificity
        /// Errors from protocol adherents that do not support newer features
        case unsupportedFeature(String)
        /// Errors only when no existing error reason is adequately clear
        case unknownError(String)
    }
    
    /// Source file name causing error
    public let file: String
    /// Source function causing error
    public let function: String
    /// Source file line causing error
    public let line: UInt
    /// Source file column causing error
    public let column: UInt
    /// The specific reason for the error
    public let reason: Reason

    
    /// Provide  a custom description of the `LeafError` based on type.
    ///
    /// - Where errors are caused by toolchain faults, will report the Swift source code location of the call
    /// - Where errors are from Lex or Parse errors, will report the template source location of the error
    var localizedDescription: String {
        let file = self.file.split(separator: "/").last
        let src = "\(file ?? "?").\(function):\(line)"

        switch self.reason {
            case .illegalAccess(let message):
                return "\(src) - \(message)"
            case .unknownError(let message):
                return "\(src) - \(message)"
            case .unsupportedFeature(let feature):
                return "\(src) - \(feature) is not implemented"
            case .cachingDisabled:
                return "\(src) - Caching is globally disabled"
            case .keyExists(let key):
                return "\(src) - Existing entry \(key); use insert with replace=true to overrride"
            case .noValueForKey(let key):
                return "\(src) - No cache entry exists for \(key)"
            case .unresolvedAST(let key, let dependencies):
                return "\(src) - Flat AST expected; \(key) has unresolved dependencies: \(dependencies)"
            case .noTemplateExists(let key):
                return "\(src) - No template found for \(key)"
            case .cyclicalReference(let key, let chain):
                return "\(src) - \(key) cyclically referenced in [\(chain.joined(separator: " -> "))]"
            case .lexerError(let e):
                return "Lexing error - \(e.localizedDescription)"
        }
    }
    
    /// Create a `LeafError` - only `reason` typically used as source locations are auto-grabbed
    public init(
        _ reason: Reason,
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        self.file = file
        self.function = function
        self.line = line
        self.column = column
        self.reason = reason
    }
}

// MARK: - `LexerError` Summary (Wrapped by LeafError)

/// `LexerError` reports errors during the stage.
public struct LexerError: Error {
    // MARK: - Public
    
    public enum Reason: Sendable {
        // MARK: Errors occuring during Lexing
        /// A character not usable in parameters is present when Lexer is not expecting it
        case invalidParameterToken(Character)
        /// A string was opened but never terminated by end of file
        case unterminatedStringLiteral
        /// Use in place of fatalError to indicate extreme issue
        case unknownError(String)
    }
    
    /// Template source file line where error occured
    public let line: Int
    /// Template source column where error occured
    public let column: Int
    /// Name of template error occured in
    public let name: String
    /// Stated reason for error
    public let reason: Reason
    
    // MARK: - Internal Only
    
    /// State of tokens already processed by Lexer prior to error
    internal let lexed: [LeafToken]
    /// Flag to true if lexing error is something that may be recoverable during parsing;
    /// EG, `"#anhtmlanchor"` may lex as a tag name but fail to tokenize to tag because it isn't
    /// followed by a left paren. Parser may be able to recover by decaying it to `.raw`.
    internal let recoverable: Bool
    
    /// Create a `LexerError`
    /// - Parameters:
    ///   - reason: The specific reason for the error
    ///   - src: File being lexed
    ///   - lexed: `LeafTokens` already lexed prior to error
    ///   - recoverable: Flag to say whether the error can potentially be recovered during Parse
    internal init(
        _ reason: Reason,
        src: LeafRawTemplate,
        lexed: [LeafToken] = [],
        recoverable: Bool = false
    ) {
        self.line = src.line
        self.column = src.column
        self.reason = reason
        self.lexed = lexed
        self.name = src.name
        self.recoverable = recoverable
    }
    
    /// Convenience description of source file name, error reason, and location in file of error source
    var localizedDescription: String {
        return "\"\(name)\": \(reason) - \(line):\(column)"
    }
}
