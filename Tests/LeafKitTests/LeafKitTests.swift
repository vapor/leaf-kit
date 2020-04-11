import XCTest
@testable import LeafKit

extension Array where Element == LeafToken {
    func dropWhitespace() -> Array<LeafToken> {
        return self.filter { token in
            guard case .whitespace = token else { return true }
            return false
        }
    }
}

final class SomeTests: XCTestCase {
    func testCodable() {
        struct Foo: Codable {
            let foo: String
        }

        // let a = Foo(foo: "afds")
    }
}

extension UInt8 {
    var str: String { return String(bytes: [self], encoding: .utf8)! }
}
final class ParserTests: XCTestCase {
//    func testNesting()... *removed - identical to testParsingNesting()
    
    func testParsingNesting() throws {
        let input = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """
        
        let expectation = """
        conditional:
          if(expression(lowercase(first(name == "admin")) == "welcome")):
            raw("\\nfoo\\n")
        """
        
        let syntax = try parse(input)
        let output = syntax.map { $0.description } .joined(separator: "\n")
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
        conditional:
          if(variable(foo)):
            raw("\\nfoo\\n")
          else:
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
        
        let expectation = """
        conditional:
          if(variable(sayhello)):
            raw("\\n    abc\\n    ")
            for(name in names):
              raw("\\n        hi, ")
              variable(name)
              raw("\\n    ")
            raw("\\n    def\\n")
          else:
            raw("\\n    foo\\n")
        """
        
        let output = try parse(input).map { $0.description } .joined(separator: "\n")
        XCTAssertEqual(output, expectation)
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
        
        let expectation = """
        conditional:
          if(variable(sayhello)):
            raw("\\n    abc\\n    ")
            for(name in names):
              raw("\\n        hi, ")
              variable(name)
              raw("\\n    ")
            raw("\\n    def\\n")
          else:
            raw("\\n    foo\\n")
        """
        
        let output = try parse(input).map { $0.description } .joined(separator: "\n")
        XCTAssertEqual(output, expectation)
    }
    
    func testUnresolvedAST() throws {
        let base = """
        #extend("header")
        <title>#import("title")</title>
        #import("body")
        """
        
        let syntax = try! parse(base)
        let ast = LeafAST(name: "base", ast: syntax)
        XCTAssertFalse(ast.unresolvedRefs.count == 0, "Unresolved template")
    }
    
    func testInsertResolution() throws {
        let header = """
        <h1>Hi!</h1>
        """
        let base = """
        #extend("header")
        <title>#import("title")</title>
        #import("body")
        """
        
        let baseAST = try LeafAST(name: "base", ast: parse(base))
        let headerAST = try LeafAST(name: "header", ast: parse(header))
        let baseResolvedAST = LeafAST(from: baseAST, referencing: ["header": headerAST])

        let output = baseResolvedAST.ast.map { $0.description } .joined(separator: "\n")

        let expectation = """
        raw("<h1>Hi!</h1>")
        raw("\\n<title>")
        import("title")
        raw("</title>\\n")
        import("body")
        """
        XCTAssertEqual(output, expectation)
    }
    
    func testDocumentResolveExtend() throws {
        let header = """
        <h1>#import("header")</h1>
        """

        let base = """
        #extend("header")
        <title>#import("title")</title>
        #import("body")
        """
        
        let home = """
        #extend("base"):
            #export("title", "Welcome")
            #export("body"):
                Hello, #(name)!
            #endexport
        #endextend
        """
        
        let headerAST = try LeafAST(name: "header", ast: parse(header))
        let baseAST = try LeafAST(name: "base", ast: parse(base))
        let homeAST = try LeafAST(name: "home", ast: parse(home))
        
        let baseResolved = LeafAST(from: baseAST, referencing: ["header": headerAST])
        let homeResolved = LeafAST(from: homeAST, referencing: ["base": baseResolved])
  
        let output = homeResolved.ast.map { $0.description } .joined(separator: "\n")
        let expectation = """
        raw("<h1>")
        import("header")
        raw("</h1>")
        raw("\\n<title>")
        raw("Welcome")
        raw("</title>\\n")
        raw("\\n        Hello, ")
        variable(name)
        raw("!\\n    ")
        """
        XCTAssertEqual(output, expectation)
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
        extend("base"):
          export("body"):
            raw("\\n        Hello, ")
            variable(name)
            raw("!\\n    ")
          export("title"):
            raw("Welcome")
        """
        
        let rawAlt = try! parse(input)
        let output = rawAlt.map { $0.description } .joined(separator: "\n")
        XCTAssertEqual(output, expectation)
    }
    
    func testPPP() throws {
        let it = [0, 1, 2, 3, 4] // .reversed().makeIterator()
        let stripped = it.drop(while: { $0 > 2 })
        print(Array(stripped))
        print("")
    }
}

final class PrintTests: XCTestCase {
    func testRaw() throws {
        let template = """
        hello, raw text
        """
        let v = parse(template).first!
        guard case .raw = v else { throw "nope" }
        
        let expectation = """
        raw(\"hello, raw text\")
        """
        let output = v.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
    
    func testVariable() throws {
        let template = """
        #(foo)
        """
        let v = parse(template).first!
        guard case .variable(let test) = v else { throw "nope" }
        
        let expectation = """
        variable(foo)
        """
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
    
    func testLoop() throws {
        let template = """
        #for(name in names):
            hello, #(name).
        #endfor
        """
        let v = parse(template).first!
        guard case .loop(let test) = v else { throw "nope" }
        
        let expectation = """
        for(name in names):
          raw("\\n    hello, ")
          variable(name)
          raw(".\\n")
        """
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
        let v = parse(template).first!
        guard case .conditional(let test) = v else { throw "nope" }
        
        let expectation = """
        conditional:
          if(variable(foo)):
            raw("\\n    some stuff\\n")
          elseif(expression(bar == "bar")):
            raw("\\n    bar stuff\\n")
          else:
            raw("\\n    no stuff\\n")
        """
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
    
    func testImport() throws {
        let template = """
        #import("someimport")
        """
        let v = parse(template).first!
        guard case .import(let test) = v else { throw "nope" }
        
        let expectation = """
        import(\"someimport\")
        """
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
        let v = parse(template).first!
        guard case .extend(let test) = v else { throw "nope" }
        
        let expectation = """
        extend("base"):
          export("body"):
            raw("\\n        hello there\\n    ")
          export("title"):
            raw("Welcome")
        """
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
    
    
    func testCustomTag() throws {
        let template = """
        #custom(tag, foo == bar):
            some body
        #endcustom
        """
        
        let v = parse(template).first!
        guard case .custom(let test) = v else { throw "nope" }
        
        let expectation = """
        custom(variable(tag), expression(foo == bar)):
          raw("\\n    some body\\n")
        """
        let output = test.print(depth: 0)
        XCTAssertEqual(output, expectation)
    }
    
    func parse(_ str: String) -> [Syntax] {
        var lexer = LeafLexer(name: "test-lex", template: str)
        let tokens = try! lexer.lex()
        var parser = LeafParser(name: "parse", tokens: tokens)
        return try! parser.parse()
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
        
        _ = try lex(home).map { $0.description + "\n" } .reduce("", +)
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
        param(operator(==))
        param(stringLiteral("admin"))
        parametersEnd
        parametersEnd
        param(operator(==))
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
        // input is really '\#' w/ escaping
        let input = "\\#"
        let output = try lex(input).map { $0.description } .reduce("", +)
        XCTAssertEqual(output, "raw(\"#\")")
    }
    
    func testTagIndicator() throws {
        Character.tagIndicator = "🤖"
        let input = """
        🤖extend("base"):
            🤖export("title", "Welcome")
            🤖export("body"):
                Hello, 🤖(name)!
            🤖endexport
        🤖endextend
        """
        
        let expectation = """
        extend("base"):
          export("body"):
            raw("\\n        Hello, ")
            variable(name)
            raw("!\\n    ")
          export("title"):
            raw("Welcome")
        """
        
        let rawAlt = try! parse(input)
        let output = rawAlt.map { $0.description } .joined(separator: "\n")
        XCTAssertEqual(output, expectation)
        Character.tagIndicator = .octothorpe
    }
    
    func testParameters() throws {
        let input = "#(foo == 40, and, \"literal\", and, foo_bar)"
        let expectation = """
        tagIndicator
        tag(name: "")
        parametersStart
        param(variable(foo))
        param(operator(==))
        param(constant(40))
        parameterDelimiter
        param(variable(and))
        parameterDelimiter
        param(stringLiteral("literal"))
        parameterDelimiter
        param(variable(and))
        parameterDelimiter
        param(variable(foo_bar))
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

    func testNestedEcho() throws {
        let input = """
        #(todo)
        #(todo.title)
        #(todo.user.name.first)
        """
        let expectation = """
        tagIndicator
        tag(name: "")
        parametersStart
        param(variable(todo))
        parametersEnd
        raw("\\n")
        tagIndicator
        tag(name: "")
        parametersStart
        param(variable(todo.title))
        parametersEnd
        raw("\\n")
        tagIndicator
        tag(name: "")
        parametersStart
        param(variable(todo.user.name.first))
        parametersEnd

        """
        let output = try lex(input).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output, expectation)
    }
}

func lex(_ str: String) throws -> [LeafToken] {
    var lexer = LeafLexer(name: "lex-test", template: str)
    return try lexer.lex().dropWhitespace()
}


func parse(_ str: String) throws -> [Syntax] {
    var lexer = LeafLexer(name: "alt-parse", template: str)
    let tokens = try! lexer.lex()
    var parser = LeafParser(name: "alt-parse", tokens: tokens)
    let syntax = try! parser.parse()
    
    return syntax
}

//func parse(... *removed as pass-through to altParse (now parse)

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

        #parent:
            #if(somebs):
                #for(boo in far):
                    ya, ok, some stuff is here ;)
                #endfor
            #endif
        #endparent

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
        
        var lexer = LeafLexer(name: "test-parser", template: template)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
//        var parser = _LeafParser(tokens: tokens)
//        let ast = try! parser.altParse().map { $0.description } .joined(separator: "\n")
        let rawAlt = try! parse(template)
        print("AST")
        rawAlt.forEach { print($0) }
        print()
        _ = rawAlt.map { $0.description } .joined(separator: "\n")
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
    
//    func testLoader()... *removed as non-useful test (duplicates testUnresolvedAST)
    
    func testParserasdf() throws {
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
        
        var lexer = LeafLexer(name: "test-parseasdf", template: template)
        let tokens = try! lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
        var parser = LeafParser(name: "test-parseasdf", tokens: tokens)
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

    func testNestedEcho() throws {
        let input = """
        Todo: #(todo.title)
        """
        var lexer = LeafLexer(name: "nested-echo", template: input)
        let tokens = try lexer.lex()
        var parser = LeafParser(name: "nested-echo", tokens: tokens)
        let ast = try parser.parse()
        var serializer = LeafSerializer(ast: ast, context: ["todo": ["title": "Leaf!"]])
        let view = try serializer.serialize()
        XCTAssertEqual(view.string, "Todo: Leaf!")
    }
    
    func _testRenderer() throws {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileio = NonBlockingFileIO(threadPool: threadPool)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let config = LeafConfiguration(rootDirectory: templateFolder)
        let renderer = LeafRenderer(
            configuration: config,
            files: NIOLeafFiles(fileio: fileio),
            eventLoop: group.next()
        )
        
        var buffer = try! renderer.render(path: "test", context: [:]).wait()
        let string = buffer.readString(length: buffer.readableBytes)!
        print(string)
        
        try threadPool.syncShutdownGracefully()
        try group.syncShutdownGracefully()
    }

    func testRendererContext() throws {
        var test = TestFiles()
        test.files["/foo.leaf"] = """
        Hello #custom(name)
        """

        struct CustomTag: LeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                let prefix = ctx.userInfo["prefix"] as? String ?? ""
                let param = ctx.parameters.first?.string ?? ""
                return .string(prefix + param)
            }
        }

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            tags: [
                "custom": CustomTag()
            ],
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop(),
            userInfo: [
                "prefix": "bar"
            ]
        )
        let view = try renderer.render(path: "foo", context: [
            "name": "vapor"
        ]).wait()

        XCTAssertEqual(view.string, "Hello barvapor")
    }
    
    func testCacheSpeedLinear() {
        self.measure {
            self._testCacheSpeedLinear(templates: 10, iterations: 100_000)
        }
    }
    
    func _testCacheSpeedLinear(templates: Int, iterations: Int) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var test = TestFiles()
        for name in 1...templates { test.files["/\(name).leaf"] = "Template \(name)" }
        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: group.next()
        )
        
        for _ in 1...iterations {
            for key in test.files.keys { _ = renderer.render(path: key, context: [:]) }
        }
        
        try! group.syncShutdownGracefully()
    }
}

struct TestFiles: LeafFiles {
    var files: [String: String]

    init() {
        files = [:]
    }


    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        if let file = self.files[path] {
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            buffer.writeString(file)
            return eventLoop.makeSucceededFuture(buffer)
        } else {
            return eventLoop.makeFailedFuture("no test file: \(path)")
        }
    }
}

extension ByteBuffer {
    var string: String {
        String(decoding: self.readableBytesView, as: UTF8.self)
    }
}

var templateFolder: String {
    let folder = #file.split(separator: "/").dropLast().joined(separator: "/")
    return "/" + folder + "/Templates/"
}
