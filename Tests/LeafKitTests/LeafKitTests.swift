import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

// MARK: `[LeafToken]` Extension moved to TestHelpers.swift
// MARK: `testCodable` Test removed - not useful
// MARK: `UInt8.str()` Extension removed - unused

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
              variable(name)
              raw("\\n    ")
            raw("\\n    def\\n")
          else:
            raw("\\n    foo\\n")
        """

        let output = try parse(input).string
        XCTAssertEqual(output, expectation)
    }

// MARK: testCompile2 removed - exact duplicate of testCompile

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

        let output = try parse(input).string
        XCTAssertEqual(output, expectation)
    }

// MARK: `testPPP()` removed - pointless?
}

// MARK: PrintTests moved to TestHelpers.swift

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

        _ = try lex(home).description
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
        let output = try lex(input).string
        XCTAssertEqual(output, "raw(\"#\")\n")
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

        let output = try! parse(input).string
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

// MARK: `lex` helper function moved to TestHelpers.swift
// MARK: `parse` helper function moved to TestHelpers.swift

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
        _ = rawAlt.description
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
        let renderer = TestRenderer(
            configuration: .init(rootDirectory: templateFolder),
            sources: .singleSource(NIOLeafFiles(fileio: fileio)),
            eventLoop: group.next()
        )

        var buffer = try! renderer.render(path: "test").wait()
        let string = buffer.readString(length: buffer.readableBytes)!
        print(string)

        try threadPool.syncShutdownGracefully()
        try group.syncShutdownGracefully()
    }

    func testRendererContext() throws {
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
        let view = try renderer.render(path: "foo", context: [
            "name": "vapor"
        ]).wait()

        XCTAssertEqual(view.string, "Hello barvapor")
    }

// MARK: testCyclicalError() - moved to LeafErrorTests.swift
// MARK: testDependencyError() - moved to LeafErrorTests.swift

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

        let renderer = TestRenderer(sources: .singleSource(test))

        do {
            let output = try renderer.render(path: "a").wait().string
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
        let renderer = TestRenderer(
            sources: .singleSource(test),
            eventLoop: group.next()
        )

        let progressLock = Lock()
        var progress = 0
        var done = false
        var delay = 0

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            group.next()
                .submit { renderer.render(path: template) }
                .whenComplete { result in progressLock.withLock { progress += 1 } }
        }

        while !done {
            progressLock.withLock { delay = (iterations - progress) * 10 }
            guard delay == 0 else { usleep(UInt32(delay)); break }
            done = true
            group.shutdownGracefully { shutdown in
                guard shutdown == nil else { XCTFail("ELG shutdown issue"); return }
                XCTAssertEqual(renderer.r.cache.entryCount(), templates)
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

        let renderer = TestRenderer(
            sources: .singleSource(test),
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
                .submit { renderer.render(path: template) }
                .whenComplete { result in progressLock.withLock { progress += 1 } }
        }

        while !done {
            progressLock.withLock { delay = (iterations - progress) * 10  }
            guard delay == 0 else { usleep(UInt32(delay)); break }
            done = true
            group.shutdownGracefully { shutdown in
                guard shutdown == nil else { XCTFail("ELG shutdown issue"); return }
                XCTAssertEqual(renderer.r.cache.entryCount(), layer1+layer2+layer3)
            }
        }
    }

// MARK: testGH33() - moved to GHTests/VaporLeafKit.swift
// MARK: testGH50() - moved to GHTests/VaporLeafKit.swift

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

        let renderer = TestRenderer(sources: .singleSource(test))

        let page = try! renderer.render(path: "a", context: ["b":["1","2","3"]]).wait()
            XCTAssertEqual(page.string, expected)
    }
    
    func testFileSandbox() throws {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileio = NonBlockingFileIO(threadPool: threadPool)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let renderer = TestRenderer(
            configuration: .init(rootDirectory: templateFolder),
            sources: .singleSource(NIOLeafFiles(fileio: fileio,
                              limits: .default,
                              sandboxDirectory: templateFolder,
                              viewDirectory: templateFolder + "SubTemplates/")),
            eventLoop: group.next()
        )
        
        let progressLock = Lock()
        var progress = 4
        var done = false
        
        // TODO: needs a better test to prevent shutdown of renderer
        _ = renderer.render(path: "test").whenFailure { error in
            progressLock.withLock { progress -= 1 }
            let e = error as! LeafError
            XCTFail(e.localizedDescription)
        }
        _ = renderer.render(path: "../test").whenFailure { error in
            progressLock.withLock { progress -= 1 }
            let e = error as! LeafError
            XCTFail(e.localizedDescription)
        }
        _ = renderer.render(path: "../../test").whenFailure { error in
            progressLock.withLock { progress -= 1 }
            let e = error as! LeafError
            XCTAssert(e.localizedDescription.contains("Attempted to escape sandbox"))
        }
        _ = renderer.render(path: ".test").whenFailure { error in
            progressLock.withLock { progress -= 1 }
            let e = error as! LeafError
            XCTAssert(e.localizedDescription.contains("Attempted to access .test"))
        }
        
        while !done {
            progressLock.withLock {
                if progress == 0 { done = true }
            }
            if !done { usleep(UInt32(10)); break }
            try group.syncShutdownGracefully()
            try threadPool.syncShutdownGracefully()
        }
    }
    
    func testMultipleSources() throws {
        var sourceOne = TestFiles()
        var sourceTwo = TestFiles()
        var hiddenSource = TestFiles()
        sourceOne.files["/a.leaf"] = "This file is in sourceOne"
        sourceTwo.files["/b.leaf"] = "This file is in sourceTwo"
        hiddenSource.files["/c.leaf"] = "This file is in hiddenSource"

        let renderer = TestRenderer(sources: .singleSource(sourceOne))
        try! renderer.r.sources.register(source: "sourceTwo", using: sourceTwo)
        try! renderer.r.sources.register(source: "hiddenSource", using: hiddenSource, searchable: false)
        XCTAssert(renderer.r.sources.all.contains("sourceTwo"))
        
        let output1 = try renderer.render(path: "a").wait().string
        XCTAssert(output1.contains("sourceOne"))
        let output2 = try renderer.render(path: "b").wait().string
        XCTAssert(output2.contains("sourceTwo"))
        
        
        do {
            _ = try renderer.render(path: "c").wait().string
            XCTFail("hiddenSource should not be providing results")
        } catch {
            let e = error as! LeafError
            XCTAssert(e.localizedDescription.contains("No template found"))
        }
        
        let unsearchable = LeafSources()
        let emptyRenderer = TestRenderer(sources: unsearchable)
        XCTAssert(emptyRenderer.r.sources.searchOrder.isEmpty)
        
        do {
            _ = try emptyRenderer.render(path: "a").wait().string
            XCTFail("No sources should be searched")
        } catch {
            let e = error as! LeafError
            XCTAssert(e.localizedDescription.contains("No searchable sources exist"))
        }
    }
}

// MARK: - `TestFiles` moved to TestHelpers.swift
// MARK: `ByteBuffer.string` moved to TestHelpers.swift
// MARK: `templateFolder` moved to TestHelpers.swift
