import XCTest
import NIOConcurrencyHelpers
import NIO
@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests

// MARK: - Helper Functions

/// Directly run a String "template" through `LeafLexer`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed array of ``LeafScanner.Token``
internal func lex(_ str: String) throws -> [LeafScanner.Token] {
    let scanner = LeafScanner(name: "alt-pase", source: str)
    return try scanner.scanAll().tokensOnly()
}

/// Directly run a String "template" through `LeafLexer` and `LeafParser`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed and parsed array of Statement
internal func parse(_ str: String) throws -> [Statement] {
    let scanner = LeafScanner(name: "alt-pase", source: str)
    let parser = LeafParser(from: scanner)
    let syntax = try parser.parse()

    return syntax
}

/// Directly run a String "template" through full render chain
/// - Parameter template: Raw String holding Leaf template source data
/// - Parameter context: LeafData context
/// - Returns: A fully rendered view
internal func render(name: String = "test-render", _ template: String, _ context: [String: LeafData] = [:]) throws -> String {
    let lexer = LeafScanner(name: name, source: template)
    let parser = LeafParser(from: lexer)
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
internal class TestRenderer {
    var r: LeafRenderer

    init(configuration: LeafConfiguration = .init(rootDirectory: "/"),
            tags: [String : LeafTag] = defaultTags,
            cache: LeafCache = DefaultLeafCache(),
            sources: LeafSources = .singleSource(TestFiles()),
            eventLoop: EventLoop = EmbeddedEventLoop(),
            userInfo: [AnyHashable : Any] = [:]) {
        self.r = .init(configuration: configuration,
                              tags: tags,
                              cache: cache,
                              sources: sources,
                              eventLoop: eventLoop,
                              userInfo: userInfo)
    }
    
    func render(source: String? = nil, path: String, context: [String: LeafData] = [:]) -> EventLoopFuture<ByteBuffer> {
        if let source = source {
            return self.r.render(source: source, path: path, context: context)
        } else {
            return self.r.render(path: path, context: context)
        }
    }
}

/// Helper `LeafFiles` struct providing an in-memory thread-safe map of "file names" to "file data"
internal struct TestFiles: LeafSource {
    var files: [String: String]
    var lock: Lock
    
    init() {
        files = [:]
        lock = .init()
    }
    
    public func file(template: String, escape: Bool = false, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        var path = template
        if path.split(separator: "/").last?.split(separator: ".").count ?? 1 < 2,
           !path.hasSuffix(".leaf") { path += ".leaf" }
        if !path.hasPrefix("/") { path = "/" + path }
        
        self.lock.lock()
        defer { self.lock.unlock() }
        if let file = self.files[path] {
            var buffer = ByteBufferAllocator().buffer(capacity: file.count)
            buffer.writeString(file)
            return eventLoop.makeSucceededFuture(buffer)
        } else {
            return eventLoop.makeFailedFuture(LeafError(.noTemplateExists(template)))
        }
    }
}

// MARK: - Helper Extensions

internal extension ByteBuffer {
    var string: String {
        String(decoding: self.readableBytesView, as: UTF8.self)
    }
}

// MARK: - Helper Variables

/// Automatic path discovery for the Templates folder in this package
internal var templateFolder: String {
    return projectTestFolder + "Templates/"
}

internal var projectTestFolder: String {
    let folder = #file.split(separator: "/").dropLast().joined(separator: "/")
    return "/" + folder + "/"
}

// MARK: - Internal Tests

/// Test printing descriptions of Syntax objects
final class PrintTests: XCTestCase {    
    func testSexpr() throws {
        let template = "hello, raw text"
        let expectation = "(raw)"

        assertSExprEqual(try parse(template).sexpr(), expectation)
    }

    func testVariable() throws {
        let template = "#(foo)"
        let expectation = "(substitution (variable))"
        
        assertSExprEqual(try parse(template).sexpr(), expectation)
    }

    func testLoop() throws {
        let template = """
        #for(name in names):
            hello, #(name).
        #endfor
        """
        let expectation = """
        (for (variable)
            (raw) (substitution (variable)) (raw))
        """
        
        assertSExprEqual(try parse(template).sexpr(), expectation)
    }

    func testConditional() throws {
        let template = """
        #if(foo):
            some stuff
        #elseif(bar == "bar"):
            bar stuff
        #else:
            no stuff
        #endif
        """
        let expectation = """
        (conditional (variable)
                onTrue: (raw)
                onFalse: (conditional
                    (== (variable) (string))
                        onTrue: (raw)
                        onFalse:(raw)))
        """
        
        assertSExprEqual(try parse(template).sexpr(), expectation)
    }

    func testImport() throws {
        let template = "#import(\"someimport\")"
        let expectation = "(import)"
        
        assertSExprEqual(try parse(template).sexpr(), expectation)
    }

    func testExtendAndExport() throws {
        let template = """
        #extend("base"):
            #export("title"): Welcome #endexport
            #export("body"):
                hello there
            #endexport
        #endextend
        """
        let expectation = """
        (extend
            (export (raw))
            (export (raw)))
        """
        
        assertSExprEqual(try parse(template).sexpr(), expectation)
    }
}
