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

extension UInt8 {
    var str: String { return String(bytes: [self], encoding: .utf8)! }
}
final class ParserTests: XCTestCase {
    func testParsingNesting() throws {
        let input = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """
        
        let expectation = """
        conditional(if(expression(tag(lowercase: tag(first: expression(parameter(variable(name)) parameter(operator(operator(==))) parameter(stringLiteral("admin"))))) parameter(operator(operator(==))) parameter(stringLiteral("welcome"))))):
            raw("\\nfoo\\n")
        """
        
        let syntax = try altParse(input)
        let output = syntax.map { $0.description } .joined(separator: "\n")
//        var matched = ""
//        for x in 0..<output.count {
//            let l = Array(output.utf8)[x]
//            let r = Array(expectation.utf8)[x]
//            guard l == r else { fatalError("crashed at[\(x) ([\(l)]\(l.str), [\(r)]\(r.str)) match: ***\n\(matched)***") }
//            matched += l.str
//        }
        XCTAssertEqual(output, expectation)
    }
    
    func testComplex() throws {
        let input = """
        #if(foo):
        foo
        #else:
        foo
        #endif
        """
        
        let expectation = """
        conditional(if(parameter(variable(foo)))):
            raw("\\nfoo\\n")
        conditional(else):
            raw("\\nfoo\\n")
        """
        
        let syntax = try! parse(input)
        let output = syntax.map { $0.description } .joined(separator: "\n")
        XCTAssertEqual(output, expectation)
    }
    
    func testCompiler() throws {
        let input = """
        #if(sayhello):
            abc
            #for(name in names):
                hi, #(name)
            #endfor
            def
        #else:
        foo
        #endif
        """
        
        let output = try compile(input).map { $0.description } .joined(separator: ",\n")
        XCTAssertEqual(output, "todo")
        
        //        let syntax = try compile(input)
        //        let output = syntax.map { $0.description } .joined(separator: "\n")
        //        XCTAssertEqual(output, expectation)
    }
    func testCompiler2() throws {
        let input = """
        #if(sayhello):
            abc
            #for(name in names):
                hi, #(name)
            #endfor
            def
        #else:
        foo
        #endif
        """
        
        let output = try compile(input).map { $0.description } .joined(separator: ",\n\n")
        XCTAssertEqual(output, "todo")
    }
    
    
    func testCompileExtend() throws {
        let input = """
        #extend("base"):
            #export("title", "Welcome")
            #export("body"):
                Hello, #(name)!
            #endexport
        #endextend
        """
        
        let expectation = """
        extend(parameter(stringLiteral("base")))
        raw("\\n    ")
        export(hasBody: false: parameter(stringLiteral("title")), parameter(stringLiteral("Welcome")))
        raw("\\n    ")
        export(hasBody: true: parameter(stringLiteral("body")))
        raw("\\n        Hello, ")
        variable(parameter(variable(name)))
        raw("!\\n    ")
        tagTerminator(export)
        raw("\\n")
        tagTerminator(extend)

        """
        
        let lexed = try! lex(input).map { $0.description + "\n" } .reduce("", +)
        let rawAlt = try! altParse(input)
        let alt = rawAlt.map { $0.description + "\n" } .reduce("", +)
        let parsed = try! parse(input).map { $0.description + "\n" } .reduce("", +)
        let compiled = try! compile(input).map { $0.description + "\n" } .reduce("", +)
        let _ = lexed + parsed + compiled
        
        let output = parsed
        XCTAssertEqual(output, expectation)
    }
    
    func testPPP() throws {
        var it = [0, 1, 2, 3, 4] // .reversed().makeIterator()
        let stripped = it.drop(while: { $0 > 2 })
        print(Array(stripped))
        print("")
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
        param(tag("lowercase"))
        parametersStart
        param(tag("first"))
        parametersStart
        param(variable(name))
        param(operator(operator(==)))
        param(stringLiteral("admin"))
        parametersEnd
        parametersEnd
        param(operator(operator(==)))
        param(stringLiteral("welcome"))
        parametersEnd
        tagBodyIndicator
        raw("\\nfoo\\n")
        tagIndicator
        tag(name: "endif")

        """
        
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
    }
    
    func testConstant() throws {
        let input = "<h1>#(42)</h1>"
        let expectation = """
        raw("<h1>")
        tagIndicator
        tag(name: "")
        parametersStart
        param(constant(42))
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
    
    func testParameters() throws {
        let input = "#(foo == 40, and, \"literal\")"
        let expectation = """
        tagIndicator
        tag(name: "")
        parametersStart
        param(variable(foo))
        param(operator(operator(==)))
        param(constant(40))
        parameterDelimiter
        param(variable(and))
        parameterDelimiter
        param(stringLiteral("literal"))
        parametersEnd

        """
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
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
        param(variable(foo))
        parametersEnd
        raw("\\n")
        tagIndicator
        tag(name: "tag")
        parametersStart
        param(variable(foo))
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


func altParse(_ str: String) throws -> [_ALTSyntax] {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(str)
    
    var lexer = LeafLexer(template: buffer)
    let tokens = try! lexer.lex()
    var parser = _LeafParser.init(tokens: tokens)
    let syntax = try! parser.altParse()
    
    return syntax
}

func parse(_ str: String) throws -> [_Syntax] {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(str)
    
    var lexer = LeafLexer(template: buffer)
    let tokens = try! lexer.lex()
    var parser = _LeafParser.init(tokens: tokens)
    let syntax = try! parser.parse()

    return syntax
}

func compile(_ str: String) throws -> [_Block] {
    var buffer = ByteBufferAllocator().buffer(capacity: 0)
    buffer.writeString(str)
    
    var lexer = LeafLexer(template: buffer)
    let tokens = try! lexer.lex()
    var parser = _LeafParser.init(tokens: tokens)
    let syntax = try! parser.parse()
    
    var compiler = _Compiler(syntax: syntax)
    let elements = try compiler.compile()
    return elements
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

//        let template = """
//        #if(foo):
//        123
//        #elseif(bar):
//        456
//        #else:
//        789
//        #endif
//        """
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(template)
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
//        var parser = _LeafParser(tokens: tokens)
//        let ast = try! parser.altParse().map { $0.description } .joined(separator: "\n")
        let rawAlt = try! altParse(template)
        print("AST")
        rawAlt.forEach { print($0) }
        print()
        let alt = rawAlt.map { $0.description } .joined(separator: "\n")
//        print("AST:")
//        ast.forEach { print($0) }
        print("")
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
        let ast = try! parser.parse()
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
