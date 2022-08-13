// MARK: `LeafError` Summary

/// `LeafError` reports errors during the template rendering process, wrapping more specific
/// errors if necessary during Lexing and Parsing stages.
///
public struct LeafError: Error {
    /// Possible cases of a LeafError.Reason, with applicable stored values where useful for the type
    public enum Reason: Equatable {
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
        case lexerError(LeafScannerError)
        
        // MARK: Errors lacking specificity
        /// Errors from protocol adherents that do not support newer features
        case unsupportedFeature(String)
        /// Errors only when no existing error reason is adequately clear
        case unknownError(String)

        /// Errors when something goes wrong internally
        case internalError(what: String)

        /// Errors when an import is not found
        case importNotFound(name: String)

        /// Errors when a tag is not found
        case tagNotFound(name: String)

        /// Errors when one type was expected, but another was obtained
        case typeError(shouldHaveBeen: LeafData.NaturalType, got: LeafData.NaturalType)

        /// A typeError specialised for Double | Int
        case expectedNumeric(got: LeafData.NaturalType)

        /// A typeError specialised for binary operators of (T, T) -> T
        case badOperation(on: LeafData.NaturalType, what: String)

        /// Errors when a tag receives a bad parameter count
        case badParameterCount(tag: String, expected: Int, got: Int)

        /// Errors when a tag receives a body, but doesn't want one
        case extraneousBody(tag: String)

        /// Errors when a tag doesn't receive a body, but wants one
        case missingBody(tag: String)

        /// Serialization error
        case serializationError
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
            case .importNotFound(let name):
                return "Import \(name) was not found"
            case .internalError(let what):
                return "Something in Leaf broke: \(what)\nPlease report this to https://github.com/vapor/leaf-kit"
            case .tagNotFound(let name):
                return "Tag \(name) was not found"
            case .typeError(let shouldHaveBeen, let got):
                return "Type error: I was expecting \(shouldHaveBeen), but I got \(got) instead"
            case .badOperation(let on, let what):
                return "Type error: \(on) cannot do \(what)"
            case .expectedNumeric(let got):
                return "Type error: I was expecting a numeric type, but I got \(got) instead"
            case .badParameterCount(let tag, let expected, let got):
                return "Type error: \(tag) was expecting \(expected) parameters, but got \(got) parameters instead"
            case .extraneousBody(let tag):
                return "Type error: \(tag) wasn't expecting a body, but got one"
            case .missingBody(let tag):
                return "Type error: \(tag) was expecting a body, but didn't get one"
            case .serializationError:
                return "Serialization error"
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
