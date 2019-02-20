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
//    let parameters: [_Syntax]
//    let body: [_Syntax]?
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

//struct _Conditional {
//
//}

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
indirect enum _asdfSyntax {
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

struct Compiler {
    let syntax: [_Syntax]
    
    func compile() -> [Action] {
        fatalError()
    }
}

enum _Conditional {
    case `if`([ProcessedParameter])
    case `elseif`([ProcessedParameter])
    case `else`
}


indirect enum _Syntaxxxx: CustomStringConvertible {
    case raw(ByteBuffer)
    case tag(name: String, parameters: [ProcessedParameter]?, body: [_Syntaxxxx]?)
    
    //    case variable(name: String)
    //    case conditional(_Conditional)
    
    var description: String {
        let t = type(of: self)
        return "\(t) \(self)"
//        switch self {
//        case .raw(var byteBuffer):
//            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
//            return "raw(\(string.debugDescription))"
//            //        case .variable(let name):
//        //            return "variable(\(name))"
//        case .tagTerminator(name: let terminator):
//            return "tagTerminator(\(terminator))"
//        case .tagDeclaration(let name, let params, let hasBody):
//            let name = name + "(hasBody: " + hasBody.description + ")"
//            return "tag(" + name + ": " + params.map { $0.description } .joined(separator: ",") + ")"
//        default:
//            fatalError()
//            return "conditional()"
//        }
    }
}

indirect enum _Syntax: CustomStringConvertible {
    case raw(ByteBuffer)
    case tagDeclaration(name: String, parameters: [ProcessedParameter], hasBody: Bool)
    case tagTerminator(name: String)
    case conditional(_Conditional)
    case loop([ProcessedParameter])
    case variable([ProcessedParameter])
    
    case `import`([ProcessedParameter])
    case extend([ProcessedParameter])
    case export([ProcessedParameter])
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
        case .tagTerminator(name: let terminator):
            return "tagTerminator(\(terminator))"
        case .tagDeclaration(let name, let params, let hasBody):
            let name = name + "(hasBody: " + hasBody.description + ")"
            return "tag(" + name + ": " + params.map { $0.description } .joined(separator: ", ") + ")"
        case .conditional(let c):
            var print = "conditional("
            switch c {
            case .if(let params):
                print += "if(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .elseif(let params):
                print += "elseif(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .else:
                print += "else"
            }
            return print + ")"
        case .loop(let params):
            return "loop(" + params.map { $0.description } .joined(separator: ", ") + ")"
        case .variable(let params):
            return "variable(" + params.map { $0.description } .joined(separator: ", ") + ")"
        case .import(let params):
            return "import(" + params.map { $0.description } .joined(separator: ", ") + ")"
        case .extend(let params):
            return "extend(" + params.map { $0.description } .joined(separator: ", ") + ")"
        case .export(let params):
            return "export(" + params.map { $0.description } .joined(separator: ", ") + ")"
        }
    }
}

extension String: Error {}

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

struct Tagggg {
    let name: String
    let parameters: [ProcessedParameter]?
    let body: [_Syntax]?
}

//struct Comprehension {
//    let list: [PreProcess]
//    func syntax() -> [_Syntax] {
//        fatalError()
//    }
//}

//class TTTTagDeclaration {
//    let name
//}

struct _Compiler {
    let syntax: [_Syntax]
    private var reversed: ReversedCollection<[_Syntax]>.Iterator
    
    init(syntax: [_Syntax]) {
        self.syntax = syntax
        let reversed = syntax.reversed().makeIterator()
        self.reversed = reversed
    }
    
    mutating func compile() throws {
        var registry: [_Syntax]
        while let next = reversed.next() {
//            switch next {
//            case .raw, .tagDeclaration:
//                registry.append(next)
//            case .tagTerminator(let name):
//                fatalError()
//            }
        }
    }
}

struct _LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }

    
    mutating func parse() throws -> [_Syntax] {
        var collected = [_Syntax]()
        while let val = try nextSyntax() {
//            switch val {
//            case .tagTerminator(let name):
//                let body = collected.reversed().drop { syn -> Bool in
//                    switch syn {
//                    case .tagDeclaration(let tag, let _, let hasBody) where tag == name && hasBody:
//                        print("found: \(tag) matching \(name)")
//                        return false
//                    default:
//                        return true
//                    }
//                }
//                let bodyOpened = collected.last!
//                print(bodyOpened)
//                print("")
//            default:
//                print("do nothing")
//            }
            collected.append(val)
        }
        return collected
    }
    
//    mutating func close(name: String) {
//        var tagName: String = ""
//        var parameters: [ProcessedParameter]
//        let body = collected.reversed().drop { syn -> Bool in
//            switch syn {
//            case .tagDeclaration(let tag, let parameters, let hasBody) where tag == name && hasBody:
//                return tag != name
//            default:
//                return true
//            }
//        }
////        collected.reversed().c
//        let found = collected.reversed().firstIndex { syn -> Bool in
//            switch syn {
//            case .tagDeclaration(let tag, let parameters, let hasBody) where hasBody:
//                return tag == name
//            default:
//                return false
//            }
//        }
//
//        guard let idx = found else { fatalError("found end token w/o close") }
////        collected.dropLast(<#T##k: Int##Int#>)
////        for syntax in collected {
////            switch syntax {
////                case .tagDeclaration(let name, let parameters, let hasBody)
////            default:
////                return
////            }
////        }
//    }
    
    private mutating func nextSyntax() throws -> _Syntax? {
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
//    private mutating func _readTagDeclaration() throws -> Tagggg {
//        // consume tag indicator
//        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
//        // a tag should ALWAYS follow a tag indicator
//        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
//
//        // TODO: WARN: tags that begin w/ 'end' are reserved, and can NOT have a body
//        if name.starts(with: "end") {
//
//            return .tagTerminator(name: String(name.dropFirst(3)))
//        }
//
//        // if no further, then we've ended document w/ a tag
//        guard let next = peek() else { return Tagggg(name: name, parameters: nil, body: nil) }
//
//        // following a tag can be,
//        // .raw - tag is complete
//        // .tagBodyIndicator - ready to read body
//        // .parametersStart - start parameters
//        switch next {
//        case .raw:
//            // a basic tag, something like `#date` w/ no params, and no body
//            return Tagggg(name: name, parameters: nil, body: nil)
//        case .tagBodyIndicator:
//            // consume ':'
//            pop()
//            // no parameters, but with a body
//            return Tagggg(name: name, parameters: nil, body: [])
////            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: true)
//        case .parametersStart:
//            let params = try readParameters()
//            var hasBody = false
//            if peek() == .tagBodyIndicator {
//                hasBody = true
//                pop()
//            }
//            return try convertTagDeclarationSyntax(name: name, parameters: params, hasBody: hasBody)
//        default:
//            fatalError()
//        }
//    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
//    private mutating func _readTagDeclaration() throws -> _Syntax {
//        // consume tag indicator
//        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
//        // a tag should ALWAYS follow a tag indicator
//        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
//
//        switch name {
//        case let n where n.starts(with: "end"):
//            // TODO: WARN: tags that begin w/ 'end' are reserved, and can NOT have a body
//            return .tagTerminator(name: String(name.dropFirst(3)))
//        case "if":
//            let params = try readParameters()
//            guard peek() == .tagBodyIndicator else { throw "if statement requires body" }
//            pop()
//            return .conditional(.if(params))
//        case "elseif":
//            let params = try readParameters()
//            guard peek() == .tagBodyIndicator else { throw "elseif statement requires body" }
//            pop()
//            return .conditional(.elseif(params))
//        case "else":
//            guard peek() == .tagBodyIndicator else { throw "if statement requires body" }
//            pop()
//            return .conditional(.else)
//        case "for":
//            let params = try readParameters()
//            guard peek() == .tagBodyIndicator else { throw "elseif statement requires body" }
//            pop()
//            return .loop(params)
//        default: fatalError()
//        }
//
//        if name.starts(with: "end") {
//            return .tagTerminator(name: String(name.dropFirst(3)))
//        }
//
//        // if no further, then we've ended w/ a tag
//        guard let next = peek() else { return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false) }
//
//        // following a tag can be,
//        // .raw - tag is complete
//        // .tagBodyIndicator - ready to read body
//        // .parametersStart - start parameters
//        switch next {
//        case .raw:
//            // a basic tag, something like `#date` w/ no params, and no body
//            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false)
//        case .tagBodyIndicator:
//            // consume ':'
//            pop()
//            // no parameters, but with a body
//            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: true)
//        case .parametersStart:
//            let params = try readParameters()
//            var hasBody = false
//            if peek() == .tagBodyIndicator {
//                hasBody = true
//                pop()
//            }
//            return try convertTagDeclarationSyntax(name: name, parameters: params, hasBody: hasBody)
//        default:
//            fatalError()
//        }
//    }
//
//    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
//    private mutating func _readBody() throws -> _Syntax {
//        // consume tag indicator
//        guard let first = read(), first == .tagBodyIndicator else { throw "expected body indicator" }
//        // a tag should ALWAYS follow a tag indicator
//        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
//
//        // TODO: WARN: tags that begin w/ 'end' are reserved, and can NOT have a body
//        if name.starts(with: "end") {
//            return .tagTerminator(name: String(name.dropFirst(3)))
//        }
//
//        // if no further, then we've ended w/ a tag
//        guard let next = peek() else { return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false) }
//
//        // following a tag can be,
//        // .raw - tag is complete
//        // .tagBodyIndicator - ready to read body
//        // .parametersStart - start parameters
//        switch next {
//        case .raw:
//            // a basic tag, something like `#date` w/ no params, and no body
//            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false)
//        case .tagBodyIndicator:
//            // consume ':'
//            pop()
//            // no parameters, but with a body
//            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: true)
//        case .parametersStart:
//            let params = try readParameters()
//            var hasBody = false
//            if peek() == .tagBodyIndicator {
//                hasBody = true
//                pop()
//            }
//            return try convertTagDeclarationSyntax(name: name, parameters: params, hasBody: hasBody)
//        default:
//            fatalError()
//        }
//    }
//
//    private mutating func readBody(to: Tagggg) throws -> [ProcessedParameter] {
//        fatalError()
//    }
    
    // once a tag has started, it is terminated by `.raw`, `.parameters`, or `.tagBodyIndicator`
    private mutating func readTagDeclaration() throws -> _Syntax {
        // consume tag indicator
        guard let first = read(), first == .tagIndicator else { throw "expected tag indicator" }
        // a tag should ALWAYS follow a tag indicator
        guard let tag = read(), case .tag(let name) = tag else { throw "expected tag following a `#` indicator" }
        
        // if no further, then we've ended w/ a tag
        guard let next = peek() else { return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false) }
        
        // following a tag can be,
        // .raw - tag is complete
        // .tagBodyIndicator - ready to read body
        // .parametersStart - start parameters
        switch next {
        case .raw:
            // a basic tag, something like `#date` w/ no params, and no body
            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: false)
        case .tagBodyIndicator:
            // consume ':'
            pop()
            // no parameters, but with a body
            return try convertTagDeclarationSyntax(name: name, parameters: [], hasBody: true)
        case .parametersStart:
            let params = try readParameters()
            var hasBody = false
            if peek() == .tagBodyIndicator {
                hasBody = true
                pop()
            }
            return try convertTagDeclarationSyntax(name: name, parameters: params, hasBody: hasBody)
        default:
            throw "found unexpected token " + next.description
        }
    }
    
    func convertTagDeclarationSyntax(name: String, parameters params: [ProcessedParameter], hasBody: Bool) throws -> _Syntax {
        switch name {
        case let n where n.starts(with: "end"):
            guard !hasBody else { throw "terminators must NOT have a body" }
            return .tagTerminator(name: String(name.dropFirst(3)))
        case "":
            return .variable(params)
        case "if":
            guard hasBody else { throw "if statement requires body" }
            return .conditional(.if(params))
        case "elseif":
            guard hasBody else { throw "elseif statement requires body" }
            return .conditional(.elseif(params))
        case "else":
            guard hasBody else { throw "else statement requires body" }
            return .conditional(.else)
        case "for":
            guard hasBody else { throw "for statement requires body" }
            return .loop(params)
        case "export":
            return .export(params)
        case "extend":
            guard hasBody else { throw "extensions require body" }
            return .extend(params)
        default:
            // custom tag declaration
            return .tagDeclaration(name: name, parameters: params, hasBody: hasBody)
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

