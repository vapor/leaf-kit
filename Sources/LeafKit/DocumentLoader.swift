struct UnresolvedDocument {
    let name: String
    let raw: [Syntax]
    
    var unresolvedDependencies: [String] {
        return extensions.map { $0.key }
    }
    
    private var extensions: [Syntax.Extend] {
        return raw.compactMap {
            switch $0 {
            case .extend(let e): return e
            default: return nil
            }
        }
    }
}

struct ResolvedDocument {
    let name: String
    let ast: [Syntax]
    
    init(name: String, ast: [Syntax]) throws {
        for syntax in ast {
            switch syntax {
            case .extend, .export:
                // all extentions MUST be resolved
                throw "unresolved ast"
            default:
                continue
            }
        }
        
        self.name = name
        self.ast = ast
    }
}

internal struct ExtendResolver {
    private let document: UnresolvedDocument
    private let dependencies: [String: ResolvedDocument]
    
    init(document: UnresolvedDocument, dependencies list: [ResolvedDocument]) {
        self.document = document
        var dependencies = [String: ResolvedDocument]()
        list.forEach { dep in
            dependencies[dep.name] = dep
        }
        self.dependencies = dependencies
    }
    
    
    /// an individual object resolution
    /// could probably be optimized
    func resolve() throws -> ResolvedDocument {
        guard canSatisfyAllDependencies() else { throw "unable to resolve \(document)" }
        
        var processed: [Syntax] = []
        document.raw.forEach { syntax in
            if case .extend(let e) = syntax {
                guard let base = dependencies[e.key] else { fatalError("disallowed by guard") }
                let extended = e.extend(base: base.ast)
                processed += extended
            } else {
                processed.append(syntax)
            }
        }
        
        return try ResolvedDocument(name: document.name, ast: processed)
    }
    
    
    private func canSatisfyAllDependencies() -> Bool {
        // no deps, easily satisfy
        return document.unresolvedDependencies.isEmpty
            // see if all dependencies necessary have already been compiled
            || document.unresolvedDependencies.allSatisfy(dependencies.keys.contains)
    }
}

// MARK: Testing Only
import Foundation

protocol FileAccessProtocol {
    func load(name: String) throws -> ByteBuffer
    func fload(name: String) throws -> EventLoopFuture<ByteBuffer>
}

// TODO: Take things like view directory
final class FileAccessor: FileAccessProtocol {
    func fload(name: String) throws -> EventLoopFuture<ByteBuffer> {
        fatalError()
    }

    func load(name: String) throws -> ByteBuffer {
        // todo: support things like view directory
        guard let data = FileManager.default.contents(atPath: name) else { throw "no document found at path \(name)" }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(data)
        return buffer
    }
}

internal final class DocumentLoader {
    private var fileAccess: FileAccessProtocol
    private var resolved: [String: ResolvedDocument] = [:]
    private var unresolved: [String: UnresolvedDocument] = [:]
    
    init(_ access: FileAccessProtocol = FileAccessor()) {
        self.fileAccess = access
    }
    
    /// insert raw documents into the loader manually
    @discardableResult
    func insert(name: String, raw: String) throws -> UnresolvedDocument {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(raw)
        return try insert(name: name, raw: buffer)
    }
    
    /// insert raw documents into the loader manually
    @discardableResult
    func insert(name: String, raw: ByteBuffer) throws -> UnresolvedDocument {
        let document = try parse(name: name, raw: raw)
        unresolved[name] = document
        return document
    }
    
    // insert raw documents into the loader manually
    @discardableResult
    func insert(name: String, raw: [Syntax]) -> UnresolvedDocument {
        let document = UnresolvedDocument(name: name, raw: raw)
        unresolved[name] = document
        return document
    }
    
    /// parse a raw body into an unresolved document
    private func parse(name: String, raw: ByteBuffer) throws -> UnresolvedDocument {
        var raw = raw
        guard let str = raw.readString(length: raw.readableBytes) else { throw "unable to read document" }
        var lexer = LeafLexer(template: str)
        let tokens = try lexer.lex()
        var parser = LeafParser(tokens: tokens)
        let syntax = try parser.parse()
        return UnresolvedDocument(name: name, raw: syntax)
    }
    
    /// Loads and resolves a document
    
    func load(_ name: String) throws -> ResolvedDocument {
        if let cached = resolved[name] { return cached }
        if let cached = unresolved[name] { return try resolve(cached) }
        
        // load raw from file
        let buffer = try fileAccess.load(name: name)
        let new = try parse(name: name, raw: buffer)
        return try resolve(new)
    }
    
    /// an individual object resolution
    /// could probably be optimized
    private func resolve(_ doc: UnresolvedDocument) throws -> ResolvedDocument {
        unresolved[doc.name] = nil
        try resolve([doc])
        guard let value = resolved[doc.name] else { throw "unable to resolve \(doc)" }
        return value
    }
    
    // we're gonna be real lazy about this stop
    // as opposed to trying to prioritize
    // just keep checking what we can compile
    // and if we can't, stick it in the back of
    // the array and try again later
    private func resolve(_ raw: [UnresolvedDocument]) throws {
        var start = raw + unresolved.values
        unresolved = [:]
        var drain = start
        var waitingToRetry = [UnresolvedDocument]()
        
        while let next = drain.first {
            drain.removeFirst()
            
            if canSatisfyAllDependenciesFor(doc: next) {
                try ready(next: next)
            } else {
                waitingToRetry.append(next)
            }
            
            // until we've exhausted our drain, keep resolving
            guard drain.isEmpty else { continue }
            
            if waitingToRetry.isEmpty {
                // all resolved properly
                break
            } else if waitingToRetry.map({ $0.name }) == start.map({ $0.name }) {
                // if those still waiting are the same as those we started with, then
                // we've found a point where we can't resolve
                let fullyResolved = Array(resolved.keys)
                let unresolvedDocuments = waitingToRetry.map { $0.name }
                
                let allUnresolvedDependencies = Set(waitingToRetry.flatMap { $0.unresolvedDependencies })
                
                // the result here is all dependencies that are not
                // already loaded into the system, attempt to fetch from disk
                let missing = allUnresolvedDependencies.filter { dependency in
                    // we've already loaded the dependency
                    // but haven't been able to resolve it,
                    // continue up tree to see which loads are missing
                    return !unresolvedDocuments.contains(dependency)
                        // this dependency is ready and fully resolved,
                        // there must be other dependencies
                        // to resolve before this dependency can work
                        && !fullyResolved.contains(dependency)
                }
                
                // TODO: Would be nice to detect circular or unresolvable dependencies here
                guard !missing.isEmpty else {
                    unresolved = [:]
                    waitingToRetry.forEach { stillRaw in
                        unresolved[stillRaw.name] = stillRaw
                    }
                    return
                }
                
                // load missing dependencies from files
                let fresh = try Set(missing).map { name -> UnresolvedDocument in
                    let raw = try fileAccess.load(name: name)
                    return try parse(name: name, raw: raw)
                }
                
                
                // put fresh in front, since they're known dependencies
                start = fresh + waitingToRetry
                drain = start
                waitingToRetry = []
            } else {
                // still some unresolved, let's try another pass
                start = waitingToRetry
                drain = start
                waitingToRetry = []
            }
        }
        
        guard waitingToRetry.isEmpty else { fatalError("can only break when empty") }
    }
    
    private func ready(next doc: UnresolvedDocument) throws {
        precondition(canSatisfyAllDependenciesFor(doc: doc))
        
        var processed: [Syntax] = []
        try doc.raw.forEach { syntax in
            if case .extend(let e) = syntax {
                let base = try load(e.key)
                let extended = e.extend(base: base.ast)
                processed += extended
            } else {
                processed.append(syntax)
            }
        }
        
        let new = try ResolvedDocument(name: doc.name, ast: processed)
        resolved[new.name] = new
    }
    
    private func canSatisfyAllDependenciesFor(doc: UnresolvedDocument) -> Bool {
        // no deps, easily satisfy
        return doc.unresolvedDependencies.isEmpty
            // see if all dependencies necessary have already been compiled
            || doc.unresolvedDependencies.allSatisfy(resolved.keys.contains)
    }
}
