import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit
import NIO

final class LeafKitTests: XCTestCase {
    func testNestedEcho() throws {
        let input = """
        Todo: #(todo.title)
        """
        let rendered = try render(name: "nested-echo", input, ["todo": ["title": "Leaf!"]])
        XCTAssertEqual(rendered, "Todo: Leaf!")
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

        var tasks: [EventLoopFuture<ByteBuffer>] = []
        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            tasks.append(renderer.render(path: template))
        }

        let combine = EventLoopFuture<[ByteBuffer]>.reduce(into: [], tasks, on: group.next(), { arr, val in arr.append(val) })
        _ = try! combine.wait()

        XCTAssertEqual(renderer.r.cache.count, templates)
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

        var tasks: [EventLoopFuture<ByteBuffer>] = []
        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count { template = hitList.removeFirst() }
            else { template = allKeys[Int.random(in: 0 ..< totalTemplates)] }
            tasks.append(renderer.render(path: template))
        }

        let combine = EventLoopFuture<[ByteBuffer]>.reduce(into: [], tasks, on: group.next(), { arr, val in arr.append(val) })
        _ = try! combine.wait()

        XCTAssertEqual(renderer.r.cache.count, layer1+layer2+layer3)
    }

    func testDeepResolve() throws {
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

        let page = try renderer.render(path: "a", context: ["b":["1","2","3"]]).wait()
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

        var tasks: [EventLoopFuture<ByteBuffer>] = []
        tasks.append(renderer.render(path: "test"))
        tasks.append(renderer.render(path: "../test"))
        let escape = renderer.render(path: "../../test")
        escape.whenComplete { result in
            if case .failure(let e) = result, let err = e as? LeafError {
                XCTAssert(err.localizedDescription.contains("Attempted to escape sandbox"))
            } else { XCTFail() }
        }
        tasks.append(escape)
        let badAccess = renderer.render(path: ".test")
        tasks.append(badAccess)
        badAccess.whenComplete { result in
            if case .failure(let e) = result, let err = e as? LeafError {
                XCTAssert(err.localizedDescription.contains("Attempted to access .test"))
            } else { XCTFail() }
        }
        
        let combine = EventLoopFuture<[ByteBuffer]>.reduce(into: [], tasks, on: group.next(), { arr, val in arr.append(val) })
        _ = try? combine.wait()
    }
    
    func testMultipleSources() throws {
        var sourceOne = TestFiles()
        var sourceTwo = TestFiles()
        var hiddenSource = TestFiles()
        sourceOne.files["/a.leaf"] = "This file is in sourceOne"
        sourceTwo.files["/b.leaf"] = "This file is in sourceTwo"
        hiddenSource.files["/c.leaf"] = "This file is in hiddenSource"
        
        let multipleSources = LeafSources()
        try multipleSources.register(using: sourceOne)
        try multipleSources.register(source: "sourceTwo", using: sourceTwo)
        try multipleSources.register(source: "hiddenSource", using: hiddenSource, searchable: false)
        
        let unsearchableSources = LeafSources()
        try unsearchableSources.register(source: "unreachable", using: sourceOne, searchable: false)
        
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
