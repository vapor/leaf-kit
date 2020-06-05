import NIOConcurrencyHelpers

/// An object holding named `LeafSource` adherants specifying a default search order
public final class LeafSources {
    /// All available `LeafSource`s of templates
    public var all: Set<String> { lock.withLock { .init(self.sources.keys) } }
    /// Configured default implicit search order of `LeafSource`'s
    public var searchOrder: [String] { lock.withLock { order } }
    
    /// Internal storage
    internal private(set) var sources: [String: LeafSource]
    private var order: [String]
    private let lock: Lock = .init()

    /// Register a `LeafSource` as `key`
    /// - Parameters:
    ///   - key: Name for the source; at most one may be registered without a name
    ///   - source: A fully configured `LeafSource` object
    ///   - searchable: Whether the source should be added to the default search path
    /// - Throws: Attempting to overwrite a previously named source is not permitted
    public func register(source key: String = "default",
                         using source: LeafSource,
                         searchable: Bool = true) throws {
        try lock.withLock {
            guard !sources.keys.contains(key) else { throw "Can't replace source at \(key)" }
            sources[key] = source
            if searchable { order.append(key) }
        }
    }
    
    /// Locate a template from the sources; if a specific source is named, only try to read from it. Otherwise, use the specified search order
    internal func find(template: String, in source: String? = nil, on eventLoop: EventLoop) throws -> EventLoopFuture<(String, ByteBuffer)> {
        var keys: [String]
        
        switch source {
            case .none: keys = searchOrder
            case .some(let source):
                if all.contains(source) { keys = [source] }
                else { throw LeafError(.illegalAccess("Invalid source \(source) specified")) }
        }
        guard !keys.isEmpty else { throw LeafError(.illegalAccess("No searchable sources exist")) }
        
        return searchSources(t: template, on: eventLoop, s: keys)
    }
    
    private func searchSources(t: String, on eL: EventLoop, s: [String]) -> EventLoopFuture<(String, ByteBuffer)> {
        guard !s.isEmpty else { return eL.makeFailedFuture(LeafError(.noTemplateExists(t))) }
        var more = s
        let key = more.removeFirst()
        lock.lock()
            let source = sources[key]!
        lock.unlock()
        
        do {
            let file = try source.file(template: t, escape: true, on: eL)
            // Hit the file - return the combined tuple
            return eL.makeSucceededFuture(key).and(file).flatMapError { _ in
                // Or move onto the next one if this source can't get the file
                return self.searchSources(t: t, on: eL, s: more)
            }
        }
        catch {
            // If the throwing error is illegal access, fail immediately
            if let e = error as? LeafError,
               case .illegalAccess(_) = e.reason { return eL.makeFailedFuture(e) }
            else {
                // Or move onto the next one
                return searchSources(t: t, on: eL, s: more)
            }
        }
    }
    
    public init() {
        self.sources = [:]
        self.order = []
    }
    
    public static func singleSource(_ source: LeafSource) -> LeafSources {
        let sources = LeafSources()
        try! sources.register(using: source)
        return sources
    }
}


