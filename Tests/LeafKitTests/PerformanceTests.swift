import XCTest
import NIOConcurrencyHelpers
import Foundation
@testable import LeafKit

final class CachePerformanceTests: FullstackRendererTestCase {
    override var threads: Int { max(System.coreCount, 1) }
    var files: LeafMemorySource { source as! LeafMemorySource }
    var leafCache: DefaultLeafCache { cache as! DefaultLeafCache }
    
    override func setUp() { LKROption.caching.subtract(.autoUpdate) }
    
    func testCacheLinearSpeed() {
        var timer = Stopwatch()
        let start = Date()
        let iterations = threads * 1_250
        let templates = Int(pow(Double(iterations), 1.0 / 3.0)) * 5
        var touches: [(Double, Int)] = []
        
        self.measure {
            timer.lap()
            touches.append(_linear(templates, iterations))
            timer.lap(accumulate: true)
        }
        
        print((start +-> Date()).formatSeconds())
        let total = touches.reduce(into: (0.0, 0)) { $0.0 += $1.0; $0.1 += $1.1 }
        
        print("""
        Linear Cache Speed: \(iterations) renders of \(templates) templates
        -------------------------------------------------------------------
        Average \(timer.average) clock time / test
        Average \((total.0 / 10).formatSeconds()) CPU time / test
        Average \((total.0 / Double(total.1)).formatSeconds()) CPU time / render
        """)
    }
    
    /// Returns total cpu serialization time + call count
    func _linear(_ templates: Int, _ iterations: Int) -> (Double, Int) {
        var offset: Int { (-10_000_000...10_000_000).randomElement()! }
           
        (1...templates).forEach { files[String($0)] = "#Date(Timestamp() + \(offset).0)" }
        
        (1...iterations).forEach {
            renderBuffer("\(($0 % templates) + 1)").whenComplete {
                switch $0 {
                    case .failure(let e) : XCTFail(e.localizedDescription)
                    case .success        : XCTAssert(true)
                }
            }
        }
        
        waitTilDone()
        
        return leafCache.keys.map { leafCache.info(for: $0)!.touch }
                            .reduce(into: (0.0, 0)) {
                                $0.0 += $1.execAvg * Double($1.count)
                                $0.1 += Int($1.count)
                            }
    }
    
    func testCacheRandomSpeed() {
        var timer = Stopwatch()
        let start = Date()
        let iterations = threads * 1_000
        let factor = Int(pow(Double(iterations), 1.0 / 3.0)) * 5
        var touches: [(Double, Int)] = []
        
        self.measure {
            timer.lap()
            touches.append(_random(iterations, factor))
            timer.lap(accumulate: true)
        }
        
        print((start +-> Date()).formatSeconds())
        let total = touches.reduce(into: (0.0, 0)) { $0.0 += $1.0; $0.1 += $1.1 }
        
        print("""
        Random Cache Speed: \(iterations) renders of \(leafCache.keys.count) templates
        -------------------------------------------------------------------
        Average \(timer.average) clock time / test
        Average \((total.0 / 10).formatSeconds()) CPU time / test
        Average \((total.0 / Double(total.1)).formatSeconds()) CPU time / render
        """)
    }
    
    /// Returns total cpu serialization time + call count
    func _random(_ iterations: Int, _ ratio: Int) -> (Double, Int) {
        let totalTemplates = max(1, iterations / ratio)
        let bottom = (1...max(1, totalTemplates / 13))
        let middle = (1...min(bottom.count * 2, totalTemplates))
        let top = (1...min(bottom.count * 10, totalTemplates))
        
        bottom.forEach { files["\($0)bottom"] = $0.description }
        middle.forEach { files["\($0)middle"] = """
        \($0)
        -> #inline(\"\(bottom.randomElement()!)bottom\")
        """ }
        top.forEach { files["\($0)top"] = """
        \($0)
        -> #inline(\"\(middle.randomElement()!)middle\")
        -> #inline(\"\(middle.randomElement()!)middle\")
        """ }
        
        let all = files.keys
        let ratio = max(1, iterations / all.count)
        var priority = all.shuffled()
        
        (1...max(3, iterations)).reversed().forEach {
            let pick = priority.isEmpty || ($0 / ratio) < priority.count
                     ? all.randomElement()! : priority.removeFirst()
            renderBuffer(pick).whenComplete {
                switch $0 {
                    case .failure(let e) : XCTFail(e.localizedDescription)
                    case .success        : XCTAssert(true)
                }
            }
        }
        
        waitTilDone()
        
        return leafCache.keys.map { leafCache.info(for: $0)!.touch }
                             .reduce(into: (0.0, 0)) {
                                $0.0 += $1.execAvg * Double($1.count)
                                $0.1 += Int($1.count)
                             }
    }
}

final class NIOFilesTests: FullstackRendererTestCase {
    let threadPool = NIOThreadPool(numberOfThreads: 1)
    lazy var fileio = NonBlockingFileIO(threadPool: threadPool)
    lazy var nioFiles = NIOLeafFiles(fileio: fileio,
                                     limits: .default,
                                     sandboxDirectory: templateFolder,
                                     viewDirectory: templateFolder + "SubTemplates/")
    
    override var source: LeafSource { get { nioFiles } set {} }
    
    override func setUp() { threadPool.start() }
    
    override func tearDownWithError() throws { try threadPool.syncShutdownGracefully() }
    
    func testNIOFileSandbox() throws {
        LKConf.entities.use(IntFormatterMap.bytes, asMethod: "formatBytes")
        
        renderBuffer("test").whenComplete {
            try? XCTAssertNoThrow($0.get()) }
        renderBuffer("../test").whenComplete {
            try? XCTAssertNoThrow($0.get()) }
        renderBuffer("../../test").whenComplete {
            try? self.AssertErrors($0.get(), contains: "Attempted to escape sandbox") }
        renderBuffer(".test").whenComplete {
            try? self.AssertErrors($0.get(), contains: "Attempted to access hidden file `.test`") }
    }
}


final class MultisourceTests: FullstackRendererTestCase {
    override var useDefaultSource: Bool { get {false} set {} }
    
    var one: LeafMemorySource { source as! LeafMemorySource }
    let two: LeafMemorySource = .init()
    let hidden: LeafMemorySource = .init()
    
    func testEmptySources() throws {
        XCTAssert(sources.all.count == 0)
        try sources.register(source: "sourceHidden", using: hidden, searchable: false)
        XCTAssert(sources.all == ["sourceHidden"])
        renderBuffer("a").whenComplete {
            try? self.AssertErrors($0.get(), contains: "No searchable sources exist") }
    }
    
    func testMultipleSources() throws {
        try sources.register(source: "sourceOne", using: one, searchable: true)
        try sources.register(source: "sourceTwo", using: two, searchable: true)
        try sources.register(source: "sourceHidden", using: hidden, searchable: false)
        
        one["a"] = "This file is in sourceOne"
        two["b"] = "This file is in sourceTwo"
        hidden["c"] = "This file is in sourceHidden"
        
        XCTAssert(sources.all.contains("sourceTwo"))
        renderBuffer("a").whenComplete { XCTAssert($0.contains("in sourceOne")) }
        renderBuffer("b").whenComplete { XCTAssert($0.contains("in sourceTwo")) }
        renderBuffer("c").whenComplete {
            try? self.AssertErrors($0.get(), contains: "No template found") }
        renderBuffer("c", from: "sourceHidden").whenComplete { XCTAssert($0.contains("in sourceHidden")) }
    }
    
}
