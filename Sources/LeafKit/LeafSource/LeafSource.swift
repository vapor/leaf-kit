/// Public protocol to adhere to in order to provide template source originators to `LeafRenderer`
public protocol LeafSource {
    /// Given a path name, return an EventLoopFuture holding a ByteBuffer
    /// - Parameters:
    ///   - path: Fully expanded pathname to file for reading
    ///   - escape: Whether to allow escaping paths up to `sandbox` level at most
    ///   - eventLoop: `EventLoop` on which to perform file access
    func file(template: String,
              escape: Bool,
              on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer>
    
    /// DO NOT IMPLEMENT. Deprecated as of Leaf-Kit 1.0.0rc1.??
    @available(*, deprecated, message: "Update to adhere to `file(template, escape, eventLoop)`")
    func file(path: String, on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer>
}

/// An object holding named `LeafSource` adherants specifying a default search order
public final class LeafSources {
    /// All available sources of Leaf templates
    public var all: Set<String> { .init(sources.keys) }
    /// Search order of Leaf template sources
    public internal(set) var searchOrder: [String]
    /// Internal storage
    internal var sources: [String: LeafSource]
    
    /// Register a `LeafSource` as `key`
    /// - Parameters:
    ///   - key: Name for the source; at most one may be registered without a name
    ///   - source: A fully configured `LeafSource` object
    ///   - searchable: Whether the source should be added to the default search path
    /// - Throws: Attempting to overwrite a previously named source is not permitted
    public func register(source key: String = "default",
                         using source: LeafSource,
                         searchable: Bool = true) throws {
        guard !sources.keys.contains(key) else { throw "Can't replace source at \(key)" }
        sources[key] = source
        if searchable { searchOrder.append(key) }
    }
    
    /// Locate a template from the sources; if a specific source is named, only try to read from it. Otherwise, use the specified search order
    internal func find(template: String, in source: String? = nil, on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        let keys: [String]
        if let source = source {
            guard self.sources.keys.contains(source) else { throw LeafError(.unknownError("No source \"\(source)\" exists")) }
            keys = [source]
        } else { keys = searchOrder }
        
        guard !keys.isEmpty else { throw LeafError(.unknownError("No searchable sources exist")) }
        
        return searchSources(t: template, on: eventLoop, s: ArraySlice(keys))
    }
    
    private func searchSources(t: String, on eL: EventLoop, s: ArraySlice<String>) -> EventLoopFuture<ByteBuffer> {
        guard !s.isEmpty, let key = s.first, let source = sources[key] else { return eL.makeFailedFuture(LeafError(.noTemplateExists(t))) }
        // If non-future related failure when reading (eg, malformed path for template for source), go to next
        guard let future = try? source.file(template: t, escape: true, on: eL) else { return searchSources(t: t, on: eL, s: s.dropFirst()) }
        return future.flatMapError { _ in self.searchSources(t: t, on: eL, s: s.dropFirst()) }
    }
    
    internal init() {
        self.sources = [:]
        self.searchOrder = []
    }
    
    public static func singleSource(_ source: LeafSource) -> LeafSources {
        let sources = LeafSources()
        try! sources.register(using: source)
        return sources
    }
}


