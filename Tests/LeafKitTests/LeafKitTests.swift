import XCTest
import NIOConcurrencyHelpers
import Foundation
@testable import LeafKit

final class ParserTests: LeafTestClass {
    func testParsingNesting() throws {
        let input = """
        #if((name.first == "admin").lowercased() == "welcome"):
        foo
        #endif
        """

        let expectation = """
        0: if([lowercased([$:name.first == string(admin)]) == string(welcome)]):
        1: raw(LeafBuffer: 5B)
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
        1: raw(LeafBuffer: 5B)
        2: else:
        3: raw(LeafBuffer: 5B)
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
           0: raw(LeafBuffer: 13B)
           1: for($:names):
           2: scope(table: 2)
              0: raw(LeafBuffer: 13B)
              1: $:name
              2: raw(LeafBuffer: 5B)
           3: raw(LeafBuffer: 9B)
        2: else:
        3: raw(LeafBuffer: 9B)
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
        2: raw(LeafBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(LeafBuffer: 9B)
        6: inline("header", leaf):
        7: scope(undefined)
        """

        let expectation = """
        0: inline("header", leaf):
        1: raw(LeafBuffer: 12B)
        2: raw(LeafBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(LeafBuffer: 9B)
        6: inline("header", leaf):
        7: raw(LeafBuffer: 12B)
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
        #export(title = "Welcome")
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
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
        6: extend("base", leaf):
        7: scope(table: 2)
           0: extend("header", leaf):
           1: scope(table: 3)
              0: raw(LeafBuffer: 4B)
              1: import(header):
              2: scope(undefined)
              3: raw(LeafBuffer: 5B)
           2: raw(LeafBuffer: 8B)
           3: import(title):
           4: scope(undefined)
           5: raw(LeafBuffer: 9B)
           6: import(body):
           7: scope(undefined)
        """

        let headerAST = try parse(header, name: "header")
        var baseAST = try parse(base, name: "base")
        var homeAST = try parse(home, name: "home", options: [.parseWarningThrows(false)])

        baseAST.inline(ast: headerAST)
        homeAST.inline(ast: baseAST)

        XCTAssertEqual(homeAST.terse, expectation)
    }

    func testCompileExtend() throws {
        let input = """
        #define(title = "Welcome")
        #define(body):
            Hello, #(name)!
        #enddefine
        #inline("base")
        #title()
        #implictEval()
        """

        let expectation = """
         0: define(title):
         1: string(Welcome)
         3: define(body):
         4: scope(table: 1)
            0: raw(LeafBuffer: 12B)
            1: $:name
            2: raw(LeafBuffer: 2B)
         6: inline("base", leaf):
         7: scope(undefined)
         9: evaluate(title):
        10: scope(undefined)
        12: evaluate(implictEval):
        13: scope(undefined)
        """

        let ast = try parse(input, options: [.parseWarningThrows(false)])
        XCTAssertEqual(ast.terse, expectation)
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
        2: [hasPrefix($server:baseURL, string(www)) == bool(true)]
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

    func testTagIndicator() throws {
        Character.tagIndicator = "🤖"
        let input = """
        🤖let(title = "Welcome")
        🤖export(body):
            Hello, 🤖(name)!
        🤖endexport
        🤖extend("base")
        """

        let expectation = """
        0: [let $:title string(Welcome)]
        2: export(body):
        3: scope(table: 1)
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
        5: extend("base", leaf):
        6: scope(undefined)
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

    func testRendererContext() throws {
        struct CustomTag: LeafUnsafeEntity, StringReturn {
            static var callSignature: [LeafCallParameter]  {[.string]}
            
            var unsafeObjects: UnsafeObjects? = nil
            var prefix: String? { unsafeObjects?["prefix"] as? String }
            
            func evaluate(_ params: LeafCallValues) -> LeafData {
                .string((prefix ?? "") + params[0].string!) }
        }
        
        LeafConfiguration.entities.use(CustomTag(), asFunction: "custom")
        
        let test = LeafTestFiles()
        test.files["/foo.leaf"] = "Hello #custom(name)"
        let renderer = TestRenderer(sources: .singleSource(test))
        
        var baseContext: LeafRenderer.Context = ["name": "vapor"]
        var moreContext: LeafRenderer.Context = [:]
        try moreContext.register(object: "bar", toScope: "prefix", type: .unsafe)
        try baseContext.overlay(moreContext)
        
        let view = try renderer.render(path: "foo", context: baseContext).wait()

        XCTAssertEqual(view.string, "Hello barvapor")
    }

    func testImportResolve() {
        let test = LeafTestFiles()
        test.files["/a.leaf"] = """
        #export(value = "Hello")
        #extend("b")
        """
        test.files["/b.leaf"] = """
        #import(value)
        """

        let renderer = TestRenderer(sources: .singleSource(test))

        do {
            let output = try renderer.render(path: "a", options: [.parseWarningThrows(false)]).wait().string
            XCTAssertEqual(output, "Hello")
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
            let result = self._testCacheSpeedLinear(templates: 50, iterations: iterations)
            dur += result.0
            ser += result.1
            stop += start +-> Date()
        }
        dur /= 10
        ser /= 10
        stop /= 10
        print("Linear Cache Speed: \(iterations) render")
        print("\(String(format:"%.2f%%", 100.0*(stop-dur)/stop)) test overhead")
        print("\(dur.formatSeconds()) avg/test: \((dur/Double(iterations)).formatSeconds()):\(ser.formatSeconds()) pipe:serialize/iteration")
    }

    func _testCacheSpeedLinear(templates: Int, iterations: Int) -> (Double, Double) {
        let threads = min(System.coreCount, 4)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
        let test = LeafTestFiles()

        for name in 1...templates { test.files["/\(name).leaf"] = "#Date(Timestamp() + \((-1000000...1000000).randomElement()!).0)" }
//        for name in 1...templates { test.files["/\(name).leaf"] = "Template /\(name).leaf\"" }
        let per = iterations / threads
        var left = iterations
        let renderers = (1...threads).map { x -> TestRenderer in
            left -= x != threads ? per : 0
            return TestRenderer(sources: .singleSource(test),
                                eventLoop: group.next(),
                                tasks: x != threads ? per : left)
        }

        for iteration in 1...iterations {
            let which = iteration.remainderReportingOverflow(dividingBy: threads).partialValue
            let template = String((iteration % templates) + 1)
            renderers[which].r.eventLoop.makeSucceededFuture(template).flatMap {
                renderers[which].render(path: $0, context: ["iteration": iteration.leafData])
            }.whenComplete {
                renderers[which].finishTask()
                if case .failure(let e) = $0 { XCTFail(e.localizedDescription) }
            }
        }

        // Sleep 1 µs per queued task
        while let x = renderers.first(where: {!$0.isDone}) { usleep(UInt32(x.queued)) }
        let duration = renderers.reduce(into: Double.init(0), {$0 += $1.lap}) / Double(threads)
        var serialize = renderers.map {
            ($0.r.cache as! DefaultLeafCache).cache.values
                .reduce(into: Double.init(0)) { $0 += $1.info.touch.execAvg }
        }.reduce(into: 0, { $0 += $1 })
        serialize /= Double(templates * threads)

        try! group.syncShutdownGracefully()
        return (duration, serialize)
    }

    func testCacheSpeedRandom() {
        let iterations = 130
        var dur: Double = 0
        var ser: Double = 0
        var stop: Double = 0
        self.measure {
            let start = Date()
            // layer1 > layer2 > layer3
            let result = self._testCacheSpeedRandom(layer1: 100, layer2: 20, layer3: 10, iterations: iterations)
            dur += result.0
            ser += result.1
            stop += start +-> Date()
        }
        dur /= 10
        ser /= 10
        stop /= 10
        print("Random Cache Speed: \(iterations) render")
        print("\(String(format:"%.2f%%", 100.0*(stop-dur)/stop)) test overhead")
        print("\(dur.formatSeconds()) avg/test: \((dur/Double(iterations)).formatSeconds())/\(ser.formatSeconds()) pipe:serialize/iteration")
    }

    func _testCacheSpeedRandom(layer1: Int,
                               layer2: Int,
                               layer3: Int,
                               iterations: Int) -> (Double, Double) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let test = LeafTestFiles()

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
            .reduce(into: Double.init(0)) { $0 += $1.info.touch.execAvg }
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
        let test = LeafTestFiles()
        test.files["/base.leaf"] = """
        #define(adminValue = admin)
        #inline("parameter")
        """
        test.files["/delegate.leaf"] = """
        #define(delegated = false || bypass)
        #inline("parameter")
        """
        test.files["/parameter.leaf"] = """
        #if(evaluate(adminValue ?? false)):
            Hi Admin
        #elseif(evaluate(delegated ?? false)):
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

    func testDeepResolve() throws {
        let test = LeafTestFiles()
        test.files["/a.leaf"] = """
        #for(a in b):
        #if(false):
        Hi
        #elseif(true && false):
        Hi
        #else:
        #export(derp):
        DEEP RESOLUTION #(a)
        #endexport
        #extend("b")
        #endif
        #endfor
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

        let page = try renderer.render(path: "a", context: .init(["b":["1","2","3"]])).wait()
        XCTAssertEqual(page.string, expected)
    }

    func testFileSandbox() throws {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileio = NonBlockingFileIO(threadPool: threadPool)
        let files = NIOLeafFiles(fileio: fileio,
                                 limits: .default,
                                 sandboxDirectory: templateFolder,
                                 viewDirectory: templateFolder + "SubTemplates/")
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        let renderer = TestRenderer(sources: .singleSource(files), eventLoop: group.next())

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
        let sourceOne = LeafTestFiles()
        let sourceTwo = LeafTestFiles()
        let hiddenSource = LeafTestFiles()
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
    
    func testInline() throws {
        LKROption.missingVariableThrows = false
        let template = """
        #(var variable = 10)
        #inline("external", as: raw)
        #inline("external", as: leaf)
        #inline("external")
        """
        
        let testFiles = LeafTestFiles()
        testFiles.files = ["/template.leaf": template,
                           "/external.leaf": "#(variable)\n",
                           "/uncachedraw.leaf": "#inline(\"excessiveraw.txt\", as: raw)",
                           "/excessiveraw.txt": .init(repeating: ".",
                                                      count: Int(LKROption.embeddedASTRawLimit) + 1)]
        
        let expected = """
        #(variable)
        10
        10

        """
                
        let renderer = TestRenderer(sources: .singleSource(testFiles))
        let output = try renderer.render(path: "template").wait().string
        let info = try renderer.r.info(for: "template").wait()!
        XCTAssertEqual(output, expected)
        XCTAssertTrue(info.resolved)
        
        let excessive = try renderer.render(path: "uncachedraw").wait().string
        let ast = (renderer.r.cache as! DefaultLeafCache).retrieve(.searchKey("uncachedraw"))!
        XCTAssertTrue(excessive.count == Int(LKROption.embeddedASTRawLimit) + 1)
        XCTAssertTrue(ast.info.requiredRaws.contains("excessiveraw.txt"))
    }
    
    func testDatesAndFormatters() throws {
        IntFormatterMap.defaultPlaces = 2
        DoubleFormatterMap.defaultPlaces = 3
        
        LKConf.entities.use(DoubleFormatterMap.seconds, asFunctionAndMethod: "formatSeconds")
        LKConf.entities.use(IntFormatterMap.bytes, asFunctionAndMethod: "formatBytes")
        
        let template = """
        Set start time
        #(let start = Timestamp())
        Bytes: #((500).formatBytes())
        Kilobytes: #((5_000).formatBytes())
        Megabytes: #((5_000_000).formatBytes())
        Gigabytes: #((5_000_000_000).formatBytes())
        unixEpoch: #Timestamp("unixEpoch")
        unixEpoch rebased: #Timestamp("unixEpoch", since: "unixEpoch")
        Formatted "referenceDate": #Date("referenceDate")
        Formatted "referenceDate": #Date("referenceDate", timeZone: "Europe/Athens")
        Fixed "unixEpoch": #Date(timeStamp: "unixEpoch",
                                 fixedFormat: "MM.dd.yyyy HH:mm",
                                 timeZone: "US/Eastern") EST
        Localized "unixEpoch": #Date(timeStamp: Timestamp("unixEpoch") + 2_500_000,
                                     localizedFormat: "MMddyyyy",
                                     locale: "en")
        """
        
        let expected = """
        Set start time
        Bytes: 500B
        Kilobytes: 4.88KB
        Megabytes: 4.77MB
        Gigabytes: 4.66GB
        unixEpoch: -978307200.0
        unixEpoch rebased: 0.0
        Formatted "referenceDate": 2001-01-01T00:00:00Z
        Formatted "referenceDate": 2001-01-01T02:00:00+02:00
        Fixed "unixEpoch": 12.31.1969 19:00 EST
        Localized "unixEpoch": 01/29/1970
        """
        
        let output = try render(template)
        print(output)
        try print(parse(template).terse)
        XCTAssertEqual(output, expected)
    }
    
    func testType() throws {
        let template = """
        #type(of: 0)
        #type(of: 0.0)
        #type(of: "0")
        #type(of: [0])
        #type(of: ["zero": 0])
        #(x.type())
        #if(x.type() == "String?"):x is an optional String#endif
        """
        
        let expected = """
        Int
        Double
        String
        Array
        Dictionary
        String?
        x is an optional String
        """
        
        let output = try render(template, ["x": .string(nil)])
        XCTAssertEqual(output, expected)
    }
    
    // FIXME: Catching assertion?!
    func _testRuntimeGuard() throws {
        _ = try render("Blahblahblah")
        LeafBuffer.intFormatter = {"\($0.description)"}
    }
    
    func _testRawBlock() throws {
        let template = """
        #raw():
        Body
            #raw():
            More Body #("and a" + variable)
            #endraw
        #endraw
        """
        
        let expected = """
        0: raw:
        1: scope(table: 1)
           0: raw(LeafBuffer: 10B)
           1: raw:
           2: scope(table: 2)
              0: raw(LeafBuffer: 15B)
              1: [string(and a) + $:variable]
              2: raw(LeafBuffer: 5B)
        """
        
        let parsed = try parse(template)
        XCTAssertEqual(parsed.terse, expected)
    }
    
    func testContexts() throws {
        var aContext: LeafRenderer.Context = [:]
        let myAPI = _APIVersioning("myAPI", (0,0,1))
        try aContext.register(object: myAPI, toScope: "api")
        try aContext.register(generators: myAPI.extendedVariables, toScope: "api")
                
        let template = """
        #if(!$api.isRelease && !override):#Error("This API is not vended publically")#endif
        #($api ? $api : throw(reason: "No API information"))
        Results!
        """
        let expected = """
        ["identifier": "myAPI", "isRelease": false, "version": ["major": 0, "minor": 0, "patch": 1]]
        Results!
        """
        
        try XCTAssertThrowsError(render(template, aContext))
        
        try aContext.setValue(at: "override", to: true)
        let output = try render(template, aContext)
        XCTAssertEqual(output, expected)
        
        myAPI.version.major = 1
        
        let retry = try render(template, aContext)
        XCTAssert(retry.contains("\"major\": 1"))
    }
    
    func testEncoderEncodable() throws {
        struct Test: Encodable, Equatable {
            let fieldOne: String = "One"
            let fieldTwo: Int = 2
            let fieldThree: Double = 3.0
            let fieldFour = ["One", "Two", "Three", "Four"]
            let fieldFive = ["a": "A", "b": "B", "c": "C"]
            
            static func ==(lhs: Test, rhs: Test) -> Bool { true }
        }
        
        let encoder = LKEncoder()
        let encodable = Test()
        try encodable.encode(to: encoder)
        
        let template = """
        #(test.fieldOne)
        #(test.fieldTwo)
        #(test.fieldThree)
        #(test.fieldFour)
        #(test.fieldFive)
        """
        
        let expected = """
        One
        2
        3.0
        ["One", "Two", "Three", "Four"]
        ["a": "A", "b": "B", "c": "C"]
        """
            
        let output = try render(template, .init(["test": encoder.leafData]))
        XCTAssertEqual(output, expected)
        
        let ctx = LeafRenderer.Context(encodable: ["test": encodable])!
        let direct = try render(template, ctx)
        XCTAssertEqual(direct, expected)
        
    }
    
    func testElideRenderOptionChanges() throws {
        XCTAssertEqual(LeafRenderer.Option.Case.allCases.count,
                       LeafRenderer.Option.allCases.count)
        XCTAssertEqual(LeafRenderer.Option.allCases.count, 7)
        var options: LeafRenderer.Options = .globalSettings
        XCTAssertEqual(options._storage.count, 0)
        options.update(.timeout(1.0))
        XCTAssertEqual(options._storage.count, 1)
        options.unset(.timeout)
        XCTAssertEqual(options._storage.count, 0)
    }
    
    func testRenderOptions() throws {
        let expected = "Original Template"
        let source = LeafTestFiles()
        source.files["/template.leaf"] = expected
        
        let renderer = LeafRenderer(cache: DefaultLeafCache(),
                                    sources: .singleSource(source),
                                    eventLoop: EmbeddedEventLoop())
        
        func render(bypass: Bool = false) throws -> String {
            try renderer.render(template: "template",
                                context: [:],
                                options: [.caching(bypass ? .bypass : .default)]).wait().string
        }
        
        try XCTAssertEqual(render(), expected)
        source.files["/template.leaf"] = "Updated Template"
        try XCTAssertEqual(render(), expected)
        try XCTAssertEqual(render(bypass: true), "Updated Template")
    }
    
    func testMisc() throws {
        LKConf.entities.use(IntIntToIntMap._min, asFunction: "min")
        LKConf.entities.use(IntIntToIntMap._max, asFunction: "max")
        try XCTAssertEqual(render("#min(1, 0)"), "0")
        try XCTAssertEqual(render("#max(1, 0)"), "1")
    }
    
    /// µ is 2byte with lower 0xB5 in UTF8, 1byte 0x9D in NeXT encoding
    func testEncoding() throws {
        let files = LeafTestFiles()
        files.files["/micro.leaf"] = "µ"
        files.files["/tau.leaf"] = "τ"
        let renderer = TestRenderer(sources: .singleSource(files))
        
        var utf8micro = try renderer.render(path: "micro", options: [.encoding(.utf8)]).wait()
        XCTAssertEqual(utf8micro.readBytes(length: 2)![1], 0xB5)
        
        var nextstepmicro = try renderer.render(path: "micro", options: [.encoding(.nextstep)]).wait()
        XCTAssertEqual(nextstepmicro.readBytes(length: 1)![0], 0x9D)
        
        var utf8tau = try renderer.render(path: "tau", options: [.encoding(.utf8)]).wait()
        XCTAssertEqual(utf8tau.readBytes(length: 2)![1], 0x84)
        
        try XCTAssertThrowsError(renderer.render(path: "tau", options: [.encoding(.nextstep)]).wait()) {
            XCTAssert(($0 as? LeafError)!.description.contains("`τ` is not encodable to `Western (NextStep)`"))
        }
    }
}

// MARK: For `testContexts()`
class _APIVersioning: LeafContextPublisher {
    init(_ a: String, _ b: (Int, Int, Int)) { self.identifier = a; self.version = b }
    
    let identifier: String
    var version: (major: Int, minor: Int, patch: Int)

    lazy private(set) var leafVariables: [String: LeafDataGenerator] = [
        "identifier" : .immediate(identifier),
        "version"    : .lazy(["major": self.version.major,
                              "minor": self.version.minor,
                              "patch": self.version.patch])
    ]
}

extension _APIVersioning {
    var extendedVariables: [String: LeafDataGenerator] {[
        "isRelease": .lazy(self.version.major > 0)
    ]}
}
