import XCTest
import NIOConcurrencyHelpers
import Foundation
@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests

/// Inherit from `LeafTestClass` rather than XCTestCase to avoid "Already running" assertions from other tests
internal class LeafTestClass: XCTestCase {
    override func setUp() {
        LKConf.__reset()
        LKConf.entities = .leaf4Transitional
    }
}

// MARK: - Helper Functions

/// Directly run a String "template" through `LKLexer`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed array of LKTokens
internal func lex(_ str: String, name: String = "default") throws -> [LKToken] {
    var lexer = LKLexer(LKRawTemplate(name, str))
    return try lexer.lex()
}

/// Directly run a String "template" through `LKLexer` and `LeafParser`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed and parsed array of Syntax
internal func parse(_ str: String, name: String = "default") throws -> LeafAST {
    var lexer = LKLexer(LKRawTemplate(name, str))
    let tokens = try lexer.lex()
    var parser = LKParser(.searchKey(name), tokens)
    let syntax = try parser.parse()

    return syntax
}

/// Directly run a String "template" through full render chain
/// - Parameter template: Raw String holding Leaf template source data
/// - Parameter context: LeafData context
/// - Returns: A fully rendered view
internal func render(name: String = "test-render",
                     _ template: String,
                     _ context: LeafRenderer.Context = [:]) throws -> String {
    var lexer = LKLexer(LKRawTemplate(name, template))
    let tokens = try lexer.lex()
    var parser = LKParser(.searchKey(name), tokens)
    let ast = try parser.parse()
    var block = ByteBuffer.instantiate(size: ast.underestimatedSize, encoding: .utf8)
    let serializer = LKSerializer(ast, context, LeafBuffer.self)
    switch serializer.serialize(&block) {
        case .success        : return block.contents
        case .failure(let e) : throw e
    }
}

// MARK: - Helper Structs and Classes

/// Helper wrapping` LeafRenderer` to preconfigure for simplicity & allow eliding context
internal class TestRenderer {
    var r: LeafRenderer
    private let lock: Lock
    private var counter: Int
    private static var configured = false
    private var timer: Date = .distantPast

    init(cache: LeafCache = DefaultLeafCache(),
         sources: LeafSources = .singleSource(LeafTestFiles()),
         eventLoop: EventLoop = EmbeddedEventLoop(),
         tasks: Int = 1) {
        self.r = .init(cache: cache,
                       sources: sources,
                       eventLoop: eventLoop)
        lock = .init()
        counter = tasks
    }

    func render(source: String? = nil, path: String,
                context: LeafRenderer.Context = [:],
                options: LeafRenderer.Options? = nil) -> EventLoopFuture<ByteBuffer> {
        if timer == .distantPast { timer = Date() }
        return r.render(template: path, from: source != nil ? source! : "$", context: context, options: options)
    }

    var queued: Int { lock.withLock { counter } }
    var isDone: Bool { lock.withLock { counter <= 0 } ? true : false }
    func finishTask() { lock.withLock { counter -= 1 } }
    var lap: Double { let lap = timer.distance(to: Date()); timer = Date(); return lap }
}

/// Helper `LeafFiles` struct providing an in-memory thread-safe map of "file names" to "file data"
internal final class LeafTestFiles: LeafSource {
    var files: [String: String] {
        get { lock.withLock {_files} }
        set { lock.withLockVoid {_files = newValue} }
    }
    
    var _files: [String: String]
    var lock: Lock

    init() {
        _files = [:]
        lock = .init()
    }

    public func file(template: String, escape: Bool = false, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        var path = template
        if path.split(separator: "/").last?.split(separator: ".").count ?? 1 < 2,
           !path.hasSuffix(".leaf") { path += ".leaf" }
        if !path.hasPrefix("/") { path = "/" + path }

        return lock.withLock {
            if let file = _files[path] {
                var buffer = ByteBufferAllocator().buffer(capacity: file.count)
                buffer.writeString(file)
                return succeed(buffer, on: eventLoop)
            } else { return fail(err(.noTemplateExists(template)), on: eventLoop) }
        }
    }
}

// MARK: - Helper Extensions

internal extension ByteBuffer {
    var string: String { String(decoding: readableBytesView, as: UTF8.self) }
    var terse: String {
        var result = String(decoding: readableBytesView, as: UTF8.self)
        var index = result.indices.index(after: result.indices.startIndex)
        while index < result.indices.endIndex {
            if result[index] == .newLine,
               result[index] == result[result.indices.index(before: index)] {
                result.remove(at: index) }
            else { index = result.indices.index(after: index) }
        }
        return result
    }
}

internal extension Array where Element == LKToken {
    var string: String {
        compactMap { if case .whiteSpace(_) = $0 { return nil }
                     else if $0 == .raw("\n") { return nil }
                     return $0.description + "\n" }.reduce("", +) }
}

// MARK: - Helper Variables

/// Automatic path discovery for the Templates folder in this package
internal var templateFolder: String { projectTestFolder + "Templates/" }
internal var projectTestFolder: String { "/\(#file.split(separator: "/").dropLast().joined(separator: "/"))/"}

// MARK: - Internal Tests

/// Test printing descriptions of Syntax objects
final class PrintTests: LeafTestClass {
    func testRaw() throws {
        let template = "hello, raw text"
        let expectation = "0: raw(LeafBuffer: 15B)"

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
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
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
        1: raw(LeafBuffer: 16B)
        2: elseif([$:bar == string(bar)]):
        3: raw(LeafBuffer: 15B)
        4: else:
        5: raw(LeafBuffer: 14B)
        """

        let v = try parse(template)
        XCTAssertEqual(v.terse, expectation)
    }

    func testImport() throws {
        let template = "#import(someimport)"
        let expectation = """
        0: import(someimport):
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
        0: export(title):
        1: string(Welcome)
        3: export(body):
        4: raw(LeafBuffer: 17B)
        6: extend("base", leaf):
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
