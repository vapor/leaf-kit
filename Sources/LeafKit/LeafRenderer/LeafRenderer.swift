import Foundation

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
    // MARK: Instance Properties
    /// A thread-safe implementation of `LeafCache` protocol
    public let cache: LeafCache
    /// A thread-safe implementation of `LeafSource` protocol
    public let sources: LeafSources

    /// Initial configuration of LeafRenderer.
    public init(cache: LeafCache,
                sources: LeafSources,
                eventLoop: EventLoop) {
        if !LKConf.started { LKConf.started = true }
        
        self.cache = cache
        self.sources = sources
        self.eL = eventLoop
        self.blockingCache = cache as? LKSynchronousCache
        self.cacheIsSync = blockingCache != nil
    }
    
    // MARK: Private Only
    private let eL: EventLoop
    private let cacheIsSync: Bool
    private let blockingCache: LKSynchronousCache?
    
    // MARK: - Scoped Objects
    
    // MARK: - LeafRenderer.Option
    /// Locally overrideable options for how LeafRenderer handles rendering
    public enum Option: Hashable, CaseIterable {
        /// Rendering timeout duration limit in seconds; must be at least 1ms
        @LeafRuntimeGuard(condition: {$0 >= 0.001})
        public static var timeout: Double = 0.050
        
        /// If true, warnings during parse will throw errors.
        @LeafRuntimeGuard public static var parseWarningThrows: Bool = true
        
        /// Controls behavior of serialize when a variable has no value in context:
        /// When true, throws an error and aborts serializing; when false, returns Void? and decays chain.
        @LeafRuntimeGuard public static var missingVariableThrows: Bool = true
        
        /// When true, `LeafUnsafeEntity` tags will have access to contextual objects
        @LeafRuntimeGuard public static var grantUnsafeEntityAccess: Bool = false
                
        /// Output buffer encoding
        @LeafRuntimeGuard public static var encoding: String.Encoding = .utf8
        
        /// Behaviors for how render calls will use the configured `LeafCache` for compiled templates
        @LeafRuntimeGuard public static var caching: LeafCacheBehavior = .default
        
        /// The limit in bytes for an `inline(..., as: raw)` statement to embed the referenced
        /// raw inline in the *cached* AST.
        @LeafRuntimeGuard public static var embeddedASTRawLimit: UInt32 = 4096
        
        /// If caching behavior allows auto-updating, the polling frequency dictates how many seconds
        /// can elapse before `LeafRenderer` checks the original source for changes
        @LeafRuntimeGuard(condition: {$0.sign == .plus})
        public static var pollingFrequency: Double = 10.0
        
        case timeout(Double)
        case parseWarningThrows(Bool)
        case missingVariableThrows(Bool)
        case grantUnsafeEntityAccess(Bool)
        case encoding(String.Encoding)
        case caching(LeafCacheBehavior)
        case embeddedASTRawLimit(UInt32)
        case pollingFrequency(Double)
        
        public enum Case: UInt16, RawRepresentable, CaseIterable {
            case timeout
            case parseWarningThrows
            case missingVariableThrows
            case grantUnsafeEntityAccess
            case encoding
            case caching
            case embeddedASTRawLimit
            case pollingFrequency
        }
    }
    
    // MARK: - LeafRenderer.Options
    /// A set of configured options for overriding global settings
    ///
    /// Values are only set if they *actually* override global settings.
    ///
    public struct Options: ExpressibleByArrayLiteral {
        var _storage: Set<Option>
    }
    
    // MARK: - LeafRenderer.Context
    /// A wrapper object for storing external model data that will be provided to `LeafRenderer`
    ///
    /// This is used as an intermediate object rather than immediately computed as arbitrary objects may
    /// have costly conversions to LeafData and may not need to occur for any particular, arbitrary template
    ///
    /// All values may be freely updated at any point prior to LeafKit starting; however, values can be set by
    /// the user in a root context as *literal* values (ones that are fixed for the lifetime of the application).
    /// Such values can not be overridden, or converted back to variable values, once LeafKit is running.
    ///
    /// Note that the context will be "frozen" in its state at the time it is passed to `LeafRenderer` and no
    /// alterations in Swift will affect the state of the rendering of the template.
    ///
    /// `Context` objects may be stacked or overlaid to allow multiple state contexts to be merged prior
    /// to rendering. If a context `isRootContext`, it can only be the lowest context in a flattened stack.
    ///
    /// Note that when objects are registered to a `Context`, rather than simply set as values, they may
    /// have been set to disallow overlaying their values, or to allow creation of additional values in their
    /// named scope, and attempts to overlay will fail.
    ///
    /// If a context has `options` set, overlaying will always favor the top-most configuration for options.
    public struct Context: ExpressibleByDictionaryLiteral {
        // MARK: LeafRenderer.Context.ObjectMode
        public struct ObjectMode: OptionSet {
            public init(rawValue: UInt8) { self.rawValue = rawValue }
            public var rawValue: UInt8
            
            /// Register the provided object as an unsafe object
            public static var unsafe: Self = .init(rawValue: 1 << 0)
            /// Register the provided object as a context publisher (via LeafContextPublisher or LeafDataRepresentable)
            public static var contextual: Self = .init(rawValue: 1 << 1)
            /// Prevent the object from being replaced, if registered as unsafe, and/or to prevents its context
            /// variables from being replaced, if contextual. `lockContext` overrides contextual overlay if set.
            public static var preventOverlay: Self = .init(rawValue: 1 << 2)
            /// If contexual, prevents any context variables from being added to its associated scope.
            public static var lockContextVariables: Self = .init(rawValue: 1 << 3)
            
            /// Default options register an object only as a context object, and allows additional
            /// variables to be registered to the scope it owns but not replace its own values.
            public static var `default`: Self = [contextual, preventOverlay]
            
            /// Both `unsafe` && `contextual`
            public static var bothModes: Self = [contextual, unsafe]
        }
        
        /// Context must be set as root as initialization in order to allow values to be set as literal
        public let isRootContext: Bool
        
        /// Render-specific option overrides
        public var options: Options? = nil
        
        // MARK: Internal Stored Properties
        internal var contexts: [LKVariable: LKContextDictionary] = [:]
        internal var unsafeObjects: UnsafeObjects = [:]
        internal var objects: [String: [(ObjectMode, Any, Set<String>)]] = [:]
        internal var anyLiteral: Bool = false
    }
}

// MARK: - Public Implementation
public extension LeafRenderer {
    // MARK: Stored Properties
    
    /// The NIO `EventLoop` on which this instance of `LeafRenderer` will operate
    var eventLoop: EventLoop { eL }
       
    // MARK: Methods
    
    /// The public interface to `LeafRenderer`
    /// - Parameters:
    ///   - template: Name of the template to be used
    ///   - context:  Any unique context data for the template to use
    ///   - options:  Any overrides of global options for this render call
    /// - Returns:    Serialized result of using the template, or a failed future
    ///
    /// Interpretation of `template` is dependent on the implementation of `LeafSource` but is assumed to
    /// be relative to the source's configured root directory.
    ///
    /// Where `LeafSource` is a file sytem based source, some assumptions should be made;
    /// `LeafSources.defaultExtension` (defaults to .`leaf`) extension is inferred if none is
    /// provided.
    ///
    /// `"path/to/template"` might correspond to`"/.../Views/path/to/template.leaf"`,
    ///  while an explicit extension - `"file.svg"` would correspond to `"/.../Views/file.svg"`
    func render(template: String,
                context: Context,
                options: Options? = nil) -> EventLoopFuture<ByteBuffer> {
        if template.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        return _render(.searchKey(template), context, options)
    }
    
    /// The public interface to `LeafRenderer`
    /// - Parameters:
    ///   - template: Name of the template to be used
    ///   - source:   A specific (and only) `LeafSource` key to check for the template
    ///   - context:  Any unique context data for the template to use
    ///   - options:  Any overrides of global options for this render call
    /// - Returns:    Serialized result of using the template, or a failed future
    ///
    /// Interpretation of `template` is dependent on the implementation of `LeafSource` but is assumed to
    /// be relative to the source's configured root directory.
    ///
    /// Where `LeafSource` is a file sytem based source, some assumptions should be made;
    /// `LeafSources.defaultExtension` (defaults to .`leaf`) extension is inferred if none is
    /// provided.
    ///
    /// `"path/to/template"` might correspond to`"/.../Views/path/to/template.leaf"`,
    ///  while an explicit extension - `"file.svg"` would correspond to `"/.../Views/file.svg"`
    func render(template: String,
                from source: String,
                context: Context,
                options: Options? = nil) -> EventLoopFuture<ByteBuffer> {
        if template.isEmpty { return fail(.noTemplateExists("No template name provided"), on: eL) }
        if source.isEmpty { return fail(.noSourceForKey(source, invalid: true), on: eL) }
        if source != "$", source.first == "$" || source.contains(":") {
            return fail(.noSourceForKey(source, invalid: true), on: eL)
        }
        return _render(.init(source, template), context, options)
    }
    
    func info(for template: String,
              in source: String? = nil) -> EventLoopFuture<LeafAST.Info?> {
        cache.info(for: .init(source ?? "$", template), on: eL)
    }
}

// MARK: - Private Implementation
private extension LeafRenderer {
    // 10 ms limit for execution to act in a blocking fashion
    private static var blockLimit: Double { 0.010 }
    
    func _render(_ key: LeafAST.Key, _ context: Context, _ options: Options?) -> ELF<ByteBuffer> {
        var context = context
        if let options = options {
            if context.options == nil { context.options = options }
            else { options._storage.forEach { context.options?._storage.update(with: $0) } }
        }
        
        /// Short circuit for resolved blocking cache hits
        if cacheIsSync, context.caching.contains(.read),
           let hit = blockingCache!.retrieve(key),
           hit.info.requiredASTs.isEmpty,
           hit.info.touch.execAvg < Self.blockLimit,
           !hit.autoUpdate(context) {
            return syncSerialize(hit, context)
        }
        
        return fetch(key, context).flatMap { self.arbitrate($0, context) }
                                  .flatMap { self.syncSerialize($0, context) }
    }

    /// Call with any state of ASTBox - will fork to various behaviors as required until finally returning a
    /// cached and serializable AST, if a failure hasn't bubbled out
    func arbitrate(_ ast: LeafAST, _ context: Context, via chain: [String] = []) -> ELF<LeafAST> {
        if ast.info.requiredASTs.isEmpty && ast.info.requiredRaws.isEmpty {
            /// Succeed immediately if the ast is cached and doesn't need any kind of resolution
            if ast.cached || context.caching.intersection([.store, .autoUpdate]).isEmpty {
                return succeed(ast, on: eL) }
            var toCache = ast
            
            toCache.stripOversizeRaws(cacheLimit: context.embeddedASTRawLimit)
            
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
        let chain = chain + CollectionOfOne(ast.name)
        let cycle = Set(chain).intersection(ast.requiredASTs)
        if !cycle.isEmpty { return fail(.cyclicalReference(cycle.first!, chain), on: eL) }
        return resolve(ast, context, chain)
    }

    /// Get a `LeafAST` from the configured `LeafCache` or read the raw template if none is cached
    ///
    /// - If the AST can't be found (either from cache or reading), future errors
    /// - If found or read, return complete AST and a Bool signaling whether it was a cache hit or not
    func fetch(_ key: LeafAST.Key, _ context: Context) -> ELF<LeafAST> {
        guard context.caching.contains(.read) else { return read(key, context) }
                
        /// Try to hit blocking cache LeafAST, otherwise hit async cache, then try if no cache hit - read a template
        if cacheIsSync, let hit = blockingCache!.retrieve(key),
           !hit.autoUpdate(context) { return succeed(hit, on: eL) }
            
        return cache.retrieve(key, on: eL)
                    .flatMapThrowing { ast in
                        if let hit = ast { return hit }
                        else { throw err(.noValueForKey(""))} }
                    .flatMapError { e in self.read(key, context) }
                    .flatMap { $0.autoUpdate(context) ? self.poll($0, context)
                                                      : succeed($0, on: self.eL) }
    }
    
    func poll(_ ast: LeafAST, _ context: Context) -> ELF<LeafAST> {
        sources.timestamp(ast.key, on: eL).flatMap {
            if ast.info.parsed < $0 { return self.read(ast.key, context) }
            else {
                var ast = ast
                ast.info.pollTime = Date()
                ast.cached = false
                return succeed(ast, on: self.eL)
            }
        }
    }

    /// Read in an individual `LeafAST`
    ///
    /// If the configured `LeafSource` can't read a file, future will fail
    /// Otherwise, a complete (but not necessarily flat) `LeafAST` will be returned.
    func read(_ key: LeafAST.Key, _ context: Context, _ escape: Bool = false) -> ELF<LeafAST> {
        sources.file(key, on: eL)
               .flatMapThrowing {
            var buf = $0.1

            guard let string = buf.readString(length: buf.readableBytes) else {
                throw err(.unknownError("\($0.0) exists but was unreadable")) }

            // FIXME: Lex/Parse should fork to a threadpool
            var lexer = LKLexer(LKRawTemplate($0.0, string))
            let tokens = try lexer.lex()
            var parser = LKParser(key, tokens, context)
            return try parser.parse()
        }
    }
    
    func arbitrateRaws(_ ast: LeafAST, _ context: Context) -> ELF<LeafAST> {
        let fetches = ast.info.requiredRaws.map { self.readRaw($0) }
        return ELF.reduce(into: ast, fetches, on: eL) {
                    $0.inline(name: $1.0, raw: $1.1,
                              cacheLimit: context.embeddedASTRawLimit)
                 }.flatMap { self.arbitrate($0, context) }
    }
    
    func readRaw(_ name: String, _ escape: Bool = false) -> ELF<(String, ByteBuffer)> {
        sources.file(.searchKey(name), on: eL).map { (_, buffer) in (name, buffer) }
    }

    /// Attempt to resolve a `LeafAST` - call only when ast has unresolved inlines
    func resolve(_ ast: LeafAST, _ context: Context, _ chain: [String] = []) -> ELF<LeafAST> {
        let fetches = ast.info.requiredASTs.map {
            self.fetch(.searchKey($0), context)
                .flatMap { self.arbitrate($0, context, via: chain) } }

        return ELF.reduce(into: ast, fetches, on: eL) { $0.inline(ast: $1) }
                  .flatMap { self.arbitrate($0, context) }
    }

    /// Given a `LeafAST` and context data, serialize the AST with provided data into a final render
    func syncSerialize(_ ast: LeafAST, _ context: Context) -> ELF<ByteBuffer> {
        var needed = Set<LKVariable>(ast.info._requiredVars
                                        .map {$0.isDefine ? $0 : !$0.isScoped ? $0.contextualized : $0})
        needed.subtract(context.allVariables)
        needed.subtract(needed.compactMap {$0.isCoalesced ? $0 : nil})
        needed.subtract(needed.compactMap {context.allVariables.contains($0.contextualized) ? $0 : nil})
        
        let shouldThrow = needed.isEmpty ? false : context.missingVariableThrows
        
        if shouldThrow { return fail(err("[\(needed.map {$0.terse}.joined(separator: ", "))] variable(s) missing"), on: eL) }
        
        var block = LKConf.entities.raw.instantiate(size: ast.info.underestimatedSize,
                                                    encoding: context.encoding)
        
        let serializer = LKSerializer(ast, context, type(of: block))
        switch serializer.serialize(&block) {
            case .failure(let e): return fail(e, on: eL)
            case .success(let t):
                if context.caching.contains(.store) {
                    cache.touch(serializer.ast.key, with: .atomic(time: t, size: block.byteCount)) }
                return succeed(block.serialized.buffer, on: eL)
        }
    }
}
