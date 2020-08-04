import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests

/// Inherit from `LeafTestClass` rather than XCTestCase to avoid "Already running" assertions from other tests
internal class LeafTestClass: XCTestCase {
    override func setUp() {
        LeafConfiguration.__reset()
        LeafConfiguration.entities = .leaf4Core
    }
}


// MARK: - Helper Functions

/// Directly run a String "template" through `LeafLexer`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed array of LeafTokens
internal func lex(_ str: String) throws -> [LeafToken] {
    var lexer = LeafLexer(name: "lex-test", template: str)
    return try lexer.lex()
}

/// Directly run a String "template" through `LeafLexer` and `LeafParser`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed and parsed array of Syntax
internal func parse(_ str: String) throws -> Leaf4AST {
    var lexer = LeafLexer(name: "alt-parse", template: str)
    let tokens = try! lexer.lex()
    var parser = Leaf4Parser(name: "alt-parse", tokens: tokens)
    let syntax = try! parser.parse()

    return syntax
}

/// Directly run a String "template" through full render chain
/// - Parameter template: Raw String holding Leaf template source data
/// - Parameter context: LeafData context
/// - Returns: A fully rendered view
internal func render(name: String = "test-render", _ template: String, _ context: [String: LeafData] = [:]) throws -> String {
    var lexer = LeafLexer(name: name, template: template)
    let tokens = try lexer.lex()
    var parser = Leaf4Parser(name: name, tokens: tokens)
    let ast = try parser.parse()
    let buffer = ByteBufferAllocator().buffer(capacity: Int(ast.underestimatedSize))
    var block = ByteBuffer.instantiate(data: buffer, encoding: LeafConfiguration.encoding)
    var serializer = Leaf4Serializer(ast: ast, context: context)
    switch serializer.serialize(buffer: &block) {
        case .success(_)     : return block.contents
        case .failure(let e) : throw e
    }
}

// MARK: - Helper Structs and Classes

/// Helper wrapping` LeafRenderer` to preconfigure for simplicity & allow eliding context
internal class TestRenderer {
    var r: LeafRenderer
    private let lock: Lock
    private var counter: Int = 0
    private static var configured = false
    
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
        lock = .init()
    }
    
    func render(source: String? = nil, path: String, context: [String: LeafData] = [:]) -> EventLoopFuture<ByteBuffer> {
        lock.withLock { counter += 1 }
        if let source = source {
            return self.r.render(source: source, path: path, context: context)
        } else {
            return self.r.render(path: path, context: context)
        }
    }
    
    public var isDone: Bool { lock.withLock { counter == 0 } ? true : false }
    
    func finishTask() { lock.withLock { counter -= 1 } }
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
    var string: String { String(decoding: readableBytesView, as: UTF8.self) }
}

internal extension Array where Element == LeafToken {
    var string: String { filter { $0 != .raw("\n") }.map { $0.description + "\n" } .reduce("", +) }
}

internal extension Array where Element == Syntax {
    var string: String { map { $0.description } .joined(separator: "\n") }
}

// MARK: - Helper Variables

/// Automatic path discovery for the Templates folder in this package
internal var templateFolder: String {
    return projectTestFolder + "Templates/"
}

internal var projectTestFolder: String {
    "/\(#file.split(separator: "/").dropLast().joined(separator: "/"))/"
}

// MARK: - Internal Tests

/// Test printing descriptions of Syntax objects
final class PrintTests: XCTestCase {    
    func testRaw() throws {
        let template = "hello, raw text"
        let expectation = "0: raw(ByteBuffer: 15B))"
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }

    func testPassthrough() throws {
        let template = "#(foo)"
        let expectation = "0: $:foo"
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }

    func testLoop() throws {
        let template = """
        #for(name in names):
            hello, #(name).
        #endfor
        """
        let expectation = """
        0: for($:names):
        1: scope(table: 1)
           0: raw(ByteBuffer: 12B))
           1: $:name
           2: raw(ByteBuffer: 2B))
        """
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
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
        0: if($:foo):
        1: raw(ByteBuffer: 16B))
        2: elseif([$:bar == string(bar)]):
        3: raw(ByteBuffer: 15B))
        4: else():
        5: raw(ByteBuffer: 14B))
        """
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }

    func testImport() throws {
        let template = "#import(someimport)"
        let expectation = """
        0: import($:someimport):
        1: scope(undefined)
        """
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }

    func testExtendAndExport() throws {
        let template = """
        #export(title, "Welcome")
        #export(body):
            hello there
        #endexport
        #extend("base")
        """
        let expectation = """
        0: export($:title, string(Welcome)):
        1: string(Welcome)
        3: export($:body):
        4: raw(ByteBuffer: 17B))
        6: extend(string(base)):
        7: scope(undefined)
        """
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }
    
    // No longer relevant
    func _testCustomTag() throws {
        let template = """
        #custom(tag, foo == bar):
            some body
        #endcustom
        """
        let expectation = """
        custom(variable(tag), [foo == bar]):
          raw("\\n    some body\\n")
        """
        
        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }
}
