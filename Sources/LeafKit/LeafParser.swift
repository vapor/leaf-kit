import Foundation

public struct LeafParseError: Error, LocalizedError {
    public let kind: Kind
    public let pos: LeafScanner.Span

    public init(_ kind: Kind, _ pos: LeafScanner.Span) {
        self.kind = kind
        self.pos = pos
    }

    var localizedDescription: String {
        "\(self.pos): \(self.kind)"
    }

    public enum Kind {
        case earlyEOF(wasExpecting: String)
        case expectedGot(expected: LeafScanner.Token, got: LeafScanner.Token, while: String)
        case expectedOneOfGot(expected: [LeafScanner.Token], got: LeafScanner.Token, while: String)
        case expectedExpressionGot(got: LeafScanner.Token, while: String)
        case unexpected(token: LeafScanner.Token, while: String)
        case unimplemented
        case badNumber
        case nonassociative(LeafScanner.Token, LeafScanner.Token)
        case badElseEnding
        case operatorIsNotPrefix(LeafScanner.Operator)
        case operatorIsNotInfix(LeafScanner.Operator)
        case badParameterCount(what: String, expected: [Int], got: Int)
        case expectedStringConstant
    }
}

func combine(_ from: LeafScanner.Span, _ to: LeafScanner.Span) -> LeafScanner.Span {
    return .init(from: from.from, to: to.to)
}

/// a hybrid recursive-descent and pratt parser
/// most of the parser is written in rec-dec style, while
/// ``parseExpression`` and ``parseAtom`` are written in
/// the pratt parser style to handle the general issue of recursive parsers
/// being unable to handle left-recursive grammars (e.g. [[[[[[...] + 1] + 1] + 1] + 1] + 1])
/// more specifically, the two functions implement a form of precedence climbing.
///
/// for those not familiar with parsers, the parser is written in two ways:
/// - one where the function calls mirror the language itself, e.g. for the start of an if statement, the grammar would look like:
///   ifStatement = "if" + expression + ":"
///   and the code would mirror that:
///       parseIfStatement() {
///           expect("if")
///           parseExpression()
///           expect(":")
///       }
/// - one where we switch to a more complex yet more capable algorithim for the complexity of handling operators, e.g.
///   deciding how to group 1 + 1 / 3 ^ 2 != 3 and parsing that efficiently
///
/// most subsequent documentation assumes you understand the parsing techniques being used, and
/// notes expected invariants for the methods to be called
///
/// more formally, the parser is an top-down LR(1) parser that switches to being an
/// operator precedence parser implemented using precedence climbing.
public class LeafParser {
    public let scanner: LeafScanner

    public init(from: LeafScanner) {
        self.scanner = from
    }

    private func error(_ kind: LeafParseError.Kind, _ span: LeafScanner.Span) -> LeafParseError {
        .init(kind, span)
    }

    private func expect(token expects: LeafScanner.Token, while doing: String) throws {
        guard let (span, token) = try read() else {
            throw error(.earlyEOF(wasExpecting: expects.description), .eof)
        }
        guard token == expects else {
            throw error(.expectedGot(expected: expects, got: token, while: doing), span)
        }
    }

    private func expectExpression(while doing: String) throws -> (LeafScanner.Span, LeafScanner.ExpressionToken) {
        guard let (span, token) = try read() else {
            throw error(.earlyEOF(wasExpecting: "the start of an expression"), .eof)
        }
        guard case .expression(let inner) = token else {
            throw error(.expectedExpressionGot(got: token, while: doing), span)
        }
        return (span, inner)
    }

    private func expectPeekExpression(while doing: String) throws -> (LeafScanner.Span, LeafScanner.ExpressionToken) {
        guard let (span, token) = try peek() else {
            throw error(.earlyEOF(wasExpecting: "the start of an expression"), .eof)
        }
        guard case .expression(let inner) = token else {
            throw error(.expectedExpressionGot(got: token, while: doing), span)
        }
        return (span, inner)
    }

    @discardableResult
    private func expect(oneOf expects: [LeafScanner.Token], while doing: String) throws -> (LeafScanner.Span, LeafScanner.Token) {
        guard let (span, token) = try read() else {
            throw error(.earlyEOF(wasExpecting: "one of " + expects.map { $0.description }.joined(separator: ", ")), .eof)
        }
        guard expects.contains(token) else {
            throw error(.expectedOneOfGot(expected: expects, got: token, while: doing), span)
        }
        return (span, token)
    }

    /// expects that you've just parsed the ``.bodyStart``
    /// returns:
    /// - the final span
    /// - the ast
    private func parseConditional(_ initialExpr: Expression) throws -> (LeafScanner.Span, Statement.Conditional) {
        var ifTrueStatements: [Statement] = []
        var optFinalTagSpan: LeafScanner.Span?
        var optFinalTag: Substring?
        outer:
        while let (span, token) = try read() {
            switch token {
            case .tag(let tag) where tag == "endif" || tag == "elseif" || tag == "else":
                optFinalTagSpan = span
                optFinalTag = tag
                break outer
            default:
                ifTrueStatements.append(try parseStatement(span: span, token: token))
            }
        }
        guard let finalTagSpan = optFinalTagSpan, let finalTag = optFinalTag else {
            throw error(.earlyEOF(wasExpecting: "ending tag for a conditional"), .eof)
        }
        switch finalTag {
        case "endif":
            return (finalTagSpan, .init(condition: initialExpr, onTrue: ifTrueStatements, onFalse: []))
        case "elseif":
            try expect(token: .enterExpression, while: "parsing elseif's condition")
            let elseIfExpr = try parseExpression(minimumPrecedence: 0)
            try expect(token: .exitExpression, while: "finishing parsing elseif's condition")
            try expect(token: .bodyStart, while: "looking for elseif's body")
            let (span, cond) = try parseConditional(elseIfExpr)
            return (span, .init(condition: initialExpr, onTrue: ifTrueStatements, onFalse: [.init(.conditional(cond), span: combine(finalTagSpan, span))]))
        case "else":
            try expect(token: .bodyStart, while: "looking for else's body")
            var ifFalseStatements: [Statement] = []
            var optFinalTagSpan: LeafScanner.Span?
            var optFinalTag: Substring?
            outer:
            while let (span, token) = try read() {
                switch token {
                case .tag(let tag) where tag == "endif" || tag == "elseif" || tag == "else":
                    optFinalTagSpan = span
                    optFinalTag = tag
                    break outer
                default:
                    ifFalseStatements.append(try parseStatement(span: span, token: token))
                }
            }
            guard let finalTagSpan = optFinalTagSpan, let finalTag = optFinalTag else {
                throw error(.earlyEOF(wasExpecting: "ending tag for a conditional"), .eof)
            }
            switch finalTag {
            case "endif":
                return (finalTagSpan, .init(condition: initialExpr, onTrue: ifTrueStatements, onFalse: ifFalseStatements))
            case "elseif", "else":
                throw error(.badElseEnding, finalTagSpan)
            default:
                assert(false)
            }
        default:
            assert(false)
        }
    }

    /// expects that you're right after the body opening; i.e. ':'
    private func parseTagBody(name: Substring) throws -> (LeafScanner.Span, [Statement]) {
        var statements: [Statement] = []
        var optFinalTagSpan: LeafScanner.Span?
        var optFinalTag: Substring?
        outer:
        while let (span, token) = try read() {
            switch token {
            case .tag(let tag) where tag == "end"+name:
                optFinalTagSpan = span
                optFinalTag = tag
                break outer
            default:
                statements.append(try parseStatement(span: span, token: token))
            }
        }
        guard let finalTagSpan = optFinalTagSpan, let _ = optFinalTag else {
            throw error(.earlyEOF(wasExpecting: "the end of the \(name) tag"), .eof)
        }
        return (finalTagSpan, statements)
    }

    /// expects peek() == .enterExpression
    private func parseEnterExitParams() throws -> (LeafScanner.Span, [Expression]) {
        var first = true
        var parms: [Expression] = []
        repeat {
            if first {
                try expect(token: .enterExpression, while: "starting to parse parameters")
            } else {
                try expect(token: .expression(.comma), while: "in the middle of parsing parameters")
            }
            parms.append(try parseExpression(minimumPrecedence: 0))
            first = false
        } while try peek()?.1 == .expression(.comma)

        guard let (span, token) = try read() else {
            throw LeafParseError(.earlyEOF(wasExpecting: "right bracket for parameter list"), .eof)
        }
        guard case .exitExpression = token else {
            throw LeafParseError(.expectedGot(expected: .exitExpression, got: token, while: "looking for ending bracket of parameter list"), span)
        }
        return (span, parms)
    }

    /// expects peek() == .expression(.leftParen)
    private func parseExpressionParams() throws -> (LeafScanner.Span, [Expression]) {
        var first = true
        var parms: [Expression] = []
        repeat {
            if first {
                try expect(token: .expression(.leftParen), while: "starting to parse inline tag parameters")
            } else {
                try expect(token: .expression(.comma), while: "in the middle of parsing inline tag parameters")
            }
            parms.append(try parseExpression(minimumPrecedence: 0))
            first = false
        } while try peek()?.1 == .expression(.comma)

        guard let (span, token) = try read() else {
            throw error(.earlyEOF(wasExpecting: "right bracket for inline tag parameter list"), .eof)
        }
        guard case .expression(.rightParen) = token else {
            throw error(.expectedGot(expected: .expression(.rightParen), got: token, while: "looking for ending bracket of inline tag parameter list"), span)
        }
        return (span, parms)
    }

    private func parseIdent(while doing: String) throws -> (LeafScanner.Span, Substring) {
        guard let (span, tok) = try read() else {
            throw error(.earlyEOF(wasExpecting: doing), .eof)
        }
        guard case .expression(.identifier(let substr)) = tok else {
            throw error(.expectedExpressionGot(got: tok, while: doing), span)
        }
        return (span, substr)
    }

    private func parseStatement(span: LeafScanner.Span, token: LeafScanner.Token) throws -> Statement {
        switch token {
        case .raw(let val):
            return .init(.raw(val), span: span)
        case .tag(let tag):
            switch tag {
            case "if":
                try expect(token: .enterExpression, while: "looking for start of if condition")
                let expr = try parseExpression(minimumPrecedence: 0)
                try expect(token: .exitExpression, while: "looking for end of if condition")
                try expect(token: .bodyStart, while: "looking for start of if body")
                let (span, cond) = try parseConditional(expr)
                return .init(.conditional(cond), span: span)
            case "with":
                try expect(token: .enterExpression, while: "looking for start of with context")
                let expr = try parseExpression(minimumPrecedence: 0)
                try expect(token: .exitExpression, while: "looking for end of with context")
                try expect(token: .bodyStart, while: "looking for start of with body")
                let (endSpan, statements) = try parseTagBody(name: tag)
                return .init(.with(.init(context: expr, body: statements)), span: combine(span, endSpan))
            case "for":
                try expect(token: .enterExpression, while: "looking for start of for loop")
                let (_, firstName) = try parseIdent(while: "looking for foreach loop variable")
                let (_, tok) = try expect(oneOf: [.expression(.identifier("in")), .expression(.comma)], while: "looking for 'in' keyword or comma in foreach loop")
                let secondName: Substring?
                switch tok {
                case .expression(.identifier("in")):
                    secondName = nil
                case .expression(.comma):
                    let (_, second) = try parseIdent(while: "looking for foreach loop variable")
                    try expect(token: .expression(.identifier("in")), while: "looking for 'in' keyword in foreach loop")
                    secondName = second
                default:
                    throw LeafError(.internalError(what: "for loop parsing shouldn't have gotten to where it's trying to discriminate between something that isn't 'in' or ','"))
                }
                let expr = try parseExpression(minimumPrecedence: 0)
                try expect(token: .exitExpression, while: "looking for closing parenthesis of foreach loop header")
                try expect(token: .bodyStart, while: "looking for start of for loop body")
                let (endSpan, statements) = try parseTagBody(name: tag)
                let contentName = secondName ?? firstName
                let indexName = secondName != nil ? firstName : nil
                return .init(.forLoop(.init(name: contentName, indexName: indexName, inValue: expr, body: statements)), span: combine(span, endSpan))
            case "import":
                let (endSpan, params) = try parseEnterExitParams()
                guard params.count == 1 else {
                    throw error(.badParameterCount(what: "import", expected: [1], got: params.count), combine(span, endSpan))
                }
                guard case .string(let reference) = params[0].kind else {
                    throw error(.expectedStringConstant, params[0].span)
                }
                return .init(.import(.init(name: reference)), span: combine(span, endSpan))
            case "export":
                let (endSpan, params) = try parseEnterExitParams()
                guard params.count == 1 else {
                    throw error(.badParameterCount(what: "export", expected: [1], got: params.count), combine(span, endSpan))
                }
                guard case .string(let reference) = params[0].kind else {
                    throw error(.expectedStringConstant, params[0].span)
                }
                try expect(token: .bodyStart, while: "looking for start of export body")
                let (bodyEndSpan, statements) = try parseTagBody(name: tag)
                return .init(.export(.init(name: reference, body: statements)), span: combine(span, bodyEndSpan))
            case "extend":
                let (endSpan, params) = try parseEnterExitParams()
                guard params.count == 1 || params.count == 2 else {
                    throw error(.badParameterCount(what: "extend", expected: [1, 2], got: params.count), combine(span, endSpan))
                }
                guard case .string(let reference) = params[0].kind else {
                    throw error(.expectedStringConstant, params[0].span)
                }

                let expr = params.count == 2 ? params[1] : nil
                if try peek()?.1 == .bodyStart {
                    try consume()
                    let (endSpan, statements) = try parseTagBody(name: tag)
                    return .init(
                        .extend(.init(
                            reference: reference,
                            context: expr,
                            exports: statements.compactMap { (statement: Statement) in
                                if case .export(let export) = statement.kind {
                                    return export
                                }
                                return nil
                            }
                        )), span: combine(span, endSpan)
                    )
                } else {
                    return .init(.extend(.init(reference: reference, context: expr, exports: [])), span: combine(span, endSpan))
                }
            default:
                let params: [Expression]
                if try peek()?.1 == .enterExpression {
                    (_, params) = try parseEnterExitParams()
                } else {
                    params = []
                }
                let finalSpan: LeafScanner.Span
                let statements: [Statement]?
                if try peek()?.1 == .bodyStart {
                    try consume()
                    let endSpan: LeafScanner.Span
                    (endSpan, statements) = try parseTagBody(name: tag)
                    finalSpan = combine(span, endSpan)
                } else {
                    finalSpan = span
                    statements = nil
                }
                return .init(.tag(name: tag, parameters: params, body: statements), span: finalSpan)
            }
        case .substitution:
            try expect(token: .enterExpression, while: "looking for start bracket of substitution")
            let expr = try parseExpression(minimumPrecedence: 0)
            try expect(token: .exitExpression, while: "looking for end bracket of substitution")
            return .init(.substitution(expr), span: expr.span)
        case .bodyStart:
            return .init(.raw(":"), span: span)
        case .expression, .enterExpression, .exitExpression:
            throw error(.unexpected(token: token, while: "parsing statements"), span)
        }
    }

    public func parse() throws -> [Statement] {
        var statements: [Statement] = []
        while let (span, token) = try read() {
            statements.append(try parseStatement(span: span, token: token))
        }
        return statements
    }

    private func parseAtom() throws -> Expression {
        let (span, expr) = try self.expectPeekExpression(while: "parsing expression atom")
        switch expr {
        // structural elements
        case .leftParen:
            try consume()
            let expr = try parseExpression(minimumPrecedence: 1)
            try expect(token: .expression(.rightParen), while: "parsing parenthesized expression")
            return expr
        case .leftBracket: // array or dictionary
            try consume()
            // empty array
            if let (endSpan, tok) = try peek(), tok == .expression(.rightBracket) {
                try consume()
                return .init(.arrayLiteral([]), span: combine(span, endSpan))
            }
            // empty dictionary
            if let (_, tok) = try peek(), tok == .expression(.colon) {
                try consume()
                let (endSpan, tok) = try expectExpression(while: "parsing end bracket of dictionary literal")
                guard tok == .rightBracket else {
                    throw error(.expectedGot(expected: .expression(.rightBracket), got: .expression(tok), while: "parsing end bracket of dictionary literal"), endSpan)
                }
                return .init(.dictionaryLiteral([]), span: combine(span, endSpan))
            }
            // parse the first element
            let firstElement = try parseExpression(minimumPrecedence: 0)
            // now, whether the next token is a comma or a colon determines if we're parsing an array or dictionary
            let (signifierSpan, signifier) = try expectPeekExpression(while: "parsing array or dictionary literal")
            if signifier == .comma { // parse an n-item array where n >= 2

                var items: [Expression] = [firstElement]
                repeat {
                    try expect(token: .expression(.comma), while: "in the middle of parsing parameters")
                    items.append(try parseExpression(minimumPrecedence: 0))
                } while try peek()?.1 == .expression(.comma)

                guard let (endSpan, token) = try read() else {
                    throw error(.earlyEOF(wasExpecting: "closing bracket for array"), .eof)
                }
                guard case .expression(.rightBracket) = token else {
                    throw error(.expectedGot(expected: .expression(.rightBracket), got: token, while: "looking for closing bracket of array"), endSpan)
                }

                return .init(.arrayLiteral(items), span: combine(span, endSpan))

            } else if signifier == .rightBracket { // parse a single-item array
                try consume()
                return .init(.arrayLiteral([firstElement]), span: combine(span, signifierSpan))
            } else if signifier == .colon { // parse an n-item dictionary where n >= 1
                try consume()

                // parse the first element manually before hitting the loop
                let firstValue = try parseExpression(minimumPrecedence: 0)

                var pairs: [(Expression, Expression)] = [(firstElement, firstValue)]

                while try peek()?.1 == .expression(.comma) {
                    try consume() // eat comma
                    let key = try parseExpression(minimumPrecedence: 0)
                    _ = try expect(token: .expression(.colon), while: "parsing dictionary item")
                    let value = try parseExpression(minimumPrecedence: 0)
                    pairs.append((key, value))
                }

                guard let (endSpan, token) = try read() else {
                    throw error(.earlyEOF(wasExpecting: "closing bracket for dictionary"), .eof)
                }
                guard case .expression(.rightBracket) = token else {
                    throw error(.expectedGot(expected: .expression(.rightBracket), got: token, while: "looking for closing bracket of dictionary"), endSpan)
                }

                return .init(.dictionaryLiteral(pairs), span: combine(span, endSpan))
            } else {
                let expected: [LeafScanner.Token] = [.expression(.comma), .expression(.rightBracket), .expression(.colon)]
                throw error(.expectedOneOfGot(expected: expected, got: .expression(signifier), while: "parsing array or dictionary literal"), combine(span, signifierSpan))
            }
        case .operator(let op) where op.data.kind.prefix:
            try consume()
            let expr = try parseAtom()
            return .init(.unary(op, expr), span: combine(span, expr.span))
        case .operator(let op):
            // TODO: unexpected error
            throw error(.operatorIsNotPrefix(op), span)
        case .identifier(let name):
            try consume()
            return .init(.variable(name), span: span)
        case .integer(let base, let digits):
            try consume()
            guard let num = Int64(digits, radix: base) else {
                throw error(.badNumber, span)
            }
            return .init(.integer(num), span: span)
        case .decimal(let base, let digits):
            try consume()
            _ = base // TODO: parse as right base
            guard let num = Float64(digits) else {
                throw error(.badNumber, span)
            }
            return .init(.float(num), span: span)
        case .stringLiteral(let lit):
            try consume()
            return .init(.string(lit), span: span)
        case .boolean(let val):
            try consume()
            return .init(.boolean(val), span: span)
        case .comma, .rightParen, .rightBracket, .colon:
            try consume()
            throw error(.unexpected(token: .expression(expr), while: "parsing expression atom"), span)
        }
    }

    private func parseExpression(minimumPrecedence: Int) throws -> Expression {
        var lhs = try parseAtom()
        while true {
            guard let (span, rTok) = try peek() else {
                break
            }
            if case .variable(let name) = lhs.kind, case .expression(.leftParen) = rTok {
                let (span, parms) = try parseExpressionParams()
                lhs = .init(.tagApplication(name: name, params: parms), span: combine(lhs.span, span))
                continue
            }
            guard case .expression(let opTok) = rTok else {
                break
            }
            if case .operator(.fieldAccess) = opTok {
                try consume()
                let (span2, tok2) = try expectExpression(while: "parsing field name")
                guard case .identifier(let field) = tok2 else {
                    throw error(.unexpected(token: .expression(tok2), while: "parsing field name"), span2)
                }
                lhs = .init(.fieldAccess(value: lhs, fieldName: field), span: combine(span, span2))
                continue
            }
            guard
                case .operator(let op) = opTok,
                op.data.priority >= minimumPrecedence
                else { break }
            guard op.data.kind.interfix else {
                throw error(.operatorIsNotInfix(op), span)
            }

            try consume()
            let nextMinimumPrecedence = op.data.rightAssociative ? op.data.priority+1 : op.data.priority
            let rhs = try parseExpression(minimumPrecedence: nextMinimumPrecedence)

            lhs = .init(.binary(lhs, op, rhs), span: combine(lhs.span, rhs.span))
            if let tok = try peek(),
                case .expression(.operator(let nextOp)) = tok.1 {
                    if op.data.nonAssociative || nextOp.data.nonAssociative {
                        throw error(.nonassociative(tok.1, .expression(opTok)), span)
                    }
                }
        }

        return lhs
    }

    private func consume() throws {
        _ = try read()
    }

    private func read() throws -> (LeafScanner.Span, LeafScanner.Token)? {
        if let val = peeked {
            peeked = nil
            return val
        } else {
            return try self.scanner.scan()
        }
    }

    private var peeked: (LeafScanner.Span, LeafScanner.Token)? = nil
    private func peek() throws -> (LeafScanner.Span, LeafScanner.Token)? {
        if peeked == nil {
            peeked = try self.scanner.scan()
        }
        return peeked
    }
}

public protocol SExprRepresentable {
    func sexpr() -> String
}

public protocol Substitutable {
    func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Self
    func substituteImport(name: String, with statement: Statement) -> Self
    func unsubstitutedExtends() -> Set<String>
}

public extension Sequence where Element: SExprRepresentable {
    func sexpr() -> String {
        self.map { $0.sexpr() }.joined(separator: " ")
    }
}

public extension Sequence where Element: Substitutable {
    func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> [Element] {
        self.map { $0.substituteExtend(name: name, with: statement) }
    }
    func substituteImport(name: String, with: Statement) -> [Element] {
        self.map { $0.substituteImport(name:name, with: with) }
    }
    func unsubstitutedExtends() -> Set<String> {
        Set(self.map { $0.unsubstitutedExtends() }.joined())
    }
}

public struct Statement: SExprRepresentable, Substitutable {
    public let kind: Kind
    public let span: LeafScanner.Span

    init(_ kind: Kind, span: LeafScanner.Span) {
        self.span = span
        self.kind = kind
    }
    init(combined statements: [Statement]) {
        self.span = combine(statements.first!.span, statements.last!.span)
        self.kind = .combined(statements)
    }

    public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement {
        switch self.kind {
        case .raw(_), .import(_), .substitution(_), .tag(_, _, _):
            return self
        case .conditional(let cond):
            return .init(.conditional(cond.substituteExtend(name: name, with: statement)), span: span)
        case .extend(let extend):
            if extend.reference == name {
                let state = statement(extend.exports.substituteExtend(name: name, with: statement))
                if let ctx = extend.context {
                    return .init(.with(.init(context: ctx, body: [state])), span: state.span)
                } else {
                    return state
                }
            }
            return .init(.extend(extend.substituteExtend(name: name, with: statement)), span: span)
        case .forLoop(let forLoop):
            return .init(.forLoop(forLoop.substituteExtend(name: name, with: statement)), span: span)
        case .with(let with):
            return .init(.with(with.substituteExtend(name: name, with: statement)), span: span)
        case .export(let export):
            return .init(.export(export.substituteExtend(name: name, with: statement)), span: span)
        case .combined(let combined):
            return .init(.combined(combined.substituteExtend(name: name, with: statement)), span: span)
        }
    }
    public func substituteImport(name: String, with statement: Statement) -> Statement {
        switch self.kind {
        case .import(let imp) where imp.name == name:
            return statement
        case .raw(_), .substitution(_), .tag(_, _, _), .import(_):
            return self
        case .conditional(let cond):
            return .init(.conditional(cond.substituteImport(name: name, with: statement)), span: span)
        case .extend(let extend):
            return .init(.extend(extend.substituteImport(name: name, with: statement)), span: span)
        case .forLoop(let forLoop):
            return .init(.forLoop(forLoop.substituteImport(name: name, with: statement)), span: span)
        case .with(let with):
            return .init(.with(with.substituteImport(name: name, with: statement)), span: span)
        case .export(let export):
            return .init(.export(export.substituteImport(name: name, with: statement)), span: span)
        case .combined(let combined):
            return .init(.combined(combined.substituteImport(name: name, with: statement)), span: span)
        }
    }
    public func unsubstitutedExtends() -> Set<String> {
        switch self.kind {
        case .raw(_), .import(_), .substitution(_), .tag(_, _, _):
            return []
        case .conditional(let cond):
            return cond.unsubstitutedExtends()
        case .extend(let extend):
            return extend.unsubstitutedExtends()
        case .forLoop(let forLoop):
            return forLoop.unsubstitutedExtends()
        case .with(let with):
            return with.unsubstitutedExtends()
        case .export(let export):
            return export.unsubstitutedExtends()
        case .combined(let combined):
            return combined.unsubstitutedExtends()
        }
    }

    public func sexpr() -> String {
        switch self.kind {
        case .raw(_):
            return "(raw)"
        case .conditional(let cond):
            return cond.sexpr()
        case .extend(let extend):
            return extend.sexpr()
        case .forLoop(let loop):
            return loop.sexpr()
        case .with(let with):
            return with.sexpr()
        case .import(_):
            return "(import)"
        case .export(let export):
            return export.sexpr()
        case .substitution(let expr):
            return "(substitution \(expr.sexpr()))"
        case .tag(_, let parameters, let statements):
            if let states = statements {
                return "(tag \(parameters.sexpr()) \(states.sexpr()))"
            }
            return "(tag \(parameters.sexpr()))"
        case .combined(let statement):
            return "\(statement)"
        }
    }

    /// A statement in a Leaf file
    public indirect enum Kind {
        /// A raw string to be printed directly
        case raw(Substring)

        /// An expression to be evaluated and substituted into the text
        case substitution(Expression)

        /// A tag invocation
        case tag(name: Substring, parameters: [Expression], body: [Statement]?)

        /// A conditional
        case conditional(Conditional)

        /// A for in loop
        case forLoop(ForLoop)

        /// A with statement
        case with(With)

        /// An import statement
        case `import`(Import)

        /// An export statement
        case export(Export)

        /// An extend statement
        case extend(Extend)

        /// A combined statement, generated during substitution
        case combined([Statement])
    }

    public struct Conditional: SExprRepresentable, Substitutable {
        public let condition: Expression
        public let onTrue: [Statement]
        public let onFalse: [Statement]

        public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement.Conditional {
            .init(
                condition: condition,
                onTrue: onTrue.substituteExtend(name: name, with: statement),
                onFalse: onFalse.substituteExtend(name: name, with: statement)
            )
        }
        public func substituteImport(name: String, with statement: Statement) -> Statement.Conditional {
            .init(
                condition: condition,
                onTrue: onTrue.substituteImport(name: name, with: statement),
                onFalse: onFalse.substituteImport(name: name, with: statement)
            )
        }
        public func unsubstitutedExtends() -> Set<String> {
            var unsubst = onTrue.unsubstitutedExtends()
            onFalse.unsubstitutedExtends().forEach { unsubst.insert($0) }
            return unsubst
        }
        public func sexpr() -> String {
            "(conditional \(condition.sexpr()) onTrue: \(onTrue.sexpr()) onFalse: \(onFalse.sexpr()))"
        }
    }

    public struct ForLoop: SExprRepresentable, Substitutable {
        public let name: Substring
        public let indexName: Substring?
        public let inValue: Expression
        public let body: [Statement]

        public func unsubstitutedExtends() -> Set<String> {
            self.body.unsubstitutedExtends()
        }
        public func substituteImport(name: String, with statement: Statement) -> Statement.ForLoop {
            .init(name: self.name, indexName: self.indexName, inValue: inValue, body: body.substituteImport(name: name, with: statement))
        }
        public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement.ForLoop {
            .init(name: self.name, indexName: self.indexName, inValue: inValue, body: body.substituteExtend(name: name, with: statement))
        }
        public func sexpr() -> String {
            return #"(for \#(inValue.sexpr()) \#(body.sexpr()))"#
        }
    }

    public struct With: SExprRepresentable, Substitutable {
        public let context: Expression
        public let body: [Statement]

        public func unsubstitutedExtends() -> Set<String> {
            self.body.unsubstitutedExtends()
        }
        public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement.With {
            .init(context: context, body: body.substituteExtend(name: name, with: statement))
        }
        public func substituteImport(name: String, with statement: Statement) -> Statement.With {
            .init(context: context, body: body.substituteImport(name: name, with: statement))
        }
        public func sexpr() -> String {
            return #"(with \#(context.sexpr()) \#(body.sexpr()))"#
        }
    }

    public struct Extend: SExprRepresentable, Substitutable {
        public let reference: Substring
        public let context: Expression?
        public let exports: [Export]

        public func unsubstitutedExtends() -> Set<String> {
            return Set<String>([String(reference)]).union(exports.unsubstitutedExtends())
        }
        public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement.Extend {
            .init(reference: reference, context: context, exports: exports.substituteExtend(name: name, with: statement))
        }
        public func substituteImport(name: String, with statement: Statement) -> Statement.Extend {
            .init(reference: reference, context: context, exports: exports.substituteImport(name: name, with: statement))
        }
        public func sexpr() -> String {
            return #"(extend \#(exports.sexpr()))"#
        }
    }

    public struct Export: SExprRepresentable, Substitutable {
        let name: Substring
        let body: [Statement]

        public func unsubstitutedExtends() -> Set<String> {
            return body.unsubstitutedExtends()
        }
        public func substituteExtend(name: String, with statement: ([Statement.Export]) -> Statement) -> Statement.Export {
            .init(name: self.name, body: body.substituteExtend(name: name, with: statement))
        }
        public func substituteImport(name: String, with statement: Statement) -> Statement.Export {
            .init(name: self.name, body: body.substituteImport(name: name, with: statement))
        }
        public func sexpr() -> String {
            return #"(export \#(body.sexpr()))"#
        }
    }

    public struct Import: SExprRepresentable {
        public let name: Substring

        public func sexpr() -> String {
            return "(import)"
        }
    }
}

public struct Expression: SExprRepresentable {
    public let span: LeafScanner.Span
    public let kind: Kind

    init(_ kind: Kind, span: LeafScanner.Span) {
        self.kind = kind
        self.span = span
    }

    public func sexpr() -> String {
        switch self.kind {
        case .integer(_):
            return "(integer)"
        case .float(_):
            return "(integer)"
        case .string(_):
            return "(string)"
        case .variable(_):
            return "(variable)"
        case .boolean(true):
            return "(true)"
        case .boolean(false):
            return "(false)"
        case .fieldAccess(let expr, _):
            return "(field_access \(expr.sexpr()))"
        case .tagApplication(_, let params):
            return "(tag_application \(params.sexpr()))"
        case .unary(let op, let rhs):
            return #"(\#(op.rawValue) \#(rhs.sexpr()))"#
        case .binary(let lhs, let op, let rhs):
            return #"(\#(op.rawValue) \#(lhs.sexpr()) \#(rhs.sexpr()))"#
        case .arrayLiteral(let items):
            return #"(array_literal \#(items.sexpr()))"#
        case .dictionaryLiteral(let pairs):
            let inner = pairs.map { "(\($0.0.sexpr()) \($0.1.sexpr()))" }.joined(separator: " ")
            return #"(dictionary_literal \#(inner))"#
        }
    }

    public indirect enum Kind {
        case integer(Int64)
        case float(Float64)
        case string(Substring)
        case variable(Substring)
        case boolean(Bool)
        case fieldAccess(value: Expression, fieldName: Substring)
        case tagApplication(name: Substring, params: [Expression])
        case unary(LeafScanner.Operator, Expression)
        case binary(Expression, LeafScanner.Operator, Expression)
        case arrayLiteral([Expression])
        case dictionaryLiteral([(Expression, Expression)])
    }
}

