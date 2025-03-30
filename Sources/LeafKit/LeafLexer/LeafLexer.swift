// MARK: `LeafLexer` Summary

/// `LeafLexer` is an opaque structure that wraps the lexing logic of Leaf-Kit.
///
/// Initialized with a `LeafRawTemplate` (raw string-providing representation of a file or other source),
/// used by evaluating with `LeafLexer.lex()` and either erroring or returning `[LeafToken]`
internal struct LeafLexer {
    // MARK: - Internal Only
    
    /// Convenience to initialize `LeafLexer` with a `String`
    init(name: String, template string: String) {
        self.name = name
        self.src = LeafRawTemplate(name: name, src: string)
        self.state = .raw
    }
    
    /// Init with `LeafRawTemplate`
    init(name: String, template: LeafRawTemplate) {
        self.name = name
        self.src = template
        self.state = .raw
    }
    
    /// Lex the stored `LeafRawTemplate`
    /// - Throws: `LexerError`
    /// - Returns: An array of fully built `LeafTokens`, to then be parsed by `LeafParser`
    mutating func lex() throws -> [LeafToken] {
        while let next = try self.nextToken() {
            lexed.append(next)
            offset += 1
        }
        return lexed
    }
    
    // MARK: - Private Only
    
    private enum State {
        /// Parse as raw, until it finds `#` (but consuming escaped `\#`)
        case raw
        /// Start attempting to sequence tag-viable tokens (tagName, parameters, etc)
        case tag
        /// Start attempting to sequence parameters
        case parameters
        /// Start attempting to sequence a tag body
        case body
    }
    
    /// Current state of the Lexer
    private var state: State
    /// Current parameter depth, when in a Parameter-lexing state
    private var depth = 0
    /// Current index in `lexed` that we want to insert at
    private var offset = 0
    /// Streat of `LeafTokens` that have been successfully lexed
    private var lexed: [LeafToken] = []
    /// The originating template source content (ie, raw characters)
    private var src: LeafRawTemplate
    /// Name of the template (as opposed to file name) - eg if file = "/views/template.leaf", `template`
    private var name: String
    
    // MARK: - Private - Actual implementation of Lexer

    private mutating func nextToken() throws -> LeafToken? {
        // if EOF, return nil - no more to read
        guard let current = src.peek() else { return nil }
        let isTagID = current == .tagIndicator.withLockedValue { $0 }
        let isTagVal = current.isValidInTagName
        let isCol = current == .colon
        let next = src.peek(aheadBy: 1)

        switch   (state,       isTagID, isTagVal, isCol, next) {
            case (.raw,        false,   _,        _,     _):     return lexRaw()
            case (.raw,        true,    _,        _,     .some): return lexCheckTagIndicator()
            case (.tag,        _,       true,     _,     _):     return lexNamedTag()
            case (.tag,        _,       false,    _,     _):     return lexAnonymousTag()
            case (.parameters, _,   _,   _,  _):                 return try lexParameters()
            case (.body,       _,   _, true,  _):                return lexBodyIndicator()
            /// Ambiguous case  - `#endTagName#` at EOF. Should this result in `tag(tagName),raw(#)`?
            case (.raw,        true,    _,        _,     .none):
                throw LexerError(.unknownError("Unescaped # at EOF"), src: src, lexed: lexed)
            default:
                throw LexerError(.unknownError("Template cannot be lexed"), src: src, lexed: lexed)
        }
    }

    // Lexing subroutines that can produce state changes:
    // * to .raw:           lexRaw, lexCheckTagIndicator
    // * to .tag:           lexCheckTagIndicator
    // * to .parameters:    lexAnonymousTag, lexNamedTag
    // * to .body:          lexNamedTag

    private mutating func lexAnonymousTag() -> LeafToken {
        state = .parameters
        depth = 0
        return .tag(name: "")
    }

    private mutating func lexNamedTag() -> LeafToken {
        let name = src.readWhile { $0.isValidInTagName }
        let trailing = src.peek()
        state = .raw
        if trailing == .colon { state = .body }
        if trailing == .leftParenthesis { state = .parameters; depth = 0 }
        return .tag(name: name)
    }

    /// Consume all data until hitting an unescaped `tagIndicator` and return a `.raw` token
    private mutating func lexRaw() -> LeafToken {
        var slice = ""
        let tagIndicator = Character.tagIndicator.withLockedValue({ $0 })
        while let current = src.peek(), current != tagIndicator {
            slice += src.readWhile { $0 != tagIndicator && $0 != .backSlash }
            guard let newCurrent = src.peek(), newCurrent == .backSlash else { break }
            if let next = src.peek(aheadBy: 1), next == tagIndicator {
                src.pop()
            }
            slice += src.pop()!.description
        }
        return .raw(slice)
    }

    /// Consume `#`, change state to `.tag` or `.raw`, return appropriate token
    private mutating func lexCheckTagIndicator() -> LeafToken {
        // consume `#`
        src.pop()
        // if tag indicator is followed by an invalid token, assume that it is unrelated to leaf
        let current = src.peek()
        if let current = current, current.isValidInTagName || current == .leftParenthesis {
            state = .tag
            return .tagIndicator
        } else {
            state = .raw
            return .raw((Character.tagIndicator.withLockedValue { $0 }).description)
        }
    }

    /// Consume `:`, change state to `.raw`, return `.tagBodyIndicator`
    private mutating func lexBodyIndicator() -> LeafToken {
        src.pop()
        state = .raw
        return .tagBodyIndicator
    }

    /// Parameter hot mess
    private mutating func lexParameters() throws -> LeafToken {
        // consume first character regardless of what it is
        let current = src.pop()!

        // Simple returning cases - .parametersStart/Delimiter/End, .whitespace, .stringLiteral Parameter
        switch current {
            case .leftParenthesis:
                depth += 1
                return .parametersStart
            case .rightParenthesis:
                switch (depth <= 1, src.peek() == .colon) {
                    case (true, true):  state = .body
                    case (true, false): state = .raw
                    case (false, _):    depth -= 1
                }
                return .parametersEnd
            case .comma:
                return .parameterDelimiter
            case .quote:
                let read = readWithEscapingQuotes(src: &src)
                guard src.peek() == .quote else {
                    throw LexerError(.unterminatedStringLiteral, src: src, lexed: lexed)
                }
                src.pop() // consume final quote
                return .parameter(.stringLiteral(read))
            case .space:
                let read = src.readWhile { $0 == .space }
                return .whitespace(length: read.count + 1)
            default: break
        }

        // Complex Parameter lexing situations - enhanced to allow non-whitespace separated values
        // Complicated by overlap in acceptable isValidInParameter characters between possible types
        // Process from most restrictive options to least to help prevent overly aggressive tokens
        // Possible results, most restrictive to least
        // * Operator
        // * Constant(Int)
        // * Constant(Double)
        // * Keyword
        // * Tag
        // * Variable

        // if current character isn't valid for any kind of parameter, something's majorly wrong
        guard current.isValidInParameter else {
            throw LexerError(.invalidParameterToken(current), src: src, lexed: lexed)
        }

        // Test for Operator first - this will only handle max two character operators, not ideal
        // Can't switch on this, MUST happen before trying to read tags
        if current.isValidOperator {
            // Try to get a valid 2char Op
            var op = LeafOperator(rawValue: String(current) + String(src.peek()!))
            if op != nil, !op!.available { throw LeafError(.unknownError("\(op!) is not yet supported as an operator")) }
            if op == nil { op = LeafOperator(rawValue: String(current)) } else { src.pop() }
            if op != nil, !op!.available { throw LeafError(.unknownError("\(op!) is not yet supported as an operator")) }
            return .parameter(.operator(op!))
        }

        // Test for numerics next. This is not very intelligent but will read base2/8/10/16
        // for Ints and base 10/16 for decimal through native Swift initialization
        // Will not adequately decay to handle things like `0b0A` and recognize as invalid.
        if current.canStartNumeric {
            var testInt: Int?
            var testDouble: Double?
            var radix: Int? = nil
            var sign = 1

            let next = src.peek()!
            let peekRaw = String(current) + (src.peekWhile { $0.isValidInNumeric })
            var peekNum = peekRaw.replacingOccurrences(of: String(.underscore), with: "")
            // We must be immediately preceeded by a minus to flip the sign
            // And only flip back if immediately preceeded by a const, tag or variable
            // (which we assume will provide a numeric). Grammatical errors in the
            // template (eg, keyword-numeric) may throw here
            if case .parameter(let p) = lexed[offset - 1], case .operator(let op) = p, op == .minus {
                switch lexed[offset - 2] {
                    case .parameter(let p):
                        switch p {
                            case .constant,
                                 .tag,
                                 .variable: sign = 1
                            default: throw LexerError(.invalidParameterToken("-"), src: src)
                        }
                    case .stringLiteral: throw LexerError(.invalidParameterToken("-"), src: src)
                    default: sign = -1
                }
            }

            switch (peekNum.contains(.period), next, peekNum.count > 2) {
                case (true, _, _) :                  testDouble = Double(peekNum)
                case (false, .binaryNotation, true): radix = 2
                case (false, .octalNotation, true):  radix = 8
                case (false, .hexNotation, true):    radix = 16
                default:                             testInt = Int(peekNum)
            }

            if let radix = radix {
                let start = peekNum.startIndex
                peekNum.removeSubrange(start ... peekNum.index(after: start))
                testInt = Int(peekNum, radix: radix)
            }

            if testInt != nil || testDouble != nil {
                // discard the minus
                if sign == -1 { self.lexed.removeLast(); offset -= 1 }
                src.popWhile { $0.isValidInNumeric }
                if testInt != nil { return .parameter(.constant(.int(testInt! * sign))) }
                else { return .parameter(.constant(.double(testDouble! * Double(sign)))) }
            }
        }

        // At this point, just read anything that's parameter valid, but not an operator,
        // Could be handled better and is probably way too aggressive.
        let name = String(current) + (src.readWhile { $0.isValidInParameter && !$0.isValidOperator })

        // If it's a keyword, return that
        if let keyword = LeafKeyword(rawValue: name) { return .parameter(.keyword(keyword)) }
        // Assume anything that matches .isValidInTagName is a tag
        // Parse can decay to a variable if necessary - checking for a paren
        // is over-aggressive because a custom tag may not take parameters
        let tagValid = name.compactMap { $0.isValidInTagName ? $0 : nil }.count == name.count

        if tagValid && src.peek()! == .leftParenthesis {
            return .parameter(.tag(name: name))
        } else {
            return .parameter(.variable(name: name))
        }
    }

    private func readWithEscapingQuotes(src: inout LeafRawTemplate) -> String {
        let read = src.readWhile { $0 != .quote && $0 != .newLine }
        if read.last == .backSlash && src.peek() == .quote {
            src.pop()
            return read.dropLast() + "\"" + readWithEscapingQuotes(src: &src)
        } else {
            return read
        }
    }
}
