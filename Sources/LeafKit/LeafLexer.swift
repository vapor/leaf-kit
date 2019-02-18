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
    
    case keyword(Keyword)
    case `operator`(Operator)
    case variable(name: String)
    
    init(raw: String) {
        if let keyword = Keyword(rawValue: raw) {
            self = .keyword(keyword)
        } else if let `operator` = Operator(rawValue: raw) {
            self = .operator(`operator`)
        } else {
            self = .variable(name: raw)
        }
    }
}

enum _LeafToken: CustomStringConvertible, Equatable  {
    case raw(ByteBuffer)
    
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parametersEnd
    
    case variable(name: String)
    
    case stringLiteral(String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.stringify() ?? ""
            return "raw(\(string.debugDescription))"
        case .tag(let name):
            return "tag(name: \(name.debugDescription))"
        case .tagBodyIndicator:
            return "tagBodyIndicator"
        case .parametersStart:
            return "parametersStart"
        case .parametersEnd:
            return "parametersEnd"
        case .parameterDelimiter:
            return "parameterDelimiter"
        case .variable(let name):
            return "variable(name: \(name.debugDescription))"
        case .stringLiteral(let string):
            return "stringLiteral(\(string.debugDescription))"
        }
    }
    
    static func makeVariable(with val: String) -> _LeafToken {
        if let keyword = Parameter.Keyword(rawValue: val) { fatalError() }
        fatalError()
    }
}

struct _LeafLexer {
    enum State {
        case normal
        case tag
        case parameters
        case escaping
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
        self.state = .normal
    }
}

struct LeafLexer {
    enum State {
        case normal
        case tag
        case parameters
        case escaping
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
        self.state = .normal
    }
    
    mutating func lex() throws -> [LeafToken] {
        var tokens: [LeafToken] = []
        while let next = try self.next() {
            tokens.append(next)
        }
        return tokens
    }
    
    mutating func next() throws -> LeafToken? {
        guard let next = self.peek() else {
            // empty
            return nil
        }
        print(String.init(bytes: [next], encoding: .utf8)!)
        switch state {
        case .normal:
            switch next {
            case .forwardSlash:
                // consume slash
                self.buffer.moveReaderIndex(forwardBy: 1)
                self.state = .escaping
                return try self.next()
            case .octothorpe:
                self.buffer.moveReaderIndex(forwardBy: 1)
                guard let length = self.countMatching(check: { $0.isAllowedInVariable }) else {
                    return nil
                }
                guard let name = self.buffer.readString(length: length) else {
                    return nil
                }
                self.state = .tag
                return .tag(name: name)
            default:
                guard let length = self.countMatching(check: { $0 != .octothorpe && $0 != .forwardSlash }) else {
                    return nil
                }
                return self.buffer.readSlice(length: length)
                    .map { .raw($0) }
            }
        case .tag:
            switch next {
            case .leftParenthesis:
                self.buffer.moveReaderIndex(forwardBy: 1)
                self.state = .parameters
                return .parametersStart
            case .colon:
                self.buffer.moveReaderIndex(forwardBy: 1)
                self.state = .normal
                return .tagBodyIndicator
            default:
                self.state = .normal
                return try self.next()
            }
        case .parameters:
            switch next {
            case .rightParenthesis:
                // tag, to check for closing body
                self.state = .tag
                self.buffer.moveReaderIndex(forwardBy: 1)
                return .parametersEnd
            case .comma:
                self.buffer.moveReaderIndex(forwardBy: 1)
                return .parameterDelimiter
            case .quote:
                let source = LeafSource.start(at: self.buffer)
                // consume first quote
                self.buffer.moveReaderIndex(forwardBy: 1)
                guard let length = self.countMatching(check: { $0 != .quote && $0 != .newLine }) else {
                    return nil
                }
                guard let string = self.buffer.readString(length: length) else {
                    return nil
                }
                guard self.peek() == .quote else {
                    throw LeafError(.unterminatedStringLiteral, source: source.end(at: self.buffer))
                }
                // consume final quote
                self.buffer.moveReaderIndex(forwardBy: 1)
                return .stringLiteral(string)
            case .space:
                // skip space
                self.buffer.moveReaderIndex(forwardBy: 1)
                return try self.next()
            default:
                guard let length = self.countMatching(check: { $0.isAllowedInVariable }) else {
                    return nil
                }
                if length == 0 {
                    let source = LeafSource.start(at: self.buffer).end(at: self.buffer)
                    throw LeafError(.unexpectedToken, source: source)
                }
                guard let name = self.buffer.readString(length: length) else {
                    return nil
                }
                return .variable(name: name)
            }
        case .escaping:
            state = .normal
            return buffer.readSlice(length: 1).map { .raw($0) }
        }
    }
    
    // MARK: byte buffer methods
    
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
