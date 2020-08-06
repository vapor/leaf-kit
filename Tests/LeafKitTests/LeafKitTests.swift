import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class ParserTests: LeafTestClass {
    func testParsingNesting() throws {
        let input = """
        #if(lowercased(((name.first == "admin"))) == "welcome"):
        foo
        #endif
        """
        
        let expectation = """
        0: if([lowercased([$:name.first == string(admin)]) == string(welcome)]):
        1: raw(ByteBuffer: 5B))
        """

        try XCTAssertEqual(parse(input).terse, expectation)
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
        0: if($:foo):
        1: raw(ByteBuffer: 5B))
        2: else():
        3: raw(ByteBuffer: 5B))
        """

        try XCTAssertEqual(parse(input).terse, expectation)
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
        0: if($:sayhello):
        1: scope(table: 1)
           0: raw(ByteBuffer: 13B))
           1: for($:names):
           2: scope(table: 2)
              0: raw(ByteBuffer: 13B))
              1: $:name
              2: raw(ByteBuffer: 5B))
           3: raw(ByteBuffer: 9B))
        2: else():
        3: raw(ByteBuffer: 9B))
        """

        try XCTAssertEqual(parse(input).terse, expectation)
    }

    func testUnresolvedAST() throws {
        let base = """
        #inline("header")
        <title>#evaluate(title)</title>
        #evaluate(body)
        """

        try XCTAssertFalse(parse(base).requiredFiles.isEmpty,
                           "Unresolved template")
    }

    func testInsertResolution() throws {
        let header = """
        <h1>Hi!</h1>
        """
        let base = """
        #inline("header")
        <title>#evaluate(title)</title>
        #inline("header")
        """
        
        let preinline = """
        0: inline(string(header)):
        1: scope(undefined)
        2: raw(ByteBuffer: 8B))
        3: evaluate($:title):
        4: scope(undefined)
        5: raw(ByteBuffer: 9B))
        6: inline(string(header)):
        7: scope(undefined)
        """
        
        let expectation = """
        0: inline(string(header)):
        1: scope(table: 1)
           0: raw(ByteBuffer: 12B))
        2: raw(ByteBuffer: 8B))
        3: evaluate($:title):
        4: scope(undefined)
        5: raw(ByteBuffer: 9B))
        6: inline(string(header)):
        7: scope(table: 1)
           0: raw(ByteBuffer: 12B))
        """

        var baseAST = try parse(base, name: "base")
        
        XCTAssertEqual(baseAST.terse, preinline)
        let headerAST = try parse(header, name: "header")
        baseAST.inline(ast: headerAST)
        
        XCTAssertEqual(baseAST.terse, expectation)
    }

    func testDocumentResolveExtend() throws {
        let header = """
        <h1>#import(header)</h1>
        """

        let base = """
        #extend("header")
        <title>#import(title)</title>
        #import(body)
        """

        let home = """
        #export(title, "Welcome")
        #export(body):
            Hello, #(name)!
        #endexport
        #extend("base")
        """
        
        let expectation = """
        0: export($:title, string(Welcome)):
        1: string(Welcome)
        3: export($:body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B))
           1: $:name
           2: raw(ByteBuffer: 2B))
        6: extend(string(base)):
        7: scope(table: 2)
           0: extend(string(header)):
           1: scope(table: 3)
              0: raw(ByteBuffer: 4B))
              1: import($:header):
              2: scope(undefined)
              3: raw(ByteBuffer: 5B))
           2: raw(ByteBuffer: 8B))
           3: import($:title):
           4: scope(undefined)
           5: raw(ByteBuffer: 9B))
           6: import($:body):
           7: scope(undefined)
        """
        
        let headerAST = try parse(header, name: "header")
        var baseAST = try parse(base, name: "base")
        var homeAST = try parse(home, name: "home")
    
        baseAST.inline(ast: headerAST)
        homeAST.inline(ast: baseAST)
        
        XCTAssertEqual(homeAST.terse, expectation)
    }

    func testCompileExtend() throws {
        let input = """
        #define(title, "Welcome")
        #define(body):
            Hello, #(name)!
        #enddefine
        #inline("base")
        """

        let expectation = """
        0: define($:title, string(Welcome)):
        1: string(Welcome)
        3: define($:body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B))
           1: $:name
           2: raw(ByteBuffer: 2B))
        6: inline(string(base)):
        7: scope(undefined)
        """

        try XCTAssertEqual(parse(input).terse, expectation)
    }
    
    func testScopingAndMethods() throws {
        let input = """
        #(x + $x + $context.x + $server.x)
        #($server.baseURL.hasPrefix("www") == true)
        #(array[0] + dictionary["key"])
        #($server.domain[$request.cname])
        """

        let expectation = """
        0: [$:x + [$x + [$context:x + $server:x]]]
        2: [hasPrefix($server:baseURL, string(www)) == true]
        4: [[$:array [] int(0)] + [$:dictionary [] string(key)]]
        6: [$server:domain [] $request:cname]
        """

        try XCTAssertEqual(parse(input).terse, expectation)
    }
}

final class LexerTests: LeafTestClass {
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
        function("if")
        parametersStart
        param(function(id: "lowercase"))
        parametersStart
        param(function(id: "first"))
        parametersStart
        param(variable(part: name))
        param(operator(Equality: ==))
        param(literal(String: "admin"))
        parametersEnd
        parametersEnd
        param(operator(Equality: ==))
        param(literal(String: "welcome"))
        parametersEnd
        blockIndicator
        raw("\\nfoo\\n")
        tagIndicator
        function("endif")

        """

        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }

    func testConstant() throws {
        let input = "<h1>#(42)</h1>"
        let expectation = """
        raw("<h1>")
        tagIndicator
        expression
        parametersStart
        param(literal(Int: 42))
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
        let input = "#(0b0101010 0o052 42 0_042 0x02A 42.0 0_042.0 0x02A.0)"
        let expectation = """
        tagIndicator
        expression
        parametersStart
        param(literal(Int: 42))
        param(literal(Int: 42))
        param(literal(Int: 42))
        param(literal(Int: 42))
        param(literal(Int: 42))
        param(literal(Double: 42.0))
        param(literal(Double: 42.0))
        param(literal(Double: 42.0))
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

    // deactivated because changing tagIndicator, for some reason, is causing a data race
    func testTagIndicator() throws {
        Character.tagIndicator = "🤖"
        let input = """
        🤖export(title, "Welcome")
        🤖export(body):
            Hello, 🤖(name)!
        🤖endexport
        🤖extend("base")
        """

        let expectation = """
        0: export($:title, string(Welcome)):
        1: string(Welcome)
        3: export($:body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B))
           1: $:name
           2: raw(ByteBuffer: 2B))
        6: extend(string(base)):
        7: scope(undefined)
        """

        try! XCTAssertEqual(parse(input).terse, expectation)
        Character.tagIndicator = .octothorpe
    }

    func testParameters() throws {
        let input = "#(foo == 40, and, \"literal\", and, foo_bar)"
        let expectation = """
        tagIndicator
        expression
        parametersStart
        param(variable(part: foo))
        param(operator(Equality: ==))
        param(literal(Int: 40))
        parameterDelimiter
        param(variable(part: and))
        parameterDelimiter
        param(literal(String: "literal"))
        parameterDelimiter
        param(variable(part: and))
        parameterDelimiter
        param(variable(part: foo_bar))
        parametersEnd

        """
        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }

    func testTags() throws {
        let input = """
        #enddefine
        #define()
        #define():
        #define(foo)
        #define(foo):
        """
        let expectation = """
        tagIndicator
        function("enddefine")
        tagIndicator
        function("define")
        parametersStart
        parametersEnd
        tagIndicator
        function("define")
        parametersStart
        parametersEnd
        blockIndicator
        tagIndicator
        function("define")
        parametersStart
        param(variable(part: foo))
        parametersEnd
        tagIndicator
        function("define")
        parametersStart
        param(variable(part: foo))
        parametersEnd
        blockIndicator

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
        expression
        parametersStart
        param(variable(part: todo))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        param(variable(part: todo))
        param(operator(Scoping Accessor: .))
        param(variable(part: title))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        param(variable(part: todo))
        param(operator(Scoping Accessor: .))
        param(variable(part: user))
        param(operator(Scoping Accessor: .))
        param(variable(part: name))
        param(operator(Scoping Accessor: .))
        param(variable(part: first))
        parametersEnd
        
        """
        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }
}

final class LeafKitTests: LeafTestClass {
    func testNestedEcho() throws {
        let input = """
        Todo: #(todo.title)
        """
        let view = try render(input, ["todo": ["title": "Leaf!"]])
        XCTAssertEqual(view, "Todo: Leaf!")
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
            self._testCacheSpeedLinear(templates: 10, iterations: 1_000_000)
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

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            renderer.render(path: template).whenComplete { _ in renderer.finishTask() }
        }
        
        // Sleep 10 µs per queued task
        while !renderer.isDone { usleep(10 * UInt32(renderer.queued)) }
        group.shutdownGracefully { _ in XCTAssertEqual(renderer.r.cache.count, templates) }
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

        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count { template = hitList.removeFirst() }
            else { template = allKeys[Int.random(in: 0 ..< totalTemplates)] }
            renderer.render(path: template).whenComplete { _ in renderer.finishTask() }
        }

        while !renderer.isDone { usleep(10) }
        group.shutdownGracefully { _ in XCTAssertEqual(renderer.r.cache.count, layer1+layer2+layer3) }
    }

    func testImportParameter() throws {
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
        
        let normalPage = try renderer.render(path: "base", context: ["admin": false]).wait()
        let adminPage = try renderer.render(path: "base", context: ["admin": true]).wait()
        let delegatePage = try renderer.render(path: "delegate", context: ["bypass": true]).wait()
        XCTAssertEqual(normalPage.string.trimmingCharacters(in: .whitespacesAndNewlines), "No Access")
        XCTAssertEqual(adminPage.string.trimmingCharacters(in: .whitespacesAndNewlines), "Hi Admin")
        XCTAssertEqual(delegatePage.string.trimmingCharacters(in: .whitespacesAndNewlines), "Also an admin")
    }
    
    func testDeepResolve() {
        var test = TestFiles()
        test.files["/a.leaf"] = """
        #for(a in b):#if(false):Hi#elseif(true && false):Hi#else:#export(derp):DEEP RESOLUTION #(a)#endexport#extend("b")#endif#endfor
        """
        test.files["/b.leaf"] = """
        #import(derp)

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
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
        let renderer = TestRenderer(
            configuration: .init(rootDirectory: templateFolder),
            sources: .singleSource(NIOLeafFiles(fileio: fileio,
                                                limits: .default,
                                                sandboxDirectory: templateFolder,
                                                viewDirectory: templateFolder + "SubTemplates/")),
            eventLoop: group.next()
        )
        
        renderer.render(path: "test").whenComplete { _ in renderer.finishTask() }
        renderer.render(path: "../test").whenComplete { _ in renderer.finishTask() }
        renderer.render(path: "../../test").whenComplete { result in
            renderer.finishTask()
            if case .failure(let e) = result, let err = e as? LeafError {
                XCTAssert(err.localizedDescription.contains("Attempted to escape sandbox"))
            } else { XCTFail() }
        }
        renderer.render(path: ".test").whenComplete { result in
            renderer.finishTask()
            if case .failure(let e) = result, let err = e as? LeafError {
                XCTAssert(err.localizedDescription.contains("Attempted to access .test"))
            } else { XCTFail() }
        }
        
        while !renderer.isDone { usleep(10) }
        try group.syncShutdownGracefully()
        try threadPool.syncShutdownGracefully()
    }
    
    func testMultipleSources() throws {
        var sourceOne = TestFiles()
        var sourceTwo = TestFiles()
        var hiddenSource = TestFiles()
        sourceOne.files["/a.leaf"] = "This file is in sourceOne"
        sourceTwo.files["/b.leaf"] = "This file is in sourceTwo"
        hiddenSource.files["/c.leaf"] = "This file is in hiddenSource"
        
        let multipleSources = LeafSources()
        try! multipleSources.register(using: sourceOne)
        try! multipleSources.register(source: "sourceTwo", using: sourceTwo)
        try! multipleSources.register(source: "hiddenSource", using: hiddenSource, searchable: false)
        
        let unsearchableSources = LeafSources()
        try! unsearchableSources.register(source: "unreachable", using: sourceOne, searchable: false)
        
        let goodRenderer = TestRenderer(sources: multipleSources)
        let emptyRenderer = TestRenderer(sources: unsearchableSources)
        
        XCTAssert(goodRenderer.r.sources.all.contains("sourceTwo"))
        
        XCTAssert(emptyRenderer.r.sources.searchOrder.isEmpty)

        let output1 = try goodRenderer.render(path: "a").wait().string
        XCTAssert(output1.contains("sourceOne"))
        let output2 = try goodRenderer.render(path: "b").wait().string
        XCTAssert(output2.contains("sourceTwo"))

        do { try XCTFail(goodRenderer.render(path: "c").wait().string) }
        catch {
            let error = error as! LeafError
            XCTAssert(error.localizedDescription.contains("No template found"))
        }
        
        let output3 = try goodRenderer.render(source: "hiddenSource", path: "c").wait().string
        XCTAssert(output3.contains("hiddenSource"))
        
        do { try XCTFail(emptyRenderer.render(path: "c").wait().string) }
        catch {
            let error = error as! LeafError
            XCTAssert(error.localizedDescription.contains("No searchable sources exist"))
        }
    }
}
