import NIO

public indirect enum Syntax: Sendable {
    // MARK: .raw - Makeable, Entirely Readable
    case raw(ByteBuffer)
    // MARK: `case variable(Variable)` removed
    // MARK: .expression - Makeable, Entirely Readable
    case expression([ParameterDeclaration])
    // MARK: .custom - Unmakeable, Semi-Readable
    case custom(CustomTagDeclaration)
    // MARK: .with - Makeable, Entirely Readable
    case with(With)

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

public enum ConditionalSyntax: Sendable {
    case `if`([ParameterDeclaration])
    case `elseif`([ParameterDeclaration])
    case `else`
    
    internal func imports() -> Set<String> {
        switch self {
            case .if(let pDA), .elseif(let pDA):
                var imports = Set<String>()
                _ = pDA.map { imports.formUnion($0.imports()) }
                return imports
            default: return .init()
        }
    }
    
    internal func inlineImports(_ imports: [String : Syntax.Export]) -> ConditionalSyntax {
        switch self {
            case .else: return self
            case .if(let pDA): return .if(pDA.inlineImports(imports))
            case .elseif(let pDA): return .elseif(pDA.inlineImports(imports))
        }
    }
    
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

// temporary addition
extension Syntax: BodiedSyntax  {
    internal func externals() -> Set<String> {
        switch self {
            case .conditional(let bS as BodiedSyntax),
                 .custom(let bS as BodiedSyntax),
                 .export(let bS as BodiedSyntax),
                 .extend(let bS as BodiedSyntax),
                 .with(let bS as BodiedSyntax),
                 .loop(let bS as BodiedSyntax): return bS.externals()
            default: return .init()
        }
    }
    
    internal func imports() -> Set<String> {
        switch self {
            case .import(let i): return .init(arrayLiteral: i.key)
            case .conditional(let bS as BodiedSyntax),
                 .custom(let bS as BodiedSyntax),
                 .export(let bS as BodiedSyntax),
                 .extend(let bS as BodiedSyntax),
                 .expression(let bS as BodiedSyntax),
                 .loop(let bS as BodiedSyntax): return bS.imports()
            // .variable, .raw
            default: return .init()
        }
    }
    
    internal func inlineRefs(_ externals: [String: LeafAST], _ imports: [String: Export]) -> [Syntax] {
        if case .extend(let extend) = self, let context = extend.context {
            let inner = extend.inlineRefs(externals, imports)
            return [.with(.init(context: context, body: inner))]
        }
        var result = [Syntax]()
        switch self {
            case .import(let im):
                let ast = imports[im.key]?.body
                if let ast = ast {
                    // If an export exists for this import, inline it
                    ast.forEach { result += $0.inlineRefs(externals, imports) }
                } else {
                    // Otherwise just keep itself
                    result.append(self)
                }
            // Recursively inline single Syntaxes
            case .conditional(let bS as BodiedSyntax),
                 .custom(let bS as BodiedSyntax),
                 .export(let bS as BodiedSyntax),
                 .extend(let bS as BodiedSyntax),
                 .with(let bS as BodiedSyntax),
                 .loop(let bS as BodiedSyntax): result += bS.inlineRefs(externals, imports)
            case .expression(let pDA): result.append(.expression(pDA.inlineImports(imports)))
            // .variable, .raw
            default: result.append(self)
        }
        return result
    }
}

internal protocol BodiedSyntax {
    func externals() -> Set<String>
    func imports() -> Set<String>
    func inlineRefs(_ externals: [String: LeafAST], _ imports: [String: Syntax.Export]) -> [Syntax]
}

extension Array: BodiedSyntax where Element == Syntax {
    internal func externals() -> Set<String> {
        var result = Set<String>()
        _ = self.map { result.formUnion( $0.externals()) }
        return result
    }
    
    internal func imports() -> Set<String> {
        var result = Set<String>()
        _ = self.map { result.formUnion( $0.imports() ) }
        return result
    }

    internal func inlineRefs(_ externals: [String: LeafAST], _ imports: [String: Syntax.Export]) -> [Syntax] {
        var result = [Syntax]()
        _ = self.map { result.append(contentsOf: $0.inlineRefs(externals, imports)) }
        return result
    }
}

func indent(_ depth: Int) -> String {
    let block = "  "
    var buffer = ""
    for _ in 0..<depth {
        buffer += block
    }
    return buffer
}

extension Syntax {
    public struct Import: Sendable {
        public let key: String
        public init(_ params: [ParameterDeclaration]) throws {
            guard params.count == 1 else { throw "import only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
        }

        func print(depth: Int) -> String {
            return indent(depth) + "import(" + key.debugDescription + ")"
        }
    }

    public struct Extend: BodiedSyntax, Sendable {
        public let key: String
        public private(set) var exports: [String: Export]
        public private(set) var context: [ParameterDeclaration]?
        private var externalsSet: Set<String>
        private var importSet: Set<String>

        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard params.count == 1 || params.count == 2 else { throw "extend only supports one or two parameters \(params)" }
            if params.count == 2 {
                guard let context = With.extract(params: Array(params[1...])) else {
                    throw "#extend's context requires a single expression"
                }
                self.context = context
            }
            guard case .parameter(let p) = params[0] else { throw "extend expected parameter type, got \(params[0])" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
            self.externalsSet = .init(arrayLiteral: self.key)
            self.importSet = .init()
            self.exports = [:]

            try body.forEach { syntax in
                switch syntax {
                    // extend can ONLY export, raw space in body ignored
                    case .raw: return
                    case .export(let export):
                        guard !export.externals().contains(self.key) else {
                            throw LeafError(.cyclicalReference(self.key, [self.key]))
                        }
                        self.exports[export.key] = export
                        externalsSet.formUnion(export.externals())
                        importSet.formUnion(export.imports())
                    default:
                        throw "unexpected token in extend body: \(syntax).. use raw space and `export` only"
                }
            }
        }
        
        internal init(key: String, exports: [String : Syntax.Export], externalsSet: Set<String>, importSet: Set<String>) {
            self.key = key
            self.exports = exports
            self.externalsSet = externalsSet
            self.importSet = importSet
        }
        
        func externals() -> Set<String> {
            return externalsSet
        }
        func imports() -> Set<String> {
            return importSet
        }
        
        func inlineRefs(_ externals: [String: LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            var newExports = [String: Export]()
            var newImports = imports
            var newExternalsSet = Set<String>()
            var newImportSet = Set<String>()
            
            // In the case where #exports themselves contain #extends or #imports, rebuild those
            for (key, value) in exports {
                guard !value.externals().isEmpty || !value.imports().isEmpty else {
                    newExports[key] = value
                    continue
                }
                guard case .export(let e) = value.inlineRefs(externals, imports).first else { fatalError() }
                newExports[key] = e
                newExternalsSet.formUnion(e.externals())
                newImportSet.formUnion(e.imports())
            }
            
            // Now add this extend's exports onto the passed imports
            newExports.forEach {
                newImports[$0.key] = $0.value
            }
            
            var results = [Syntax]()
            
            // Either return a rebuilt #extend or an inlined and (potentially partially) resolved extended syntax
            if !externals.keys.contains(self.key) {
                let resolvedExtend = Syntax.Extend(key: self.key,
                                                   exports: newExports,
                                                   externalsSet: externalsSet,
                                                   importSet: newImportSet)
                results.append(.extend(resolvedExtend))
            } else {
                // Get the external AST
                let newAst = externals[self.key]!
                // Remove this AST from the externals to avoid needless checks
                let externals = externals.filter { $0.key != self.key }
                newAst.ast.forEach {
                    // Add each external syntax, resolving with the current available
                    // exports and passing this extend's exports to the syntax's imports
                    
                    results += $0.inlineRefs(externals, newImports)
                    // expressions may have been created by imports, convert
                    // single parameter static values to .raw
                    if case .expression(let e) = results.last {
                        if let raw = e.atomicRaw() {
                            results.removeLast()
                            results.append(raw)
                        }
                    }
                }
            }
            
            return results
        }
        
        func availableExports() -> Set<String> {
            return .init(exports.keys)
        }

        func print(depth: Int) -> String {
            var print = indent(depth)
            if let context = self.context {
                print += "extend(" + key.debugDescription + "," + context.debugDescription + ")"
            } else {
                print += "extend(" + key.debugDescription + ")"
            }
            if !exports.isEmpty {
                print += ":\n" + exports.sorted { $0.key < $1.key } .map { $0.1.print(depth: depth + 1) } .joined(separator: "\n")
            }
            return print
        }
    }

    public struct Export: BodiedSyntax, Sendable {
        public let key: String
        public internal(set) var body: [Syntax]
        private var externalsSet: Set<String>
        private var importSet: Set<String>

        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard (1...2).contains(params.count) else { throw "export expects 1 or 2 params" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "export only supports string literals" }
            self.key = s

            if params.count == 2 {
            //    guard case .parameter(let _) = params[1] else { throw "expected parameter" }
                guard body.isEmpty else { throw "extend w/ two args requires NO body" }
                self.body = [.expression([params[1]])]
                self.externalsSet = .init()
                self.importSet = .init()
            } else {
                guard !body.isEmpty else { throw "export requires body or secondary arg" }
                self.body = body
                self.externalsSet = body.externals()
                self.importSet = body.imports()
            }
        }
        
        internal init(key: String, body: [Syntax]) {
            self.key = key
            self.body = body
            self.externalsSet = body.externals()
            self.importSet = body.imports()
        }
        
        func externals() -> Set<String> {
            return self.externalsSet
        }
        
        func imports() -> Set<String> {
            return self.importSet
        }
        
        func inlineRefs(_ externals: [String: LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            guard !externalsSet.isEmpty || !importSet.isEmpty else { return [.export(self)] }
            return [.export(.init(key: self.key, body: self.body.inlineRefs(externals, imports)))]
        }

        func print(depth: Int) -> String {
            var print = indent(depth)
            print += "export(" + key.debugDescription + ")"
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
            return print
        }
    }

    public struct Conditional: BodiedSyntax, Sendable {
        public internal(set) var chain: [(
            condition: ConditionalSyntax,
            body: [Syntax]
        )]
        
        private var externalsSet: Set<String>
        private var importSet: Set<String>

        public init(_ condition: ConditionalSyntax, body: [Syntax]) {
            self.chain = []
            self.chain.append((condition, body))
            self.externalsSet = body.externals()
            self.importSet = body.imports()
            self.importSet.formUnion(condition.imports())
        }
        
        internal init(chain: [(condition: ConditionalSyntax, body: [Syntax])], externalsSet: Set<String>, importSet: Set<String>) {
            self.chain = chain
            self.externalsSet = externalsSet
            self.importSet = importSet
        }

        internal mutating func attach(_ new: Conditional) throws {
            if chain.isEmpty {
                self.chain = new.chain
                self.importSet = new.importSet
            } else if !new.chain.isEmpty {
                let state = chain.last!.condition.naturalType
                let next = new.chain.first!.condition.naturalType
                if (next.rawValue > state.rawValue) ||
                    (state == next && state == .elseif) {
                    self.chain.append(contentsOf: new.chain)
                    self.externalsSet.formUnion(new.externalsSet)
                    self.importSet.formUnion(new.importSet)
                } else {
                    throw "\(next.description) can't follow \(state.description)"
                }
            }
        }
        
        func externals() -> Set<String> {
            return externalsSet
        }
        
        func imports() -> Set<String> {
            return importSet
        }
        
        func inlineRefs(_ externals: [String: LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            guard !externalsSet.isEmpty || !importSet.isEmpty else { return [.conditional(self)] }
            var newChain = [(ConditionalSyntax, [Syntax])]()
            var newImportSet = Set<String>()
            var newExternalsSet = Set<String>()
            
            chain.forEach {
                if !$0.body.externals().isEmpty || !$0.body.imports().isEmpty || !$0.condition.imports().isEmpty {
                    newChain.append(($0.0.inlineImports(imports), $0.1.inlineRefs(externals, imports)))
                    newImportSet.formUnion(newChain.last!.0.imports())
                    newImportSet.formUnion(newChain.last!.1.imports())
                    newExternalsSet.formUnion(newChain.last!.1.externals())
                } else {
                    newChain.append($0)
                }
            }
            
            return [.conditional(.init(chain: newChain, externalsSet: newExternalsSet, importSet: newImportSet))]
        }

        func print(depth: Int) -> String {
            var print = indent(depth) + "conditional:\n"
            print += _print(depth: depth + 1)
            return print
        }

        private func _print(depth: Int) -> String {
            let buffer = indent(depth)

            var print = ""
            
            for index in chain.indices {
                switch chain[index].condition {
                    case .if(let params):
                        print += buffer + "if(" + params.map { $0.description } .joined(separator: ", ") + ")"
                    case .elseif(let params):
                        print += buffer + "elseif(" + params.map { $0.description } .joined(separator: ", ") + ")"
                    case .else:
                        print += buffer + "else"
                }

                if !chain[index].body.isEmpty {
                    print += ":\n" + chain[index].body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
                }
                
                if index != chain.index(before: chain.endIndex) { print += "\n" }
            }

            return print
        }
    }

    public struct With: BodiedSyntax, Sendable {
        public internal(set) var body: [Syntax]
        public internal(set) var context: [ParameterDeclaration]

        private var externalsSet: Set<String>
        private var importSet: Set<String>

        func externals() -> Set<String> {
            self.externalsSet
        }

        func imports() -> Set<String> {
            self.importSet
        }

        func inlineRefs(_ externals: [String : LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            guard !externalsSet.isEmpty || !importSet.isEmpty else { return [.with(self)] }
            return [.with(.init(context: context, body: body.inlineRefs(externals, imports)))]
        }

        internal init(context: [ParameterDeclaration], body: [Syntax]) {
            self.context = context
            self.body = body
            self.externalsSet = body.externals()
            self.importSet = body.imports()
        }

        static internal func extract(params: [ParameterDeclaration]) -> [ParameterDeclaration]? {
            if
                params.count == 1,
                case .expression(let list) = params[0] {
                    return list
                }

            if
                params.count == 1,
                case .parameter = params[0] {
                    return params
                }

            return nil
        }

        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            Swift.print(params)
            guard let params = With.extract(params: params) else {
                throw "with statements expect a single expression"
            }

            guard !body.isEmpty else { throw "with statements require a body" }
            self.body = body
            self.context = params
            self.externalsSet = body.externals()
            self.importSet = body.imports()
        }

        func print(depth: Int) -> String {
            var print = indent(depth)
            print += "with(\(context)):\n"
            print += body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            return print
        }
    }

    public struct Loop: BodiedSyntax, Sendable {
        /// the key to use when accessing items
        public let item: String
        /// the key to use to access the array
        public let array: String
        /// the key to use when accessing the current index
        public let index: String

        /// the body of the looop
        public internal(set) var body: [Syntax]
        
        private var externalsSet: Set<String>
        private var importSet: Set<String>

        /// initialize a new loop
        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            if params.count == 1 {
                guard
                    case .expression(let list) = params[0],
                    list.count == 3,
                    case .parameter(let left) = list[0],
                    case .variable(let item) = left,
                    case .parameter(let `in`) = list[1],
                    case .keyword(let k) = `in`,
                    k == .in,
                    case .parameter(let right) = list[2],
                    case .variable(let array) = right
                    else { throw "for loops expect one of the following expressions: 'name in names' or 'nameIndex, name in names'" }
                self.item = item
                self.array = array
                self.index = "index"
            } else {
                guard
                    params.count == 2,
                    case .parameter(.variable(let index)) = params[0],
                    case .expression(let list) = params[1],
                    list.count == 3,
                    case .parameter(let left) = list[0],
                    case .variable(let item) = left,
                    case .parameter(let `in`) = list[1],
                    case .keyword(let k) = `in`,
                    k == .in,
                    case .parameter(let right) = list[2],
                    case .variable(let array) = right
                else { throw "for loops expect one of the following expressions: 'name in names' or 'nameIndex, name in names'" }
                self.item = item
                self.array = array
                self.index = index
            }

            guard !body.isEmpty else { throw "for loops require a body" }
            self.body = body
            self.externalsSet = body.externals()
            self.importSet = body.imports()
        }
        
        internal init(item: String, array: String, index: String, body: [Syntax]) {
            self.item = item
            self.array = array
            self.index = index
            self.body = body
            self.externalsSet = body.externals()
            self.importSet = body.imports()
        }
        
        func externals() -> Set<String> {
            return externalsSet
        }
        
        func imports() -> Set<String> {
            return importSet
        }

        func inlineRefs(_ externals: [String: LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            guard !externalsSet.isEmpty || !importSet.isEmpty else { return [.loop(self)] }
            return [.loop(.init(item: item, array: array, index: index, body: body.inlineRefs(externals, imports)))]
        }
        
        func print(depth: Int) -> String {
            var print = indent(depth)
            print += "for(" + (index == "index" ? "" : "\(index), ") + item + " in " + array + "):\n"
            print += body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            return print
        }
    }

    public struct CustomTagDeclaration: BodiedSyntax, Sendable {
        public let name: String
        public let params: [ParameterDeclaration]
        public internal(set) var body: [Syntax]?
        private var externalsSet: Set<String>
        private var importSet: Set<String>
        
        internal init(name: String, params: [ParameterDeclaration], body: [Syntax]? = nil) {
            self.name = name
            self.params = params
            self.externalsSet = .init()
            self.importSet = params.imports()
            self.body = body
            if let b = body {
                self.externalsSet.formUnion(b.externals())
                self.importSet.formUnion(b.imports())
            }
        }
        
        func externals() -> Set<String> {
            return externalsSet
        }
        
        func imports() -> Set<String> {
            return importSet
        }
        
        func inlineRefs(_ externals: [String: LeafAST], _ imports: [String : Syntax.Export]) -> [Syntax] {
            guard !importSet.isEmpty || !externalsSet.isEmpty else { return [.custom(self)] }
            let p = params.imports().isEmpty ? params : params.inlineImports(imports)
            let b = body == nil ? nil : body!.inlineRefs(externals, imports)
            return [.custom(.init(name: name, params: p, body: b))]
        }

        func print(depth: Int) -> String {
            var print = indent(depth)
            print += name + "(" + params.map { $0.description } .joined(separator: ", ") + ")"
            if let body = body, !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
            return print
        }
    }
}

extension Syntax: CustomStringConvertible {
    public var description: String {
        return print(depth: 0)
    }

    func print(depth: Int) -> String {
        switch self {
            case .expression(let exp): return indent(depth) + "expression\(exp.description)"
 //           case .variable(let v):     return v.print(depth: depth)
            case .custom(let custom):  return custom.print(depth: depth)
            case .conditional(let c):  return c.print(depth: depth)
            case .loop(let loop):      return loop.print(depth: depth)
            case .import(let imp):     return imp.print(depth: depth)
            case .extend(let ext):     return ext.print(depth: depth)
            case .export(let export):  return export.print(depth: depth)
            case .with(let with):      return with.print(depth: depth)
            case .raw(var bB):
                let string = bB.readString(length: bB.readableBytes) ?? ""
                return indent(depth) + "raw(\(string.debugDescription))"
        }
    }
}
