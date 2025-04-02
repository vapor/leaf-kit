@testable import LeafKit
import NIOCore
import NIOPosix
import XCTest

final class ParserTests: XCTestCase {
    func testParsingNesting() throws {
        let input = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """

        let expectation = """
        conditional:
          if([lowercase(first([name == "admin"])) == "welcome"]):
            raw("\\nfoo\\n")
        """

        let output = try parse(input).string
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

        let output = try parse(input).string
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
              expression[variable(name)]
              raw("\\n    ")
            raw("\\n    def\\n")
          else:
            raw("\\n    foo\\n")
        """

        let output = try parse(input).string
        XCTAssertEqual(output, expectation)
    }

    func testUnresolvedAST() throws {
        let base = """
        #extend("header")
        <title>#import("title")</title>
        #import("body")
        """

        let syntax = try parse(base)
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

        let output = baseResolvedAST.ast.string

        let expectation = """
        raw("<h1>Hi!</h1>\\n<title>")
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

        let output = homeResolved.ast.string
        let expectation = """
        raw("<h1>")
        import("header")
        raw("</h1>\\n<title>Welcome</title>\\n\\n        Hello, ")
        expression[variable(name)]
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
            expression[variable(name)]
            raw("!\\n    ")
          export("title"):
            expression[stringLiteral("Welcome")]
        """

        let output = try parse(input).string
        XCTAssertEqual(output, expectation)
    }
}

final class LexerTests: XCTestCase {
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

        let output = try lex(input).string
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

        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }

    func testNoWhitespace() throws {
        let input1 = "#if(!one||!two)"
        let input2 = "#if(!one || !two)"
        let input3 = "#if(! one||! two)"
        let input4 = "#if(! one || ! two)"

        let output1 = try lex(input1).string
        let output2 = try lex(input2).string
        let output3 = try lex(input3).string
        let output4 = try lex(input4).string
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

        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }

    func testEscaping() throws {
        // input is really '\#' w/ escaping
        let input = "\\#"
        let output = try lex(input).string
        XCTAssertEqual(output, "raw(\"#\")\n")
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
        let output = try lex(input).string
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

        let output = try lex(input).string
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
        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }
}

final class LeafKitTests: XCTestCase {
    func testNestedEcho() throws {
        let input = """
        Todo: #(todo.title)
        """
        var lexer = LeafLexer(name: "nested-echo", template: input)
        let tokens = try lexer.lex()
        var parser = LeafParser(name: "nested-echo", tokens: tokens)
        let ast = try parser.parse()
        var serializer = LeafSerializer(ast: ast, ignoreUnfoundImports: false)
        let view = try serializer.serialize(context: ["todo": ["title": "Leaf!"]])
        XCTAssertEqual(view.string, "Todo: Leaf!")
    }

    func testRendererContext() async throws {
        var test = TestFiles()
        test.files["/foo.leaf"] = "Hello #custom(name)"

        struct CustomTag: LeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                let prefix = ctx.userInfo["prefix"] as? String ?? ""
                let param = ctx.parameters.first?.string ?? ""
                return .string(prefix + param)
            }
        }

        let renderer = TestRenderer(
            tags: ["custom": CustomTag()],
            sources: .singleSource(test),
            userInfo: ["prefix": "bar"]
        )

        await XCTAssertEqualAsync(try await renderer.render(path: "foo", context: ["name": "vapor"]).string, "Hello barvapor")
    }

    func testImportResolve() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = """
            #extend("b"):
            #export("variable"):Hello#endexport
            #endextend
            """
            test.files["/b.leaf"] = """
            #import("variable")
            """

        let renderer = TestRenderer(sources: .singleSource(test))

        await XCTAssertEqualAsync(try await renderer.render(path: "a").string, "Hello")
    }

    #if !os(Android)
    func testCacheSpeedLinear() {
        self.measure {
            self._testCacheSpeedLinear(templates: 10, iterations: 100)
        }
    }

    func _testCacheSpeedLinear(templates: Int, iterations: Int) {
        let group = NIOSingletons.posixEventLoopGroup
        var test = TestFiles()

        for name in 1...templates { test.files["/\(name).leaf"] = "Template /\(name).leaf" }
        let renderer = TestRenderer(
            sources: .singleSource(test),
            eventLoop: group.any()
        )

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            _ = try? renderer.render(path: template).wait(); renderer.finishTask()
        }

        XCTAssertEqual(renderer.r.cache.count, templates)
    }

    func testCacheSpeedRandom() {
        self.measure {
            // layer1 > layer2 > layer3
            self._testCacheSpeedRandom(layer1: 100, layer2: 20, layer3: 10, iterations: 130)
        }
    }

    func _testCacheSpeedRandom(layer1: Int, layer2: Int, layer3: Int, iterations: Int) {
        let group = NIOSingletons.posixEventLoopGroup
        var test = TestFiles()

        for name in 1...layer3 { test.files["/\(name)-3.leaf"] = "Template \(name)"}
        for name in 1...layer2 { test.files["/\(name)-2.leaf"] = "Template \(name) -> #extend(\"\((name % layer3)+1)-3\")"}
        for name in 1...layer1 { test.files["/\(name).leaf"] = "Template \(name) -> #extend(\"\(Int.random(in: 1...layer2))-2\") & #extend(\"\(Int.random(in: 1...layer2))-2\")" }

        let allKeys: [String] = test.files.keys.map{ String($0.dropFirst().dropLast(5)) }.shuffled()
        var hitList = allKeys
        let totalTemplates = allKeys.count
        let ratio = iterations / allKeys.count

        let renderer = TestRenderer(
            sources: .singleSource(test),
            eventLoop: group.any()
        )

        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count { template = hitList.removeFirst() }
            else { template = allKeys[Int.random(in: 0 ..< totalTemplates)] }
            _ = try? renderer.render(path: template).wait(); renderer.finishTask()
        }

        XCTAssertEqual(renderer.r.cache.count, layer1 + layer2 + layer3)
    }
    #endif

    func testImportParameter() async throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
            #extend("parameter"):
                #export("admin", admin)
            #endextend
            """
        test.files["/delegate.leaf"] = """
            #extend("parameter"):
                #export("delegated", false || bypass)
            #endextend
            """
        test.files["/parameter.leaf"] = """
            #if(import("admin")):
                Hi Admin
            #elseif(import("delegated")):
                Also an admin
            #else:
                No Access
            #endif
            """

        let renderer = TestRenderer(sources: .singleSource(test))
        
        await XCTAssertEqualAsync(try await renderer.render(path: "base", context: ["admin": false]).string, "\n    No Access\n")
        await XCTAssertEqualAsync(try await renderer.render(path: "base", context: ["admin": true]).string, "\n    Hi Admin\n")
        await XCTAssertEqualAsync(try await renderer.render(path: "delegate", context: ["bypass": true]).string, "\n    Also an admin\n")
    }
    
    func testDeepResolve() async throws {
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

        let renderer = TestRenderer(sources: .singleSource(test))

        await XCTAssertEqualAsync(try await renderer.render(path: "a", context: ["b":["1","2","3"]]).string, expected)
    }

    // The #filePath trick this test relies on doesn't work in the Android CI because the build
    // machine is not the same box as the test machine; we'd need to turn the templates into working
    // resources for that. Disable for now.
    #if !os(Android)
    func testFileSandbox() async throws {
        let renderer = TestRenderer(
            configuration: .init(rootDirectory: templateFolder),
            sources: .singleSource(NIOLeafFiles(
                fileio: .init(threadPool: NIOSingletons.posixBlockingThreadPool),
                limits: .default,
                sandboxDirectory: templateFolder,
                viewDirectory: templateFolder + "/SubTemplates"
            )),
            eventLoop: NIOSingletons.posixEventLoopGroup.any()
        )
        
        await XCTAssertNoThrowAsync(try await renderer.render(path: "test"))
        await XCTAssertNoThrowAsync(try await renderer.render(path: "../test"))
        await XCTAssertThrowsErrorAsync(try await renderer.render(path: "../../test")) {
            XCTAssert(($0 as? LeafError)?.localizedDescription.contains("Attempted to escape sandbox") ?? false)
        }
        await XCTAssertThrowsErrorAsync(try await renderer.render(path: ".test")) {
            XCTAssert(($0 as? LeafError)?.localizedDescription.contains("Attempted to access .test") ?? false)
        }
        XCTAssert(renderer.isDone)
    }
    #endif

    func testMultipleSources() async throws {
        var sourceOne = TestFiles()
        var sourceTwo = TestFiles()
        sourceOne.files["/a.leaf"] = "This file is in sourceOne"
        sourceTwo.files["/b.leaf"] = "This file is in sourceTwo"

        let multipleSources = LeafSources()
        try multipleSources.register(using: sourceOne)
        try multipleSources.register(source: "sourceTwo", using: sourceTwo)

        let unsearchableSources = LeafSources()
        try unsearchableSources.register(source: "unreachable", using: sourceOne, searchable: false)

        let goodRenderer = TestRenderer(sources: multipleSources)
        let emptyRenderer = TestRenderer(sources: unsearchableSources)
        
        XCTAssert(goodRenderer.r.sources.all.contains("sourceTwo"))
        XCTAssert(emptyRenderer.r.sources.searchOrder.isEmpty)

        await XCTAssertAsync(try await goodRenderer.render(path: "a").string.contains("sourceOne"))
        await XCTAssertAsync(try await goodRenderer.render(path: "b").string.contains("sourceTwo"))

        await XCTAssertThrowsErrorAsync(try await goodRenderer.render(path: "c")) {
            XCTAssert(($0 as? LeafError)?.localizedDescription.contains("No template found") ?? false)
        }
        await XCTAssertThrowsErrorAsync(try await emptyRenderer.render(path: "c")) {
            XCTAssert(($0 as? LeafError)?.localizedDescription.contains("No searchable sources exist") ?? false)
        }
    }

    func testBodyRequiring() async throws {
        var test = TestFiles()
        test.files["/body.leaf"] = "#bodytag:test#endbodytag"
        test.files["/bodyError.leaf"] = "#bodytag:#endbodytag"
        test.files["/nobody.leaf"] = "#nobodytag"
        test.files["/nobodyError.leaf"] = "#nobodytag:test#endnobodytag"

        struct BodyRequiringTag: UnsafeUnescapedLeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                _ = try ctx.requireBody()
                return .string("Hello there")
            }
        }

        struct NoBodyRequiringTag: UnsafeUnescapedLeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                try ctx.requireNoBody()
                return .string("General Kenobi")
            }
        }

        let renderer = TestRenderer(
            tags: [
                "bodytag": BodyRequiringTag(),
                "nobodytag": NoBodyRequiringTag()
            ],
            sources: .singleSource(test)
        )

        await XCTAssertEqualAsync(try await renderer.render(path: "body", context: ["test":"ciao"]).string, "Hello there")
        await XCTAssertThrowsErrorAsync(try await renderer.render(path: "bodyError", context: [:]))

        await XCTAssertEqualAsync(try await renderer.render(path: "nobody", context: [:]).string, "General Kenobi")
        await XCTAssertThrowsErrorAsync(try await renderer.render(path: "nobodyError", context: [:]))
    }
}
