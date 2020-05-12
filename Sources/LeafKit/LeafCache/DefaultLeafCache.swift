import NIOConcurrencyHelpers

public final class DefaultLeafCache: LeafCache {
    let lock: Lock
    var cache: [String: ResolvedDocument]
    public var isEnabled: Bool = true

    public init() {
        self.lock = .init()
        self.cache = [:]
    }

    // Superseded by insert with remove: parameter - Remove in Leaf-Kit 2?
    public func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument> {
        self.insert(document, on: loop, replace: false)
    }

    public func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<ResolvedDocument> {
        // future fails if caching is enabled
        guard isEnabled else { return loop.makeSucceededFuture(document) }

        self.lock.lock()
        defer { self.lock.unlock() }
        // return an error if replace is false and the document name is already in cache
        switch (self.cache.keys.contains(document.name),replace) {
            case (true, false): return loop.makeFailedFuture(LeafError(.keyExists(document.name)))
            default: self.cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }

    public func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?> {
        guard isEnabled == true else { return loop.makeSucceededFuture(nil) }
        self.lock.lock()
        defer { self.lock.unlock() }
        return loop.makeSucceededFuture(self.cache[documentName])
    }

    public func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?> {
        guard isEnabled == true else { return loop.makeFailedFuture(LeafError(.cachingDisabled)) }

        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.cache[documentName] != nil else { return loop.makeSucceededFuture(nil) }
        self.cache[documentName] = nil
        return loop.makeSucceededFuture(true)
    }

    public func entryCount() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return cache.count
    }
}
