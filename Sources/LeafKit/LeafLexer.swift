extension ByteBuffer {
    mutating func stringify() -> String? {
        return readString(length: readableBytes)
    }
}

extension UInt8 {
    var isValidInTagName: Bool {
        return isLowercaseLetter
            || isUppercaseLetter
    }
    
    var isValidInParameter: Bool {
        return isLowercaseLetter
            || isUppercaseLetter
            || isValidOperator
            || (.zero ... .nine) ~= self
    }
    
    var isValidOperator: Bool {
        switch self {
        case .plus, .minus, .star, .forwardSlash, .equals, .exclamation, .lessThan, .greaterThan:
            return true
        default:
            return false
        }
    }
}


struct LeafLexer {
    enum State {
        class Machine {
            var stack: [State] = []
            var state: State = .normal
            
            func push(_ new: State) {
                stack.append(new)
                state = new
            }
            
            func pop() {
                state = stack.removeLast()
            }
        }
        
        // parses as raw, until it finds `#` (excluding escaped `\#`)
        case normal
        // found a `#`
        case tag
        // found a `(` continues until `)`
        case parameters(depth: Int)
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
            tokens.append(next)
        }
        return tokens
    }
    
    mutating func nextToken() throws -> LeafToken? {
        guard let next = peek() else { return nil }
        switch state {
        case .normal:
            switch next {
            case .backSlash:
                // consume '\' only in event of '\#'
                // otherwise allow it to remain for other
                // escapes, a la javascript
                if peek(at: 1) == .octothorpe {
                    pop()
                }
                // either way, add raw '#' or '\' to registry
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
                state = .parameters(depth: 0)
                return .tag(name: "")
            case let x where x.isValidInTagName:
                // collect the named tag, letters only
                let val = readWhile { $0.isValidInTagName }
                guard let name = val else { fatalError("switch case should disallow this") }
                
                let trailing = peek()
                if trailing == .colon { state = .body }
                else if trailing == .leftParenthesis { state = .parameters(depth: 0) }
                else { state = .normal }
                
                return .tag(name: name)
            default:
                fatalError("unexpected token: \(String(bytes: [next], encoding: .utf8) ?? "<unknown>")")
            }
        case .parameters(let depth):
            switch next {
            case .leftParenthesis:
                pop()
                state = .parameters(depth: depth + 1)
                return .parametersStart
            case .rightParenthesis:
                pop()
                if depth <= 1 {
                    state = .body
                } else {
                    state = .parameters(depth: depth - 1)
                }
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
            case let x where x.isValidInParameter:
                let read = readWhile { $0.isValidInParameter }
                guard let name = read else { fatalError("switch case should disallow this") }
                
                // this parameter is a tag
                if peek() == .leftParenthesis { return .tag(name: name) }
                
                
                if let keyword = LeafToken.Keyword(rawValue: name) { return .keyword(keyword) }
                else if let op = LeafToken.Operator(rawValue: name) { return .operator(op) }
                else if let val = Int(name) { return .constant(.int(val)) }
                else if let val = Double(name) { return .constant(.double(val)) }
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
