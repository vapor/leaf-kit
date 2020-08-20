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
        1: raw(ByteBuffer: 5B)
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
        1: raw(ByteBuffer: 5B)
        2: else:
        3: raw(ByteBuffer: 5B)
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
           0: raw(ByteBuffer: 13B)
           1: for($:names):
           2: scope(table: 2)
              0: raw(ByteBuffer: 13B)
              1: $:name
              2: raw(ByteBuffer: 5B)
           3: raw(ByteBuffer: 9B)
        2: else:
        3: raw(ByteBuffer: 9B)
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
        0: inline("header", leaf):
        1: scope(undefined)
        2: raw(ByteBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(ByteBuffer: 9B)
        6: inline("header", leaf):
        7: scope(undefined)
        """

        let expectation = """
        0: inline("header", leaf):
        1: raw(ByteBuffer: 12B)
        2: raw(ByteBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(ByteBuffer: 9B)
        6: inline("header", leaf):
        7: raw(ByteBuffer: 12B)
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
        0: export(title):
        1: string(Welcome)
        3: export(body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B)
           1: $:name
           2: raw(ByteBuffer: 2B)
        6: extend("base", leaf):
        7: scope(table: 2)
           0: extend("header", leaf):
           1: scope(table: 3)
              0: raw(ByteBuffer: 4B)
              1: import(header):
              2: scope(undefined)
              3: raw(ByteBuffer: 5B)
           2: raw(ByteBuffer: 8B)
           3: import(title):
           4: scope(undefined)
           5: raw(ByteBuffer: 9B)
           6: import(body):
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
        0: define(title):
        1: string(Welcome)
        3: define(body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B)
           1: $:name
           2: raw(ByteBuffer: 2B)
        6: inline("base", leaf):
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
        parameter(function(id: "lowercase"))
        parametersStart
        parameter(function(id: "first"))
        parametersStart
        parameter(variable(part: name))
        parameter(operator(Equality: ==))
        parameter(literal(String: "admin"))
        parametersEnd
        parametersEnd
        parameter(operator(Equality: ==))
        parameter(literal(String: "welcome"))
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
        parameter(literal(Int: 42))
        parametersEnd
        raw("</h1>")
        
        """

        let output = try lex(input).string
        XCTAssertEqual(output, expectation)
    }

    // Base2/8/10/16 lexing for Int constants, Base10/16 for Double
    func testNonDecimals() throws {
        let input = "#(0b0101010 0o052 42 0_042 0x02A 42.0 0_042.0 0x02A.0)"
        let expectation = """
        tagIndicator
        expression
        parametersStart
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Double: 42.0))
        parameter(literal(Double: 42.0))
        parameter(literal(Double: 42.0))
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
        0: export(title):
        1: string(Welcome)
        3: export(body):
        4: scope(table: 1)
           0: raw(ByteBuffer: 12B)
           1: $:name
           2: raw(ByteBuffer: 2B)
        6: extend("base", leaf):
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
        parameter(variable(part: foo))
        parameter(operator(Equality: ==))
        parameter(literal(Int: 40))
        parameterDelimiter
        parameter(variable(part: and))
        parameterDelimiter
        parameter(literal(String: "literal"))
        parameterDelimiter
        parameter(variable(part: and))
        parameterDelimiter
        parameter(variable(part: foo_bar))
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
        parameter(variable(part: foo))
        parametersEnd
        tagIndicator
        function("define")
        parametersStart
        parameter(variable(part: foo))
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
        parameter(variable(part: todo))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: todo))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: title))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: todo))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: user))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: name))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: first))
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
        test.files["/foo.leaf"] = "Hello #custom($prefix, name)"

//        struct CustomTag: LeafTag {
//            func render(_ ctx: LeafContext) throws -> LeafData {
//                let prefix = ctx.userInfo["prefix"] as? String ?? ""
//                let param = ctx.parameters.first?.string ?? ""
//                return .string(prefix + param)
//            }
//        }
        struct CustomTag: LeafFunction {
            static let callSignature: CallParameters = [
                .init(types: [.string], defaultValue: ""),
                .init(types: [.string], defaultValue: "") ]
            static let returns: Set<LeafDataType> = [.string]
            static let invariant: Bool = false
            
            func evaluate(_ params: CallValues) -> LeafData {
                .string(params[0].string! + params[1].string!) }
        }
        
        LeafConfiguration.entities.use(CustomTag(), asFunction: "custom")
        
        let renderer = TestRenderer(
//            tags: ["custom": CustomTag()],
            sources: .singleSource(test),
            userInfo: ["prefix": "bar"]
        )
        let view = try renderer.render(path: "foo", context: ["name": "vapor"]).wait()

        XCTAssertEqual(view.string, "Hello barvapor")
    }

    func testImportResolve() {
        var test = TestFiles()
        test.files["/a.leaf"] = """
        #export(variable):Hello#endexport
        #extend("b")
        """
        test.files["/b.leaf"] = """
        #import(variable)
        """

        let renderer = TestRenderer(sources: .singleSource(test))

        do {
            let output = try renderer.render(path: "a").wait().string
            XCTAssertEqual(output, "\nHello")
        } catch {
            let e = error as! LeafError
            XCTFail(e.localizedDescription)
        }
    }

    func testCacheSpeedLinear() {
        let iterations = 1_000
        var dur: Double = 0
        var ser: Double = 0
        var stop: Double = 0
        self.measure {
            let start = Date()
            let result = self._testCacheSpeedLinear(templates: 10, iterations: iterations)
            dur += result.0
            ser += result.1
            stop += start.distance(to: Date())
        }
        dur /= 10
        ser /= 10
        stop /= 10
        print("Linear Cache Speed: \(iterations) render")
        print("\(String(format:"%.2f%%", 100.0*(stop-dur)/stop)) test overhead")
        print("\(dur.formatSeconds) avg/test: \((dur/Double(iterations)).formatSeconds)/\(ser.formatSeconds) pipe:serialize/iteration")
    }

    func _testCacheSpeedLinear(templates: Int, iterations: Int) -> (Double, Double) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var test = TestFiles()

//        for name in 1...templates { test.files["/\(name).leaf"] = """
//        #lowercased(\"Template /\(name).leaf\")"
//        #uppercased(\"Template /\(name).leaf\")"
//        #(true == 5 + variable)
//        #(uppercased(variable))
//        """ }
        for name in 1...templates { test.files["/\(name).leaf"] = "#lowercased(\"Template /\(name).leaf\")" }
//        for name in 1...templates { test.files["/\(name).leaf"] = "Template /\(name).leaf\"" }
        let renderer = TestRenderer(
            sources: .singleSource(test),
            eventLoop: group.next(),
            tasks: iterations
        )

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            renderer.r.eventLoop.makeSucceededFuture(template).flatMap {
                renderer.render(path: $0, context: [:])
            }.whenComplete {
                switch $0 {
                    case .failure(let e): XCTFail(e.localizedDescription)
                    case .success: renderer.finishTask()
                }
            }
        }

        // Sleep 1 µs per queued task
        while !renderer.isDone { usleep(UInt32(renderer.queued)) }
        let duration = renderer.lap
        var serialize = (renderer.r.cache as! DefaultLeafCache).cache.values
                        .reduce(into: Double.init(0)) { $0 += $1.info.averages.exec }
        serialize /= Double((renderer.r.cache as! DefaultLeafCache).cache.values.count)

//        (renderer.r.cache as! DefaultLeafCache).cache.values.forEach {
//            let avg = $0.info.averages
//            let max = $0.info.maximums
//            let summary = """
//            \($0.key): \($0.info.touches) cache hits
//                Execution Time: \(avg.exec.formatSeconds) average, \(max.exec.formatSeconds) maximum
//               Serialized Size: \(avg.size.formatBytes) average, \(max.size.formatBytes) maximum
//            """
//            print(summary)
//        }

        group.shutdownGracefully { _ in XCTAssertEqual(renderer.r.cache.count, templates) }
        return (duration, serialize)
    }

    func testCacheSpeedRandom() {
        let iterations = 1_000
        var dur: Double = 0
        var ser: Double = 0
        var stop: Double = 0
        self.measure {
            let start = Date()
            // layer1 > layer2 > layer3
            let result = self._testCacheSpeedRandom(layer1: 100, layer2: 20, layer3: 10, iterations: iterations)
            dur += result.0
            ser += result.1
            stop += start.distance(to: Date())
        }
        dur /= 10
        ser /= 10
        stop /= 10
        print("Random Cache Speed: \(iterations) render")
        print("\(String(format:"%.2f%%", 100.0*(stop-dur)/stop)) test overhead")
        print("\(dur.formatSeconds) avg/test: \((dur/Double(iterations)).formatSeconds)/\(ser.formatSeconds) pipe:serialize/iteration")
    }

    func _testCacheSpeedRandom(layer1: Int,
                               layer2: Int,
                               layer3: Int,
                               iterations: Int) -> (Double, Double) {
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
            eventLoop: group.next(),
            tasks: iterations
        )

        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count { template = hitList.removeFirst() }
            else { template = allKeys[Int.random(in: 0 ..< totalTemplates)] }
            renderer.r.eventLoop.makeSucceededFuture(template).flatMap {
                renderer.render(path: $0, context: [:])
            }.whenComplete {
                switch $0 {
                    case .failure(let e): XCTFail(e.localizedDescription)
                    case .success: renderer.finishTask()
                }
            }
        }

        // Sleep 1 µs per queued task
        while !renderer.isDone { usleep(UInt32(renderer.queued)) }
        let duration = renderer.lap
        var serialize = (renderer.r.cache as! DefaultLeafCache).cache.values
                        .reduce(into: Double.init(0)) { $0 += $1.info.averages.exec }
        serialize /= Double((renderer.r.cache as! DefaultLeafCache).cache.values.count)

//        (renderer.r.cache as! DefaultLeafCache).cache.values.forEach {
//            let avg = $0.info.averages
//            let max = $0.info.maximums
//            let summary = """
//            \($0.key): \($0.info.touches) cache hits
//                Execution Time: \(avg.exec.formatSeconds) average, \(max.exec.formatSeconds) maximum
//               Serialized Size: \(avg.size.formatBytes) average, \(max.size.formatBytes) maximum
//            """
//            print(summary)
//        }

        group.shutdownGracefully { _ in XCTAssertEqual(renderer.r.cache.count, layer1+layer2+layer3) }
        return (duration, serialize)
    }

    func testImportParameter() throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
        #define(adminValue, admin)
        #inline("parameter")
        """
        test.files["/delegate.leaf"] = """
        #define(delegated, false || bypass)
        #inline("parameter")
        """
        test.files["/parameter.leaf"] = """
        #if(evaluate(adminValue)):
            Hi Admin
        #elseif(evaluate(delegated)):
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
