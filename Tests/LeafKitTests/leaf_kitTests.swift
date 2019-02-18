import XCTest
@testable import LeafKit

typealias LeafDict = [String: LeafData]

func render(raw: String, ctx: LeafDict) throws -> String {
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

class LeafTests { //: XCTestCase {
    func testRaw() throws {
        let template = "raw text, should be same"
        let result = try render(raw: template, ctx: [:])
        XCTAssertEqual(result, template)
    }
    
    func testPrint() throws {
        let template = "Hello, #(name)!"
        let data = ["name": "Tanner"] as LeafDict
        try XCTAssertEqual(render(raw: template, ctx: data), "Hello, Tanner!")
    }

    func testConstant() throws {
        let template = "<h1>#(42)</h1>"
        try XCTAssertEqual(render(raw: template, ctx: [:]), "<h1>42</h1>")
    }

    func testInterpolated() throws {
        let template = """
        <p>#("foo: #(foo)")</p>
        """
        let data = ["foo": "bar"] as LeafDict
        try XCTAssertEqual(render(raw: template, ctx: data), "<p>foo: bar</p>")
    }
}

final class LexerTests: XCTestCase {
    func testEscaping() throws {
        let input = "\\#"
        let output = try lex(input).map { $0.description } .reduce("", +)
        XCTAssertEqual(output, "raw(\"#\")")
    }
    
    func testTags() throws {
        let input = """
        #tag
        #tag:
        #endtag
        #tag()
        #tag():
        #tag(foo)
        #tag(foo):
        """
        let expectation = """
        tagIndicator
        tag(name: "tag")
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        tagBodyIndicator
        raw("\\n")
        tagIndicator
        tag(name: "endtag")
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        parametersStart
        parametersEnd
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        parametersStart
        parametersEnd
        tagBodyIndicator
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        parametersStart
        variable(name: "foo")
        parametersEnd
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        parametersStart
        variable(name: "foo")
        parametersEnd
        tagBodyIndicator

        """
        XCTAssertEqual(output, expectation)
    }
    
    func lex(_ str: String) throws -> [LeafToken] {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(str)
        
        var lexer = _LeafLexer(template: buffer)
        return try lexer.lex()
    }
}

final class LeafKitTests: XCTestCase {
    
    func _testEscaping() throws {
        let template = """
        \\#escapedHashtag
        \\\\
        \\#
        """
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(template)
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
    }
    
    func _testTagName() throws {
        let template = """
        #tag
        #tag:
        #tag()
        #tag():
        #tag(foo)
        #tag(foo):
        """
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(template)
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
    }
    
    func _testParameters() {
        let temp = """
        #(foo:)
        """
    }
    
    func _testParser() throws {
        let template = """
        Hello #(name)!

        Hello #get(name)!

        #set(name):
            Hello #get(name)
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
        
        var lexer = _LeafLexer(template: buffer)
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
    
    func _testRenderer() throws {
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
}

var templateFolder: String {
    let folder = #file.split(separator: "/").dropLast().joined(separator: "/")
    return "/" + folder + "/Templates/"
}
