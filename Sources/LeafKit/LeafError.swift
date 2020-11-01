// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

// MARK: `LeafError` Summary

public typealias LeafErrorCause = LeafError.Reason
public typealias LexErrorCause = LexError.Reason
public typealias ParseErrorCause = ParseError.Reason

/// `LeafError` reports errors during the template rendering process, wrapping more specific
/// errors if necessary during Lexing and Parsing stages.
///
/// #TODO
/// - Implement a ParserError subtype
public struct LeafError: LocalizedError, CustomStringConvertible {
    /// Possible cases of a LeafError.Reason, with applicable stored values where useful for the type
    public enum Reason {
        // MARK: Errors related to loading raw templates
        case noSources
        case noSourceForKey(String, invalid: Bool = false)
        /// Attempted to access a template blocked for security reasons
        case illegalAccess(String, NIOLeafFiles.Limit = .toVisibleFiles)
                
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
        /// Attempt to render a non-flat AST
        /// - Provide raw file name needed
        case missingRaw(String)
        /// Attempt to render a non-existant template
        /// Provide template name
        case noTemplateExists(String)
        /// Attempt to render an AST with cyclical external references
        /// - Provide template name & ordered array of template names that causes the cycle path
        case cyclicalReference(String, [String])
        
        case defineMismatch(a: String, b: String, define: String)

        // MARK: Wrapped Errors related to Lexing or Parsing
        /// Errors due to malformed template syntax or grammar
        case lexError(LexError)
        /// Errors due to malformed template syntax or grammar
        case parseError(ParseError)
        /// Warnings from parsing, if escalated to an error
        case parseWarnings([ParseError])
        /// Errors from serializing to a LKRawBlock
        case serializeError(LeafFunction.Type, Error, SourceLocation)
        
        case invalidIdentifier(String)

        /// Error due to timeout (may or may not be permanent)
        case timeout(Double)
        
        // MARK: Errors lacking specificity
        /// General errors occuring prior to running LeafKit
        case configurationError(String)
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
    public var localizedDescription: String {
        var m = "\(file.split(separator: "/").last ?? "?").\(function):\(line)\n"
        switch reason {
            case .illegalAccess(let f, let l) : m += l.contains(.toVisibleFiles) ? "Attempted to access hidden file "
                                                                                 : "Attempted to escape sandbox "
                                                m += "`\(f)`"
            case .noSources                   : m += "No searchable sources exist"
            case .noSourceForKey(let s,let b) : m += b ? "`\(s)` is invalid source key" : "No source `\(s)` exists"
            case .unknownError(let r)         : m += r
            case .unsupportedFeature(let f)   : m += "`\(f)` not implemented"
            case .cachingDisabled             : m += "Caching is globally disabled"
            case .keyExists(let k)            : m += "Existing entry `\(k)`"
            case .noValueForKey(let k)        : m += "No cache entry exists for `\(k)`"
            case .noTemplateExists(let k)     : m += "No template found for `\(k)`"
            case .unresolvedAST(let k, let d) : m += "\(k) has unresolved dependencies: \(d)"
            case .defineMismatch(let a, let b, let d)
                                              : m += """
                Resolution failure:
                `\(a)` defines `\(d)()` as a block, but `\(b)` requires parameter semantics for `\(d)()` in usage.
                """
            case .timeout(let d)              : m += "Exceeded timeout at \(d.formatSeconds())"
            case .configurationError(let d)   : m += "Configuration error: `\(d)`"
            case .missingRaw(let f)           : m += "Missing raw inline file ``\(f)``"
            case .invalidIdentifier(let i)    : m += "`\(i)` is not a valid Leaf identifier"
            case .cyclicalReference(let k, let c)
                : m += "`\(k)` cyclically referenced in [\((c + ["!\(k)"]).joined(separator: " -> "))]"
                
            case .lexError(let e)             : m = "Lexing error\n\(e.description)"
            case .parseError(let e)           : m = "Parse \(e.description)"
            case .serializeError(let f, let e, let l) :
                m = """
                Serializing error
                Error from \(f) in template "\(l.name)" while appending data at \(l.line):\(l.column):
                \(e.localizedDescription)
                """
            case .parseWarnings(let w)        :
                guard !w.isEmpty else { break }
                m = """
                Template "\(w.first!.name)" Parse Warning\(w.count > 0 ? "s" : ""):
                \(w.map {"\($0.line):\($0.column) - \($0.reason.description)"}.joined(separator: "\n"))
                """
        }
        return m
    }

    public var errorDescription: String? { localizedDescription }
    public var description: String { localizedDescription }

    /// Create a `LeafError` - only `reason` typically used as source locations are auto-grabbed
    public init(_ reason: Reason,
                _ file: String = #file,
                _ function: String = #function,
                _ line: UInt = #line,
                _ column: UInt = #column) {
        self.file = file
        self.function = function
        self.line = line
        self.column = column
        self.reason = reason
    }
}

// MARK: - `LexerError` Summary (Wrapped by LeafError)

/// `LexerError` reports errors during the stage.
public struct LexError: Error, CustomStringConvertible {
    // MARK: - Public

    public enum Reason: CustomStringConvertible {
        // MARK: Errors occuring during Lexing
        /// A character not usable in parameters is present when Lexer is not expecting it
        case invalidParameterToken(Character)
        /// An invalid operator was used
        case invalidOperator(LeafOperator)
        /// A string was opened but never terminated by end of line
        case unterminatedStringLiteral
        /// Use in place of fatalError to indicate extreme issue
        case unknownError(String)
        
        public var description: String {
            switch self {
                case .invalidOperator(let o): return "`\(o)` is not a valid operator"
                case .invalidParameterToken(let c): return "`\(c)` is not meaningful in context"
                case .unknownError(let e): return e
                case .unterminatedStringLiteral: return "Unterminated string literal"
            }
        }
    }

    /// Stated reason for error
    public let reason: Reason
    /// Name of template error occured in
    public var name: String { sourceLocation.name }
    /// Template source file line where error occured
    public var line: Int { sourceLocation.line }
    /// Template source column where error occured
    public var column: Int { sourceLocation.column }
    
    /// Template source location where error occured
    internal let sourceLocation: SourceLocation

    // MARK: - Internal Only

    /// State of tokens already processed by Lexer prior to error
    internal let lexed: [LKToken]

    /// Create a `LexerError`
    /// - Parameters:
    ///   - reason: The specific reason for the error
    ///   - src: File being lexed
    ///   - lexed: `LKTokens` already lexed prior to error
    ///   - recoverable: Flag to say whether the error can potentially be recovered during Parse
    internal init(_ reason: Reason,
                  _ src: LKRawTemplate,
                  _ lexed: [LKToken] = []) {
        self.reason = reason
        self.lexed = lexed
        self.sourceLocation = src.state
    }

    /// Convenience description of source file name, error reason, and location in file of error source
    var localizedDescription: String { "Error in template \"\(name)\" - \(line):\(column)\n\(reason.description)" }
    public var description: String { localizedDescription }
}

// MARK: - `ParserError` Summary (Wrapped by LeafError)
/// `ParserError` reports errors during the stage.
public struct ParseError: Error, CustomStringConvertible {
    public enum Reason: Error, CustomStringConvertible {
        case noEntity(type: String, name: String)
        case sameName(type: String, name: String, params: String, matches: [String])
        case mutatingMismatch(name: String)
        case cantClose(name: String, open: String?)
        case parameterError(name: String, reason: String)
        case unset(String)
        case declared(String)
        case unknownError(String)
        case missingKey
        case missingValue(isDict: Bool)
        case noPostfixOperand
        case unvaluedOperand
        case missingOperator
        case missingIdentifier
        case invalidIdentifier(String)
        case invalidDeclaration
        case malformedExpression
        case noSubscript
        case keyMismatch
        case constant(String, mutate: Bool = false)
        
        public var description: String {
            switch self {
                case .constant(let v, let m): return "Can't \(m ? "mutate" : "assign"); `\(v)` is constant"
                case .keyMismatch: return "Subscripting accessor is wrong type for object"
                case .noSubscript: return "Non-collection objects cannot be subscripted"
                case .malformedExpression: return "Couldn't close expression"
                case .invalidIdentifier(let s): return "`\(s)` is not a valid Leaf identifier"
                case .invalidDeclaration: return "Variable declaration may only occur at start of top level expression"
                case .missingIdentifier: return "Missing expected identifier in expression"
                case .missingOperator: return "Missing valid operator between operands"
                case .unvaluedOperand: return "Can't operate on non-valued operands"
                case .noPostfixOperand: return "Missing operand for postfix operator"
                case .missingKey: return "Collection literal missing key"
                case .missingValue(let dict): return "\(dict ? "Dictionary" : "Array") literal missing value"
                case .unknownError(let e): return e
                case .unset(let v): return "Variable `\(v)` used before initialization"
                case .declared(let v): return "Variable `\(v)` is already declared in this scope"
                case .cantClose(let n, let o):
                    return o.map { "`\(n)` can't close `\($0)`" }
                        ?? "No open block matching `\(n)` to close"
                case .mutatingMismatch(let name):
                    return "Mutating methods exist for \(name) but operand is immutable"
                case .parameterError(let name, let reason):
                    return "\(name)(...) couldn't be parsed: \(reason)"
                case .noEntity(let t, let name):
                    return "No \(t) named `\(name)` exists"
                case .sameName(let t, let name, let params, let matches):
                    return "No exact match for \(t) \(name + params); \(matches.count) possible matches: \(matches.map { "\(name)\($0)" }.joined(separator: "\n"))"
            }
        }
    }
    
    public let reason: Reason
    public let recoverable: Bool
    
    /// Name of template error occured in
    public var name: String { sourceLocation.name }
    /// Template source file line where error occured
    public var line: Int { sourceLocation.line }
    /// Template source column where error occured
    public var column: Int { sourceLocation.column }
    
    /// Template source location where error occured
    let sourceLocation: SourceLocation
    
    
    init(_ reason: Reason,
         _ location: SourceLocation,
         _ recoverable: Bool = false) {
        self.reason = reason
        self.sourceLocation = location
        self.recoverable = recoverable
    }
    
    static func error(_ reason: String, _ location: SourceLocation) -> Self {
        .init(.unknownError(reason), location, false) }
    static func error(_ reason: Reason, _ location: SourceLocation) -> Self {
        .init(reason, location, false) }
    static func warning(_ reason: Reason, _ location: SourceLocation) -> Self {
        .init(reason, location, true) }
    
    /// Convenience description of source file name, error reason, and location in file of error source
    var localizedDescription: String { "\(recoverable ? "Warning" : "Error") in template \"\(name)\"\n\(line):\(column) - \(reason.description)" }
    public var description: String { localizedDescription }
}

// MARK: - Internal Conveniences

extension Error {
    var leafError: LeafError? { self as? LeafError }
}

@inline(__always)
func err(_ cause: LeafErrorCause,
         _ file: String = #file,
         _ function: String = #function,
         _ line: UInt = #line,
         _ column: UInt = #column) -> LeafError { .init(cause, String(file.split(separator: "/").last ?? ""), function, line, column) }

@inline(__always)
func err(_ reason: String,
         _ file: String = #file,
         _ function: String = #function,
         _ line: UInt = #line,
         _ column: UInt = #column) -> LeafError { err(.unknownError(reason), file, function, line, column) }

@inline(__always)
func parseErr(_ cause: ParseErrorCause,
              _ location: SourceLocation,
              _ recoverable: Bool = false) -> LeafError {
    .init(.parseError(.init(cause, location, recoverable))) }

@inline(__always)
func succeed<T>(_ value: T, on eL: EventLoop) -> ELF<T> { eL.makeSucceededFuture(value) }

@inline(__always)
func fail<T>(_ error: LeafError, on eL: EventLoop) -> ELF<T> { eL.makeFailedFuture(error) }

@inline(__always)
func fail<T>(_ error: LeafErrorCause, on eL: EventLoop,
             _ file: String = #file, _ function: String = #function,
             _ line: UInt = #line, _ column: UInt = #column) -> ELF<T> {
    fail(LeafError(error, file, function, line, column), on: eL) }

func __MajorBug(_ message: String = "Unspecified",
                _ file: String = #file,
                _ function: String = #function,
                _ line: UInt = #line) -> Never {
    fatalError("""
    LeafKit Major Bug: "\(message)"
    Please File Issue Immediately at https://github.com/vapor/leaf-kit/issues
      - Reference "fatalError in `\(file.split(separator: "/").last ?? "").\(function) line \(line)`"
    """)
}

func __Unreachable(_ file: String = #file,
                   _ function: String = #function,
                   _ line: UInt = #line) -> Never {
    __MajorBug("Unreachable Switch Case", file, function, line) }
