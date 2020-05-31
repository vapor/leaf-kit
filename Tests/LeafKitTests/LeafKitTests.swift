import XCTest
import NIOConcurrencyHelpers
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
    func testParsingNesting() throws {
        let input = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """

        let expectation = """
        conditional:
          if(expression(lowercase(first([name == "admin"])) == "welcome")):
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
        raw("<h1>Hi!</h1>\\n<title>")
        import("title")
        raw("</title>\\n")
        import("body")
        """
        XCTAssertEqual(output.description, expectation)
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
        raw("</h1>\\n<title>Welcome</title>\\n\\n        Hello, ")
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

    func testNoWhitespace() throws {
        let input1 = "#if(!one||!two)"
        let input2 = "#if(!one || !two)"
        let input3 = "#if(! one||! two)"
        let input4 = "#if(! one || ! two)"

        let output1 = try lex(input1).map { $0.description + "\n" } .reduce("", +)
        let output2 = try lex(input2).map { $0.description + "\n" } .reduce("", +)
        let output3 = try lex(input3).map { $0.description + "\n" } .reduce("", +)
        let output4 = try lex(input4).map { $0.description + "\n" } .reduce("", +)
        XCTAssertEqual(output1, output2)
        XCTAssertEqual(output2, output3)
        XCTAssertEqual(output3, output4)
    }

    // Base2/8/10/16 lexing for Int constants, Base10/16 for Double
    func testNonDecimals() throws {
        let input = "#(0b0101010 0o052 42 0_042 0x02A 0b0101010.0 0o052.0 42.0 0_042.0 0x02A.0)"
        let expectation = """
        tagIndicator
        tag(name: "")
        parametersStart
        param(constant(42))
        param(constant(42))
        param(constant(42))
        param(constant(42))
        param(constant(42))
        param(variable(0b0101010.0))
        param(variable(0o052.0))
        param(constant(42.0))
        param(constant(42.0))
        param(constant(42.0))
        parametersEnd

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

    // deactivated because changing tagIndicator, for some reason, is causing a data race
    func _testTagIndicator() throws {
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

    func testCyclicalError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        do {
            _ = try renderer.render(path: "a", context: [:]).wait()
            XCTFail("Should have thrown LeafError.cyclicalReference")
        } catch let error as LeafError {
            switch error.reason {
                case .cyclicalReference(let name, let cycle): XCTAssertEqual([name:cycle],["a":["a","b","c","a"]])
                default: XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }

    func testDependencyError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"d\")"

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        do {
            _ = try renderer.render(path: "a", context: [:]).wait()
            XCTFail("Should have thrown LeafError.noTemplateExists")
        } catch let error as LeafError {
            switch error.reason {
                case .noTemplateExists(let name): XCTAssertEqual(name,"/d.leaf")
                default: XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }

    func testImportResolve() {
        var test = TestFiles()
        test.files["/a.leaf"] = """
        #extend("b"):
        #export("variable"):Hello#endexport
        #endextend
        """
        test.files["/b.leaf"] = """
        #import("variable")
        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        do {
            let output = try renderer.render(path: "a", context: [:]).wait().string
            XCTAssertEqual(output, "Hello")
        } catch {
            let e = error as! LeafError
            XCTFail(e.localizedDescription)
        }
    }

    func testCacheSpeedLinear() {
        self.measure {
            self._testCacheSpeedLinear(templates: 10, iterations: 100)
        }
    }

    func _testCacheSpeedLinear(templates: Int, iterations: Int) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var test = TestFiles()

        for name in 1...templates { test.files["/\(name).leaf"] = "Template /\(name).leaf" }
        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: group.next()
        )

        let progressLock = Lock()
        var progress = 0
        var done = false
        var delay = 0

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            group.next()
                .submit { renderer.render(path: template, context: [:]) }
                .whenComplete { result in progressLock.withLock { progress += 1 } }
        }

        while !done {
            progressLock.withLock { delay = (iterations - progress) * 10 }
            guard delay == 0 else { usleep(UInt32(delay)); break }
            done = true
            group.shutdownGracefully { shutdown in
                guard shutdown == nil else { XCTFail("ELG shutdown issue"); return }
                XCTAssertEqual(renderer.cache.entryCount(), templates)
            }
        }
    }

    func testCacheSpeedRandom() {
        self.measure {
            // layer1 > layer2 > layer3
            self._testCacheSpeedRandom(layer1: 100, layer2: 20, layer3: 10, iterations: 130)
        }
    }

    func _testCacheSpeedRandom(layer1: Int, layer2: Int, layer3: Int, iterations: Int) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var test = TestFiles()

        for name in 1...layer3 { test.files["/\(name)-3.leaf"] = "Template \(name)"}
        for name in 1...layer2 { test.files["/\(name)-2.leaf"] = "Template \(name) -> #extend(\"\((name % layer3)+1)-3\")"}
        for name in 1...layer1 { test.files["/\(name).leaf"] = "Template \(name) -> #extend(\"\(Int.random(in: 1...layer2))-2\") & #extend(\"\(Int.random(in: 1...layer2))-2\")" }

        let allKeys: [String] = test.files.keys.map{ String($0.dropFirst().dropLast(5)) }.shuffled()
        var hitList = allKeys
        let totalTemplates = allKeys.count
        let ratio = iterations / allKeys.count

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: group.next()
        )

        let progressLock = Lock()
        var progress = 0
        var done = false
        var delay = 0

        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count { template = hitList.removeFirst() }
            else { template = allKeys[Int.random(in: 0 ..< totalTemplates)] }
            group.next()
                .submit { renderer.render(path: template, context: [:]) }
                .whenComplete { result in progressLock.withLock { progress += 1 } }
        }

        while !done {
            progressLock.withLock { delay = (iterations - progress) * 10  }
            guard delay == 0 else { usleep(UInt32(delay)); break }
            done = true
            group.shutdownGracefully { shutdown in
                guard shutdown == nil else { XCTFail("ELG shutdown issue"); return }
                XCTAssertEqual(renderer.cache.entryCount(), layer1+layer2+layer3)
            }
        }
    }

    func testGH33() {
        var test = TestFiles()
        test.files["/base.leaf"] = """
        <body>
            Directly extended snippet
            #extend("partials/picture.svg"):#endextend
            #import("body")
        </body>
        """
        test.files["/page.leaf"] = """
        #extend("base"):
            #export("body"):
            Snippet added through export/import
            #extend("partials/picture.svg"):#endextend
        #endexport
        #endextend
        """
        test.files["/partials/picture.svg"] = """
        <svg><path d="M0..."></svg>
        """

        let expected = """
        <body>
            Directly extended snippet
            <svg><path d="M0..."></svg>
            
            Snippet added through export/import
            <svg><path d="M0..."></svg>

        </body>
        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

            let page = try! renderer.render(path: "page", context: [:]).wait()
            XCTAssertEqual(page.string, expected)
    }

    func testGH50() {
        var test = TestFiles()
        test.files["/a.leaf"] = """
        #extend("a/b"):
        #export("body"):#for(challenge in challenges):
        #extend("a/b-c-d"):#endextend#endfor
        #endexport
        #endextend
        """
        test.files["/a/b.leaf"] = """
        #import("body")
        """
        test.files["/a/b-c-d.leaf"] = """
        HI
        """

        let expected = """

        HI
        HI
        HI

        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        let page = try! renderer.render(path: "a", context: ["challenges":["","",""]]).wait()
            XCTAssertEqual(page.string, expected)
    }

    func testDeepResolve() {
        var test = TestFiles()
        test.files["/a.leaf"] = """
        #for(a in b):#if(false):Hi#elseif(true && false):Hi#else:#extend("b"):#export("derp"):DEEP RESOLUTION #(a)#endexport#endextend#endif#endfor
        """
        test.files["/b.leaf"] = """
        #import("derp")

        """

        let expected = """
        DEEP RESOLUTION 1
        DEEP RESOLUTION 2
        DEEP RESOLUTION 3

        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        let page = try! renderer.render(path: "a", context: ["b":["1","2","3"]]).wait()
            XCTAssertEqual(page.string, expected)
    }

    func testLoopedConditionalImport() throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
        #for(x in list):
        #extend("entry"):#export("something", "Whatever")#endextend
        #endfor
        """
        test.files["/entry.leaf"] = """
        #(x): #if(isFirst):#import("something")#else:Not First#endif
        """

        let expected = """

        A: Whatever

        B: Not First

        C: Not First

        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        let page = try renderer.render(path: "base", context: ["list": ["A", "B", "C"]]).wait()
        XCTAssertEqual(page.string, expected)
    }

    func testMultipleLoopedConditionalImports() throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
        #for(x in list1):
        #extend("entry"):#export("something", "Whatever")#endextend
        #endfor
        #for(x in list2):
        #extend("entry"):#export("something", "Something Else")#endextend
        #endfor
        """
        test.files["/entry.leaf"] = """
        #(x): #if(isFirst):#import("something")#else:Not First#endif
        """

        let expected = """

        A: Whatever

        B: Not First

        C: Not First


        A: Something Else

        B: Not First

        C: Not First

        """

        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: "/"),
            cache: DefaultLeafCache(),
            files: test,
            eventLoop: EmbeddedEventLoop()
        )

        let page = try renderer.render(path: "base", context: [
            "list1": ["A", "B", "C"],
            "list2": ["A", "B", "C"],
        ]).wait()
        XCTAssertEqual(page.string, expected)
    }
}

struct TestFiles: LeafFiles {
    var files: [String: String]
    var lock: Lock

    init() {
        files = [:]
        lock = .init()
    }

    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let file = self.files[path] {
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            buffer.writeString(file)
            return eventLoop.makeSucceededFuture(buffer)
        } else {
            return eventLoop.makeFailedFuture(LeafError(.noTemplateExists(path)))
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
