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

//struct _Tag {
//    let name: String
////    let parameters: [_Syntax]
////    let body: [_Syntax]?
//}

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

//struct _Extend {
//    let key: String
//    let exports: [String: [LeafSyntax]]
//}

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
    case conditional(_ConditionalSyntax)
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
    case conditional(_ConditionalSyntax)
    case expression(_Expression)
    case variable(name: String)
    
    ///
    case `import`(String)
    case extend(String)
}

//struct Compiler {
//    let syntax: [_Syntax]
//
//    func compile() -> [Action] {
//        fatalError()
//    }
//}

enum _ConditionalSyntax {
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

//extension _Syntax {
//    var isConditionalTerminator: Bool { return terminator == "if"}
//    var isLoopTerminator: Bool { return terminator == "for" }
//    var isImportTerminator: Bool { return terminator == "import" }
//    var isExtendTerminator: Bool { return terminator == "extend" }
//    var isExportTerminator: Bool { return terminator == "export" }
//
//    var isTerminator: Bool {
//        switch self {
//        case .conditional(let c):
//            switch c {
//            case .if:
//                return false
//            case .elseif, .else:
//                // else, and elseif dual function as a tag, and a terminator
//                return true
//            }
//        case .tagTerminator:
//            return true
//        default:
//            return false
//        }
//    }
//
//    var terminator: String? {
//        guard case .tagTerminator(let name) = self else { return nil }
//        return name
//    }
//}

let block = "  "

indirect enum Syntax: CustomStringConvertible {
    
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
        let body: [Syntax]
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
            guard params.count == 1 else { throw "extend only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "extend expected parameter type, got \(params[0])" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
            self.body = try body.filter {
                switch $0 {
                // extend can ONLY export, raw space in body ignored
                case .raw: return false
                case .export: return true
                default: throw "unexpected token in extend body: \($0).. use raw space and `export` only"
                }
            }
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
    }
    
    final class Conditional {
        let condition: _ConditionalSyntax
        let body: [Syntax]
        
        
        private(set) var next: Conditional?
        
        init(_ condition: _ConditionalSyntax, body: [Syntax]) {
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
    
    case raw(ByteBuffer)
    case variable(Variable)
    
    case custom(CustomTag)
    
    case conditional(Conditional)
    case loop(Loop)
    case `import`(Import)
    case extend(Extend)
    case export(Export)
    
    
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
            if !ext.body.isEmpty {
                print += ":\n" + ext.body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
        case .export(let export):
            print += "export(" + export.key.debugDescription + ")"
            if !export.body.isEmpty {
                print += ":\n" + export.body.map { $0.print(depth: depth) } .joined(separator: "\n")
            }
        }
        
        var buffer = ""
        for _ in 0..<depth {
            buffer += block
        }
        print = print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")

        return print
    }
}

extension Syntax.Conditional {
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

indirect enum _Syntax: CustomStringConvertible {
    //    case documentStart
    //    case documentEnd
    
    case raw(ByteBuffer)
    case variable([ProcessedParameter])
    
    case tagDeclaration(name: String, parameters: [ProcessedParameter], hasBody: Bool)
    case tagTerminator(name: String)
    
    case conditional(_ConditionalSyntax)
    case loop([ProcessedParameter])
    case `import`([ProcessedParameter])
    case extend([ProcessedParameter])
    case export([ProcessedParameter], hasBody: Bool)
    
    var description: String {
        switch self {
            //        case .documentStart:
            //            return "documentStart"
            //        case .documentEnd:
        //            return "documentEnd"
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
        case .export(let params, let hasBody):
            return "export(hasBody: \(hasBody): " + params.map { $0.description } .joined(separator: ", ") + ")"
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

//extension _Syntax {
//    func matches(terminator: String) -> Bool {
//        switch terminator {
//        case "if":
//            switch self {
//            case .conditional(let c):
//                switch c {
//                case .if(_):
//                    return true
//                default:
//                    return false
//                }
//            default: fatalError()
//            }
//        default: fatalError()
//        }
//    }
//}

class Thing {
    
}


//indirect enum LeafElement {
//    case raw(ByteBuffer)
//    case tagDeclaration(name: String, parameters: [ProcessedParameter], hasBody: Bool)
//    case tagTerminator(name: String)
//    case conditional(_ConditionalSyntax)
//    case loop([ProcessedParameter])
//    case variable([ProcessedParameter])
//
//    case `import`([ProcessedParameter])
//    case extend([ProcessedParameter])
//    case export([ProcessedParameter], hasBody: Bool)
//}


//protocol LeafElement {}

extension Array where Element == ProcessedParameter {
    func compile() {
        
    }
}

extension IndexingIterator where Element == [_Syntax] {
//    func readBody(matching) {
//
//    }
}

//final class _Conditional {
//
//}
//indirect enum LeafElement {
//    // todo: process [ProcessedParameters] into a proper condition
//    case conditional(condition: [ProcessedParameter], body: [LeafElement], next: LeafElement?)
//}

protocol LeafElement {}

struct _Raw: LeafElement {
    let buffer: ByteBuffer
}

struct _Tag: LeafElement {
    let name: String
    let params: [ProcessedParameter]
    let body: [LeafElement]
}

final class _Conditional: LeafElement {
    // TODO: process into something that can be evaluated
    let condition: [ProcessedParameter]
    let body: [LeafElement]
    let next: _Conditional?
    
    init(condition: [ProcessedParameter], body: [LeafElement], next: _Conditional?) {
        self.condition = condition
        self.body = body
        self.next = next
    }
}

struct _Loop: LeafElement {
    // TODO: process into something that can be evaluated
    let params: [ProcessedParameter]
    let body: [LeafElement]
    
//    init(params: [ProcessedParameter], body: [LeafElement]) {
//        self.params = params
//        self.body = body
//    }
}

struct _Variable: LeafElement {
    let name: String
}

struct _Import: LeafElement {
    let params: [ProcessedParameter]
}

struct _Export {
    let name = "first param"
    let body = "second param, or body"
    let params: [ProcessedParameter]
}

struct _Extend: LeafElement {
    let params: [ProcessedParameter]
    let body: [LeafElement]
}

/*
 // => raw
 case raw(ByteBuffer)
 
 // => collect body,
 case tagDeclaration(name: String, parameters: [ProcessedParameter], hasBody: Bool)
 // <= matches w/ body
 case tagTerminator(name: String)
 
 case conditional(_ConditionalSyntax)
 
 // => collect body
 case loop([ProcessedParameter])
 case variable([ProcessedParameter])
 
 case `import`([ProcessedParameter])
 case extend([ProcessedParameter])
 case export([ProcessedParameter], hasBody: Bool)
 */

//class Block {
//    let parent: _Syntax
//    let body: [_Syntax]?
//}

extension IndexingIterator where Element == [_Syntax] {
    mutating func dropLast(_ k: Int = 1) -> [Array<_Syntax>] {
        fatalError()
    }
}

//final class Group {
//    let parent: _Syntax?
//    var body: [Group]? = nil
//    init(parent: _Syntax?, body: [Group]?) {
//        self.parent = parent
//    }
//}

extension _Syntax {
    func matches(terminator: _Syntax) -> Bool {
        switch terminator {
        case .conditional(let terminatingConditional):
            switch terminatingConditional {
                // if can NOT be a terminator
            case .if: return false
            case .else, .elseif:
                // else and elseif can only match to
                guard case .conditional(let parent) = self else { return false }
                switch parent {
                case .if, .elseif: return true
                case .else:
                    // else conditions can't be terminated by a subsequent
                    // conditional terminator
                    return false
                }
            }
        case .tagTerminator(let terminator):
            switch self {
            case .tagDeclaration(let name, _, _): return name == terminator
            case .conditional(let condition): return terminator == "if"
            case .export: return terminator == "export"
            case .extend: return terminator == "extend"
            case .loop: return terminator == "for"
            case .import: return false
            case .raw: return false
            case .tagTerminator: return false
            case .variable: return false
            }
        default: fatalError()
        }
//        guard case .tagDeclaration(let name, _, _) = self, terminator == name else { return false }
        return true
    }
}

extension Array {
    mutating func readLastUntilInclusive(_ check: (Element) throws -> Bool) -> Array {
        var array = [Element]()
//        while let next = f
        return array
    }
}

extension _Syntax {
    var expectsBody: Bool {
        switch self {
        case .export(_, let hasBody): return hasBody
        case .tagDeclaration(_, _, let hasBody): return hasBody
        case .conditional: return true
        case .extend: return true
        case .loop: return true
        case .import: return false
        case .raw: return false
        case .tagTerminator: return false
        case .variable: return false
        }
    }
}
/*
 extend(base)
 raw("\n    ")
 export("title", "Welcome")
 raw("\n    ")
 export("body")
 raw("\n        Hello, ")
 variable(parameter(variable(name)))
 raw("!\n    ")
 tagTerminator(export)
 raw("\n")
 tagTerminator(extend)
 */

class Group {
    let parent: _Syntax?
    var body: [Group]? = nil
    init(parent: _Syntax?, body: [Group]?) {
        self.parent = parent
    }
}

//final class Link {
//    let parent: _Syntax?
//
//}

final class Block: CustomStringConvertible {
    let parent: _Syntax
    var body: [_Syntax] = []
    init(_ parent: _Syntax) {
        self.parent = parent
    }
    
    var description: String {
        var print = ""
        print += "parent(" + parent.description + ")\n"
        print += "body(" + body.map { $0.description } .joined(separator: ", ") + ")"
        return print
    }
}

final class _Block {
    let parent: _Syntax
    var body: [_Block] = []
    init(_ parent: _Syntax) {
        self.parent = parent
    }
    var description: String {
        let bod = body.map { $0.description } .joined(separator: ", ")
        var print = "\n"
        print += "<block>\n"
        print += parent.description + "\n"
        if !body.isEmpty {
            print += "<body>"
            print += bod
            print += "\n</body>"
        }
        print += "</block>"
        return print
    }
}

struct TagDeclaration {
    let name: String
    let parameters: [ProcessedParameter]?
    let expectsBody: Bool
}

final class __Collector {
    let parent: _Syntax
    var body: [_Syntax] = []
    init(_ parent: _Syntax) {
        self.parent = parent
    }
}

final class _Collector {
    let parent: _Syntax
    var body: [_Syntax] = []
    init(_ parent: _Syntax) {
        self.parent = parent
    }
}

final class OpenTag {
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


struct _LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }

    
    var finished: [Syntax] = []
    var awaitingBody: [OpenTag] = []
    
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
