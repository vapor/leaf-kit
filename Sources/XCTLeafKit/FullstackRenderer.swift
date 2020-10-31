@testable import LeafKit
import NIOConcurrencyHelpers

/// Always uses MultiThreadedEventLoopGroup, thus `render` is unavailable, only `renderBuffer`
///
/// Allows multiple sources
///
/// Handles setup/teardown of ELG and
open class FullstackRendererTestCase: LeafKitTestCase {
    open var threads: Int { 1 }
    open var useDefaultSource = true
    
    final public let sources: LeafSources = .init()
    
    final public override var eLGroup: EventLoopGroup { get { super.eLGroup } set {} }
    
    final public override func setUpLeaf() throws  {
        if self.threads < 1 { throw "Must be at least one thread" }
        super.eLGroup = MultiThreadedEventLoopGroup(numberOfThreads: threads)
        if useDefaultSource {
            try sources.register(source: "default", using: source, searchable: true)
        }
        addTeardownBlock { self.waitTilDone() }
    }
    
    final public override func tearDown() {
        do { try eLGroup.syncShutdownGracefully() }
        catch { XCTFail("Couldn't shut down EventLoopGroup") }
    }

    @discardableResult
    final public override func renderBuffer(_ template: String,
                                            from source: String = "$",
                                            _ context: LeafRenderer.Context = .emptyContext(),
                                            options: LeafRenderer.Options = []) -> EventLoopFuture<ByteBuffer> {
        let which = self.next
        let this = renderers[which].r
        return this.eventLoop.makeSucceededFuture(template)
                   .flatMap { this.render(template: $0,
                                          from: source,
                                          context: context,
                                          options: options) }
                   .always { _ in self.complete(which) }
    }
    
    /// Sleep 5 µs per uncompleted task at a time
    final public func waitTilDone() { while let sleep = toGo { usleep(5 * sleep) } }
    
    private class Renderer {
        init(_ r: LeafRenderer) { self.r = r }
        
        let r: LeafRenderer
        var tasks: Int = 0

        var isDone: Bool { tasks == 0 }
    }
    
    private var lock: Lock = .init()
    private var started = false
    private var _next: Int = -1
    private var renderers: [Renderer] = []
}

private extension FullstackRendererTestCase {
    var isDone: Bool { lock.withLock { renderers.allSatisfy { $0.isDone } } }
    var toGo: UInt32? { isDone ? nil : UInt32(lock.withLock { renderers.reduce(into: 0, { $0 += $1.tasks }) }) }
    func complete(_ which: Int) { lock.withLockVoid { renderers[which].tasks -= 1 } }
    
    var next: Int {
        lock.withLock {
            if !started { primeRenderers() }
            _next = (_next + 1) % renderers.count
            renderers[_next].tasks += 1
            return _next
        }
    }
    
    func primeRenderers() {
        guard !started else { return }
        started = true
        for _ in (0..<threads) {
            renderers.append(Renderer(.init(cache: cache, sources: sources, eventLoop: eLGroup.next())))
        }
    }
}

extension Result where Success == ByteBuffer {
    func contains(_ str: String) -> Bool {
        guard let b = try? get() else { return false }
        return String(decoding: b.readableBytesView, as: UTF8.self).contains(str)
    }
}
