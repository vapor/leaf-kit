import NIOConcurrencyHelpers
import Foundation

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
]

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
        guard isEnabled else { return loop.makeFailedFuture(LeafCacheError.cachingDisabled) }
        
        self.lock.lock()
        defer { self.lock.unlock() }
        // return an error if replace is false and the document name is already in cache
        switch (self.cache.keys.contains(document.name),replace) {
            case (true, false): return loop.makeFailedFuture(LeafCacheError.keyExists(document.name))
            default: self.cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }
    
    public func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?> {
        guard isEnabled == true else { return loop.makeFailedFuture(LeafCacheError.cachingDisabled) }
        self.lock.lock()
        defer { self.lock.unlock() }
        return loop.makeSucceededFuture(self.cache[documentName])
    }

    public func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?> {
        guard isEnabled == true else { return loop.makeFailedFuture(LeafCacheError.cachingDisabled) }
        
        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.cache[documentName] != nil else { return loop.makeSucceededFuture(nil) }
        self.cache[documentName] = nil
        return loop.makeSucceededFuture(true)
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

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to lowercase unexpected data"
        }
        return .init(.string(str.lowercased()))
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
            throw "unable to open file \(path)"
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
        let document = fetch(path: path)
        return document.flatMapThrowing { document in
            try self.render(document, context: context) }
    }
    
    func render(_ doc: ResolvedDocument, context: [String: LeafData]) throws -> ByteBuffer {
        var serializer = LeafSerializer(
            ast: doc.ast,
            context: context,
            tags: self.tags,
            userInfo: self.userInfo
        )
        return try serializer.serialize()
    }
    
    private func expand(path: String) -> String {
        var path = path
        // ignore files that already have a type
        if path.split(separator: ".").count < 2, !path.hasSuffix(".leaf") {
            path += ".leaf"
        }
        
        if !path.hasPrefix("/") {
            path = self.configuration.rootDirectory.trailSlash + path
        }
        return path
    }
    
    private func fetch(path: String) -> EventLoopFuture<ResolvedDocument> {
        let expanded = expand(path: path)
      
        // if caching is off immediately read file
        guard cache.isEnabled else { return self.read(file: expanded) }
        // if caching is on, attempt to load cached ResolvedDocument.
        // if cached is nil, read file, otherwise return cached file.        
        return cache.load(documentName: expanded, on: eventLoop).flatMap { [unowned self] cached in
            guard let cached = cached else { return self.read(file: expanded) }
            return self.eventLoop.makeSucceededFuture(cached)
        }
    }
    
    private func read(file: String) -> EventLoopFuture<ResolvedDocument> {
        let raw = readBytes(file: file)
        
        let syntax = raw.flatMapThrowing { raw -> [Syntax] in
            var raw = raw
            guard let template = raw.readString(length: raw.readableBytes) else { return [] }
            var lexer = LeafLexer(name: file, template: template)
            let tokens = try lexer.lex()
            var parser = LeafParser(name: file, tokens: tokens)
            return try parser.parse()
        }
        
        return syntax.flatMap { [unowned self] syntax in
            let dependencies = self.readDependencies(syntax.dependencies)
            let resolved = dependencies.flatMapThrowing { dependencies -> ResolvedDocument in
                let unresolved = UnresolvedDocument(name: file, raw: syntax)
                let resolver = ExtendResolver(document: unresolved, dependencies: dependencies)
                return try resolver.resolve(rootDirectory: self.configuration.rootDirectory)
            }

            guard self.cache.isEnabled else { return resolved }
            
            return resolved.flatMap { [unowned self] resolved in
                self.cache.insert(resolved, on: self.eventLoop, replace: false)
            }
        }
    }
    
    private func readDependencies(_ dependencies: [String]) -> EventLoopFuture<[ResolvedDocument]> {
        let fetchRequests = dependencies.map(self.fetch)
        let results = EventLoopFuture.whenAllComplete(fetchRequests, on: eventLoop)
        return results.flatMapThrowing { results in
            return try results.map { result -> ResolvedDocument in
                switch result {
                case .success(let ob): return ob
                case .failure(let e): throw e
                }
            }
        }
    }
    
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
        return loop.makeFailedFuture( LeafCacheError.unsupportedFeature("Protocol adopter does not support removing entries") )
    }
    
    /// default implementation of remove to avoid breaking custom LeafCache adopters
    ///     throws an error if used with replace == true
    func insert(
        _ documentName: String,
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<ResolvedDocument>
    {
        if replace { return loop.makeFailedFuture( LeafCacheError.unsupportedFeature("Protocol adopter does not support replacing entries") ) }
        else { return self.insert(documentName, on: loop) }
    }
}

public enum LeafCacheError: LocalizedError {
    // throw if protocol adopter doesn't support requested feature, with optional message
    case unsupportedFeature(String)
    // throw on RW attempts when cache is globably disabled
    case cachingDisabled
    // throw on lazy cache write attempts where entry exists
    case keyExists(String)
    
    var errorDescription: String {
        switch self {
            case .unsupportedFeature(let message): return message
            case .cachingDisabled: return "Caching is globablly disabled"
            case .keyExists(let key): return "Existing entry \(key): use insert with replace=true to overrride"
        }
    }
    
    // cast unspecified errors to
    init(_ message: String) {
        self = .unsupportedFeature(message)
    }
}
