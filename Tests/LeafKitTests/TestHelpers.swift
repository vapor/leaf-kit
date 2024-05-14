import XCTest
import NIOConcurrencyHelpers
import NIO
@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests

// MARK: - Helper Functions

/// Directly run a String "template" through `LeafLexer`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed array of LeafTokens
internal func lex(_ str: String) throws -> [LeafToken] {
    var lexer = LeafLexer(name: "lex-test", template: str)
    return try lexer.lex().dropWhitespace()
}

/// Directly run a String "template" through `LeafLexer` and `LeafParser`
/// - Parameter str: Raw String holding Leaf template source data
/// - Returns: A lexed and parsed array of Syntax
internal func parse(_ str: String) throws -> [Syntax] {
    var lexer = LeafLexer(name: "alt-parse", template: str)
    let tokens = try! lexer.lex()
    var parser = LeafParser(name: "alt-parse", tokens: tokens)
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
///
/// `@unchecked Sendable` because uses locks to guarantee Sendability.
internal class TestRenderer: @unchecked Sendable {
    var r: LeafRenderer
    private let lock: NIOLock
    private var counter: Int = 0
    
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
    
    public var isDone: Bool {
        return lock.withLock { counter == 0 } ? true : false
    }
    
    func finishTask() {
        lock.withLock { counter -= 1 }
    }
}

/// Helper `LeafFiles` struct providing an in-memory thread-safe map of "file names" to "file data"
internal struct TestFiles: LeafSource {
    var files: [String: String]
    var lock: NIOLock

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

internal extension Array where Element == LeafToken {
    func dropWhitespace() -> Array<LeafToken> {
        return self.filter { token in
            guard case .whitespace = token else { return true }
            return false
        }
    }
    
    var string: String {
        return self.map { $0.description + "\n" } .reduce("", +)
    }
}

internal extension Array where Element == Syntax {
    var string: String {
        return self.map { $0.description } .joined(separator: "\n")
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
    func testRaw() throws {
        let template = "hello, raw text"
        let expectation = "raw(\"hello, raw text\")"
        
        let v = try parse(template).first!
        guard case .raw = v else { throw "nope" }
        let output = v.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }

    func testVariable() throws {
        let template = "#(foo)"
        let expectation = "variable(foo)"
        
        let v = try parse(template).first!
        guard case .expression(let e) = v,
              let test = e.first else { throw "nope" }
        let output = test.description
        XCTAssertEqual(output, expectation)
    }

    func testLoop() throws {
        let template = """
        #for(name in names):
            hello, #(name).
        #endfor
        """
        let expectation = """
        for(name in names):
          raw("\\n    hello, ")
          expression[variable(name)]
          raw(".\\n")
        """
        
        let v = try parse(template).first!
        guard case .loop(let test) = v else { throw "nope" }
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }

    func testLoopCustomIndex() throws {
        let template = """
        #for(i, name in names):
            #(i): hello, #(name).
        #endfor
        """
        let expectation = """
        for(i, name in names):
          raw("\\n    ")
          expression[variable(i)]
          raw(": hello, ")
          expression[variable(name)]
          raw(".\\n")
        """

        let v = try parse(template).first!
        guard case .loop(let test) = v else { throw "nope" }
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
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
        conditional:
          if(variable(foo)):
            raw("\\n    some stuff\\n")
          elseif([bar == "bar"]):
            raw("\\n    bar stuff\\n")
          else:
            raw("\\n    no stuff\\n")
        """
        
        let v = try parse(template).first!
        guard case .conditional(let test) = v else { throw "nope" }
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }

    func testImport() throws {
        let template = "#import(\"someimport\")"
        let expectation = "import(\"someimport\")"
        
        let v = try parse(template).first!
        guard case .import(let test) = v else { throw "nope" }
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }

    func testExtendAndExport() throws {
        let template = """
        #extend("base"):
            #export("title","Welcome")
            #export("body"):
                hello there
            #endexport
        #endextend
        """
        let expectation = """
        extend("base"):
          export("body"):
            raw("\\n        hello there\\n    ")
          export("title"):
            expression[stringLiteral("Welcome")]
        """
        
        let v = try parse(template).first!
        guard case .extend(let test) = v else { throw "nope" }
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }

    func testCustomTag() throws {
        let template = """
        #custom(tag, foo == bar):
            some body
        #endcustom
        """

        let v = try parse(template).first!
        guard case .custom(let test) = v else { throw "nope" }

        let expectation = """
        custom(variable(tag), [foo == bar]):
          raw("\\n    some body\\n")
        """
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
}
