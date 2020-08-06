public indirect enum Syntax {
    // MARK: .raw - Makeable, Entirely Readable
    case raw(ByteBuffer)
    // MARK: `case variable(Variable)` removed
    // MARK: .expression - Makeable, Entirely Readable
    case expression([ParameterDeclaration])
    // MARK: .custom - Unmakeable, Semi-Readable
    case custom(CustomTagDeclaration)

    // MARK: .conditional - Makeable, Entirely Readable
    case conditional(Conditional)
    // MARK: .loop - Makeable, Semi-Readable
    case loop(Loop)
    // MARK: .`import` - Makeable, Readable (Pointlessly)
    case `import`(Import)
    // MARK: .extend - Makeable, Semi-Readable
    case extend(Extend)
    // MARK: .export - Makeable, Semi-Readable
    case export(Export)
}

public enum ConditionalSyntax {
    case `if`([ParameterDeclaration])
    case `elseif`([ParameterDeclaration])
    case `else`
    
    internal func expression() -> [ParameterDeclaration] {
        switch self {
            case .else: return [.parameter(.keyword(.true))]
            case .elseif(let e): return e
            case .if(let i): return i
        }
    }
    
    internal var naturalType: ConditionalSyntax.NaturalType {
        switch self {
            case .if: return .if
            case .elseif: return .elseif
            case .else: return .else
        }
    }
    
    internal enum NaturalType: Int, CustomStringConvertible {
        case `if` = 0
        case `elseif` = 1
        case `else` = 2
        
        var description: String {
            switch self {
                case .else: return "else"
                case .elseif: return "elseif"
                case .if: return "if"
            }
        }
    }
}

extension Syntax {
    public struct Import {
        public let key: String
        public init(_ params: [ParameterDeclaration]) throws {
            guard params.count == 1 else { throw "import only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .literal(.string(let s)) = p else { throw "import only supports string literals" }
            self.key = s
        }
    }

    public struct Extend {
        public let key: String
        public private(set) var exports: [String: Export]

        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard params.count == 1 else { throw "extend only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "extend expected parameter type, got \(params[0])" }
            guard case .literal(.string(let s)) = p else { throw "import only supports string literals" }
            self.key = s
            self.exports = [:]

            try body.forEach { syntax in
                switch syntax {
                    // extend can ONLY export, raw space in body ignored
                    case .raw: return
                    case .export(let export):
                        self.exports[export.key] = export
                    default:
                        throw "unexpected token in extend body: \(syntax).. use raw space and `export` only"
                }
            }
        }
        
        internal init(key: String, exports: [String : Syntax.Export], externalsSet: Set<String>, importSet: Set<String>) {
            self.key = key
            self.exports = exports
        }
    }

    public struct Export {
        public let key: String
        public internal(set) var body: [Syntax]

        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard (1...2).contains(params.count) else { throw "export expects 1 or 2 params" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .literal(.string(let s)) = p else { throw "export only supports string literals" }
            self.key = s

            if params.count == 2 {
            //    guard case .parameter(let _) = params[1] else { throw "expected parameter" }
                guard body.isEmpty else { throw "extend w/ two args requires NO body" }
                self.body = [.expression([params[1]])]
            } else {
                guard !body.isEmpty else { throw "export requires body or secondary arg" }
                self.body = body
            }
        }
        
        internal init(key: String, body: [Syntax]) {
            self.key = key
            self.body = body
        }
    }

    public struct Conditional {
        public internal(set) var chain: [(
            condition: ConditionalSyntax,
            body: [Syntax]
        )]
    
        public init(_ condition: ConditionalSyntax, body: [Syntax]) {
            self.chain = []
            self.chain.append((condition, body))
        }
        
        internal init(chain: [(condition: ConditionalSyntax, body: [Syntax])], externalsSet: Set<String>, importSet: Set<String>) {
            self.chain = chain
        }

        internal mutating func attach(_ new: Conditional) throws {
            if chain.isEmpty {
                self.chain = new.chain
            } else if !new.chain.isEmpty {
                let state = chain.last!.condition.naturalType
                let next = new.chain.first!.condition.naturalType
                if (next.rawValue > state.rawValue) ||
                    (state == next && state == .elseif) {
                    self.chain.append(contentsOf: new.chain)
                } else {
                    throw "\(next.description) can't follow \(state.description)"
                }
            }
        }

       
    }

    public struct Loop {
        /// the key to use when accessing items
        public let item: String
        /// the key to use to access the array
        public let array: String

        /// the body of the looop
        public internal(set) var body: [Syntax]

        /// initialize a new loop
        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
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
            self.item = item.description
            self.array = array.description

            guard !body.isEmpty else { throw "for loops require a body" }
            self.body = body
        }
        
        internal init(item: String, array: String, body: [Syntax]) {
            self.item = item
            self.array = array
            self.body = body
        }
     
    }

    public struct CustomTagDeclaration {
        public let name: String
        public let params: [ParameterDeclaration]
        public internal(set) var body: [Syntax]?
        
        internal init(name: String, params: [ParameterDeclaration], body: [Syntax]? = nil) {
            self.name = name
            self.params = params
            self.body = body
        }
    }
}
