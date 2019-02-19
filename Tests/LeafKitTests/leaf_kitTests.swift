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

extension Array where Element == LeafToken {
    func dropWhitespace() -> Array<LeafToken> {
        return self.filter { token in
            guard case .whitespace = token else { return true }
            return false
        }
    }
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
    
    func _testExtenasdfd() throws {
        /// 'base.leaf
//        let base = """
//        <title>#import(title)</title>
//        #import(body)
//        """
//
        /// `home.leaf`
        let home = """
        #if(if(foo):bar#endif == "bar", "value")
        """
        
        let output = try lex(home).map { $0.description + "\n" } .reduce("", +)
        //        XCTAssertEqual(output, expectation)
        print("")
    }
    
    func testExtend() throws {
        /// 'base.leaf
        let base = """
        <title>#import(title)</title>
        #import(body)
        """
        
        /// `home.leaf`
        let home = """
        #extend("base"):
            #export("title", "Welcome")
            #export("body"):
                Hello, #(name)!
            #endexport
        #endextend
        """
        
        let output = try lex(home).map { $0.description + "\n" } .reduce("", +)
//        XCTAssertEqual(output, expectation)
        print("")
    }
    
    func testParamNesting() throws {
        let input = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """
        
        let expectation = """
        tagIndicator
        tag(name: "if")
        parametersStart
        tag(name: "lowercase")
        parametersStart
        tag(name: "first")
        parametersStart
        variable(name: "name")
        operator(==)
        stringLiteral("admin")
        parametersEnd
        parametersEnd
        operator(==)
        stringLiteral("welcome")
        parametersEnd
        tagBodyIndicator
        raw("\\nfoo\\n")
        tagIndicator
        tag(name: "endif")

        """
        
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        let _ = try parse(input)
        XCTAssertEqual(output, expectation)
    }
    
    func testConstant() throws {
        let input = "<h1>#(42)</h1>"
        let expectation = """
        raw("<h1>")
        tagIndicator
        tag(name: "")
        parametersStart
        constant(42)
        parametersEnd
        raw("</h1>")

        """

        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
    }
    
    /*
     // TODO:
     
     #("#")
     #()
     "#("\")#(name)" == '\logan'
     "\#(name)" == '#(name)'
     */
    func testEscaping() throws {
        let input = "\\#"
        let output = try lex(input).map { $0.description } .reduce("", +)
        XCTAssertEqual(output, "raw(\"#\")")
    }
    
    func _testParameters() throws {
        let input = "#(foo == 40, and, \"literal\")"
        let expectation = """
        tagIndicator
        tag(name: "")
        parametersStart
        variable(name: "foo")
        operator(==)
        constant(40)
        parameterDelimiter
        variable(name: "and")
        parameterDelimiter
        stringLiteral("literal")
        parametersEnd

        """
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
    }
    
    func _testTags() throws {
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
        
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
    }
}

func lex(_ str: String) throws -> [LeafToken] {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(str)
    
    var lexer = LeafLexer(template: buffer)
    return try lexer.lex().dropWhitespace()
}

func parse(_ str: String) throws -> [LeafToken] {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(str)
    
    var lexer = LeafLexer(template: buffer)
    let tokens = try lexer.lex()
    var parser = _LeafParser.init(tokens: tokens)
    let syntax = try parser.preProcess()
    let printable = syntax.map { $0.description + "\n" } .reduce("", +)
    print(printable)
    print("")
    
    fatalError()
}

final class LeafKitTests: XCTestCase {
    func testParser() throws {
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
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
        var parser = _LeafParser(tokens: tokens)
        let ast = try! parser.preProcess()
        print("AST:")
        ast.forEach { print($0) }
        print()
        //
        //        var serializer = LeafSerializer(ast: ast, context: [
        //            "name": "Tanner",
        //            "a": true,
        //            "bar": true
        //        ])
        //        var view = try serializer.serialize()
        //        let string = view.readString(length: view.readableBytes)!
        //        print("View:")
        //        print(string)
        //        print()
    }
    
    func __testParser() throws {
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
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
        var parser = _LeafParser(tokens: tokens)
        let ast = try! parser.preProcess()
        print("AST:")
        ast.forEach { print($0) }
        print()
        //
        //        var serializer = LeafSerializer(ast: ast, context: [
        //            "name": "Tanner",
        //            "a": true,
        //            "bar": true
        //        ])
        //        var view = try serializer.serialize()
        //        let string = view.readString(length: view.readableBytes)!
        //        print("View:")
        //        print(string)
        //        print()
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
