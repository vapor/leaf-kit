extension String: Error {}

private struct TagDeclaration {
    let name: String
    let parameters: [ProcessedParameter]?
    let expectsBody: Bool
}

private final class OpenContext {
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

    
    private var finished: [Syntax] = []
    private var awaitingBody: [OpenContext] = []
    
    mutating func parse() throws -> [Syntax] {
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
    
    private mutating func close(with terminator: TagDeclaration) throws {
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
