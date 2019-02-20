extension Array where Element == LeafToken {
    func dropWhitespace() -> Array<LeafToken> {
        return self.filter { token in
            guard case .whitespace = token else { return true }
            return false
        }
    }
}

/*
 
 tag:
     parameterGroup:
     body:

 */

struct _Tag {
    let name: String
    let parameters: [_Syntax]
    let body: [_Syntax]?
}

struct _TagDeclaration {
    let name: String
    // todo: convert to '[Parameter]' ?
    let parameters: [LeafToken]
    let hasBody: Bool
    
    init(name: String, parameterTokens: [LeafToken], hasBody: Bool) {
        self.name = name
        self.parameters = parameterTokens // .map { toParameter }
        self.hasBody = hasBody
    }
}

struct _Expression {
    
}

//enum _Parameter {
////    case constant(Constant)
////    case variable(name: String)
//    case stringLiteral(String)
//    case constant(Constant)
//    case variable(name: String)
//    case keyword(Keyword)
//    case `operator`(Operator)
//    case tag(_Tag)
//    case expression(_Expression)
//}

//indirect enum Parameter {
//    case stringLiteral(String)
//    case constant(Constant)
//    case variable(name: String)
//    case keyword(Keyword)
//    case `operator`(Operator)
//    case tag(name: String, parameters: [Parameter])
//    case expression([Parameter])
//}

struct _Extend {
    let key: String
    let exports: [String: [LeafSyntax]]
}

struct _For {
    
}

struct _Conditional {
    
}

/*
 
 #(foo == 40, and, \"literal\")
 #if
 
 */


/*
 #for(foo in over18(bar)):
 #endfor
 #if(a == b,"whoops")
 #(a b c)
 */
indirect enum _Syntax {
    case raw(ByteBuffer)
    
    //
    case tag(_Tag)
    
    //
    case loop(_For)
    case conditional(_Conditional)
    case expression(_Expression)
    case variable(name: String)

    ///
    case `import`(String)
    case extend(String)
}

/*
 Token
 => Syntax (PreProcess)
 => Action
 */
indirect enum Action {
    case raw(ByteBuffer)
    
    //
    case tag(_Tag)
    
    //
    case loop(_For)
    case conditional(_Conditional)
    case expression(_Expression)
    case variable(name: String)
    
    ///
    case `import`(String)
    case extend(String)
}


indirect enum PreProcess: CustomStringConvertible {
    case raw(ByteBuffer)
    case tagDeclaration(name: String, parameters: [ProcessedParameter], hasBody: Bool)
    case tagTerminator(name: String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
        case .tagTerminator(name: let terminator):
            return "tagTerminator(\(terminator))"
        case .tagDeclaration(let name, let params, let hasBody):
            let name = name + "(hasBody: " + hasBody.description + ")"
            return "tag(" + name + ": " + params.map { $0.description } .joined(separator: ",") + ")"
        }
    }
}

indirect enum _Parameter {
    //    case constant(Constant)
    //    case variable(name: String)
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(_Tag)
    case expression([Parameter])
}

indirect enum __Syntax {
    case raw(ByteBuffer)
    
    //
    case tag(name: String, params: [_Syntax])
    case parameter(LeafToken)
    
    //
    case loop(_For)
    case conditional(_Conditional)
    case expression(_Expression)
    case variable(name: String)
    
    ///
    case `import`(String)
    case extend(String)
}

extension String: Error {}

struct Syntaxer {
    let tokens: [LeafToken]
    
    enum State {
        case normal
        case tag
//        case
    }
    
    
    var registry = [LeafToken]()
    
    mutating func process() {
        for token in tokens {
            switch token {
            case .tagIndicator:
                fatalError()
            case .raw:
                registry.append(token)
                return
            case .tagBodyIndicator: fallthrough
//            case .constant: fallthrough
//            case .operator: fallthrough
            case .parameterDelimiter: fallthrough
            case .parametersStart: fallthrough
            case .stringLiteral: fallthrough
            case .parametersEnd: fallthrough
            case .tag: fallthrough
//            case .variable: fallthrough
            case .whitespace: fallthrough
            case .parameter:
//            case .keyword:
                fatalError("unexpected token: \(token)")
            }
        }
    }
}

extension LeafToken {
//    func makeParam() -> Parameter? {
//        switch self {
//        case .constant(let c): return .constant(c)
//        case .keyword(let k): return .keyword(k)
//        case .operator(let o): return .oper
//        default: fatalError()
//        }
//    }
}

/*
 indirect enum _Syntax {
 case raw(ByteBuffer)
 
 //
 case tag(_Tag)
 
 //
 case loop(_For)
 case conditional(_Conditional)
 case expression(_Expression)
 case variable(name: String)
 
 ///
 case `import`(String)
 case extend(String)
 }

 */

struct Comprehension {
    let list: [PreProcess]
    func syntax() -> [_Syntax] {
        fatalError()
    }
}

struct _LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }
    
    mutating func parse() throws -> [PreProcess] {
        var collect = [PreProcess]()
        while let val = try nextSyntax() {
            collect.append(val)
        }
        return collect
    }
    
    private mutating func nextSyntax() throws -> PreProcess? {
        guard let peek = self.peek() else { return nil }
        switch peek {
        case .tagIndicator:
            return try readTagDeclaration()
        case .raw:
            let r = try collectRaw()
            return .raw(r)
        default: throw "unexpected token \(peek)"
        }
    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    private mutating func readTagDeclaration() throws -> PreProcess {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
        // a tag should ALWAYS follow a tag indicator
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
        
        // TODO: WARN: tags that begin w/ 'end' are reserved, and can NOT have a body
        if name.starts(with: "end") {
            return .tagTerminator(name: String(name.dropFirst(3)))
        }
        
        // if no further, then we've ended w/ a tag
        guard let next = peek() else { return .tagDeclaration(name: name, parameters: [], hasBody: false) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        switch next {
        case .raw:
            // a basic tag, something like `#date` w/ no params, and no body
            return .tagDeclaration(name: name, parameters: [], hasBody: false)
        case .tagBodyIndicator:
            // consume ':'
            pop()
            // no parameters, but with a body
            return .tagDeclaration(name: name, parameters: [], hasBody: true)
        case .parametersStart:
            let params = try readParameters()
            var hasBody = false
            if peek() == .tagBodyIndicator {
                hasBody = true
                pop()
            }
            return .tagDeclaration(name: name, parameters: params, hasBody: hasBody)
        default:
            fatalError()
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
                    // TODO: remove recursion
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
}

struct LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }
    
    mutating func parse() throws -> [LeafSyntax] {
        var ast: [LeafSyntax] = []
        while let next = try self.next() {
            print("appending: \n\(next)")
            ast.append(next)
        }
        return ast
    }
    
    mutating func next() throws -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let name):
            self.pop()
            return self.nextTag(named: name)
        case .tagIndicator:
            self.pop()
            return try self.next()
        default:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextTag(named name: String) -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        var parameters: [LeafSyntax] = []
        switch peek {
        case .parametersStart:
            self.pop()
            while let parameter = self.nextParameter() {
                parameters.append(parameter)
            }
        case .tagBodyIndicator:
            // will be handled below
            break
        default: fatalError("unexpected token: \(peek)")
        }
        
        let hasBody: Bool
        if self.peek() == .tagBodyIndicator {
            self.pop()
            hasBody = true
        } else {
            hasBody = false
        }
        
        switch name {
        case "", "get":
            #warning("TODO: verify param count")
            return parameters[0]
        case "import":
            guard
                let parameter = parameters.first,
                case .constant(let constant) = parameter,
                case .string(let string) = constant
            else {
                fatalError("unexpected import parameter")
            }
            return .import(.init(key: string))
        case "extend":
            guard hasBody else {
                fatalError("extend must have body")
            }
            var exports: [String: [LeafSyntax]] = [:]
            while let next = self.nextTagBody(endToken: "endextend") {
                switch next {
                case .raw:
                    // ignore any raw segments
                    break
                case .tag(let tag):
                    switch tag.name {
                    case "export":
                        guard
                            let parameter = tag.parameters.first,
                            case .constant(let constant) = parameter,
                            case .string(let string) = constant
                        else {
                            fatalError("unexpected export parameter")
                        }
                        switch tag.parameters.count {
                        case 1:
                            exports[string] = tag.body!
                        case 2:
                            assert(tag.body == nil)
                            exports[string] = [tag.parameters[1]]
                        default:
                            fatalError()
                        }
                    default:
                        fatalError("Unexpected tag \(tag.name) in extend")
                    }
                default:
                    fatalError("unexpected extend syntax: \(next)")
                }
            }
            return .extend(.init(exports: exports))
        case "if", "elseif", "else":
            return self.nextConditional(
                named: name,
                parameters: parameters
            )
        default:
            return self.nextCustomTag(
                named: name,
                parameters: parameters,
                hasBody: hasBody
            )
        }
    }
    
    mutating func nextConditional(named name: String, parameters: [LeafSyntax]) -> LeafSyntax? {
        var body: [LeafSyntax] = []
        while let next = self.nextConditionalBody() {
            body.append(next)
        }
        let next: LeafSyntax?
        if let p = self.peek(), case .tag(let a) = p, (a == "else" || a == "elseif") {
            self.pop()
            next = self.nextTag(named: a)
        } else if let p = self.peek(), case .tag(let a) = p, a == "endif" {
            self.pop()
            next = nil
        } else {
            next = nil
        }
        let parameter: LeafSyntax
        switch name {
        case "else":
            parameter = .constant(.bool(true))
        default:
            parameter = parameters[0]
        }
        return .conditional(.init(
            condition: parameter,
            body: body,
            next: next
        ))
    }
    
    mutating func nextCustomTag(named name: String, parameters: [LeafSyntax], hasBody: Bool) -> LeafSyntax? {
        let body: [LeafSyntax]?
        if hasBody {
            var b: [LeafSyntax] = []
            while let next = self.nextTagBody(endToken: "end" + name) {
                b.append(next)
            }
            body = b
        } else {
            body = nil
        }
        return .tag(.init(name: name, parameters: parameters, body: body))
    }
    
    mutating func nextConditionalBody() -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let name):
            switch name {
            case "else", "elseif", "endif":
                return nil
            default:
                self.pop()
                return self.nextTag(named: name)
            }
        case .tagIndicator:
            pop()
            return self.nextConditionalBody()
        default: fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextTagBody(endToken: String) -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let n):
            self.pop()
            if n == endToken {
                return nil
            } else {
                return self.nextTag(named: n)
            }
        case .tagIndicator:
            pop()
            return nextTagBody(endToken: endToken)
        default: fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextParameter() -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
//        case .variable(let name):
//            self.pop()
//            return .variable(.init(name: name))
        case .parameterDelimiter:
            self.pop()
            return self.nextParameter()
        case .parametersEnd:
            self.pop()
            return nil
        case .stringLiteral(let string):
            self.pop()
            return LeafSyntax.constant(.string(string))
        default:
            return nil
            fatalError("unexpected token: \(peek)")
        }
    }
    
    func peek() -> LeafToken? {
        guard self.offset < self.tokens.count else {
            return nil
        }
        return self.tokens[self.offset]
    }
    
    mutating func pop() {
        self.offset += 1
    }
}

