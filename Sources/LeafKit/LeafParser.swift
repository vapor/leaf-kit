indirect enum Syntax {
    case raw(ByteBuffer)
    case variable(Variable)
    
    case custom(CustomTag)
    
    case conditional(Conditional)
    case loop(Loop)
    case `import`(Import)
    case extend(Extend)
    case export(Export)
}

enum ConditionalSyntax {
    case `if`([ProcessedParameter])
    case `elseif`([ProcessedParameter])
    case `else`
}

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
            case .extend, .import, .export:
                throw "unresolved ast"
            default:
                continue
            }
        }
        
        self.name = name
        self.ast = ast
    }
}

struct Document {
    let name: String
    let ast: [Syntax]
    
    var unresolvedDependencies: [String] {
        return extensions.map { $0.key }
    }
    
    private var extensions: [Syntax.Extend] {
        return ast.compactMap {
            switch $0 {
            case .extend(let e): return e
            default: return nil
            }
        }
    }
}

extension Array where Element == Document {
//    func prioritize() -> Array {
//
//        var prioritized = Array()
//        forEach { element in
//            let extensions = element.extensionNames
//            guard !extensions.isEmpty else {
//                prioritized.append(element)
//                return
//            }
//
//
//        }
//        return sorted { left, right in
//            return false
//        }
//        fatalError()
//    }
}

final class DocumentAccessor {
    private(set) var cache: [String: Document] = [:]
    
    init(_ starting: [Document]) throws {
        try starting.forEach(add)
    }
    
    func load(_ name: String) throws -> Document {
        if let cached = cache[name] { return cached }
        let new = try readFromDisk(name)
        try add(new)
        return new
    }
    
    private func add(_ doc: Document) throws {
        guard cache[doc.name] == nil else { throw "document \(doc.name) already exists" }
        let _ = try doc.unresolvedDependencies.map(load)
        cache[doc.name] = try resolve(doc)
    }
    
    private func readFromDisk(_ name: String) throws -> Document {
        fatalError()
    }
    
    private func resolve(_ doc: Document) throws -> Document {
        var processed: [Syntax] = []
        try doc.ast.forEach { syntax in
            if case .extend(let e) = syntax {
                // should already be cached, avoid load because would be recursion
                guard let base = cache[e.key] else { throw "couldn't resolve extend(\"\(e)\")" }
                let extended = e.extend(base: base.ast)
                processed += extended
            } else {
                processed.append(syntax)
            }
        }
        
        return Document(name: doc.name, ast: processed)
    }
}

import Foundation
final class _DocumentAccess {
    fileprivate func _load(name: String) throws -> UnresolvedDocument {
        // todo: support things like view directory
        guard let data = FileManager.default.contents(atPath: name) else { throw "no data found" }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(data)
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        var parser = LeafParser(tokens: tokens)
        let raw = try parser.altParse()
        return .init(name: name, raw: raw)
    }
    
    fileprivate func load(name: String) throws -> Document {
        // todo: support things like view directory
        guard let data = FileManager.default.contents(atPath: name) else { throw "no data found" }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(data)
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        var parser = LeafParser(tokens: tokens)
        let raw = try parser.altParse()
        // todo: should maybe protect more from raw ast? probably not an issue
        return Document(name: name, ast: raw)
    }
}

final class _DocumentCache {
    private var cache: [String: Document] = [:]
    
    func load(name: String) -> Document? {
        return cache[name]
    }
    func save(_ doc: Document) throws {
        cache[doc.name] = doc
    }
}

protocol _DocumentLoad {
    func rawDocument(name: String) throws -> [Document]
}

final class Resolved {
    
}


struct DocumentResolver {
    private(set) var resolved: [String: ResolvedDocument] = [:]
    private let access: _DocumentAccess
    
    // we're gonna be real lazy about this stop
    // as opposed to trying to prioritize
    // just keep checking what we can compile
    // and if we can't, stick it in the back of
    // the array and try again later
    mutating func resolve(_ raw: [UnresolvedDocument]) throws -> [String: ResolvedDocument] {
        var start = raw
        var drain = start
        var unresolved = [UnresolvedDocument]()
        
        while let next = drain.first {
            drain.removeFirst()

            if canSatisfyAllDependenciesFor(doc: next) {
                try resolve(next: next)
            } else {
                unresolved.append(next)
            }
            
            // until we've exhausted our drain, keep resolving
            guard drain.isEmpty else { continue }
            
            if unresolved.isEmpty {
                // all resolved properly
                break
            } else if unresolved.map({ $0.name }) == start.map({ $0.name }) {
                let fullyResolved = Array(resolved.keys)
                let unresolvedDocuments = unresolved.map { $0.name }

                let grouped = Set(unresolved.flatMap { $0.unresolvedDependencies })
                let missing = grouped.filter { dependency in
                    // we've already loaded the dependency
                    // but haven't been able to resolve it,
                    // continue up tree to see which loads are missing
                    return !unresolvedDocuments.contains(dependency)
                        // this dependency is ready and fully resolved,
                        // we're waiting for others to properly resolve
                        && !fullyResolved.contains(dependency)
                }
                
                guard !missing.isEmpty else {
                    throw "circular dependency, or missing files detected, unable to resolve: \(unresolved)"
                }
                let fresh = try Set(missing).map(access._load)
                // put fresh in front, since they're known dependencies
                start = fresh + unresolved
                drain = start
                unresolved = []
            } else {
                // still some unresolved, let's try another pass
                start = unresolved
                drain = start
                unresolved = []
            }
        }
        
        guard unresolved.isEmpty else { fatalError("can only break when empty") }
        return resolved
    }

    private mutating func resolve(next doc: UnresolvedDocument) throws {
        var processed: [Syntax] = []
        doc.raw.forEach { syntax in
            if case .extend(let e) = syntax {
                guard let base = resolved[e.key] else { fatalError("couldn't extend \(e)") }
                let extended = e.extend(base: base.ast)
                processed += extended
            } else {
                processed.append(syntax)
            }
        }
        
        let new = try ResolvedDocument(name: doc.name, ast: processed)
        resolved[new.name] = new
    }
    
    func canSatisfyAllDependenciesFor(doc: UnresolvedDocument) -> Bool {
        // no deps, easily satisfy
        return doc.unresolvedDependencies.isEmpty
            // see if all dependencies necessary have already been compiled
            || doc.unresolvedDependencies.allSatisfy(resolved.keys.contains)
    }
}

struct ExtendResolver {
    private let raw: [Document]
    private(set) var resolved: [String: Document] = [:]
    
    init(_ docs: [Document]) {
        self.raw = docs
    }
    
    // we're gonna be real lazy about this stop
    // as opposed to trying to prioritize
    // just keep checking what we can compile
    // and if we can't, stick it in the back of
    // the array and try again later
    mutating func resolve() throws -> [String: Document] {
        var drain = self.raw
        var unresolved = [Document]()
        while let next = drain.first {
            drain.removeFirst()
            
            if canSatisfyAllDependenciesFor(doc: next) {
                resolve(next: next)
            } else {
                unresolved.append(next)
            }
            
            guard drain.isEmpty else { continue }
            if unresolved.isEmpty {
                break
            } else if unresolved.map({ $0.name }) == raw.map({ $0.name }) {
                break
            } else {
                drain = unresolved
                unresolved = []
            }
        }
        
        /// here again is pretty lazy, but we see what's unresolved
        /// and attempt to load these from disk since they're not cached
        if !unresolved.isEmpty {
            
        }
        
        guard unresolved.isEmpty else { throw "unable to resolve \(unresolved)" }
        return resolved
    }
    
    private mutating func resolve(next doc: Document) {
        var processed: [Syntax] = []
        doc.ast.forEach { syntax in
            if case .extend(let e) = syntax {
                guard let base = resolved[e.key] else { fatalError("couldn't extend \(e)") }
                let extended = e.extend(base: base.ast)
                processed += extended
            } else {
                processed.append(syntax)
            }
        }
        
        let new = Document(name: doc.name, ast: processed)
        resolved[new.name] = new
    }
    
    func canSatisfyAllDependenciesFor(doc: Document) -> Bool {
        // no deps, easily satisfy
        // see if all dependencies necessary have already been compiled
        return doc.unresolvedDependencies.isEmpty
            || doc.unresolvedDependencies.allSatisfy(resolved.keys.contains)
    }
}

/*
 
 */
extension Syntax.Extend {
    func extend(base: [Syntax]) -> [Syntax] {
        // from the base
        var extended = [Syntax]()
        base.forEach { syntax in
            switch syntax {
            case .import(let im):
                if let export = exports[im.key] {
                    // export exists, inject body
                    extended += export.body
                } else {
                    // any unsatisfied import will continue
                    // and can be satisfied later
                    extended.append(syntax)
                }
            default:
                extended.append(syntax)
            }
            
        }
        return extended
    }
}

let block = "  "

extension Syntax {
    struct Import {
        let key: String
        init(_ params: [ProcessedParameter]) throws {
            guard params.count == 1 else { throw "import only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
        }
    }
    
    struct Extend {
        let key: String
        // TODO: RANDOM ORDER FAILS TEST, OK?
        let exports: [String: Export]

        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
            guard params.count == 1 else { throw "extend only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "extend expected parameter type, got \(params[0])" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
            
            var exports: [String: Export] = [:]
            try body.forEach { syntax in
                switch syntax {
                // extend can ONLY export, raw space in body ignored
                case .raw: return
                case .export(let export):
                    exports[export.key] = export
                default:
                    throw "unexpected token in extend body: \(syntax).. use raw space and `export` only"
                }
            }
            self.exports = exports
        }
    }
    
    struct Export {
        let key: String
        let body: [Syntax]
        
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
            guard (1...2).contains(params.count) else { throw "export expects 1 or 2 params" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "export only supports string literals" }
            self.key = s
            
            if params.count == 2 {
                guard case .parameter(let p) = params[1] else { throw "expected parameter" }
                guard case .stringLiteral(let s) = p else { throw "extend only supports string literals" }
                guard body.isEmpty else { throw "extend w/ two args requires NO body" }
                var buffer = ByteBufferAllocator().buffer(capacity: 0)
                buffer.writeString(s)
                self.body = [.raw(buffer)]
            } else {
                guard !body.isEmpty else { throw "export requires body or secondary arg" }
                self.body = body
            }
        }
        
        func print(depth: Int) -> String {
            var print = ""
            
            print += "export(" + key.debugDescription + ")"
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth) } .joined(separator: "\n")
            }
            
            var buffer = ""
            for _ in 0..<depth {
                buffer += block
            }
            return print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
        }
    }
    
    final class Conditional {
        let condition: ConditionalSyntax
        let body: [Syntax]
        private(set) var next: Conditional?
        
        init(_ condition: ConditionalSyntax, body: [Syntax]) {
            self.condition = condition
            self.body = body
        }
        
        func attach(_ new: Conditional) throws {
            var tail = self
            while let next = tail.next {
                tail = next
            }
            
            // todo: verify that is valid attachment
            tail.next = new
        }
        
        func print(depth: Int) -> String {
            var print = "conditional:\n"
            print += _print(depth: depth + 1)
            return print
        }
        
        func _print(depth: Int) -> String {
            var print = ""
            switch condition {
            case .if(let params):
                print += "if(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .elseif(let params):
                print += "elseif(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .else:
                print += "else"
            }
            
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth) } .joined(separator: "\n")
            }
            
            var buffer = ""
            let block = "  "
            for _ in 0..<depth {
                buffer += block
            }
            print = print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
            
            // todo: remove recursion
            if let next = self.next {
                print += "\n"
                print += next._print(depth: depth)
            }
            return print
        }
    }
    
    struct Loop: CustomStringConvertible {
        /// the key to use when accessing items
        let item: String
        /// the key to use to access the array
        let array: String
        
        /// the body of the looop
        let body: [Syntax]
        
        /// initialize a new loop
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
            guard
                params.count == 1,
                case .expression(let list) = params[0],
                list.count == 3,
                case .parameter(let left) = list[0],
                case .variable(let item) = left,
                case .parameter(let `in`) = list[1],
                case .keyword(let k) = `in`,
                k == .in,
                case .parameter(let right) = list[2],
                case .variable(let array) = right
                else { throw "for loops expect single expression, 'name in names'" }
            self.item = item
            self.array = array
            
            guard !body.isEmpty else { throw "for loops require a body" }
            self.body = body
        }
        
        var description: String {
            return print(depth: 0)
        }
        
        func print(depth: Int) -> String {
            var print = ""
            print += "for(" + item + " in " + array + "):\n"
            print += body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            
            var buffer = ""
            for _ in 0..<depth {
                buffer += block
            }
            return print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
        }
    }
    
    struct Variable {
        let name: String
        
        init(_ params: [ProcessedParameter]) throws {
            guard params.count == 1 else { throw "only single parameter variable supported currently" }
            guard case .parameter(let p) = params[0] else { throw "expected single parameter" }
            switch p {
            case .variable(let n):
                self.name = n
            default: throw "todo: implement constant and literal? maybe process earlier as not variable, but raw"
            }
        }
        
        func print(depth: Int) -> String {
            return "variable(" + name + ")"
        }
    }
    
    struct CustomTag {
        let name: String
        let params: [ProcessedParameter]
        let body: [Syntax]?
    }
}

extension Syntax: CustomStringConvertible {
    
    var description: String {
        return print(depth: 0)
    }
    
    func print(depth: Int) -> String {
        var print = ""
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            print += "raw(\(string.debugDescription))"
        case .variable(let v):
            print += v.print(depth: depth)
        case .custom(let custom):
            print += custom.name + "(" + custom.params.map { $0.description } .joined(separator: ", ") + ")"
            if let body = custom.body, !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
        case .conditional(let c):
            print += c.print(depth: depth)
        case .loop(let loop):
            print += loop.print(depth: depth)
        case .import(let imp):
            print += "import(" + imp.key.debugDescription + ")"
        case .extend(let ext):
            print += "extend(" + ext.key.debugDescription + ")"
            if !ext.exports.isEmpty {
                print += ":\n" + ext.exports.values.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
        case .export(let export):
            print += export.print(depth: depth)
        }
        
        var buffer = ""
        for _ in 0..<depth {
            buffer += block
        }
        print = print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")

        return print
    }
}

extension String: Error {}

struct TagDeclaration {
    let name: String
    let parameters: [ProcessedParameter]?
    let expectsBody: Bool
}

final class OpenContext {
    let parent: TagDeclaration
    var body: [Syntax] = []
    init(_ parent: TagDeclaration) {
        self.parent = parent
    }
}

extension TagDeclaration {
    func makeSyntax(body: [Syntax]) throws -> Syntax {
        let params = parameters ?? []

        switch name {
        case let n where n.starts(with: "end"):
            throw "unable to convert terminator to syntax"
        case "":
            return try .variable(.init(params))
        case "if":
            return .conditional(.init(.if(params), body: body))
        case "elseif":
            return .conditional(.init(.elseif(params), body: body))
        case "else":
            guard params.count == 0 else { throw "else does not accept params" }
            return .conditional(.init(.else, body: body))
        case "for":
            return try .loop(.init(params, body: body))
        case "export":
            return try .export(.init(params, body: body))
        case "extend":
            return try .extend(.init(params, body: body))
        case "import":
            guard body.isEmpty else { throw "import does not accept a body" }
            return try .import(.init(params))
        default:
            return .custom(.init(name: name, params: params, body: body))
        }
    }
}

extension TagDeclaration {
    var isTerminator: Bool {
        switch name {
        case let x where x.starts(with: "end"): return true
        // dual function
        case "elseif", "else": return true
        default: return false
        }
    }
    
    func matches(terminator: TagDeclaration) -> Bool {
        guard terminator.isTerminator else { return false }
        switch terminator.name {
        // if can NOT be a terminator
        case "else", "elseif":
            // else and elseif can only match to if or elseif
            return name == "if" || name == "elseif"
        case "endif":
            return name == "if" || name == "elseif" || name == "else"
        default:
            return terminator.name == "end" + name
        }
    }
}


struct LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }

    
    var finished: [Syntax] = []
    var awaitingBody: [OpenContext] = []
    
    mutating func altParse() throws -> [Syntax] {
        while let next = peek() {
            try handle(next: next)
        }
        return finished
    }
    
    private mutating func handle(next: LeafToken) throws {
        switch next {
        case .tagIndicator:
            let declaration = try readTagDeclaration()
            // check terminator first
            // always takes priority, especially for dual body/terminator functors
            if declaration.isTerminator { try close(with: declaration) }
            
            // this needs to be a secondary if-statement, and
            // not joined above
            //
            // this allows for dual functors, a la elseif
            if declaration.expectsBody {
                awaitingBody.append(.init(declaration))
            } else if declaration.isTerminator {
                // dump terminators that don't also have a body,
                // already closed above
                // MUST close FIRST (as above)
                return
            } else {
                let syntax = try declaration.makeSyntax(body: [])
                if let last = awaitingBody.last {
                    last.body.append(syntax)
                } else {
                    finished.append(syntax)
                }
            }
        case .raw:
            let r = try collectRaw()
            if let last = awaitingBody.last {
                last.body.append(.raw(r))
            } else {
                finished.append(.raw(r))
            }
        default:
            throw "unexpected token \(next)"
        }
    }
    
    mutating func close(with terminator: TagDeclaration) throws {
        guard !awaitingBody.isEmpty else { throw "found terminator \(terminator), with no corresponding tag" }
        let willClose = awaitingBody.removeLast()
        guard willClose.parent.matches(terminator: terminator) else { throw "unable to match \(willClose.parent) with \(terminator)" }
        
        // closed body
        let newSyntax = try willClose.parent.makeSyntax(body: willClose.body)
        
        // if another element exists, then we are in
        // a nested body context, attach new syntax
        // as body element to this new context
        if let newTail = awaitingBody.last {
            newTail.body.append(newSyntax)
        // if the new syntax is a conditional, it may need to be attached
        // to the last parsed conditional
        } else if case .conditional(let new) = newSyntax {
            switch new.condition {
            // a new if, never attaches to a previous
            case .if:
                finished.append(newSyntax)
            case .elseif, .else:
                // elseif and else ALWAYS attach
                // ensure there is a leading conditional to
                // attach to
                guard let last = finished.last, case .conditional(let tail) = last else {
                    throw "unable to attach \(new.condition) to \(finished.last?.description ?? "<>")"
                }
                try tail.attach(new)
            }
        } else {
            // if there's no open contexts,
            // then we can just store
            finished.append(newSyntax)
        }
    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    private mutating func readTagDeclaration() throws -> TagDeclaration {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
        // a tag should ALWAYS follow a tag indicator
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
        
        // if no further, then we've ended w/ a tag
        guard let next = peek() else { return TagDeclaration(name: name, parameters: nil, expectsBody: false) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        switch next {
        case .raw:
            // a basic tag, something like `#date` w/ no params, and no body
            return TagDeclaration(name: name, parameters: nil, expectsBody: false)
        case .tagBodyIndicator:
            // consume ':'
            pop()
            // no parameters, but with a body
            return TagDeclaration(name: name, parameters: nil, expectsBody: true)
        case .parametersStart:
            let params = try readParameters()
            var expectsBody = false
            if peek() == .tagBodyIndicator {
                expectsBody = true
                pop()
            }
            return TagDeclaration(name: name, parameters: params, expectsBody: expectsBody)
        default:
            throw "found unexpected token " + next.description
        }
    }
    
    private mutating func readParameters() throws -> [ProcessedParameter] {
        // ensure open parameters
        guard read() == .parametersStart else { throw "expected parameters start" }
        
        var group = [ProcessedParameter]()
        var paramsList = [ProcessedParameter]()
        func dump() {
            defer { group = [] }

            if group.isEmpty { return }
            else if group.count == 1 { paramsList.append(group.first!) }
            else { paramsList.append(.expression(group)) }
        }
        
        outer: while let next = peek() {
            switch next {
            case .parametersStart:
                fatalError("should not find")
            case .parameter(let p):
                pop()
                switch p {
                case .tag(let name):
                    guard peek() == .parametersStart else { throw "tags in parameter list MUST declare parameter list" }
                    // TODO: remove recursion, in parameters only not so bad
                    let params = try readParameters()
                    // parameter tags not permitted to have bodies
                    group.append(.tag(name: name, params: params))
                default:
                    group.append(.parameter(p))
                }
            case .parametersEnd:
                pop()
                dump()
                break outer
            case .parameterDelimiter:
                pop()
                dump()
            case .whitespace:
                pop()
                continue
            default:
                print("breaking outer, found: \(next)")
                break outer
            }
        }
        
        return paramsList
    }
    
    private mutating func collectRaw() throws -> ByteBuffer {
        var raw = ByteBufferAllocator().buffer(capacity: 0)
        while let peek = peek(), case .raw(var val) = peek {
            pop()
            raw.writeBuffer(&val)
        }
        return raw
    }
    
    func peek() -> LeafToken? {
        guard self.offset < self.tokens.count else {
            return nil
        }
        return self.tokens[self.offset]
    }
    
    private mutating func pop() {
        self.offset += 1
    }
    
    private mutating func read() -> LeafToken? {
        guard self.offset < self.tokens.count else { return nil }
        guard let val = self.peek() else { return nil }
        pop()
        return val
    }
    
    mutating func readWhile(_ check: (LeafToken) -> Bool) -> [LeafToken]? {
        guard self.offset < self.tokens.count else { return nil }
        var matched = [LeafToken]()
        while let next = peek(), check(next) {
            matched.append(next)
        }
        return matched.isEmpty ? nil : matched
    }
}
