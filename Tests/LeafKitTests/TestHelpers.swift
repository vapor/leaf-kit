import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import XCTest

@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests

// MARK: - Helper Functions

/// Directly run a String "template" through `LeafLexer`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed array of LeafTokens
func lex(_ str: String) throws -> [LeafToken] {
    var lexer = LeafLexer(name: "lex-test", template: str)
    return try lexer.lex().dropWhitespace()
}

/// Directly run a String "template" through `LeafLexer` and `LeafParser`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed and parsed array of Syntax
func parse(_ str: String) throws -> [Syntax] {
    var lexer = LeafLexer(name: "alt-parse", template: str)
    let tokens = try lexer.lex()
    var parser = LeafParser(name: "alt-parse", tokens: tokens)
    let syntax = try parser.parse()

    return syntax
}

/// Directly run a String "template" through full render chain
/// - Parameter template: Raw String holding Leaf template source data
/// - Parameter context: LeafData context
/// - Returns: A fully rendered view
func render(name: String = "test-render", _ template: String, _ context: [String: LeafData] = [:]) throws -> String {
    var lexer = LeafLexer(name: name, template: template)
    let tokens = try lexer.lex()
    var parser = LeafParser(name: name, tokens: tokens)
    let ast = try parser.parse()
    var serializer = LeafSerializer(
        ast: ast,
        ignoreUnfoundImports: false
    )
    let view = try serializer.serialize(context: context)
    return view.getString(at: view.readerIndex, length: view.readableBytes) ?? ""
}

// MARK: - Helper Structs and Classes

/// Helper wrapping` LeafRenderer` to preconfigure for simplicity & allow eliding context
actor TestRenderer: Sendable {
    let r: LeafRenderer

    init(
        configuration: LeafConfiguration = .init(rootDirectory: "/"),
        tags: [String: any LeafTag] = defaultTags,
        cache: any LeafCache = DefaultLeafCache(),
        sources: LeafSources = LeafSources(singleSource: TestFiles()),
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.r = .init(
            configuration: configuration,
            tags: tags,
            cache: cache,
            sources: sources,
            userInfo: userInfo
        )
    }

    @discardableResult
    func render(path: String, context: [String: LeafData] = [:]) async throws -> ByteBuffer {
        try await self.r.render(path: path, context: context)
    }
}

/// Helper `LeafFiles` struct providing an in-memory thread-safe map of "file names" to "file data"
struct TestFiles: LeafSource {
    var files: [String: String] = [:]

    func file(template: String, escape: Bool = false) async throws -> ByteBuffer {
        var path = template
        if path.split(separator: "/").last?.split(separator: ".").count ?? 1 < 2, !path.hasSuffix(".leaf") {
            path += ".leaf"
        }
        if !path.starts(with: "/") {
            path = "/" + path
        }

        if let file = self.files[path] {
            return .init(string: file)
        } else {
            throw LeafError.noTemplateExists(at: template)
        }
    }
}

// MARK: - Helper Extensions

extension ByteBuffer {
    var string: String {
        String(decoding: self.readableBytesView, as: UTF8.self)
    }
}

extension Array where Element == LeafToken {
    func dropWhitespace() -> [LeafToken] {
        self.filter { token in
            guard case .whitespace = token else { return true }
            return false
        }
    }

    var string: String {
        self.map { $0.description + "\n" }.reduce("", +)
    }
}

extension Array where Element == Syntax {
    var string: String {
        self.map { $0.description }.joined(separator: "\n")
    }
}

// MARK: - Helper Variables

/// Automatic path discovery for the Templates folder in this package
var templateFolder: String {
    URL(fileURLWithPath: projectTestFolder, isDirectory: true)
        .appendingPathComponent("Templates", isDirectory: true)
        .path
}

var projectTestFolder: String {
    URL(fileURLWithPath: #filePath, isDirectory: false)  // .../leaf-kit/Tests/LeafKitTests/TestHelpers.swift
        .deletingLastPathComponent()  // .../leaf-kit/Tests/LeafKitTests
        .path
}
