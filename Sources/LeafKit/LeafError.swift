#if !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// ``LeafError`` reports errors during the template rendering process, wrapping more specific
/// errors if necessary during Lexing and Parsing stages.
public struct LeafError: Error, Sendable, Equatable {
    public struct ErrorType: Sendable, Hashable, CustomStringConvertible, Equatable {
        enum Base: String, Sendable, Equatable {
            // Loading raw templates
            case illegalAccess

            // LeafCache access
            case cachingDisabled
            case keyExists
            case noValueForKey

            // Rendering template
            case unresolvedAST
            case noTemplateExists
            case cyclicalReference

            // General errors
            case unsupportedFeature
            case unknownError
        }

        let base: Base

        private init(_ base: Base) {
            self.base = base
        }

        // Loading raw templates
        public static let illegalAccess = Self(.illegalAccess)

        // LeafCache access
        public static let cachingDisabled = Self(.cachingDisabled)
        public static let keyExists = Self(.keyExists)
        public static let noValueForKey = Self(.noValueForKey)

        // Rendering template
        public static let unresolvedAST = Self(.unresolvedAST)
        public static let noTemplateExists = Self(.noTemplateExists)
        public static let cyclicalReference = Self(.cyclicalReference)

        // General errors
        public static let unsupportedFeature = Self(.unsupportedFeature)
        public static let unknownError = Self(.unknownError)

        public var description: String {
            base.rawValue
        }
    }

    private struct Backing: Sendable, Equatable {
        fileprivate let errorType: ErrorType
        fileprivate let message: String?
        fileprivate let templateName: String?
        fileprivate let dependencies: [String]?
        fileprivate let file: String
        fileprivate let function: String
        fileprivate let line: UInt
        fileprivate let column: UInt

        init(
            errorType: ErrorType,
            message: String? = nil,
            templateName: String? = nil,
            dependencies: [String]? = nil,
            file: String = #fileID,
            function: String = #function,
            line: UInt = #line,
            column: UInt = #column
        ) {
            self.errorType = errorType
            self.message = message
            self.templateName = templateName
            self.dependencies = dependencies
            self.file = file
            self.function = function
            self.line = line
            self.column = column
        }

        static func == (lhs: LeafError.Backing, rhs: LeafError.Backing) -> Bool {
            lhs.errorType == rhs.errorType && lhs.message == rhs.message && lhs.templateName == rhs.templateName
                && lhs.dependencies == rhs.dependencies
        }
    }

    private var backing: Backing

    public var errorType: ErrorType { backing.errorType }
    public var message: String? { backing.message }
    public var templateName: String? { backing.templateName }
    public var dependencies: [String]? { backing.dependencies }
    public var file: String { backing.file }
    public var function: String { backing.function }
    public var line: UInt { backing.line }
    public var column: UInt { backing.column }

    private init(backing: Backing) {
        self.backing = backing
    }

    public static func illegalAccess(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .illegalAccess, message: message, file: file, function: function, line: line, column: column))
    }

    public static func cachingDisabled(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .cachingDisabled, file: file, function: function, line: line, column: column))
    }

    public static func keyExists(
        _ key: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .keyExists, templateName: key, file: file, function: function, line: line, column: column))
    }

    public static func noValueForKey(
        _ key: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .noValueForKey, templateName: key, file: file, function: function, line: line, column: column))
    }

    public static func unresolvedAST(
        _ key: String,
        dependencies: [String],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(
            backing: .init(
                errorType: .unresolvedAST, templateName: key, dependencies: dependencies, file: file, function: function, line: line,
                column: column))
    }

    public static func noTemplateExists(
        at key: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .noTemplateExists, templateName: key, file: file, function: function, line: line, column: column))
    }

    public static func cyclicalReference(
        _ key: String,
        chain: [String],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(
            backing: .init(
                errorType: .cyclicalReference, templateName: key, dependencies: chain, file: file, function: function, line: line,
                column: column))
    }

    public static func unsupportedFeature(
        _ feature: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .unsupportedFeature, message: feature, file: file, function: function, line: line, column: column))
    }

    public static func unknownError(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        .init(backing: .init(errorType: .unknownError, message: message, file: file, function: function, line: line, column: column))
    }

    public static func == (lhs: LeafError, rhs: LeafError) -> Bool {
        lhs.backing == rhs.backing
    }
}

extension LeafError: CustomStringConvertible {
    public var description: String {
        let file = self.file.split(separator: "/").last
        let src = "\(file ?? "?").\(function):\(line)"

        var result = "LeafError(errorType: \(self.errorType)"

        if let message = self.message {
            result.append(", message: \(String(reflecting: message))")
        }

        if let templateName = self.templateName {
            result.append(", templateName: \(String(reflecting: templateName))")
        }

        if let dependencies = self.dependencies {
            result.append(", dependencies: \(String(reflecting: dependencies))")
        }

        result.append(", source: \(src))")

        return result
    }

    public var localizedDescription: String {
        let file = self.file.split(separator: "/").last
        let src = "\(file ?? "?").\(function):\(line)"

        return switch self.errorType.base {
        case .illegalAccess:
            "\(src) - \(message ?? "Illegal access attempt")"
        case .unknownError:
            "\(src) - \(message ?? "Unknown error occurred")"
        case .unsupportedFeature:
            "\(src) - \(message ?? "Feature") is not implemented"
        case .cachingDisabled:
            "\(src) - Caching is globally disabled"
        case .keyExists:
            "\(src) - Existing entry \(templateName ?? "unknown"); use insert with replace=true to overrride"
        case .noValueForKey:
            "\(src) - No cache entry exists for \(templateName ?? "unknown")"
        case .unresolvedAST:
            "\(src) - Flat AST expected; \(templateName ?? "unknown") has unresolved dependencies: \(dependencies ?? [])"
        case .noTemplateExists:
            "\(src) - No template found for \(templateName ?? "unknown")"
        case .cyclicalReference:
            "\(src) - \(templateName ?? "unknown") cyclically referenced in [\((dependencies ?? []).joined(separator: " -> "))]"
        }
    }
}
