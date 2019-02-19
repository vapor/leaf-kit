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

indirect enum PreProcess: CustomStringConvertible {
    case raw(ByteBuffer)
    case tagDeclaration(name: String, parameters: [LeafToken], hasBody: Bool)
    case tagTerminator(name: String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
        case .tagTerminator(name: let terminator):
            return "tagTerminator(\(terminator))"
        case .tagDeclaration(name: let n, parameters: let p, hasBody: let b):
            return "tag(\(n), [\(p)], body: \(b))"
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
/**
 a quick pass to
 - collect and group raw
 Raw
 Tag
 Parameters
 Raw
 Tag
 Body?
 -
 **/

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
struct _LeafParser {
    
//    case raw(ByteBuffer)
//
//    case tagIndicator
//    case tag(name: String)
//    case tagBodyIndicator
//
//    case parametersStart
//    case parameterDelimiter
//    case parametersEnd
//
//    case variable(name: String)
//    case keyword(Keyword)
//    case `operator`(Operator)
//    case constant(Constant)
//
//    case stringLiteral(String)
//    case whitespace(length: Int)

    
    enum State {
        case normal
        case tag
        case parametersList
        case done
        case expressionList
    }
    
    private let tokens: [LeafToken]
    private var offset: Int
    
    private var stack: [State] = [.normal]
    private var state: State = .normal
    
    var registry = [LeafToken]()
    var found = [_Syntax]()
    
//    var registry: [LeafToken]
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }
//
//    mutating func handle(next: LeafToken) {
//        switch state {
//        case .normal:
//            switch next {
//            case .tagIndicator:
//                state = .tag
//            case .raw:
//                registry.append(next)
//                return
//            case .tagBodyIndicator: fallthrough
//            case .constant: fallthrough
//            case .operator: fallthrough
//            case .parameterDelimiter: fallthrough
//            case .parametersStart: fallthrough
//            case .stringLiteral: fallthrough
//            case .parametersEnd: fallthrough
//            case .tag: fallthrough
//            case .variable: fallthrough
//            case .whitespace: fallthrough
//            case .keyword:
//                fatalError("unexpected token: \(next)")
//            }
//        case .tag:
//            fatalError()
//        default:
//            fatalError()
//        }
//    }
//
//    mutating func expectIndicator(next: LeafToken) throws {
//        switch next {
//        case .tagIndicator:
//            pop()
//            let tag = try nextTag()
//            fatalError()
//        case .raw:
//            let r = try collectRaw()
//            fatalError()
//        case .tagBodyIndicator: fallthrough
//        case .constant: fallthrough
//        case .operator: fallthrough
//        case .parameterDelimiter: fallthrough
//        case .parametersStart: fallthrough
//        case .stringLiteral: fallthrough
//        case .parametersEnd: fallthrough
//        case .tag: fallthrough
//        case .variable: fallthrough
//        case .whitespace: fallthrough
//        case .keyword:
//            fatalError("unexpected token: \(peek)")
//        }
//    }
    
    mutating func parse() throws -> [_Syntax] {
        while let next = try self.next() {
            found.append(next)
        }
        return found
    }
    
    mutating func _parse() throws -> [_Syntax] {
        while let next = try self.next() {
            found.append(next)
        }
        return found
    }
    
    mutating func next() throws -> _Syntax? {
        guard let peek = self.peek() else { return nil }
        print("peeking at \(peek)")
        print("")
        switch peek {
        case .tagIndicator:
            let tag = try nextTag()
            return .tag(tag)
        case .raw:
            let r = try collectRaw()
            return .raw(r)
        case .tagBodyIndicator: fallthrough
//        case .constant: fallthrough
//        case .operator: fallthrough
        case .parameterDelimiter: fallthrough
        case .parametersStart: fallthrough
        case .stringLiteral: fallthrough
        case .parametersEnd: fallthrough
        case .tag: fallthrough
//        case .variable: fallthrough
        case .whitespace: fallthrough
        case .parameter:
//        case .keyword:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    mutating func nextTag() throws -> _Tag {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
        guard let next = peek() else { return _Tag(name: name, parameters: [], body: nil) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        switch next {
        case .raw:
            return _Tag(name: name, parameters: [], body: nil)
        case .parametersStart:
            registry.append(tag)
            fatalError()
        default:
            fatalError()
        }
        
        fatalError()
    }
    
    mutating func preProcess() throws -> [PreProcess] {
        var collect = [PreProcess]()
        while let val = try nextPreProcess() {
            print("processed:")
            print(val)
                
            collect.append(val)
        }
        return collect
    }
    
    mutating func nextPreProcess() throws -> PreProcess? {
        guard let peek = self.peek() else { return nil }
        print("peeking at \(peek)")
        print("")
        switch peek {
        case .tagIndicator:
            return try readTagDeclaration()
        case .raw:
            let r = try collectRaw()
            return .raw(r)
        case .tagBodyIndicator: fallthrough
//        case .constant: fallthrough
//        case .operator: fallthrough
        case .parameterDelimiter: fallthrough
        case .parametersStart: fallthrough
        case .stringLiteral: fallthrough
        case .parametersEnd: fallthrough
        case .tag: fallthrough
//        case .variable: fallthrough
        case .whitespace: fallthrough
        case .parameter:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    mutating func readTagDeclaration() throws -> PreProcess {
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
            print("collecting parameters for: \(tag)")
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
    
    mutating func readParameters() throws -> [LeafToken] {
        // ensure open parameters
        guard peek() == .parametersStart else { throw "expected parameters start" }
        
        var group = [Parameter]()
        var paramsList = [Parameter]()
        func dump() {
            defer { group = [] }
            
            
            if group.isEmpty { return }
            else if group.count == 1 { paramsList.append(group.first!) }
            else { paramsList.append(.expression(group))}
        }
        
        var depth = 0
        while let next = peek() {
            pop()
            
            switch next {
            case .parametersStart:
                depth += 1
            case .parameter(let p):
                group.append(p)
            case .parametersEnd:
                depth -= 1
                dump()
            case .parameterDelimiter:
                dump()
            case .whitespace:
                continue
            default:
                fatalError()
            }
            
            // MUST be OUTSIDE of switch
            if depth <= 0 { break }
        }
        
        return paramsList.map { LeafToken.parameter($0) }
    }
    
    
    mutating func collectParameters() throws -> [LeafToken] {
        // ensure open parameters
        guard peek() == .parametersStart else { throw "expected parameters start" }
        var paramsList = [LeafToken]()
        
        
        var depth = 0
        while let next = peek() {
            pop()
            
            switch next {
            case .parametersStart:
                depth += 1
                paramsList.append(next)
            case .parametersEnd:
                depth -= 1
                paramsList.append(next)
            case .tag(let name):
                fatalError("tag named: \(name)")
                /*
                 inner tags are declared w/o the `#` syntax
                 for example, #if(lowercase(name) == "me")
                 ..because of this, it MUST be followed by a `(`
                 to disambiguate between a variable if there is
                 a case where a tag is being used w/o any
                 explicit arguments
                 */
                //                guard peek() == .parametersStart else { throw "invalid tag declaration in parameters list" }
                //                let parameters = try self.collectParameters()
                fatalError()
            default:
                paramsList.append(next)
            }
            
            // MUST be OUTSIDE of switch
            if depth <= 0 { break }
        }
        
        return paramsList
    }
    
    mutating func readParameter() throws -> Parameter {
        guard let next = read() else { throw "expected parameter" }
        switch next {
//        case .constant(let c): return .constant(c)
//        case .keyword(let k): return .keyword(k)
//        case .operator(let o): return .operator(o)
        default: fatalError()
        }
    }
    
//    indirect enum Parameter {
//        case stringLiteral(String)
//        case constant(Constant)
//        case variable(name: String)
//        case keyword(Keyword)
//        case `operator`(Operator)
//        case tag(name: String, parameters: [Parameter])
//        case expression([Parameter])
//    }
//    mutating func _collectParameters() throws -> [Parameter] {
//        // ensure open parameters
//        guard let first = read(), first == .parametersStart else { throw "expected parameters start" }
//        var paramsList = [Parameter]()
//
//
//
////        var depth = 0
//        while let next = peek() {
//            pop()
//
//            switch next {
//            case .parametersStart:
////                depth += 1
//                paramsList.append(next)
//            case .parametersEnd:
////                depth -= 1
//                paramsList.append(next)
////                guard depth > 0 else { break }
//            default:
//                paramsList.append(next)
//            }
//        }
//
//        return paramsList
//    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    mutating func parseTagDeclaration() throws -> _TagDeclaration {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
        guard let next = peek() else { return _TagDeclaration(name: name, parameterTokens: [], hasBody: false) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        switch next {
        case .raw:
            return _TagDeclaration(name: name, parameterTokens: [], hasBody: false)
        case .tagBodyIndicator:
            return _TagDeclaration(name: name, parameterTokens: [], hasBody: false)
        case .parametersStart:
            registry.append(tag)
            fatalError()
        default:
            fatalError()
        }
        
        fatalError()
    }
    
    mutating func collectRaw() throws -> ByteBuffer {
        var raw = ByteBufferAllocator().buffer(capacity: 0)
        while let peek = peek(), case .raw(var val) = peek {
            pop()
            raw.writeBuffer(&val)
        }
        return raw
    }
    
    mutating func dosdf() throws {
        for value in tokens {
            
        }
        
        guard let peek = self.peek() else { return }
        switch peek {
        case .tagIndicator:
            pop()
            return
        case .raw(let r):
            fatalError("todo: collect all raw and assemble")
        case .tagBodyIndicator:
            fatalError("add body")
//        case .constant: fallthrough
//        case .operator: fallthrough
        case .parameterDelimiter: fallthrough
        case .parametersStart: fallthrough
        case .stringLiteral: fallthrough
        case .parametersEnd: fallthrough
        case .tag: fallthrough
//        case .variable: fallthrough
        case .whitespace: fallthrough
        case .parameter:
            fatalError("unexpected token: \(peek)")
        }
        
//        switch peek {
//        case .constant(let c):
////            return .parameter(.constant(c))
//            fatalError()
//        case .keyword(let k):
////            return .parameter(.keyword(k))
//            fatalError()
//        case .operator(let o):
////            return .parameter(.operator(o))
//            fatalError()
//        case .parameterDelimiter:
//            fatalError()
//        case .parametersStart:
//            fatalError()
//        case .parametersEnd:
//            fatalError()
//        case .raw(let r):
//            fatalError()
//        case .stringLiteral(let s):
//            fatalError()
//        case .tagIndicator:
//            pop()
//            fatalError()
//        case .tag(let name):
//            fatalError()
//        case .tagBodyIndicator:
//            fatalError()
//        case .variable(name: let v):
//            fatalError()
//        case .whitespace(let length):
//            fatalError("should be discarded")
//        }
    }
    
    mutating func _next() throws -> _Syntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .parameter:
            fatalError()
//        case .constant(let c):
////            return .parameter(.constant(c))
//            fatalError()
//        case .keyword(let k):
////            return .parameter(.keyword(k))
//            fatalError()
//        case .operator(let o):
////            return .parameter(.operator(o))
//            fatalError()
        case .parameterDelimiter:
            fatalError()
        case .parametersStart:
            fatalError()
        case .parametersEnd:
            fatalError()
        case .raw(let r):
            fatalError()
        case .stringLiteral(let s):
            fatalError()
        case .tagIndicator:
            pop()
            fatalError()
        case .tag(let name):
            fatalError()
        case .tagBodyIndicator:
            fatalError()
//        case .variable(name: let v):
//            fatalError()
        case .whitespace(let length):
            fatalError("should be discarded")
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
//        case .parameter(let name):
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
            fatalError("unexpected token: \(peek)")
            return nil
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
    
    mutating func read() -> LeafToken? {
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

