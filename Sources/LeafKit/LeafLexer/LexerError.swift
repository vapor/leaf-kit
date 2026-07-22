#if !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// ``LexerError`` reports errors during the lexing stage.
public struct LexerError: Error, Sendable, Equatable {
    public struct ErrorType: Sendable, Hashable, CustomStringConvertible, Equatable {
        enum Base: String, Sendable, Equatable {
            /// A character not usable in parameters is present when Lexer is not expecting it
            case invalidParameterToken
            /// A string was opened but never terminated by end of file
            case unterminatedStringLiteral
            /// Use of an unsupported operator
            case unsupportedOperator
            /// Use in place of fatalError to indicate extreme issue
            case unknownError
        }

        let base: Base

        private init(_ base: Base) {
            self.base = base
        }

        public static let invalidParameterToken = Self(.invalidParameterToken)
        public static let unterminatedStringLiteral = Self(.unterminatedStringLiteral)
        public static let unknownError = Self(.unknownError)
        public static let unsupportedOperator = Self(.unsupportedOperator)

        public var description: String {
            base.rawValue
        }
    }

    private struct Backing: Sendable, Equatable {
        fileprivate let errorType: ErrorType
        fileprivate let line: Int
        fileprivate let column: Int
        fileprivate let name: String
        fileprivate let lexed: [LeafToken]
        fileprivate let recoverable: Bool
        fileprivate let invalidChar: Character?
        fileprivate let errorMessage: String?
        fileprivate let unsupportedOperator: LeafOperator?

        init(
            errorType: ErrorType,
            line: Int,
            column: Int,
            name: String,
            lexed: [LeafToken] = [],
            recoverable: Bool = false,
            invalidChar: Character? = nil,
            errorMessage: String? = nil,
            unsupportedOperator: LeafOperator? = nil
        ) {
            self.errorType = errorType
            self.line = line
            self.column = column
            self.name = name
            self.lexed = lexed
            self.recoverable = recoverable
            self.invalidChar = invalidChar
            self.errorMessage = errorMessage
            self.unsupportedOperator = unsupportedOperator
        }

        static func == (lhs: LexerError.Backing, rhs: LexerError.Backing) -> Bool {
            lhs.errorType == rhs.errorType && lhs.line == rhs.line && lhs.column == rhs.column && lhs.name == rhs.name
        }
    }

    private var backing: Backing

    public var errorType: ErrorType { backing.errorType }
    public var line: Int { backing.line }
    public var column: Int { backing.column }
    public var name: String { backing.name }
    public var recoverable: Bool { backing.recoverable }
    public var invalidChar: Character? { backing.invalidChar }
    public var errorMessage: String? { backing.errorMessage }
    public var unsupportedOperator: LeafOperator? { backing.unsupportedOperator }

    var lexed: [LeafToken] { backing.lexed }

    private init(backing: Backing) {
        self.backing = backing
    }

    /// Create a `LexerError` for invalid parameter token
    /// - Parameters:
    ///   - character: The invalid character
    ///   - src: File being lexed
    ///   - lexed: `LeafTokens` already lexed prior to error
    ///   - recoverable: Flag to say whether the error can potentially be recovered during Parse
    static func invalidParameterToken(
        _ character: Character,
        src: LeafRawTemplate,
        lexed: [LeafToken] = [],
        recoverable: Bool = false
    ) -> Self {
        .init(
            backing: .init(
                errorType: .invalidParameterToken,
                line: src.line,
                column: src.column,
                name: src.name,
                lexed: lexed,
                recoverable: recoverable,
                invalidChar: character
            ))
    }

    /// Create a `LexerError` for unterminated string literal
    /// - Parameters:
    ///   - src: File being lexed
    ///   - lexed: `LeafTokens` already lexed prior to error
    ///   - recoverable: Flag to say whether the error can potentially be recovered during Parse
    static func unterminatedStringLiteral(
        src: LeafRawTemplate,
        lexed: [LeafToken] = [],
        recoverable: Bool = false
    ) -> Self {
        .init(
            backing: .init(
                errorType: .unterminatedStringLiteral,
                line: src.line,
                column: src.column,
                name: src.name,
                lexed: lexed,
                recoverable: recoverable
            ))
    }

    /// Create a `LexerError` for unknown errors
    /// - Parameters:
    ///   - message: Description of the error
    ///   - src: File being lexed
    ///   - lexed: `LeafTokens` already lexed prior to error
    ///   - recoverable: Flag to say whether the error can potentially be recovered during Parse
    static func unknownError(
        _ message: String,
        src: LeafRawTemplate,
        lexed: [LeafToken] = [],
        recoverable: Bool = false
    ) -> Self {
        .init(
            backing: .init(
                errorType: .unknownError,
                line: src.line,
                column: src.column,
                name: src.name,
                lexed: lexed,
                recoverable: recoverable,
                errorMessage: message
            ))
    }

    static func unsupportedOperator(
        _ operator: LeafOperator,
        src: LeafRawTemplate,
        lexed: [LeafToken] = [],
        recoverable: Bool = false
    ) -> Self {
        .init(
            backing: .init(
                errorType: .unsupportedOperator,
                line: src.line,
                column: src.column,
                name: src.name,
                lexed: lexed,
                recoverable: recoverable,
                errorMessage: "\(`operator`) is not yet supported as an operator"
            ))
    }

    public static func == (lhs: LexerError, rhs: LexerError) -> Bool {
        lhs.backing == rhs.backing
    }
}

extension LexerError: CustomStringConvertible {
    public var description: String {
        var result = #"LexerError(errorType: \#(self.errorType)"#

        result.append(", name: \(String(reflecting: name))")
        result.append(", location: \(line):\(column)")

        if let invalidChar {
            result.append(", invalidChar: \(String(reflecting: invalidChar))")
        }

        if let errorMessage {
            result.append(", message: \(String(reflecting: errorMessage))")
        }

        if recoverable {
            result.append(", recoverable: true")
        }

        if let unsupportedOperator {
            result.append(", unsupportedOperator: \(unsupportedOperator)")
        }

        result.append(")")

        return result
    }

    /// Convenience description of source file name, error reason, and location in file of error source
    public var localizedDescription: String {
        "\"\(self.name)\": \(self.errorType) - \(self.line):\(self.column)"
    }
}
