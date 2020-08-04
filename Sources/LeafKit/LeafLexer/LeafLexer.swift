// MARK: Subject to change prior to 1.0.0 release
// MARK: -

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
        
        self.openers = .init()
        self.closers = .init()
        
        self.openers.formUnion(LeafConfiguration.entities.blockFactories.keys)
        self.openers.formUnion(LeafConfiguration.entities.functions.keys)
        
        for (tag, factory) in LeafConfiguration.entities.blockFactories {
            if let chained = factory as? ChainedBlock.Type {
                if chained.chainsTo.isEmpty { closers.insert("end" + tag) }
                else if chained.callSignature.isEmpty { closers.insert(tag) }
            } else { closers.insert("end" + tag) }
        }
    }
    
    /// Init with `LeafRawTemplate`
    init(name: String, template: LeafRawTemplate) {
        self.name = name
        self.src = template
        self.state = .raw
        
        self.openers = .init()
        self.closers = .init()
        
        self.openers.formUnion(LeafConfiguration.entities.blockFactories.keys)
        self.openers.formUnion(LeafConfiguration.entities.functions.keys)
        
        for (tag, factory) in LeafConfiguration.entities.blockFactories {
            if let chained = factory as? ChainedBlock.Type {
                if chained.chainsTo.isEmpty { closers.insert("end" + tag) }
                else if chained.callSignature.isEmpty { closers.insert(tag) }
            } else { closers.insert("end" + tag) }
        }
    }
    
    /// Lex the stored `LeafRawTemplate`
    /// - Throws: `LexerError`
    /// - Returns: An array of fully built `LeafTokens`, to then be parsed by `LeafParser`
    mutating func lex() throws -> [LeafToken] {
        // FIXME: Adjust to keep lexing if `try` throws a recoverable LexerError
        while let next = try nextToken() {
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
    
    private var openers: Set<String>
    private var closers: Set<String>
    
    // MARK: - Private - Actual implementation of Lexer

    private mutating func nextToken() throws -> LeafToken? {
        // if EOF, return nil - no more to read
        guard let current = src.peek() else { return nil }
        let isTagID = current == .tagIndicator
        let isTagVal = current.canStartIdentifier
        let isCol = current == .colon
        let next = src.peek(aheadBy: 1)

        switch   (state,       isTagID, isTagVal, isCol, next) {
            case (.raw,        false,   _,        _,     _):     return lexRaw()
            case (.raw,        true,    _,        _,     .some): return lexCheckTagIndicator()
            case (.raw,        true,    _,        _,     .none): return .raw(Character.tagIndicator.description)
            case (.tag,        _,       true,     _,     _):     return try lexNamedTag()
            case (.tag,        _,       false,    _,     _):     return lexAnonymousTag()
            case (.parameters, _,   _,   _,  _):
                var token: LeafToken?
                repeat { token = try lexParameters() } while token == nil
                guard let found = token else {
                    throw LexerError(.unknownError("Template ended on open parameters"), src: src, lexed: lexed)
                }
                return found
            case (.body,       _,   _, true,  _):                return lexBodyIndicator()
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
        return .tag(nil)
    }

    private mutating func lexNamedTag() throws -> LeafToken {
        let identifier = src.readWhile { $0.isValidInIdentifier }

        // if not a recognized identifier decay to raw and rewrite tagIndicator
        guard openers.contains(identifier) || closers.contains(identifier) else {
            lexed[offset - 1] = .raw("#")
            state = .raw;
            return .raw(identifier)
        }
        
        let xor = (params: src.peek() == .leftParenthesis, closer: closers.contains(identifier))
        
        switch xor {
            case (params: true, closer: true):
                throw LexerError(.unknownError("Closing tags can't have parameters"), src: src, lexed: lexed)
            case (params: false, closer: false):
                throw LexerError(.unknownError("Tags must have parameters"), src: src, lexed: lexed)
            case (params: true, closer: false):
                state = .parameters
                depth = 0
                return .tag(identifier)
            case (params: false, closer: true):
                if LeafConfiguration.entities.blockFactories.keys.contains(identifier) {
                    guard src.peek() == .colon else {
                        throw LexerError(.unknownError("Chained block missing `:`"), src: src, lexed: lexed)
                    }
                    lexed.append(.tag(identifier))
                    offset += 1
                    return lexBodyIndicator()
                } else {
                    state = .raw
                    return .tag(identifier)
                }
        }
    }

    /// Consume all data until hitting an unescaped `tagIndicator` and return a `.raw` token
    private mutating func lexRaw() -> LeafToken {
        var slice = ""
        while let current = src.peek(), current != .tagIndicator {
            slice += src.readWhile { $0 != .tagIndicator && $0 != .backSlash }
            guard let newCurrent = src.peek(), newCurrent == .backSlash else { break }
            if let next = src.peek(aheadBy: 1), next == .tagIndicator {
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
        if let current = current, current.canStartIdentifier || current == .leftParenthesis {
            state = .tag
            return .tagIndicator
        } else {
            state = .raw
            return .raw(Character.tagIndicator.description)
        }
    }

    /// Consume `:`, change state to `.raw`, return `.scopeIndicator`
    private mutating func lexBodyIndicator() -> LeafToken {
        src.pop()
        state = .raw
        return .scopeIndicator
    }

    /// Parameter hot mess
    private mutating func lexParameters() throws -> LeafToken? {
        // consume first character regardless of what it is
        let current = src.pop()!

        // Simple returning cases - .parametersStart/Delimiter/End, .literal(.string()), ParameterToken, space/comment discard
        switch current {
            case .leftParenthesis: depth += 1; return .parametersStart
            case .rightParenthesis:
                switch (depth <= 1, src.peek() == .colon) {
                    case (true, true):  state = .body
                    case (true, false): state = .raw
                    case (false, _):    depth -= 1
                }
                return .parametersEnd
            case .comma:  return .parameterDelimiter
            case .quote:
                let read = src.readWhile { $0 != .quote && $0 != .newLine }
                guard src.peek() == .quote else {
                    throw LexerError(.unterminatedStringLiteral, src: src, lexed: lexed)
                }
                src.pop() // consume final quote
                return .parameter(.literal(.string(read)))
            case .tab, .newLine, .space: // Whitespace - silently discard
                src.popWhile { $0.isWhitespace }
                return nil
            case .tagIndicator: // A comment - silently discard
                src.popWhile { $0 != .tagIndicator }
                guard src.pop() == .tagIndicator else {
                    throw LexerError(.unknownError("Template ended in open comment"), src: src, lexed: lexed)
                }
                return nil
            case .colon: return .scopeIndicator
            case .underscore:
                if !(src.peek()?.isWhiteSpace ?? false) { break }
                return .parameter(.keyword(._))
            case .leftBracket:
                if src.peek() == .rightBracket { src.pop(); return .parameter(.literal(.emptyArray)) }
            default: break
        }

        // Complex ParameterToken lexing situations - enhanced to allow non-space separated values
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
            if op != nil, !op!.lexable { throw LeafError(.unknownError("\(op!) is not yet supported as an operator")) }
            if op == nil { op = LeafOperator(rawValue: String(current)) } else { src.pop() }
            if op != nil, !op!.lexable { throw LeafError(.unknownError("\(op!) is not yet supported as an operator")) }
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
            if case .parameter(let p) = lexed[offset - 1],
               case .operator(let op) = p, op == .minus {
                switch lexed[offset - 2] {
                    case .parameter(let p):
                        switch p {
                            case .literal, .function, .variable: sign = 1
                            case .operator: sign = -1
                            case .keyword: throw LexerError(.invalidParameterToken(.minus), src: src)
                        }
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
                // discard the minus if negative
                if sign == -1 { self.lexed.removeLast(); offset -= 1 }
                src.popWhile { $0.isValidInNumeric }
                if testInt != nil { return .parameter(.literal(.int(testInt! * sign))) }
                else { return .parameter(.literal(.double(testDouble! * Double(sign)))) }
            }
        }
        
        guard current.canStartIdentifier else {
            throw LexerError(.invalidParameterToken(current), src: src)
        }
        
        // At this point, just read anything that's identifier valid,
        let identifier = String(current) + (src.readWhile { $0.isValidInIdentifier })

        // If it's a keyword, return that (or convert to variable if `self`
        if let keyword = LeafKeyword(rawValue: identifier) {
            return .parameter(.keyword(keyword))
        }
        
        // If identifier is followed by leftParen it's a tag, otherwise a variable
        if src.peek()! == .leftParenthesis { return .parameter(.function(identifier)) }
        else { return .parameter(.variable(identifier)) }
    }
}
