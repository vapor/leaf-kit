import NIOConcurrencyHelpers

public indirect enum LeafError: Error {
    case unknownError(String)
    case unsupportedFeature(String)
    case cachingDisabled
    case keyExists(String)
    case noValueForKey(String)
    case unresolvedAST(String, String)
    case noTemplateExists(String)
    case cyclicalReference(String, [String])
    case lexerError(LexerError)

    var localizedDescription: String {
        switch self {
            case .unknownError(let message): return message
            case .unsupportedFeature(let feature): return "\(feature) is not implemented"
            case .cachingDisabled: return "Caching is globablly disabled"
            case .keyExists(let key): return "Existing entry \(key): use insert with replace=true to overrride"
            case .noValueForKey(let key): return "No cache entry exists for \(key)"
            case .unresolvedAST(let key, let dependencies):
                return "Flat AST expected; \(key) has unresolved dependencies: \(dependencies)"
            case .noTemplateExists(let key): return "No template found named \(key)"
            case .cyclicalReference(let key, let chain):
                return "\(key) was referenced in [\(chain.joined(separator: " -> "))], causing a cyclical loop"
            case .lexerError(let e): return e.localizedDescription
        }
    }

    init(_ message: String) {
        self = .unknownError(message)
    }
}

public struct LeafConfiguration {
    public var rootDirectory: String

    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }
}

public protocol LeafCache {
    // Superseded by insert with remove: parameter - Remove in Leaf-Kit 2?
    @available(*, deprecated, message: "Use insert with replace parameter instead")
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument>
    
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop,
        replace: Bool
    ) -> EventLoopFuture<ResolvedDocument>
    
    func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?>
    
    /// - return nil if cache entry didn't exist in the first place, true if purged
    /// - will never return false in this design but should be capable of it
    ///   in the event a cache implements dependency tracking between templates
    func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?>
    
    func entryCount() -> Int
    
    var isEnabled : Bool { get set }
}

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
            case (true, false): return loop.makeFailedFuture(LeafError.keyExists(document.name))
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
        guard isEnabled == true else { return loop.makeFailedFuture(LeafError.cachingDisabled) }
        
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

public struct LeafContext {
    public let parameters: [LeafData]
    public let data: [String: LeafData]
    public let body: [Syntax]?
    public let userInfo: [AnyHashable: Any]

    init(
        parameters: [LeafData],
        data: [String: LeafData],
        body: [Syntax]?,
        userInfo: [AnyHashable: Any]
    ) throws {
        self.parameters = parameters
        self.data = data
        self.body = body
        self.userInfo = userInfo
    }

    /// Throws an error if the parameter count does not equal the supplied number `n`.
    public func requireParameterCount(_ n: Int) throws {
        guard parameters.count == n else {
            throw "Invalid parameter count: \(parameters.count)/\(n)"
        }
    }

    /// Throws an error if this tag does not include a body.
    public func requireBody() throws -> [Syntax] {
        guard let body = body else {
            throw "Missing body"
        }

        return body
    }

    /// Throws an error if this tag includes a body.
    public func requireNoBody() throws {
        guard body == nil else {
            throw "Extraneous body"
        }
    }
}

public protocol LeafFiles {
    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer>
}

public struct NIOLeafFiles: LeafFiles {
    let fileio: NonBlockingFileIO

    public init(fileio: NonBlockingFileIO) {
        self.fileio = fileio
    }

    public func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        let openFile = self.fileio.openFile(path: path, eventLoop: eventLoop)
        return openFile.flatMapErrorThrowing { error in
            throw LeafError.noTemplateExists(path)
        }.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
            let allocator = ByteBufferAllocator()
            let read = self.fileio.read(fileRegion: region, allocator: allocator, eventLoop: eventLoop)
            return read.flatMapThrowing { (buffer)  in
                try handle.close()
                return buffer
            }
        }
    }
}

public final class LeafRenderer {
    public let configuration: LeafConfiguration
    public let tags: [String: LeafTag]
    public let cache: LeafCache
    public let files: LeafFiles
    public let eventLoop: EventLoop
    public let userInfo: [AnyHashable: Any]

    public init(
        configuration: LeafConfiguration,
        tags: [String: LeafTag] = defaultTags,
        cache: LeafCache = DefaultLeafCache(),
        files: LeafFiles,
        eventLoop: EventLoop,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.configuration = configuration
        self.tags = tags
        self.cache = cache
        self.files = files
        self.eventLoop = eventLoop
        self.userInfo = userInfo
    }

    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        guard path.count > 0 else { return self.eventLoop.makeFailedFuture(LeafError.noTemplateExists("(no key provided)")) }
        
        return self.cache.load(documentName: path, on: self.eventLoop).flatMapThrowing { cached in
            guard let cached = cached else { throw LeafError.noValueForKey(path) }
            guard cached.flat else { throw LeafError.unresolvedAST(path, cached.unresolvedRefs.joined(separator: ", ")) }
            return try self.serialize(cached, context: context)
        }.flatMapError { e in
            return self.fetch(template: path).flatMapThrowing { ast in
                guard let ast = ast else { throw LeafError.noTemplateExists(path) }
                guard ast.flat else { throw LeafError.unresolvedAST(path, ast.unresolvedRefs.joined(separator: ", ")) }
                return try self.serialize(ast, context: context)
            }
        }
    }

    func serialize(_ doc: LeafAST, context: [String: LeafData]) throws -> ByteBuffer {
        guard doc.flat == true else { throw LeafError.unresolvedAST(doc.name, doc.unresolvedRefs.joined(separator: ", ")) }

        var serializer = LeafSerializer(
            ast: doc.ast,
            context: context,
            tags: self.tags,
            userInfo: self.userInfo
        )
        return try serializer.serialize()
    }

    private func expand(template: String) -> String {
        var path = template
        // ignore files that already have a type
        if path.split(separator: "/").last?.split(separator: ".").count ?? 1 < 2  , !path.hasSuffix(".leaf") {
            path += ".leaf"
        }

        if !path.hasPrefix("/") {
            path = self.configuration.rootDirectory.trailSlash + path
        }
        return path
    }

    private func fetch(template: String, chain: [String] = []) -> EventLoopFuture<LeafAST?> {
        return cache.load(documentName: template, on: eventLoop).flatMap { cached in
            guard let cached = cached else {
                return self.read(name: template).flatMap { ast in
                    guard let ast = ast else { return self.eventLoop.makeSucceededFuture(nil) }
                    return self.resolve(ast: ast, chain: chain).map {$0}
                }
            }
            guard cached.flat == false else { return self.eventLoop.makeSucceededFuture(cached) }
            return self.resolve(ast: cached, chain: chain).map {$0}
        }
    }

    // resolve is only guaranteed to try to resolve an AST to flatness, not to succeed
    private func resolve(ast: LeafAST, chain: [String]) -> EventLoopFuture<LeafAST> {
        // if the ast is already flat, cache it immediately and return
        if ast.flat == true { return self.cache.insert(ast, on: self.eventLoop, replace: true) }
        
        var chain = chain
        _ = chain.append(ast.name)
        let intersect = ast.unresolvedRefs.intersection(Set<String>(chain))
        guard intersect.count == 0 else {
            let badRef = intersect.first ?? ""
            _ = chain.append(badRef)
            return self.eventLoop.makeFailedFuture(LeafError.cyclicalReference(badRef, chain))
        }

        let fetchRequests = ast.unresolvedRefs.map { self.fetch(template: $0, chain: chain) }
        
        let results = EventLoopFuture.whenAllComplete(fetchRequests, on: self.eventLoop)
        return results.flatMap { results in
            let results = results
            var externals: [String: LeafAST] = [:]
            for result in results {
                // skip any unresolvable references
                switch result {
                    case .success(let external):
                        guard let external = external else { continue }
                        externals[external.name] = external
                    case .failure(let e): return self.eventLoop.makeFailedFuture(e)
                }
            }
            // create new AST with loaded references
            let new = LeafAST(from: ast, referencing: externals)
            // Check new AST's unresolved refs to see if extension introduced new refs
            if !new.unresolvedRefs.subtracting(ast.unresolvedRefs).isEmpty {
                // AST has new references - try to resolve again recursively
                return self.resolve(ast: new, chain: chain)
            } else {
                // Cache extended AST & return - AST is either flat or unresolvable
                return self.cache.insert(new, on: self.eventLoop, replace: true)
            }
        }
    }

    private func read(name: String) -> EventLoopFuture<LeafAST?> {
        let path = expand(template: name)
        let raw = readBytes(file: path)

        return raw.flatMapThrowing { raw -> LeafAST? in
            var raw = raw

            // MARK: Should this actually throw an error if readString can't read readableBytes?
            let template = raw.readString(length: raw.readableBytes) ?? ""
            var lexer = LeafLexer(name: name, template: template)
            let tokens = try lexer.lex()
            var parser = LeafParser(name: name, tokens: tokens)
            let ast = try parser.parse()
            return LeafAST(name: name, ast: ast)
        }
    }

//    private func readDependencies... *obviated by new render/fetch/resolve functions*

    private func readBytes(file: String) -> EventLoopFuture<ByteBuffer> {
        self.files.file(path: file, on: self.eventLoop)
    }
}

extension Array where Element == Syntax {
    var dependencies: [String] {
        return extensions.map { $0.key }
    }

    private var extensions: [Syntax.Extend] {
        return compactMap {
            switch $0 {
            case .extend(let e): return e
            default: return nil
            }
        }
    }
}

extension String {
    internal var trailSlash: String {
        if hasSuffix("/") { return self }
        else { return self + "/" }
    }
}

extension LeafCache {
    /// default implementation of remove to avoid breaking custom LeafCache adopters
    func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?>
    {
        return loop.makeFailedFuture( LeafError.unsupportedFeature("Protocol adopter does not support removing entries") )
    }
    
    /// default implementation of remove to avoid breaking custom LeafCache adopters
    ///     throws an error if used with replace == true
    func insert(
        _ documentName: String,
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<ResolvedDocument>
    {
        if replace { return loop.makeFailedFuture( LeafError.unsupportedFeature("Protocol adopter does not support replacing entries") ) }
        else { return self.insert(documentName, on: loop) }
    }
}
