extension ByteBuffer {
    mutating func stringify() -> String? {
        return readString(length: readableBytes)
    }
}

enum Parameter {
    enum Keyword: String {
        case `in`, `true`, `false`, `nil`, `self`
    }
    
    enum Operator: String {
        case equals = "=="
        case notEquals = "!="
        case greaterThan = ">"
        case greaterThanOrEquals = ">="
        case lessThan = "<"
        case lessThanOrEquals = "<="
    }
    
    enum Constant {
        case int(Int)
        case double(Double)
    }
    
    case keyword(Keyword)
    case `operator`(Operator)
    case constant(Constant)
    case variable(name: String)
    case literal(String)
    
    init(nonLiteral raw: String) {
        if let keyword = Keyword(rawValue: raw) {
            self = .keyword(keyword)
        } else if let `operator` = Operator(rawValue: raw) {
            self = .operator(`operator`)
        } else if let double = Double(raw) {
            self = .constant(.double(double))
        } else if let int = Int(raw) {
            self = .constant(.int(int))
        } else {
            self = .variable(name: raw)
        }
    }
}

extension Parameter: CustomStringConvertible {
    var description: String {
        return "TODO: this thing.. 123877fhhhh"
    }
}

enum _LeafToken: CustomStringConvertible { //}, Equatable  {
    case raw(ByteBuffer)
    
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parameter(Parameter)
    case parametersEnd
    
    var description: String {
        return "todododod also this 12309fh"
//        switch self {
//        case .raw(var byteBuffer):
//            let string = byteBuffer.stringify() ?? ""
//            return "raw(\(string.debugDescription))"
//        case .tag(let name):
//            return "tag(name: \(name.debugDescription))"
//        case .tagBodyIndicator:
//            return "tagBodyIndicator"
//        case .parametersStart:
//            return "parametersStart"
//        case .parametersEnd:
//            return "parametersEnd"
//        case .parameterDelimiter:
//            return "parameterDelimiter"
//        case .variable(let name):
//            return "variable(name: \(name.debugDescription))"
//        case .stringLiteral(let string):
//            return "stringLiteral(\(string.debugDescription))"
//        }
    }
    
    static func makeVariable(with val: String) -> _LeafToken {
        if let keyword = Parameter.Keyword(rawValue: val) { fatalError() }
        fatalError()
    }
}

extension UInt8 {
    var isValidInTagName: Bool { return isLowercaseLetter || isUppercaseLetter }
}

/*
 #("#")
 #()
 "#("\")#(name)" == '\logan'
 "\#(name)" == '#(name)'
 */

struct _LeafLexer {
    enum State {
        // parses as raw, until it finds `#` (excluding escaped `\#`)
        case normal
        // found a `#`
        case tag
        // found a `(` continues until `)`
        case parameters
        // parses a tag body
        case body
    }
    
    var state: State
    
    private var buffer: ByteBuffer

    init(string: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(string)
        self.init(template: buffer)
    }
    
    init(template buffer: ByteBuffer) {
        self.state = .normal
        self.buffer = buffer
    }
    
    mutating func lex() throws -> [LeafToken] {
        var tokens: [LeafToken] = []
        while let next = try self.nextToken() {
            print("found token:\n\(next)")
            tokens.append(next)
        }
        return tokens
    }
    
    mutating func nextToken() throws -> LeafToken? {
        guard let next = peek() else { return nil }
        switch state {
        case .normal:
            switch next {
            case .backSlash where peek(at: 1) == .octothorpe:
                // consume '\' only in event of '\#'
                // otherwise allow it to remain for other
                // escapes, a la javascript
                pop()
                // add raw '#' to registry
                return buffer.readSlice(length: 1).map(LeafToken.raw)
            case .octothorpe:
                // consume `#`
                pop()
                state = .tag
                return .tagIndicator
            default:
                // read until next event
                let slice = readSliceWhile { $0 != .octothorpe && $0 != .backSlash }
                return slice.map(LeafToken.raw)
            }
        case .tag:
            switch next {
            case .leftParenthesis:
                // '#('
                state = .parameters
                return .tag(name: "")
            case let x where x.isValidInTagName:
                // collect the named tag, letters only
                let val = readWhile { $0.isValidInTagName }
                guard let name = val else { fatalError("switch case should disallow this") }
                
                let trailing = peek()
                if trailing == .colon { state = .body }
                else if trailing == .leftParenthesis { state = .parameters }
                else { state = .normal }
                
                return .tag(name: name)
            default:
                fatalError("unexpected token: \(String(bytes: [next], encoding: .utf8) ?? "<unknown>")")
            }
        case .parameters:
            switch next {
            case .leftParenthesis:
                pop()
                return .parametersStart
            case .rightParenthesis:
                pop()
                state = .body
                return .parametersEnd
            case .comma:
                pop()
                return .parameterDelimiter
            case .quote:
                let source = LeafSource.start(at: buffer)
                // consume first quote
                pop()
                let read = readWhile { $0 != .quote && $0 != .newLine }
                guard let string = read else { fatalError("todo: expected string literal in parameters list") }
                guard peek() == .quote else {
                    throw LeafError(.unterminatedStringLiteral, source: source.end(at: buffer))
                }
                // consume final quote
                pop()
                return .stringLiteral(string)
            case .space:
                // skip space
                pop()
                return try self.nextToken()
            case let x where x.isAllowedInVariable:
                let read = readWhile { $0.isAllowedInVariable }
                guard let name = read else { fatalError("switch case should disallow this") }
                return .variable(name: name)
            default:
                fatalError("unable to process")
            }
        case .body:
            state = .normal
            guard next == .colon else { return try nextToken() }
            pop()
            return .tagBodyIndicator
        }
    }
    
    // MARK: byte buffer methods
    
    mutating func readWhile(_ check: (UInt8) -> Bool) -> String? {
        guard let length = countMatching(check: check) else {
            return nil
        }
        return buffer.readString(length: length)
    }
    
    mutating func readSliceWhile(_ check: (UInt8) -> Bool) -> ByteBuffer? {
        guard let length = countMatching(check: check) else {
            return nil
        }
        return buffer.readSlice(length: length)
    }
    
    func peek(at idx: Int = 0) -> UInt8? {
        return self.buffer.getInteger(at: self.buffer.readerIndex + idx)
    }
    
    mutating func pop() {
        self.buffer.moveReaderIndex(forwardBy: 1)
    }
    
    func countMatching(check isMatch: (UInt8) -> (Bool)) -> Int? {
        guard buffer.readableBytes > 0 else { return nil }
        var copy = buffer
        while let curr = copy.readInteger(as: UInt8.self) {
            if !isMatch(curr) {
                let matchedIndex = copy.readerIndex - 1
                return matchedIndex - buffer.readerIndex
            }
        }
        return copy.readerIndex - self.buffer.readerIndex
    }
}

struct LeafLexer {
    enum State {
        // parses as body, until it finds `#` (excluding escaped `\#`)
        case body
        // found a `#`
        case tag
        // found a `(` continues until `)`
        case parameters
        

    }
    
    var state: State
    
    private var buffer: ByteBuffer
    
    init(string: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(string)
        self.init(template: buffer)
    }
    
    init(template buffer: ByteBuffer) {
        self.buffer = buffer
        self.state = .body
    }
    
    mutating func lex() throws -> [LeafToken] {
        var tokens: [LeafToken] = []
        while let next = try self.next() {
            tokens.append(next)
        }
        return tokens
    }
    
    mutating func next() throws -> LeafToken? {
        guard let next = self.peek() else { return nil }
        
        switch state {
        case .body:
            switch next {
            case .backSlash:
                // consume `\`
                pop()
                let escaped = buffer.readSlice(length: 1).map(LeafToken.raw)
                return escaped
            case .octothorpe:
                // consume `#`
                pop()
                state = .tag
                return .tagIndicator
            default:
                // read until next
                let slice = readSliceWhile { $0 != .octothorpe && $0 != .backSlash }
                return slice.map(LeafToken.raw)
            }
        case .tag:
            switch next {
            case .leftParenthesis:
                state = .parameters
                return .tag(name: "")
            case .colon:
                pop()
                state = .body
                return .tagBodyIndicator
            case let x where x.isLowercaseLetter || x.isUppercaseLetter:
                let val = readWhile { $0.isUppercaseLetter || $0.isLowercaseLetter }
                guard let name = val else { return nil }
                state = .parameters
                return .tag(name: name)
            default:
                state = .body
                return try self.next()
            }
        case .parameters:
            switch next {
            case .leftParenthesis:
                pop()
                return .parametersStart
            case .rightParenthesis:
                pop()
                // tag, to check for closing body
                state = .tag
                return .parametersEnd
            case .comma:
                pop()
                return .parameterDelimiter
            case .quote:
                let source = LeafSource.start(at: self.buffer)
                // consume first quote
                pop()
                let read = readWhile { $0 != .quote && $0 != .newLine }
                guard let string = read else { return nil }
                guard peek() == .quote else {
                    throw LeafError(.unterminatedStringLiteral, source: source.end(at: buffer))
                }
                // consume final quote
                pop()
                return .stringLiteral(string)
            case .space:
                // skip space
                pop()
                return try self.next()
            case .colon:
                pop()
                state = .body
                return .tagBodyIndicator
            default:
                let read = readWhile { $0.isAllowedInVariable }
                guard let name = read else {
                    let source = LeafSource.start(at: self.buffer).end(at: self.buffer)
                    throw LeafError(.unexpectedToken, source: source)
                }
                return .variable(name: name)
            }
        case .body:
            state = .body
            switch next {
            case .colon:
                pop()
                return .tagBodyIndicator
            default:
                return try self.next()
            }
        }
    }
    
    // MARK: byte buffer methods
    
    mutating func readWhile(while check: (UInt8) -> Bool) -> String? {
        guard let length = countMatching(check: check) else {
            return nil
        }
        return buffer.readString(length: length)
    }
    
    mutating func readSliceWhile(while check: (UInt8) -> Bool) -> ByteBuffer? {
        guard let length = countMatching(check: check) else {
            return nil
        }
        return buffer.readSlice(length: length)
    }
    
    mutating func pop(if byte: UInt8) -> Bool {
        if self.peek() == byte {
            self.pop()
            return true
        } else {
            return false
        }
    }
    
    func peek() -> UInt8? {
        return self.buffer.getInteger(at: self.buffer.readerIndex)
    }
    
    mutating func pop() {
        self.buffer.moveReaderIndex(forwardBy: 1)
    }
    
    func countMatching(check isMatch: (UInt8) -> (Bool)) -> Int? {
        if self.buffer.readableBytes == 0 {
            return nil
        }
        
        var copy = self.buffer
        while let curr = copy.readInteger(as: UInt8.self) {
            if !isMatch(curr) {
                return (copy.readerIndex - self.buffer.readerIndex) - 1
            }
        }
        return copy.readerIndex - self.buffer.readerIndex
    }
}
