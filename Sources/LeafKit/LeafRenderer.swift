import NIOConcurrencyHelpers

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
}

public final class DefaultLeafCache: LeafCache {
    let lock: Lock
    var cache: [String: ResolvedDocument]
    
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
        self.cache[document.name] = document
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
    let params: [ParameterDeclaration]
    let data: [String: LeafData]
    let body: [Syntax]?
}

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        let resolver = ParameterResolver(params: ctx.params, data: ctx.data)
        let resolved = try resolver.resolve()
        guard let str = resolved.first?.result.string else { throw "unable to lowercase unexpected data" }
        return .init(.string(str.lowercased()))
    }
}

struct Count: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        let resolver = ParameterResolver(params: ctx.params, data: ctx.data)
        let resolved = try resolver.resolve()
        
        guard resolved.count == 1,
            let storage = resolved.first?.result.storage
        else { throw "unable to count expected one parameter" }
        
        let count: LeafDataStorage
        
        switch storage {
        case .dictionary(let dict): count = .int(dict.values.count)
        case .array(let arr): count = .int(arr.count)
        default: throw "unable to count expected array or dictionary"
        }
        
        return .init(count)
    }
}

public final class LeafRenderer {
    public let configuration: LeafConfiguration
    public let cache: LeafCache
    public let fileio: NonBlockingFileIO
    public let eventLoop: EventLoop
    
    public init(
        configuration: LeafConfiguration,
        cache: LeafCache = DefaultLeafCache(),
        fileio: NonBlockingFileIO,
        eventLoop: EventLoop
    ) {
        self.configuration = configuration
        self.cache = cache
        self.fileio = fileio
        self.eventLoop = eventLoop
    }
    
    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        let expanded = expand(path: path)
        let document = fetch(path: expanded)
        return document.flatMapThrowing { try self.render($0, context: context) }
    }
    
    func render(_ doc: ResolvedDocument, context: [String: LeafData]) throws -> ByteBuffer {
        var serializer = LeafSerializer(ast: doc.ast, context: context)
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
        print("reading \(file)")
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
        let openFile = self.fileio.openFile(path: file, eventLoop: self.eventLoop)
        return openFile.flatMapErrorThrowing { error in
            throw "unable to open file \(file)"
        }.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
            let allocator = ByteBufferAllocator()
            let read = self.fileio.read(fileRegion: region, allocator: allocator, eventLoop: self.eventLoop)
            return read.flatMapThrowing { (buffer)  in
                try handle.close()
                return buffer
            }
        }
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
