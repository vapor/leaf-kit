import NIOConcurrencyHelpers

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
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument>
    func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?>
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
    
    public func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument> {
        self.lock.lock()
        defer { self.lock.unlock() }
       if isEnabled {
            self.cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }
    
    public func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return loop.makeSucceededFuture(self.cache[documentName])
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
        let expanded = expand(path: path)
        let document = fetch(path: expanded)
        return document.flatMapThrowing { try self.render($0, context: context) }
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
        return cache.load(documentName: expanded, on: eventLoop).flatMap { cached in
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
        
        return syntax.flatMap { syntax in
            let dependencies = self.readDependencies(syntax.dependencies)
            let resolved = dependencies.flatMapThrowing { dependencies -> ResolvedDocument in
                let unresolved = UnresolvedDocument(name: file, raw: syntax)
                let resolver = ExtendResolver(document: unresolved, dependencies: dependencies)
                return try resolver.resolve(rootDirectory: self.configuration.rootDirectory)
            }
            
            return resolved.flatMap { resolved in self.cache.insert(resolved, on: self.eventLoop) }
        }
    }
    
    private func readDependencies(_ dependencies: [String]) -> EventLoopFuture<[ResolvedDocument]> {
        let fetchRequests = dependencies.map(self.fetch)
        let results = EventLoopFuture.whenAllComplete(fetchRequests, on: self.eventLoop)
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
