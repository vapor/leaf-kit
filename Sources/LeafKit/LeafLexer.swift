extension Character {
    var isValidInTagName: Bool {
        return self.isLowercaseLetter
            || self.isUppercaseLetter
    }
    
    var isValidInParameter: Bool {
        return self.isLowercaseLetter
            || self.isUppercaseLetter
            || self.isValidOperator
            || (.zero ... .nine) ~= self
            || self == .period
    }
    
    var isValidOperator: Bool {
        switch self {
        case .plus,
             .minus,
             .star,
             .forwardSlash,
             .equals,
             .exclamation,
             .lessThan,
             .greaterThan,
             .ampersand,
             .vertical:
            return true
        default:
            return false
        }
    }
}

struct TemplateSource {
    private(set) var line = 0
    private(set) var column = 0
    
    private var body: [Character]
    
    init(_ str: String) {
        self.body = .init(str)
    }
    
    mutating func readWhile(_ check: (Character) -> Bool) -> String? {
        return readSliceWhile(check).flatMap { String($0) }
    }
    
    mutating func readSliceWhile(_ check: (Character) -> Bool) -> [Character]? {
        var str = [Character]()
        while let next = peek() {
            guard check(next) else { return str }
            pop()
            str.append(next)
        }
        return str
    }
    
    func peek(aheadBy idx: Int = 0) -> Character? {
        guard idx < body.count else { return nil }
        return body[idx]
    }
    
    @discardableResult
    mutating func pop() -> Character? {
        guard !body.isEmpty else { return nil }
        let popped = body.removeFirst()
        switch popped {
        case .newLine:
            line += 1
            column = 0
        default:
            column += 1
        }
        return popped
    }
}

public struct LexerError: Error {
    public enum Reason {
        case invalidTagToken(Character)
        case invalidParameterToken(Character)
        case unterminatedStringLiteral
    }
    
    public let line: Int
    public let column: Int
    public let reason: Reason
    public let lexed: [LeafToken]
    
    internal init(src: TemplateSource, lexed: [LeafToken], reason: Reason) {
        self.line = src.line
        self.column = src.column
        self.reason = reason
        self.lexed = lexed
    }
}

struct LeafLexer {
    private enum State {
        // parses as raw, until it finds `#` (excluding escaped `\#`)
        case normal
        // found a `#`
        case tag
        // found a `(` continues until `)`
        case parameters(depth: Int)
        // parses a tag body
        case body
    }
    
    private var state: State
    private var lexed: [LeafToken] = []
    private var src: TemplateSource

    init(template string: String) {
        self.src = .init(string)
        self.state = .normal
    }
    
    mutating func lex() throws -> [LeafToken] {
        while let next = try self.nextToken() {
            lexed.append(next)
        }
        return lexed
    }
    
    private mutating func nextToken() throws -> LeafToken? {
        guard let next = src.peek() else { return nil }
        
        switch state {
        case .normal:
            switch next {
            case .backSlash:
                // consume '\' only in event of '\#'
                // otherwise allow it to remain for other
                // escapes, a la javascript
                if src.peek(aheadBy: 1) == .tagIndicator {
                    src.pop()
                }
                // either way, add raw '#' or '\' to registry
                return src.pop().flatMap { .raw(.init($0)) }
            case .tagIndicator:
                // consume `#`
                src.pop()
                state = .tag
                return .tagIndicator
            default:
                // read until next event
                let slice = src.readWhile { $0 != .tagIndicator && $0 != .backSlash } ?? ""
                return .raw(slice)
            }
        case .tag:
            switch next {
            case .leftParenthesis:
                // '#('
                state = .parameters(depth: 0)
                return .tag(name: "")
            case let x where x.isValidInTagName:
                // collect the named tag, letters only
                let val = src.readWhile { $0.isValidInTagName }
                guard let name = val else { fatalError("switch case should disallow this") }
                
                let trailing = src.peek()
                if trailing == .colon { state = .body }
                else if trailing == .leftParenthesis { state = .parameters(depth: 0) }
                else { state = .normal }
                
                return .tag(name: name)
            default:
                throw LexerError(src: src, lexed: lexed, reason: .invalidTagToken(next))
            }
        case .parameters(let depth):
            switch next {
            case .leftParenthesis:
                src.pop()
                state = .parameters(depth: depth + 1)
                return .parametersStart
            case .rightParenthesis:
                // must pop before subsequent peek
                src.pop()
                if depth <= 1 {
                    if src.peek() == .colon {
                        state = .body
                    } else {
                        state = .normal
                    }
                } else {
                    state = .parameters(depth: depth - 1)
                }
                return .parametersEnd
            case .comma:
                src.pop()
                return .parameterDelimiter
            case .quote:
                // consume first quote
                src.pop()
                let read = src.readWhile { $0 != .quote && $0 != .newLine }
                guard let string = read else { fatalError("disallowed by switch") }
                guard src.peek() == .quote else {
                    throw LexerError(src: src, lexed: lexed, reason: .unterminatedStringLiteral)
                }
                // consume final quote
                src.pop()
                return .parameter(.stringLiteral(string))
            case .space:
                // skip whitespace
                let read = src.readWhile { $0 == .space }
                guard let space = read else { fatalError("disallowed by switch") }
                return .whitespace(length: space.count)
            case let x where x.isValidInParameter:
                let read = src.readWhile { $0.isValidInParameter }
                guard let name = read else { fatalError("disallowed by switch") }
                // this parameter is a tag
                if src.peek() == .leftParenthesis { return .parameter(.tag(name: name)) }
                
                // check if expected parameter type
                if let keyword = Keyword(rawValue: name) { return .parameter(.keyword(keyword)) }
                else if let op = Operator(rawValue: name) { return .parameter(.operator(op)) }
                else if let val = Int(name) { return .parameter(.constant(.int(val))) }
                else if let val = Double(name) { return .parameter(.constant(.double(val))) }
                
                // unknown param type.. var
                return .parameter(.variable(name: name))
            default:
                throw LexerError(src: src, lexed: lexed, reason: .invalidParameterToken(next))
            }
        case .body:
            guard next == .colon else { fatalError("state should only be set to .body when a colon is in queue") }
            src.pop()
            state = .normal
            return .tagBodyIndicator
        }
    }
}
