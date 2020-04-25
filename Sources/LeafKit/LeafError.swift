/// `Error` types and helper types for reporting and analyzing errors during template processing/rendering/

public struct LeafError: Error {
    public enum Reason {
        /// Errors related to LeafCache access
        /// Attempts to modify cache entries when caching is globally disabled
        case cachingDisabled
        /// Attemps to insert a cache entry when one exists and replacing is not set to true
        case keyExists(String)
        /// Attempts to modify cache for a non-existant key
        /// *NOTE* NOT used when accessing as Optional returns are adequately clear
        case noValueForKey(String)
        
        /// Errors related to rendering a template
        /// Attempts to render a non-flat AST - provide template name & array of unresolved references
        case unresolvedAST(String, [String])
        /// Attempts to render a non-existant template - provide template name
        case noTemplateExists(String)
        /// Attempts to render an AST with cyclical external references - provide template name & ordered array of cycle
        case cyclicalReference(String, [String])
        
        /// Errors due to malformed template syntax or grammar
        case lexerError(LexerError)
        /// Errors from protocol adherents that do not support newer features
        case unsupportedFeature(String)
        /// Errors only when no existing error reason is adequately clear
        case unknownError(String)
    }
    
    public let file: String
    public let function: String
    public let line: UInt
    public let column: UInt
    public let reason: Reason

    var localizedDescription: String {
        var verbose = ""
        let file = self.file.split(separator: "/").last
        
        switch self.reason {
            case .lexerError: verbose += "Lexing error - "
        default: verbose += "\(file ?? "?").\(function):\(line) - "
        }
        
        switch self.reason {
            case .unknownError(let message): verbose += message
            case .unsupportedFeature(let feature): verbose +=  "\(feature) is not implemented"
            case .cachingDisabled: verbose +=  "Caching is globally disabled"
            case .keyExists(let key): verbose +=  "Existing entry \(key); use insert with replace=true to overrride"
            case .noValueForKey(let key): verbose +=  "No cache entry exists for \(key)"
            case .unresolvedAST(let key, let dependencies):
                verbose +=  "Flat AST expected; \(key) has unresolved dependencies: \(dependencies)"
            case .noTemplateExists(let key): verbose +=  "No template found for \(key)"
            case .cyclicalReference(let key, let chain):
                verbose +=  "\(key) cyclically referenced in [\(chain.joined(separator: " -> "))]"
            case .lexerError(let e): verbose +=  e.localizedDescription
        }
        
        return verbose
    }

    internal init(
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


public struct LexerError: Error {
    public enum Reason {
        case invalidTagToken(Character)
        case invalidParameterToken(Character)
        case unterminatedStringLiteral
    }
    
    public let line: Int
    public let column: Int
    public let name: String
    public let reason: Reason
    public let lexed: [LeafToken]
    
    internal init(src: TemplateSource, lexed: [LeafToken], reason: Reason) {
        self.line = src.line
        self.column = src.column
        self.reason = reason
        self.lexed = lexed
        self.name = src.name
    }
    
    var localizedDescription: String {
        return "\"\(name)\"; \(reason) - \(line):\(column)"
    }
}
