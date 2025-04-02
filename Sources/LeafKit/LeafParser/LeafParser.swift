import NIOCore

// This is a horrible, horrible mistake, it really stinks that it can't be taken back.
extension Swift.String: Swift.Error {}

struct LeafParser {
    // MARK: - Internal Only

    let name: String

    init(name: String, tokens: [LeafToken]) {
        self.name = name
        self.tokens = tokens
        self.offset = 0
    }

    mutating func parse() throws -> [Syntax] {
        while let next = self.peek() {
            try self.handle(next: next)
        }
        return self.finished
    }

    // MARK: - Private Only

    private var tokens: [LeafToken]
    private var offset: Int

    private var finished: [Syntax] = []
    private var awaitingBody: [OpenContext] = []

    private mutating func handle(next: LeafToken) throws {
        switch next {
        case .tagIndicator:
            let declaration = try self.readTagDeclaration()
            // check terminator first
            // always takes priority, especially for dual body/terminator functors
            if declaration.isTerminator {
                try self.close(with: declaration)
            }

            // this needs to be a secondary if-statement, and
            // not joined above
            //
            // this allows for dual functors, a la elseif
            if declaration.expectsBody {
                self.awaitingBody.append(.init(declaration))
            } else if declaration.isTerminator {
                // dump terminators that don't also have a body,
                // already closed above
                // MUST close FIRST (as above)
                return
            } else {
                let syntax = try declaration.makeSyntax(body: [])
                if var last = self.awaitingBody.last {
                    last.body.append(syntax)
                    self.awaitingBody.removeLast()
                    self.awaitingBody.append(last)
                } else {
                    self.finished.append(syntax)
                }
            }
        case .raw:
            let r = try self.collectRaw()
            if var last = self.awaitingBody.last {
                last.body.append(.raw(r))
                self.awaitingBody.removeLast()
                self.awaitingBody.append(last)
            } else {
                self.finished.append(.raw(r))
            }
        default:
            throw LeafError(.unknownError("unexpected token \(next)"))
        }
    }

    private mutating func close(with terminator: TagDeclaration) throws {
        guard !self.awaitingBody.isEmpty else {
            throw LeafError(.unknownError("\(self.name): found terminator \(terminator), with no corresponding tag"))
        }
        let willClose = self.awaitingBody.removeLast()
        guard willClose.parent.matches(terminator: terminator) else {
            throw LeafError(.unknownError("\(name): unable to match \(willClose.parent) with \(terminator)"))
        }

        // closed body
        let newSyntax = try willClose.parent.makeSyntax(body: willClose.body)

        func append(_ syntax: Syntax) {
            if var newTail = self.awaitingBody.last {
                newTail.body.append(syntax)
                self.awaitingBody.removeLast()
                self.awaitingBody.append(newTail)
                // if the new syntax is a conditional, it may need to be attached
                // to the last parsed conditional
            } else {
                self.finished.append(syntax)
            }
        }

        if case .conditional(let new) = newSyntax {
            guard let conditional = new.chain.first else {
                throw LeafError(.unknownError("Malformed syntax block"))
            }
            switch conditional.0.naturalType {
            // a new if, never attaches to a previous
            case .if:
                append(newSyntax)
            case .elseif, .else:
                let aW = self.awaitingBody.last?.body
                let previousBlock: Syntax?
                switch aW {
                case .none: previousBlock = self.finished.last
                case .some(let b): previousBlock = b.last
                }
                guard let existingConditional = previousBlock,
                    case .conditional(var tail) = existingConditional
                else {
                    throw LeafError(.unknownError("Can't attach \(conditional.0) to \(previousBlock?.description ?? "empty AST")"))
                }
                try tail.attach(new)
                switch aW {
                case .none:
                    self.finished[self.finished.index(before: self.finished.endIndex)] = .conditional(tail)
                case .some(_):
                    self.awaitingBody[self.awaitingBody.index(before: self.awaitingBody.endIndex)].body.removeLast()
                    self.awaitingBody[self.awaitingBody.index(before: self.awaitingBody.endIndex)].body.append(.conditional(tail))
                }
            }
        } else {
            append(newSyntax)
        }
    }

    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    // ------
    // A tag MAY NOT expect any body given a certain number of parameters, and this will blindly
    // consume colons in that event when it's not inteded; eg `#(variable):` CANNOT expect a body
    // and thus the colon should be assumed to be raw. TagDeclaration should first validate expected
    // parameter pattern against the actual named tag before assuming expectsBody to be true OR false
    private mutating func readTagDeclaration() throws -> TagDeclaration {
        // consume tag indicator
        guard let first = self.read(), first == .tagIndicator else {
            throw LeafError(.unknownError("expected .tagIndicator(\(LeafConfiguration.tagIndicator))"))
        }
        // a tag should ALWAYS follow a tag indicator
        guard let tag = self.read(), case .tag(let name) = tag else {
            throw LeafError(.unknownError("expected tag name following a tag indicator"))
        }

        // if no further, then we've ended w/ a tag
        guard let next = self.peek() else {
            return TagDeclaration(name: name, parameters: nil, expectsBody: false)
        }

        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        // .tagIndicator - a new tag started
        switch next {
        // MARK: no param, no body case should be re-evaluated?
        // we require that tags have parameter notation INSIDE parameters even when they're
        // empty - eg `#tag(anotherTag())` - so `#anotherTag()` should be required, not
        // `#anotherTag`. If that's enforced, the only acceptable non-decaying noparam/nobody
        // use would be `#endTag` to close a body
        case .raw,
            .tagIndicator:
            // a basic tag, something like `#date` w/ no params, and no body
            return TagDeclaration(name: name, parameters: nil, expectsBody: false)
        // MARK: anonymous tBI (`#:`) probably should decay tagIndicator to raw?
        case .tagBodyIndicator:
            if !name.isEmpty {
                self.pop()
            } else {
                self.replace(with: .raw(":"))
            }
            return TagDeclaration(name: name, parameters: nil, expectsBody: true)
        case .parametersStart:
            // An anonymous function `#(variable):` is incapable of having a body, so change tBI to raw
            // Can be more intelligent - there should be observer methods on tag declarations to
            // allow checking if a certain parameter set requires a body or not
            let params = try self.readParameters()
            var expectsBody = false
            if self.peek() == .tagBodyIndicator {
                if name.isEmpty {
                    self.replace(with: .raw(":"))
                } else {
                    self.pop()
                    expectsBody = true
                }
            }
            return TagDeclaration(name: name, parameters: params, expectsBody: expectsBody)
        default:
            throw LeafError(.unknownError("found unexpected token " + next.description))
        }
    }

    private mutating func readParameters() throws -> [ParameterDeclaration] {
        // ensure open parameters
        guard self.read() == .parametersStart else {
            throw LeafError(.unknownError("expected parameters start"))
        }

        var group = [ParameterDeclaration]()
        var paramsList = [ParameterDeclaration]()

        func dump() throws {
            defer { group = [] }
            if group.isEmpty {
                return
            }
            group.evaluate()
            if group.count > 1 {
                paramsList.append(.expression(group))
            } else {
                guard let first = group.first else {
                    // It's better to handle this case as well, even though logically it might never happen
                    // since you're checking if group.isEmpty before.
                    throw LeafError(.unknownError("Found nil while iterating through params"))
                }
                paramsList.append(first)
            }
        }

        outer: while let next = peek() {
            switch next {
            case .parametersStart:
                // found a nested () that we will group together into
                // an expression, ie: #if(foo == (bar + car))
                let params = try self.readParameters()
                // parameter tags not permitted to have bodies
                if params.count > 1 {
                    group.append(.expression(params))
                } else {
                    guard let firstParam = params.first else {
                        throw LeafError(.unknownError("Found nil while iterating through params"))
                    }
                    group.append(firstParam)
                }
            case .parameter(let p):
                self.pop()
                switch p {
                case .tag(let name):
                    guard self.peek() == .parametersStart else {
                        throw LeafError(.unknownError("tags in parameter list MUST declare parameter list"))
                    }
                    let params = try self.readParameters()
                    // parameter tags not permitted to have bodies
                    group.append(.tag(.init(name: name, params: params, body: nil)))
                default:
                    group.append(.parameter(p))
                }
            case .parametersEnd:
                self.pop()
                try dump()
                break outer
            case .parameterDelimiter:
                self.pop()
                try dump()
            case .whitespace:
                self.pop()
                continue
            default:
                break outer
            }
        }

        paramsList.evaluate()
        return paramsList
    }

    private mutating func collectRaw() throws -> ByteBuffer {
        var raw = ByteBuffer()
        while let peek = self.peek(), case .raw(let val) = peek {
            self.pop()
            raw.writeString(val)
        }
        return raw
    }

    private func peek() -> LeafToken? {
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
        guard self.offset < self.tokens.count,
            let val = self.peek()
        else {
            return nil
        }
        self.pop()
        return val
    }

    private mutating func readWhile(_ check: (LeafToken) -> Bool) -> [LeafToken]? {
        guard self.offset < self.tokens.count else {
            return nil
        }
        var matched = [LeafToken]()
        while let next = self.peek(), check(next) {
            matched.append(next)
        }
        return matched.isEmpty ? nil : matched
    }

    private struct OpenContext {
        let parent: TagDeclaration
        var body: [Syntax] = []
        init(_ parent: TagDeclaration) {
            self.parent = parent
        }
    }

    private struct TagDeclaration {
        let name: String
        let parameters: [ParameterDeclaration]?
        let expectsBody: Bool

        func makeSyntax(body: [Syntax]) throws -> Syntax {
            let params = self.parameters ?? []

            switch self.name {
            case let n where n.starts(with: "end"):
                throw LeafError(.unknownError("unable to convert terminator to syntax"))
            case "":
                guard params.count == 1 else {
                    throw LeafError(.unknownError("only single parameter support, should be broken earlier"))
                }
                switch params[0] {
                case .parameter(let p):
                    switch p {
                    case .variable(_):
                        return .expression([params[0]])
                    case .constant(let c):
                        var buffer = ByteBuffer()
                        buffer.writeString(c.description)
                        return .raw(buffer)
                    case .stringLiteral(let st):
                        var buffer = ByteBuffer()
                        buffer.writeString(st)
                        return .raw(buffer)
                    case .keyword(let kw):
                        guard kw.isBooleanValued else { fallthrough }
                        var buffer = ByteBuffer()
                        buffer.writeString(kw.rawValue)
                        return .raw(buffer)
                    default:
                        throw LeafError(.unknownError("unsupported parameter \(p)"))
                    }
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
                guard params.count == 0 else {
                    throw LeafError(.unknownError("else does not accept params"))
                }
                return .conditional(.init(.else, body: body))
            case "for":
                return try .loop(.init(params, body: body))
            case "export":
                return try .export(.init(params, body: body))
            case "extend":
                return try .extend(.init(params, body: body))
            case "with":
                return try .with(.init(params, body: body))
            case "import":
                guard body.isEmpty else {
                    throw LeafError(.unknownError("import does not accept a body"))
                }
                return try .import(.init(params))
            default:
                return .custom(.init(name: self.name, params: params, body: body))
            }
        }

        var isTerminator: Bool {
            switch self.name {
            case let x where x.starts(with: "end"):
                return true
            // dual function
            case "elseif", "else":
                return true
            default:
                return false
            }
        }

        func matches(terminator: TagDeclaration) -> Bool {
            guard terminator.isTerminator else {
                return false
            }
            switch terminator.name {
            // if can NOT be a terminator
            case "else", "elseif":
                // else and elseif can only match to if or elseif
                return self.name == "if" || self.name == "elseif"
            case "endif":
                return self.name == "if" || self.name == "elseif" || self.name == "else"
            default:
                return terminator.name == "end" + self.name
            }
        }
    }
}
