public struct LeafConfig {
    public var rootDirectory: String
    
    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }
}

protocol LeafCache {
    func insert(_ document: ResolvedDocument, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument>
    func load(path: String, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument?>
}

final class Cache: LeafCache {
    func insert(_ document: ResolvedDocument, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument> {
        return loop.makeSucceededFuture(document)
    }
    
    func load(path: String, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument?> {
        return loop.makeSucceededFuture(nil)
    }
}

protocol _CustomFunctionProtocol {
    func serialize(params: [ProcessedParameter],
                   body: [Syntax]?,
                   context: [String: TemplateData]) throws -> TemplateData
}

enum ResolvedParams {
    
}

protocol _CustomTagProtocol {
    func serialize(params: [ProcessedParameter],
                   body: [Syntax]?,
                   context: [String: TemplateData]) throws -> TemplateData
}

extension TemplateData {
    init(_ buffer: ByteBuffer) {
        var buffer = buffer
        let str = buffer.readString(length: buffer.readableBytes)
        fatalError()
    }
}

protocol CustomTagProtocol {
    var params: [ProcessedParameter] { get }
    var body: [Syntax]? { get }
    init(params: [ProcessedParameter], body: [Syntax]?) throws
    func serialize(context: [String: TemplateData]) throws -> ByteBuffer
}

struct Lowercased: CustomTagProtocol {
    let params: [ProcessedParameter]
    let body: [Syntax]?
    
    let `var`: String?
    let literal: String?
    
    init(params: [ProcessedParameter], body: [Syntax]?) throws {
        self.params = params
        self.body = body
        
        guard params.count == 1 else { throw "unexpected input lowercased" }
        guard case .parameter(let param) = params[0] else { throw "unexpected type" }
        switch param {
        case .stringLiteral(let s):
            self.var = nil
            self.literal = s
        case .variable(name: let v):
            self.var = v
            self.literal = nil
        default:
            throw "only accepts string literal or variaable"
        }
    }

    func serialize(context: [String: TemplateData]) throws -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        
        if let literal = self.literal {
            buffer.writeString(literal.lowercased())
        } else if let v = self.var, let value = context[v]?.string {
            buffer.writeString(value.lowercased())
        }
        
        return buffer
    }
}

public final class LeafRenderer {
    let config: LeafConfig
    let file: NonBlockingFileIO
    let eventLoop: EventLoop
    
    // TODO: More Cache Options
    let cache: LeafCache = Cache()
    
    public init(
        config: LeafConfig,
        threadPool: BlockingIOThreadPool,
        eventLoop: EventLoop
    ) {
        self.config = config
        self.file = .init(threadPool: threadPool)
        self.eventLoop = eventLoop
    }
    
    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        let path = path.hasSuffix(".leaf") ? path : path + ".leaf"
        let expanded = config.rootDirectory + path
        let document = fetch(path: expanded)
        return document.flatMapThrowing { document in
            throw "todo: serialize document w/ context"
        }
    }
    
    private func fetch(path: String) -> EventLoopFuture<ResolvedDocument> {
        let path = path.hasSuffix(".leaf") ? path : path + ".leaf"
        let expanded = config.rootDirectory + path
        return cache.load(path: expanded, on: eventLoop).flatMap { cached in
            guard let cached = cached else { return self.read(file: path) }
            return self.eventLoop.makeSucceededFuture(cached)
        }
    }
    
    private func read(file: String) -> EventLoopFuture<ResolvedDocument> {
        let raw = readBytes(file: file)
        
        let syntax = raw.flatMapThrowing { raw -> [Syntax] in
            var lexer = LeafLexer(template: raw)
            let tokens = try lexer.lex()
            var parser = LeafParser(tokens: tokens)
            return try parser.parse()
        }
        
        return syntax.flatMap { syntax in
            let dependencies = self.readDependencies(syntax.dependencies)
            let resolved = dependencies.flatMapThrowing { dependencies -> ResolvedDocument in
                let unresolved = UnresolvedDocument(name: file, raw: syntax)
                let resolver = ExtendResolver(document: unresolved, dependencies: dependencies)
                return try resolver.resolve()
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
        let openFile  = self.file.openFile(path: file, eventLoop: self.eventLoop)
        return openFile.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
            let allocator = ByteBufferAllocator()
            let read = self.file.read(fileRegion: region, allocator: allocator, eventLoop: self.eventLoop)
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
