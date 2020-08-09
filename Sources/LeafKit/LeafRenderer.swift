// MARK: Subject to change prior to 1.0.0 release



// MARK: - `LeafRenderer` Summary

/// `LeafRenderer` implements the full Leaf language pipeline.
///
/// It must be configured before use with the appropriate `LeafConfiguration` and consituent
/// threadsafe protocol-implementating modules (an NIO `EventLoop`, `LeafCache`, `LeafSource`,
/// and potentially any number of custom `LeafTag` additions to the language).
///
/// Additional instances of LeafRenderer can then be created using these shared modules to allow
/// concurrent rendering, potentially with unique per-instance scoped data via `userInfo`.
public final class LeafRenderer {
    // MARK: - Public Only
    
    /// An initialized `LeafConfiguration` specificying default directory and tagIndicator
    public let configuration: LeafConfiguration
    /// A keyed dictionary of custom `LeafTags` to extend Leaf's basic functionality, registered
    /// with the names which will call them when rendering - eg `tags["tagName"]` can be used
    /// in a template as `#tagName(parameters)`
    public let tags: [String: LeafTag]
    /// A thread-safe implementation of `LeafCache` protocol
    public let cache: LeafCache
    /// A thread-safe implementation of `LeafSource` protocol
    public let sources: LeafSources
    /// The NIO `EventLoop` on which this instance of `LeafRenderer` will operate
    public let eventLoop: EventLoop
    /// Any custom instance data to use (eg, in Vapor, the `Application` and/or `Request` data)
    public let userInfo: [AnyHashable: Any]
    
    /// Initial configuration of LeafRenderer.
    public init(
        configuration: LeafConfiguration,
        tags: [String: LeafTag] = defaultTags,
        cache: LeafCache = DefaultLeafCache(),
        sources: LeafSources,
        eventLoop: EventLoop,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.configuration = configuration
        self.tags = tags
        self.cache = cache
        self.sources = sources
        self.eventLoop = eventLoop
        self.userInfo = userInfo
        
        self.blockingCache = cache as? SynchronousLeafCache
        self.cacheIsSync = blockingCache != nil
    }
    
    private var eL: EventLoop { self.eventLoop }
    private let cacheIsSync: Bool
    private let blockingCache: SynchronousLeafCache?
    
    /// The public interface to `LeafRenderer`
    /// - Parameter path: Name of the template to be used
    /// - Parameter context: Any unique context data for the template to use
    /// - Returns: Serialized result of using the template, or a failed future
    ///
    /// Interpretation of `path` is dependent on the implementation of `LeafSource` but is assumed to
    /// be relative to `LeafConfiguration.rootDirectory`.
    ///
    /// Where `LeafSource` is a file sytem based source, some assumptions should be made; `.leaf`
    /// extension should be inferred if none is provided- `"path/to/template"` corresponds to
    /// `"/.../ViewDirectory/path/to/template.leaf"`, while an explicit extension -
    /// `"file.svg"` would correspond to `"/.../ViewDirectory/file.svg"`
    public func render(path: String,
                       context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        if path.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        return _render(.searchKey(path), context)
    }
    
    public func render(path: String,
                       from source: String,
                       context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        if path.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        if source.isEmpty { return fail(.noTemplateExists("No LeafSource key provided"), on: eL) }
        if source != "$", source.first == "$" || source.contains(":") {
            return fail(.illegalAccess("Invalid LeafSource key"), on: eL)
        }
        return _render(.init(source, path), context)
    }
    
    internal static let blockLimit = 0.050 // 50 ms limit for execution to act in a blocking fashion
    
    @inline(__always)
    internal func _render(_ key: Leaf4AST.Key,
                          _ ctx: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        /// Short circuit for resolved blocking cache hits
        if cacheIsSync, let hit = blockingCache!.retrieve(key),
           hit.info.requiredASTs.isEmpty, hit.info.averages.exec < Self.blockLimit {
            return serialize(hit, ctx)
        }
        
        return fetch(key).flatMap { self.arbitrate($0) }
                         .flatMap { self.serialize($0, ctx) }
    }


    // MARK: - Private Only
        
    /// Call with any state of ASTBox - will fork to various behaviors as required until finally returning a
    /// cached and serializable AST, if a failure hasn't bubbled out
    private func arbitrate(_ ast: Leaf4AST,
                           via chain: [String] = []) -> EventLoopFuture<Leaf4AST> {
        if ast.info.requiredASTs.isEmpty {
            /// Succeed immediately if the ast is cached and doesn't need resolution
            if ast.cached { return succeed(ast, on: eL) }
            var ast = ast
            ast.cached = true
            /// If cache is blocking, force insert and succeed immediately
            if cacheIsSync {
                switch blockingCache!.insert(ast, replace: true) {
                    case .success(let ast): return succeed(ast, on: eL)
                    case .failure(let err): return fail(err, on: eL)
                }
            }
            /// Future-based cache insertion and succeed
            return cache.insert(ast, on: eL, replace: true)
        }
        /// If the AST is missing template inlines, try to resolve - resolve will recall arbitrate or fail as necessary
        /// An unresolved AST is not necessarily an unserializable document though:...
        /// Guard against cycles
        let chain = chain + [ast.name]
        let cycle = Set(chain).intersection(ast.requiredASTs)
        if !cycle.isEmpty { return fail(.cyclicalReference(cycle.first!, chain), on: eL) }
        return resolve(ast, chain)
    }
    
    
    
    /// Get a `LeafAST` from the configured `LeafCache` or read the raw template if none is cached
    ///
    /// - If the AST can't be found (either from cache or reading), future errors
    /// - If found or read, return complete AST and a Bool signaling whether it was a cache hit or not
    private func fetch(_ key: Leaf4AST.Key) -> EventLoopFuture<Leaf4AST> {
        /// Try to hit blocking cache first, otherwise hit async cache, then try if no cache hit - read a template
        if cacheIsSync, let hit = blockingCache!.retrieve(key) { return succeed(hit, on: eL) }
        return cache.retrieve(key, on: eL)
                    .flatMapThrowing { if let hit = $0 { return hit } else { throw "" } }
                    .flatMapError { _ in self.read(key) }
    }

    /// Read in an individual `LeafAST`
    ///
    /// If the configured `LeafSource` can't read a file, future will fail
    /// Otherwise, a complete (but not necessarily flat) `LeafAST` will be returned.
    private func read(_ key: Leaf4AST.Key,
                      _ escape: Bool = false) -> EventLoopFuture<Leaf4AST> {
        let found = sources.find(key, on: eL)
        return found.flatMapThrowing { (src, buf) in
            let name = src
            var buf = buf

            guard let str = buf.readString(length: buf.readableBytes) else {
                throw leafError(.unknownError("\(name) exists but was unreadable")) }
            
            // FIXME: lex/parse should fork to a threadpool?
            var lexer = LeafLexer(LeafRawTemplate(name, str))
            let tokens = try lexer.lex()
            var parser = Leaf4Parser(key, tokens)
            return try parser.parse()
        }
    }

    /// Attempt to resolve a `LeafAST` - call only when ast has unresolved inlines
    private func resolve(_ ast: Leaf4AST,
                         _ chain: [String] = []) -> EventLoopFuture<Leaf4AST> {
        // FIXME: A configuration flag should dictate handling of unresolved ASTS
        let fetches = ast.info.requiredASTs.map { self.fetch(.searchKey($0))
                                           .flatMap { self.arbitrate($0, via: chain) } }
        
        return EventLoopFuture.reduce(into: ast,
                                      fetches,
                                      on: eL) { $0.inline(ast: $1) }
                              .flatMap {  self.arbitrate($0) }
    }
    
    /// Given a `LeafAST` and context data, serialize the AST with provided data into a final render
    private func serialize(_ ast: Leaf4AST,
                           _ context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        
        // FIXME: serialize should fork to a threadpool?
        var block = ByteBuffer.instantiate(size: 0, encoding: LeafConfiguration.encoding)
        var serializer = Leaf4Serializer(ast: ast, context: context)
        switch serializer.serialize(buffer: &block) {
            case .success(let t) : let buffer = block as! ByteBuffer
                                   cache.touch(ast.key,
                                               .init(exec: t,
                                                     size: UInt32(buffer.readableBytes)))
                                   return succeed(buffer, on: eL)
            case .failure(let e) : return fail(e, on: eL)
        }
        
    }
}
