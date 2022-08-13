fileprivate extension Character {
    var isNumberOrUnderscore: Bool {
        return self == "_" || self.isNumber || self.isHexDigit
    }
}

public struct LeafScannerError: Error, Equatable {
    public let kind: Kind
    public let pos: LeafScanner.Position

    public init(_ kind: Kind, _ pos: LeafScanner.Position) {
        self.kind = kind
        self.pos = pos
    }

    public enum Kind: Equatable {
        case unexpected(Character, while: String)
        case unexpectedEOF(while: String)
    }
}

public class LeafScanner {
    public init(name: String, source: String) {
        self.name = name
        self.source = source
        self.index = source.startIndex
    }

    public struct Position: CustomStringConvertible, Equatable {
        public let file: String
        public let line: Int
        public let column: Int

        public var description: String {
            "\(file):\(line):\(column)"
        }
        public static var eof: Position {
            .init(file: "", line: -1, column: -1)
        }
        public var isEOF: Bool {
            file == "" && line == -1 && column == -1
        }
    }
    public struct Span: CustomStringConvertible, Equatable {
        public let from: Position
        public let to: Position

        public var description: String {
            "[\(from) ... \(to)]"
        }
        public static var eof: Span {
            .init(from: .eof, to: .eof)
        }
        public var isEOF: Bool {
            from.isEOF || to.isEOF
        }
    }
    public struct OperatorData {
        public internal(set) var priority: Int
        public internal(set) var nonAssociative: Bool = false
        public internal(set) var rightAssociative: Bool = false
        public internal(set) var kind: Operator.Kind = .interfixOnly
    }
    public enum Operator: String, Equatable, CaseIterable {
        case not = "!"
        case equal = "=="
        case unequal = "!="
        case greater = ">"
        case greaterOrEqual = ">="
        case lesser = "<"
        case lesserOrEqual = "<="
        case and = "&&"
        case or = "||"
        case plus = "+"
        case minus = "-"
        case divide = "/"
        case multiply = "*"
        case modulo = "%"
        case fieldAccess = "."

        public enum Kind {
            case prefixOnly
            case prefixAndInterfix
            case interfixOnly

            var prefix: Bool {
                switch self {
                case .prefixOnly, .prefixAndInterfix:
                    return true
                case .interfixOnly:
                    return false
                }
            }
            var interfix: Bool {
                switch self {
                case .prefixAndInterfix, .interfixOnly:
                    return true
                case .prefixOnly:
                    return false
                }
            }
        }

        var data: OperatorData {
            switch self {
            case .fieldAccess: return OperatorData(priority: 10)

            case .divide: return OperatorData(priority: 9)
            case .multiply: return OperatorData(priority: 9)
            case .modulo: return OperatorData(priority: 9)

            case .not: return OperatorData(priority: 8, kind: .prefixOnly)

            case .plus: return OperatorData(priority: 6)
            case .minus: return OperatorData(priority: 6, kind: .prefixAndInterfix)

            case .equal: return OperatorData(priority: 5)
            case .unequal: return OperatorData(priority: 5)
            case .greater: return OperatorData(priority: 5)
            case .greaterOrEqual: return OperatorData(priority: 5)
            case .lesser: return OperatorData(priority: 5)
            case .lesserOrEqual: return OperatorData(priority: 5)

            case .and: return OperatorData(priority: 3)
            case .or: return OperatorData(priority: 2)
            }
        }
    }
    public enum ExpressionToken: CustomStringConvertible, Equatable {
        case integer(base: Int, digits: Substring)
        case decimal(base: Int, digits: Substring)
        case leftParen
        case rightParen
        case comma
        case `operator`(Operator)
        case identifier(Substring)
        case stringLiteral(Substring)
        case boolean(Bool)

        public var description: String {
            switch self {
            case .integer(let base, let digits):
                return ".integer(base: \(base), digits: \(digits.debugDescription))"
            case .decimal(let base, let digits):
                return ".decimal(base: \(base), digits: \(digits.debugDescription))"
            case .identifier(let name):
                return ".identifier(\(name.debugDescription))"
            case .operator(let op):
                return ".operator(\(op))"
            case .leftParen:
                return ".leftParen"
            case .rightParen:
                return ".rightParen"
            case .comma:
                return ".comma"
            case .stringLiteral(let substr):
                return ".stringLiteral(\(substr.debugDescription))"
            case .boolean(let val):
                return ".boolean(\(val))"
            }
        }
    }
    public enum Token: CustomStringConvertible, Equatable {
        case raw(Substring)
        case tag(name: Substring)
        case substitution
        case enterExpression
        case exitExpression
        case expression(ExpressionToken)
        case bodyStart

        public var description: String {
            switch self {
            case .raw(let val):
                return ".raw(\(val.debugDescription))"
            case .tag(let name):
                return ".tag(name: \(name.debugDescription))"
            case .enterExpression:
                return ".enterExpression"
            case .exitExpression:
                return ".exitExpression"
            case .expression(let expr):
                return ".expression(\(expr.description))"
            case .substitution:
                return ".substitution"
            case .bodyStart:
                return ".bodyStart"
            }
        }
    }

    // immutable state
    let name: String
    let source: String

    // Scanning State

    // line and column are 1-indexed, because they're for humans, not for the code
    var line: Int = 1
    var column: Int = 1

    // these are what our code deal with
    var index: String.Index
    var character: Character? {
        if isEOF {
            return nil
        }
        return source[index]
    }
    var peekCharacter: Character? {
        let next = source.index(after: index)
        if next == source.endIndex {
            return nil
        }
        return source[next]
    }
    var isEOF: Bool {
        index == source.endIndex
    }
    var pos: Position {
        .init(file: name, line: line, column: column)
    }

    // we're context-aware, so gotta have some state...
    enum State {
        case raw
        case expression
    }
    var state: State = .raw
    var depth = 0
    var previous: Token? = nil

    private func next() {
        index = source.index(index, offsetBy: 1)
        if character == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }
    private func peek() -> String.Index {
        return source.index(after: index)
    }

    /// scanIdentifier scans the identifier at the current position
    /// character must already be a letter
    /// when this function returns, character won't be a letter
    private func scanIdentifier() -> Substring {
        assert(!isEOF)
        assert(character!.isLetter)

        let from = index
        var to = from

        while !isEOF {
            next()
            if character?.isLetter ?? false || character?.isNumber ?? false {
                to = index
            } else {
                break
            }
        }

        return source[from...to]
    }

    private func isTag(token: Token?) -> Bool {
        if case .tag = token {
            return true
        }
        return false
    }

    private func scanRaw() -> (Span, Token) {
        switch character {
        // if it's \# or \\, we want to scan the second character as raw
        case "\\" where peekCharacter == "#" || peekCharacter == "\\":
            next() // discard the current \
            let pos = self.pos
            let from = index
            next() // eat the following character
            let to = index
            next() // leave off at our final place
            return (.init(from: pos, to: self.pos), .raw(source[from...to]))
        // if it's # with a letter after it, let's lex it as a tag
        case "#" where peekCharacter?.isLetter ?? false:
            let pos = self.pos
            next()
            return (.init(from: pos, to: self.pos), .tag(name: scanIdentifier()))
        case "#" where peekCharacter == "(":
            let pos = self.pos
            next()
            return (.init(from: pos, to: self.pos), .substitution)
        case "(" where isTag(token: previous) || previous == .substitution:
            let pos = self.pos
            next()
            state = .expression
            depth += 1
            return (.init(from: pos, to: self.pos), .enterExpression)
        case ":" where previous == .exitExpression || isTag(token: previous):
            let pos = self.pos
            next()
            return (.init(from: pos, to: self.pos), .bodyStart)
        default:
            let pos = self.pos
            let from = index
            var to = index

        outer:
            while !isEOF {
                next()
                switch character {
                case "#", "\\":
                    break outer
                case nil:
                    break outer
                default:
                    to = index
                }
            }

            return (.init(from: pos, to: self.pos), .raw(source[from...to]))
        }
    }

    private func scanDigits() -> Substring {
        let from = index
        var to = index

        while !isEOF {
            next()
            if character?.isNumberOrUnderscore ?? false {
                to = index
            } else {
                break
            }
        }

        return source[from...to]
    }

    /// scans the number at the current position
    /// character must already be a number
    private func scanNumber() throws -> (Span, ExpressionToken) {
        assert(!isEOF)
        assert(character!.isNumber || character!.isHexDigit)

        let pos = self.pos

        var base = 10

        if character == "0" {
            next()
            switch character?.lowercased() {
            case "x":
                next()
                base = 16
            case "o":
                next()
                base = 8
            case "b":
                next()
                base = 2
            case _ where character?.isNumberOrUnderscore ?? false || character == ".":
                // it's just a leading zero
                break
            default:
                // just a zero
                return (.init(from: pos, to: self.pos), .decimal(base: 10, digits: "0"))
            }
        }

        // are we starting with a decimal point?
        if character == "." {
            next()
            // if so, it's 0.something
            return (.init(from: pos, to: self.pos), .decimal(base: base, digits: scanDigits()))
        }

        // otherwise, let's scan a decimal...
        let digits = scanDigits()

        // if it's a decimal point now...
        if character == "." {
            next()
            let decimalDigits = scanDigits()
            let from = digits.startIndex
            let to = decimalDigits.index(before: decimalDigits.endIndex)
            return (.init(from: pos, to: self.pos), .decimal(base: base, digits: source[from...to]))
        }

        return (.init(from: pos, to: self.pos), .integer(base: base, digits: digits))
    }

    private func skipWhitespace() {
        while !isEOF {
            if character?.isWhitespace ?? false {
                next()
            } else {
                break
            }
        }
    }

    private func scanExpression() throws -> (Span, Token) {
        skipWhitespace()
        let map = { (tuple: (Span, ExpressionToken)) -> (Span, Token) in
            let (span, tok) = tuple
            return (span, Token.expression(tok))
        }
        let nextAndSpan = { (advance: Int) -> Span in
            let pos = self.pos
            for _ in 0..<advance {
                self.next()
            }
            return .init(from: pos, to: self.pos)
        }

        switch character {
        case _ where character?.isNumber ?? false:
            return map(try scanNumber())
        case _ where character?.isLetter ?? false:
            let pos = self.pos
            let ident = scanIdentifier()
            if ident == "true" {
                return map(((.init(from: pos, to: self.pos)), .boolean(true)))
            } else if ident == "false" {
                return map(((.init(from: pos, to: self.pos)), .boolean(false)))
            }
            return map((.init(from: pos, to: self.pos), .identifier(ident)))
        case "!" where peekCharacter == "=":
            return map((nextAndSpan(2), .operator(.unequal)))
        case "!":
            return map((nextAndSpan(1), .operator(.not)))
        case "=" where peekCharacter == "=":
            return map((nextAndSpan(2), .operator(.equal)))
        case ">" where peekCharacter == "=":
            return map((nextAndSpan(2), .operator(.greaterOrEqual)))
        case ">":
            return map((nextAndSpan(1), .operator(.greater)))
        case "<" where peekCharacter == "=":
            return map((nextAndSpan(2), .operator(.lesserOrEqual)))
        case "<":
            return map((nextAndSpan(1), .operator(.lesser)))
        case "&" where peekCharacter == "&":
            return map((nextAndSpan(2), .operator(.and)))
        case "|" where peekCharacter == "|":
            return map((nextAndSpan(2), .operator(.or)))
        case "+":
            return map((nextAndSpan(1), .operator(.plus)))
        case "-":
            return map((nextAndSpan(1), .operator(.minus)))
        case "/":
            return map((nextAndSpan(1), .operator(.divide)))
        case "*":
            return map((nextAndSpan(1), .operator(.multiply)))
        case "%":
            return map((nextAndSpan(1), .operator(.modulo)))
        case ".":
            return map((nextAndSpan(1), .operator(.fieldAccess)))
        case ",":
            return map((nextAndSpan(1), .comma))
        case "(":
            let pos = self.pos
            next()

            depth += 1
            return map((.init(from: pos, to: self.pos), .leftParen))
        case ")":
            let pos = self.pos
            next()

            depth -= 1
            if depth == 0 {
                state = .raw
                return (.init(from: pos, to: self.pos), .exitExpression)
            } else {
                return map((.init(from: pos, to: self.pos), .rightParen))
            }
        case "\"":
            let pos = self.pos
            next()
            let from = index
            var to = index

            outer:
            while !isEOF {
                next()
                switch character {
                case "\"":
                    next()
                    break outer
                case nil:
                    throw LeafScannerError(.unexpectedEOF(while: "parsing a string literal"), self.pos)
                default:
                    to = index
                }
            }
            return map((.init(from: pos, to: self.pos), .stringLiteral(source[from...to])))
        default:
            throw LeafScannerError(.unexpected(character!, while: "parsing an expression"), self.pos)
        }
    }

    public func scan() throws -> (Span, Token)? {
        if isEOF {
            return nil
        }

        switch state {
        case .raw:
            let ret = scanRaw()
            previous = ret.1
            return ret
        case .expression:
            let ret = try scanExpression()
            previous = ret.1
            return ret
        }
    }

    public func scanAll() throws -> [(Span, Token)] {
        var ret: [(Span, Token)] = []
        while let item = try scan() {
            ret.append(item)
        }
        return ret
    }
}

extension Sequence where Element == (LeafScanner.Span, LeafScanner.Token) {
    func tokensOnly() -> [LeafScanner.Token] {
        return self.map { $0.1 }
    }
}
