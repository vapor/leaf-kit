// MARK: Subject to change prior to 1.0.0 release

//import Dispatch

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
    
    /// A thread-safe implementation of `LeafCache` protocol
    public let cache: LeafCache
    /// A thread-safe implementation of `LeafSource` protocol
    public let sources: LeafSources
    /// The NIO `EventLoop` on which this instance of `LeafRenderer` will operate
    public var eventLoop: EventLoop { eL }

    /// Initial configuration of LeafRenderer.
    public init(cache: LeafCache,
                sources: LeafSources,
                eventLoop: EventLoop) {
        self.cache = cache
        self.sources = sources
        self.eL = eventLoop
        self.blockingCache = cache as? LKSynchronousCache
        self.cacheIsSync = blockingCache != nil
//        self.worker = .init(label: "codes.vapor.leaf.renderer",
//                            attributes: .concurrent,
//                            autoreleaseFrequency: .never)
    }
    
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
    public func render(template: String,
                       context: Context) -> EventLoopFuture<ByteBuffer> {
        if template.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        return _render(.searchKey(template), context)
    }

    public func render(template: String,
                       from source: String,
                       context: Context) -> EventLoopFuture<ByteBuffer> {
        if template.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        if source.isEmpty { return fail(.noTemplateExists("No LeafSource key provided"), on: eL) }
        if source != "$", source.first == "$" || source.contains(":") {
            return fail(.illegalAccess("Invalid LeafSource key"), on: eL)
        }
        return _render(.init(source, template), context)
    }
    
    public func info(for template: String) -> EventLoopFuture<LeafASTInfo?> {
        cache.info(for: .searchKey(template), on: eL)
    }
    
    /// A wrapper object for storing all external model data that will be provided to `LeafRenderer`
    ///
    /// This is used as an intermediate object rather than immediately computed as arbitrary objects may
    /// have costly conversions to LeafData and may not need to occur for any particular, arbitrary template
    ///
    /// All values may be freely updated at any point prior to LeafKit starting; constant values may no longer
    /// be updated once LeafKit has started.
    ///
    /// Note that the context will be "frozen" in its state at the time it is passed to `LeafRenderer` and no
    /// alterations in Swift will affect the state of the rendering of the template. *WARNING*
    public struct Context: ExpressibleByDictionaryLiteral {
        public static var defaultContextScope: String { LKVariable.selfScope }
        
        // MARK: - Internal only
        internal var contexts: [LKVariable: LKContextDictionary] = [:]
        internal var externalObjects: ExternalObjects = [:]
    }
    
    // MARK: - Private Only
    
    private let eL: EventLoop
    private let cacheIsSync: Bool
    private let blockingCache: LKSynchronousCache?
//    private let worker: DispatchQueue

    // 50 ms limit for execution to act in a blocking fashion
    private static let blockLimit = 0.050
}

// MARK: - Private implementation
private extension LeafRenderer {
    func _render(_ key: LeafASTKey, _ ctx: Context) -> ELF<ByteBuffer> {
        /// Short circuit for resolved blocking cache hits
        if cacheIsSync, let hit = blockingCache!.retrieve(key),
           hit.info.requiredASTs.isEmpty, hit.info.touch.execAvg < Self.blockLimit {
            return preflight(hit, ctx)
        }

        return fetch(key, ctx).flatMap { self.arbitrate($0, ctx) }
                              .flatMap { self.preflight($0, ctx) }
    }

    /// Call with any state of ASTBox - will fork to various behaviors as required until finally returning a
    /// cached and serializable AST, if a failure hasn't bubbled out
    func arbitrate(_ ast: LeafAST,
                   _ context: LeafRenderer.Context,
                   via chain: [String] = []) -> ELF<LeafAST> {
        if ast.info.requiredASTs.isEmpty && ast.info.requiredRaws.isEmpty {
            /// Succeed immediately if the ast is cached and doesn't need any kind of resolution
            if ast.cached { return succeed(ast, on: eL) }
            var toCache = ast
            toCache.stripOversizeRaws()
            toCache.cached = true
                        
            /// If cache is blocking, force insert and succeed immediately
            if cacheIsSync {
                switch blockingCache!.insert(toCache, replace: true) {
                    case .success        : return succeed(ast, on: eL)
                    case .failure(let e) : return fail(e, on: eL)
                }
            }
            /// Future-based cache insertion and succeed
            return cache.insert(toCache, on: eL, replace: true).map { _ in ast }
        }
        
        /// No ASTs need to be inlined but raws are needed
        if !ast.info.requiredRaws.isEmpty { return arbitrateRaws(ast, context) }
        
        /// If the AST is missing template inlines, try to resolve - resolve will recall arbitrate or fail as necessary
        /// An unresolved AST is not necessarily an unserializable document though:...
        /// Guard against cycles
        let chain = chain + [ast.name]
        let cycle = Set(chain).intersection(ast.requiredASTs)
        if !cycle.isEmpty { return fail(.cyclicalReference(cycle.first!, chain), on: eL) }
        return resolve(ast, context, chain)
    }

    /// Get a `LeafAST` from the configured `LeafCache` or read the raw template if none is cached
    ///
    /// - If the AST can't be found (either from cache or reading), future errors
    /// - If found or read, return complete AST and a Bool signaling whether it was a cache hit or not
    func fetch(_ key: LeafASTKey,
               _ context: LeafRenderer.Context) -> ELF<LeafAST> {
        /// Try to hit blocking cache LeafAST, otherwise hit async cache, then try if no cache hit - read a template
        if cacheIsSync, let hit = blockingCache!.retrieve(key) { return succeed(hit, on: eL) }
        return cache.retrieve(key, on: eL)
                    .flatMapThrowing { if let hit = $0 { return hit } else { throw "" } }
                    .flatMapError { _ in self.read(key, context) }
    }

    /// Read in an individual `LeafAST`
    ///
    /// If the configured `LeafSource` can't read a file, future will fail
    /// Otherwise, a complete (but not necessarily flat) `LeafAST` will be returned.
    func read(_ key: LeafASTKey,
              _ context: LeafRenderer.Context,
              _ escape: Bool = false) -> ELF<LeafAST> {
        sources.find(key, on: eL)
               .flatMapThrowing { (src, buf) in
            let name = src
            var buf = buf

            guard let string = buf.readString(length: buf.readableBytes) else {
                throw err(.unknownError("\(name) exists but was unreadable")) }

            // FIXME: lex/parse should fork to a threadpool?
            var lexer = LKLexer(LKRawTemplate(name, string))
            let tokens = try lexer.lex()
            var parser = LKParser(key, tokens, context)
            return try parser.parse()
        }
    }
    
    func arbitrateRaws(_ ast: LeafAST,
                       _ context: LeafRenderer.Context) -> ELF<LeafAST> {
        let fetches = ast.info.requiredRaws.map { self.readRaw($0) }
        return ELF.reduce(into: ast, fetches, on: eL) { $0.inline(name: $1.0, raw: $1.1 ) }
                  .flatMap { self.arbitrate($0, context) }
    }
    
    func readRaw(_ name: String, _ escape: Bool = false) -> ELF<(String, ByteBuffer)> {
        sources.find(.searchKey(name), on: eL).map { (_, buffer) in (name, buffer) }
    }

    /// Attempt to resolve a `LeafAST` - call only when ast has unresolved inlines
    func resolve(_ ast: LeafAST,
                 _ context: LeafRenderer.Context,
                 _ chain: [String] = []) -> ELF<LeafAST> {
        // FIXME: A configuration flag should dictate handling of unresolved ASTS
        let fetches = ast.info.requiredASTs.map {
            self.fetch(.searchKey($0), context)
                .flatMap { self.arbitrate($0, context, via: chain) } }

        return ELF.reduce(into: ast, fetches, on: eL) { $0.inline(ast: $1) }
                  .flatMap { self.arbitrate($0, context) }
    }

    /// Given a `LeafAST` and context data, serialize the AST with provided data into a final render
    func preflight(_ ast: LeafAST, _ context: Context) -> ELF<ByteBuffer> {
        // FIXME: Configure behavior for rendering where "needed" is non empty
        var needed = Set<LKVariable>(ast.info._requiredVars.map { !$0.isScoped ? $0.contextualized : $0 })
        needed.subtract(context.allVariables)
        guard needed.isEmpty else { return fail(err("\(needed.description) missing"), on: eL) }
//        var contexts: LKVarTable = [.`self`: .dictionary(context)]
//        _ = context.filter { $0.key.isValidIdentifier }
//                   .map { contexts[LKVariable.atomic($0.key).contextualized] = $0.value }
//        needed.subtract(contexts.keys)
        
//        for (key, value) in self.userInfo ?? [:] {
//            guard let scope = key as? String,
//                  let key = LKVariable(scope),
//                  key != .`self` else { continue }
//            if needed.contains(key),
//               let v = value as? LeafDataRepresentable {
//                contexts[key] = v.leafData
//                needed.remove(key)
//            }
//            let scoped = needed.filter({$0.scope == scope})
//            guard !scoped.isEmpty,
//                  let dict = value as? [String: LeafDataRepresentable] else { continue }
//            scoped.forEach {
//                if let v = dict[$0.member!] { contexts[$0] = v.leafData }
//                needed.remove($0)
//            }
//        }
        
        var block = LKConf.entities.raw.instantiate(size: ast.info.underestimatedSize,
                                                    encoding: LKConf.encoding)
        let serializer = LKSerializer(ast, context, type(of: block))
        switch serializer.serialize(&block) {
            case .success(let t) : cache.touch(serializer.ast.key,
                                               .atomic(time: t, size: block.byteCount))
                                   return succeed(block.serialized.buffer, on: eL)
            case .failure(let e) : return fail(e, on: eL)

        }

    }
    
    func serialize(_ serializer: LKSerializer,
                   _ buffer: LKRawBlock,
                   _ duration: Double = 0,
                   _ resume: Bool = false) -> ELF<ByteBuffer> {
        let timeout = max(Self.blockLimit, LKConf.timeout - duration)
        var buffer = buffer
        switch serializer.serialize(&buffer, timeout, resume) {
            case .success(let t) : let buffer = buffer as! ByteBuffer
                                   cache.touch(serializer.ast.key,
                                               .atomic(time: t, size: buffer.byteCount))
                                   return succeed(buffer, on: eL)
            case .failure(let e) : guard case .timeout(let d) = e.reason,
                                         LKConf.timeout > duration + d else {
                                        return fail(e, on: eL) }
                                   return serialize(serializer, buffer, duration + d, true)
        }
    }
}
