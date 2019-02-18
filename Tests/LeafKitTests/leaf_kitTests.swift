import XCTest
@testable import LeafKit

func render(raw: String, ctx: [String: LeafData]) throws -> String {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(raw)
    
    var lexer = LeafLexer(template: buffer)
    let tokens = try lexer.lex()
    var parser = LeafParser(tokens: tokens)
    let ast = try parser.parse()
    var serializer = LeafSerializer(ast: ast, context: ctx)
    var view = try serializer.serialize()
    return view.readString(length: view.readableBytes)!
}

class LeafTests: XCTestCase {
    func testRaw() throws {
        let template = "Hello!"
        let result = try render(raw: template, ctx: [:])
        XCTAssertEqual(result, template)
    }
}

final class LeafKitTests: XCTestCase {
    func testParser() throws {
        let template = """
        Hello #(name)!

        Hello #get(name)!

        #set(name):
            Hello #(name)
        #endset!

        #if(a):b#endif

        #if(foo):
        123
        #elseif(bar):
        456
        #else:
        789
        #endif

        #import("title")

        #import("body")

        #extend("base"):
            #export("title", "Welcome")
            #export("body"):
                Hello, #(name)!
            #endexport
        #endextend

        More stuff here!
        """
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(template)
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
        var parser = LeafParser(tokens: tokens)
        let ast = try parser.parse()
        print("AST:")
        ast.forEach { print($0) }
        print()
        
        var serializer = LeafSerializer(ast: ast, context: [
            "name": "Tanner",
            "a": true,
            "bar": true
        ])
        var view = try serializer.serialize()
        let string = view.readString(length: view.readableBytes)!
        print("View:")
        print(string)
        print()
    }
    
    func testRenderer() throws {
        let threadPool = BlockingIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let config = LeafConfig(rootDirectory: templateFolder)
        let renderer = LeafRenderer(config: config, threadPool: threadPool, eventLoop: group.next())
        
        var buffer = try! renderer.render(path: "test", context: [:]).wait()
        let string = buffer.readString(length: buffer.readableBytes)!
        print(string)
        
        try threadPool.syncShutdownGracefully()
        try group.syncShutdownGracefully()
    }

    static var allTests = [
        ("testParser", testParser),
    ]
}

var templateFolder: String {
    let folder = #file.split(separator: "/").dropLast().joined(separator: "/")
    return "/" + folder + "/Templates/"
}
