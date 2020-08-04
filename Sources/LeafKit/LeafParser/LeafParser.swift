// MARK: Subject to change prior to 1.0.0 release
// MARK: -

extension String: Error {}

internal struct LeafParser {
    // MARK: - Internal Only
    
    let name: String

    init(name: String, tokens: [LeafToken]) {
        self.name = name
        self.tokens = tokens
        self.offset = 0
    }
    
    mutating func parse() throws -> [Syntax] {
        while let next = peek { try handle(next) }
        return finished
    }
    
    private struct OpenContext {
        let block: TagDeclaration
        var body: [Syntax] = []
        init(_ parent: TagDeclaration) { self.block = parent }
    }
    
    // MARK: - Private Only
    
    private var tokens: [LeafToken]
    private var offset: Int
    
    private var finished: [Syntax] = []
    private var openBodies: [OpenContext] = []
    
    private var current: [Syntax] {
        get { openBodies.isEmpty ? finished : openBodies[openBodies.endIndex - 1].body }
        set {
            if openBodies.isEmpty { finished = newValue }
            else { openBodies[openBodies.endIndex - 1].body = newValue }
        }
    }

    private mutating func handle(_ next: LeafToken) throws {
        switch next {
            case .tagIndicator:
                let declaration = try readTagDeclaration()
                if declaration.isTerminator { try close(with: declaration) }
                if declaration.expectsBody { openBodies.append(.init(declaration)) }
                else if declaration.isTerminator { return }
                else { try current = current + [declaration.makeSyntax()] }
            case .raw: try current = current + [.raw(collectRaw())]
            default:   throw "unexpected token \(next)"
        }
    }

    private mutating func close(with terminator: TagDeclaration) throws {
        guard !openBodies.isEmpty else {
            throw "\(name): found terminator \(terminator), with no corresponding tag"
        }
        let willClose = openBodies.removeLast()
        guard willClose.block.matches(terminator) else { throw "\(name): unable to match \(willClose.block) with \(terminator)" }

        // closed body
        let newSyntax = try willClose.block.makeSyntax(willClose.body)

        func append(_ syntax: Syntax) {
            if openBodies.isEmpty { finished.append(syntax) }
            else { openBodies[openBodies.endIndex - 1].body.append(syntax) }
        }

        if case .conditional(let new) = newSyntax {
            guard let conditional = new.chain.first else { throw "Malformed syntax block" }
            switch conditional.0.naturalType {
                case .if: append(newSyntax) // `if` always opens a new block
                case .elseif, .else:
                    guard let open = current.last,
                          case .conditional(var openConditional) = open else {
                        throw "Can't attach \(conditional.0) to \(current.last?.description ?? "empty AST")"
                    }
                    var current = self.current
                    try openConditional.attach(new)
                    current.removeLast()
                    current.append(.conditional(openConditional))
                    self.current = current
            }
        } else { append(newSyntax) }
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

        // if no further, then we've ended w/ a tag - DISCARD THIS CASE - no param not valid
        guard let next = peek else { return TagDeclaration(name: name, parameters: nil, expectsBody: false) }

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
            case .scopeIndicator:
                if name != nil { pop() } else { replace(with: .raw(":")) }
                return TagDeclaration(name: name, parameters: nil, expectsBody: true)
            case .parametersStart:
                // An anonymous function `#(variable):` is incapable of having a body, so change tBI to raw
                // Can be more intelligent - there should be observer methods on tag declarations to
                // allow checking if a certain parameter set requires a body or not
                let params = try readParameters()
                var expectsBody = false
                if peek == .scopeIndicator {
                    if name == nil { replace(with: .raw(":")) }
                    else { pop(); expectsBody = true }
                }
                return TagDeclaration(name: name, parameters: params, expectsBody: expectsBody)
            default: throw "Unexpected token: \(next.description)"
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
            group.nestFlatExpression()
            if group.count > 1 { paramsList.append(.expression(group)) }
            else { paramsList.append(group.first!) }
        }

        outer: while let next = peek {
            switch next {
                case .parametersStart:
                    // found a nested () that we will group together into
                    // an expression, ie: #if(foo == (bar + car))
                    let params = try readParameters()
                    // parameter tags not permitted to have bodies
                    if params.count > 1  { group.append(.expression(params)) }
                    else { group.append(params.first!) }
                case .parameter(let p):
                    pop()
                    switch p {
                        case .function(let name):
                            guard peek == .parametersStart else { throw "tags in parameter list MUST declare parameter list" }
                            // TODO: remove recursion, in parameters only not so bad
                            let params = try readParameters()
                            // parameter tags not permitted to have bodies
                            group.append(.tag(.init(name: name, params: params, body: nil)))
                        default:
                            group.append(.parameter(p))
                    }
                case .parametersEnd:      pop(); dump(); break outer
                case .parameterDelimiter: pop(); dump()
                default:                  break outer
            }
        }

        paramsList.nestFlatExpression()
        return paramsList
    }

    private mutating func collectRaw() throws -> ByteBuffer {
        var raw = ByteBufferAllocator().buffer(capacity: 0)
        while case .raw(let val) = peek { pop(); raw.writeString(val) }
        return raw
    }

    private var peek: LeafToken? { offset < tokens.count ? tokens[offset] : nil }

    private mutating func pop() { offset += 1 }

    private mutating func replace(at index: Int = 0, with new: LeafToken) {
        tokens[offset + index] = new
    }

    private mutating func read() -> LeafToken? {
        guard offset < tokens.count, let val = peek else { return nil }
        pop(); return val
    }

    private mutating func readWhile(_ check: (LeafToken) -> Bool) -> [LeafToken]? {
        guard offset < tokens.count else { return nil }
        var matched = [LeafToken]()
        while let next = peek, check(next) { matched.append(next) }
        return matched.isEmpty ? nil : matched
    }
    
    

    private struct TagDeclaration {
        let name: String?
        let parameters: [ParameterDeclaration]?
        let expectsBody: Bool
        
        func makeSyntax(_ body: [Syntax] = []) throws -> Syntax {
            let params = parameters ?? []

            switch name {
                case "for"    : return try .loop(.init(params, body: body))
                case "export" : return try .export(.init(params, body: body))
                case "extend" : return try .extend(.init(params, body: body))
                case "if"     : return .conditional(.init(.if(params), body: body))
                case "elseif" : return .conditional(.init(.elseif(params), body: body))
                case "else":
                    guard params.isEmpty else { throw "else does not accept params" }
                    return .conditional(.init(.else, body: body))
                case "import":
                    guard body.isEmpty else { throw "import does not accept a body" }
                    return try .import(.init(params))
                case .some(let n) where n.starts(with: "end"): throw "Unmatched closing tag"
                case .none:
                    guard params.count == 1 else {
                        throw "only single parameter support, should be broken earlier"
                    }
                    switch params[0] {
                        case .expression(let e): return .expression(e)
                        case .tag(let t):        return .custom(t)
                        case .parameter(let p):
                            switch p {
                                case .variable(_):
                                    return .expression([params[0]])
                                case .literal(let c):
                                    var buffer = ByteBufferAllocator().buffer(capacity: 0)
                                    if case .string(let s) = c { buffer.writeString(s) }
                                    else { buffer.writeString(c.description) }
                                    return .raw(buffer)
                                case .keyword(let kw) :
                                    guard kw.isBooleanValued else { fallthrough }
                                    var buffer = ByteBufferAllocator().buffer(capacity: 0)
                                    buffer.writeString(kw.rawValue)
                                    return .raw(buffer)
                                default:
                                    throw "unsupported parameter \(p)"
                            }
                    }
                default:
                    return .custom(.init(name: name ?? "", params: params, body: body))
            }
        }

        var isTerminator: Bool {
            guard let name = name else { return false }
            return name.hasPrefix("end") ? true : ["else", "elseif"].contains(name)
        }

        func matches(_ terminator: TagDeclaration) -> Bool {
            guard terminator.isTerminator, let name = name else { return false }
            switch terminator.name {
                case "else", "elseif": return name.hasSuffix("if")
                case "endif": return name.hasSuffix("if") || name == "else"
                default: return terminator.name == "end\(name)"
            }
        }
    }
}
