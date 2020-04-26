extension String: Error {}

private struct TagDeclaration {
    let name: String
    let parameters: [ParameterDeclaration]?
    let expectsBody: Bool
}

private struct OpenContext {
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
            guard params.count == 1 else {
                throw "only single parameter support, should be broken earlier"
            }
            switch params[0] {
            case .parameter(let p):
                switch p {
                case .variable(name: let n):
                    return .variable(.init(path: n))
                case .constant(let c):
                    var buffer = ByteBufferAllocator().buffer(capacity: 0)
                    buffer.writeString(c.description)
                    return .raw(buffer)
                case .stringLiteral(let st):
                    var buffer = ByteBufferAllocator().buffer(capacity: 0)
                    buffer.writeString(st)
                    return .raw(buffer)
                default:
                    throw "unsupported parameter \(p)"
                }
                // todo: can prevent some duplication here
            case .expression(let e):
                return .expression(e)
            case .tag(let t):
                return .custom(t)
            }
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
    let name: String
    private var tokens: [LeafToken]
    private var offset: Int
    
    init(name: String, tokens: [LeafToken]) {
        self.name = name
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
                if var last = awaitingBody.last {
                    last.body.append(syntax)
                    awaitingBody.removeLast()
                    awaitingBody.append(last)
                } else {
                    finished.append(syntax)
                }
            }
        case .raw:
            let r = try collectRaw()
            if var last = awaitingBody.last {
                last.body.append(.raw(r))
                awaitingBody.removeLast()
                awaitingBody.append(last)
            } else {
                finished.append(.raw(r))
            }
        default:
            throw "unexpected token \(next)"
        }
    }
    
    private mutating func close(with terminator: TagDeclaration) throws {
        guard !awaitingBody.isEmpty else {
            throw "\(name): found terminator \(terminator), with no corresponding tag"
        }
        let willClose = awaitingBody.removeLast()
        guard willClose.parent.matches(terminator: terminator) else { throw "\(name): unable to match \(willClose.parent) with \(terminator)" }
        
        // closed body
        let newSyntax = try willClose.parent.makeSyntax(body: willClose.body)

        func append(_ syntax: Syntax) {
            if var newTail = awaitingBody.last {
                 newTail.body.append(syntax)
                 awaitingBody.removeLast()
                 awaitingBody.append(newTail)
                 // if the new syntax is a conditional, it may need to be attached
                 // to the last parsed conditional
             } else {
                 finished.append(syntax)
             }
        }

        if case .conditional(let new) = newSyntax {
            switch new.condition {
            // a new if, never attaches to a previous
            case .if:
                append(newSyntax)
            case .elseif, .else:
                // elseif and else ALWAYS attach
                // ensure there is a leading conditional to
                // attach to, prioritize waiting bodies, then check finished
                guard let last = awaitingBody.last?.body.last ?? finished.last, case .conditional(let tail) = last else {
                    throw "unable to attach \(new.condition) to \(finished.last?.description ?? "<>")"
                }
                try tail.attach(new)
            }
        } else {
            append(newSyntax)
        }
    }

    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    // FIXME: This is a blind parsing of `.tagBodyIndicator`
    // ------
    // A tag MAY NOT expect any body given a certain number of parameters, and this will blindly
    // consume colons in that event when it's not inteded; eg `#(variable):` CANNOT expect a body
    // and thus the colon should be assumed to be raw. TagDeclaration should first validate expected
    // parameter pattern against the actual named tag before assuming expectsBody to be true OR false
    private mutating func readTagDeclaration() throws -> TagDeclaration {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected .tagIndicator(\(Character.tagIndicator))" }
        // a tag should ALWAYS follow a tag indicator
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag name following a tag indicator" }
        
        // if no further, then we've ended w/ a tag
        guard let next = peek() else { return TagDeclaration(name: name, parameters: nil, expectsBody: false) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        // .tagIndicator - a new tag started
        switch next {
        case .raw:
            // a basic tag, something like `#date` w/ no params, and no body
            return TagDeclaration(name: name, parameters: nil, expectsBody: false)
        case .tagBodyIndicator:
            if !name.isEmpty { pop() } else { replace(with: .raw(":")) }
            return TagDeclaration(name: name, parameters: nil, expectsBody: true)
        case .parametersStart:
            // An anonymous function `#(variable):` is incapable of having a body, so change tBI to raw
            // Can be more intelligent - there should be observer methods on tag declarations to
            // allow checking if a certain parameter set requires a body or not
            let params = try readParameters()
            var expectsBody = false
            if peek() == .tagBodyIndicator {
                if name.isEmpty { replace(with: .raw(":")) }
                else {
                    pop()
                    expectsBody = true
                }
            }
            return TagDeclaration(name: name, parameters: params, expectsBody: expectsBody)
        case .tagIndicator:
            // a basic tag, something like `#date` w/ no params, and no body
            return TagDeclaration(name: name, parameters: nil, expectsBody: false)
        default:
            throw "found unexpected token " + next.description
        }
    }
    
    private mutating func readParameters() throws -> [ParameterDeclaration] {
        // ensure open parameters
        guard read() == .parametersStart else { throw "expected parameters start" }
        
        var group = [ParameterDeclaration]()
        var paramsList = [ParameterDeclaration]()
        func dump() {
            defer { group = [] }

            if group.isEmpty { return }
            else if group.count == 1 { paramsList.append(group.first!) }
            else { paramsList.append(.expression(group)) }
        }
        
        outer: while let next = peek() {
            switch next {
            case .parametersStart:
                // found a nested () that we will group together into
                // an expression, ie: #if(foo == (bar + car))
                let params = try readParameters()
                // parameter tags not permitted to have bodies
                group.append(.expression(params))
            case .parameter(let p):
                pop()
                switch p {
                case .tag(let name):
                    guard peek() == .parametersStart else { throw "tags in parameter list MUST declare parameter list" }
                    // TODO: remove recursion, in parameters only not so bad
                    let params = try readParameters()
                    // parameter tags not permitted to have bodies
                    group.append(.tag(.init(name: name, params: params, body: nil)))
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
                break outer
            }
        }
        
        return paramsList
    }
    
    private mutating func collectRaw() throws -> ByteBuffer {
        var raw = ByteBufferAllocator().buffer(capacity: 0)
        while let peek = peek(), case .raw(let val) = peek {
            pop()
            raw.writeString(val)
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
    
    private mutating func replace(at offset: Int = 0, with new: LeafToken) {
        self.tokens[self.offset + offset] = new
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
