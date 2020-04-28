public indirect enum Syntax {
    case raw(ByteBuffer)
    case variable(Variable)
    case expression([ParameterDeclaration])
    case custom(CustomTagDeclaration)
    
    case conditional(Conditional)
    case loop(Loop)
    case `import`(Import)
    case extend(Extend)
    case export(Export)
}

public enum ConditionalSyntax {
    case `if`([ParameterDeclaration])
    case `elseif`([ParameterDeclaration])
    case `else`
}

extension Syntax.Extend {
    func extend(base: [Syntax]) -> [Syntax] {
        // from the base
        var extended = [Syntax]()
        base.forEach { syntax in
            switch syntax {
            case .import(let im):
                if let export = exports[im.key] {
                    // export exists, inject body
                    extended += export.body
                } else {
                    // any unsatisfied import will continue
                    // and can be satisfied later
                    extended.append(syntax)
                }
            default:
                extended.append(syntax)
            }
            
        }
        return extended
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
    public struct Import {
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
    
    public struct Extend {
        public let key: String
        public private(set) var exports: [String: Export]
        
        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard params.count == 1 else { throw "extend only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "extend expected parameter type, got \(params[0])" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
            
            var exports: [String: Export] = [:]
            try body.forEach { syntax in
                switch syntax {
                // extend can ONLY export, raw space in body ignored
                case .raw: return
                case .export(let export):
                    exports[export.key] = export
                default:
                    throw "unexpected token in extend body: \(syntax).. use raw space and `export` only"
                }
            }
            self.exports = exports
        }
        
        func print(depth: Int) -> String {
            var print = indent(depth)
            print += "extend(" + key.debugDescription + ")"
            if !exports.isEmpty {
                print += ":\n" + exports.sorted { $0.key < $1.key } .map { $0.1.print(depth: depth + 1) } .joined(separator: "\n")
            }
            return print
        }
    }
    
    public struct Export {
        public let key: String
        public internal(set) var body: [Syntax]
        
        public init(_ params: [ParameterDeclaration], body: [Syntax]) throws {
            guard (1...2).contains(params.count) else { throw "export expects 1 or 2 params" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "export only supports string literals" }
            self.key = s
            
            if params.count == 2 {
                guard case .parameter(let p) = params[1] else { throw "expected parameter" }
                guard case .stringLiteral(let s) = p else { throw "extend only supports string literals" }
                guard body.isEmpty else { throw "extend w/ two args requires NO body" }
                var buffer = ByteBufferAllocator().buffer(capacity: 0)
                buffer.writeString(s)
                self.body = [.raw(buffer)]
            } else {
                guard !body.isEmpty else { throw "export requires body or secondary arg" }
                self.body = body
            }
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
    
    public final class Conditional {
        public let condition: ConditionalSyntax
        public internal(set) var body: [Syntax]
        public private(set) var next: Conditional?
        
        public init(_ condition: ConditionalSyntax, body: [Syntax]) {
            self.condition = condition
            self.body = body
        }
        
        internal func attach(_ new: Conditional) throws {
            var tail = self
            while let next = tail.next {
                tail = next
            }
            
            // todo: verify that is valid attachment
            tail.next = new
        }
        
        func print(depth: Int) -> String {
            var print = indent(depth) + "conditional:\n"
            print += _print(depth: depth + 1)
            return print
        }
        
        private func _print(depth: Int) -> String {
            let buffer = indent(depth)
            
            var print = ""
            switch condition {
            case .if(let params):
                print += buffer + "if(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .elseif(let params):
                print += buffer + "elseif(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .else:
                print += buffer + "else"
            }
            
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
            
            // todo: remove recursion
            if let next = self.next {
                print += "\n"
                print += next._print(depth: depth)
            }
            
            
            return print
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
            self.item = item
            self.array = array
            
            guard !body.isEmpty else { throw "for loops require a body" }
            self.body = body
        }
        
        func print(depth: Int) -> String {
            var print = indent(depth)
            print += "for(" + item + " in " + array + "):\n"
            print += body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            return print
        }
    }
    
    public struct Variable {
        public let path: [String]

        public init(path: String) {
            self.path = path.split(separator: ".").map(String.init)
        }

        public init(_ params: [ParameterDeclaration]) throws {
            guard params.count == 1 else { throw "only single parameter variable supported currently" }
            guard case .parameter(let p) = params[0] else { throw "expected single parameter, got: \(params)" }
            switch p {
            case .variable(let n):
                self.init(path: n)
            default: throw "todo: implement constant and literal? maybe process earlier as not variable, but raw.. \(p)"
            }
        }
        
        func print(depth: Int) -> String {
            return indent(depth) + "variable(" + path.joined(separator: ".") + ")"
        }
    }
    
    public struct CustomTagDeclaration {
        public let name: String
        public let params: [ParameterDeclaration]
        public internal(set) var body: [Syntax]?
        
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
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return indent(depth) + "raw(\(string.debugDescription))"
        case .expression(let exp):
            return "\(exp)"
        case .variable(let v):
            return v.print(depth: depth)
        case .custom(let custom):
            return custom.print(depth: depth)
        case .conditional(let c):
            return c.print(depth: depth)
        case .loop(let loop):
            return loop.print(depth: depth)
        case .import(let imp):
            return imp.print(depth: depth)
        case .extend(let ext):
            return ext.print(depth: depth)
        case .export(let export):
            return export.print(depth: depth)
        }
    }
}

extension Syntax {
    mutating func inlineRefs(_ externals: [String: LeafAST], _ new: inout Syntax?) -> Set<String> {
        var changed = false
        var rf = Set<String>()

        switch self {
            case .conditional(let co):
                var tail: Syntax.Conditional? = co
                while tail != nil {
                    var i = tail!.body.startIndex
                    while i < tail!.body.endIndex {
                        switch tail!.body[i] {
                            case .extend(let ex):
                                let key = ex.key
                                if let insert = externals[key] {
                                    let inlined = ex.extend(base: insert.ast)
                                    tail!.body.replaceSubrange(i...i, with: inlined)
                                    changed = true
                                } else {
                                    rf.insert(key)
                                    i = tail!.body.index(after: i)
                                }
                            default:
                                var sub: Syntax? = nil
                                rf.formUnion(tail!.body[i].inlineRefs(externals, &sub))
                                if sub != nil { tail!.body[i] = sub!; changed = true}
                                i = tail!.body.index(after: i)
                        }
                    }
                    tail = tail!.next
                }
                if changed || !rf.isEmpty { new = .conditional(tail!) }
                return rf
            case .custom(var cu):
                guard cu.body != nil else { return .init() }
                var i = cu.body!.startIndex
                while i < cu.body!.endIndex {
                    switch cu.body![i] {
                        case .extend(let ex):
                            let key = ex.key
                            if let insert = externals[key] {
                                let inlined = ex.extend(base: insert.ast)
                                cu.body!.replaceSubrange(i...i, with: inlined)
                                changed = true
                            } else {
                                rf.insert(key)
                                i = cu.body!.index(after: i)
                            }
                        default:
                            var sub: Syntax? = nil
                            rf.formUnion(cu.body![i].inlineRefs(externals, &sub))
                            if sub != nil { cu.body![i] = sub!; changed = true }
                            i = cu.body!.index(after: i)
                    }
                }
                if changed || !rf.isEmpty { new = .custom(cu) }
                return rf
            case .export(var exp):
                var i = exp.body.startIndex
                while i < exp.body.endIndex {
                    switch exp.body[i] {
                        case .extend(let ex):
                            let key = ex.key
                            if let insert = externals[key] {
                                let inlined = ex.extend(base: insert.ast)
                                exp.body.replaceSubrange(i...i, with: inlined)
                                changed = true
                            } else {
                                rf.insert(key)
                                i = exp.body.index(after: i)
                            }
                        default:
                            var sub: Syntax? = nil
                            rf.formUnion(exp.body[i].inlineRefs(externals, &sub))
                            if sub != nil { exp.body[i] = sub!; changed = true}
                            i = exp.body.index(after: i)
                    }
                }
                if changed || !rf.isEmpty { new = .export(exp) }
                return rf
            case .loop(var lo):
                var i = lo.body.startIndex
                while i < lo.body.endIndex {
                    switch lo.body[i] {
                        case .extend(let ex):
                            let key = ex.key
                            if let insert = externals[key] {
                                let inlined = ex.extend(base: insert.ast)
                                lo.body.replaceSubrange(i...i, with: inlined)
                                changed = true
                            } else {
                                rf.insert(key)
                                i = lo.body.index(after: i)
                            }
                        default:
                            var sub: Syntax? = nil
                            rf.formUnion(lo.body[i].inlineRefs(externals, &sub))
                            if sub != nil { lo.body[i] = sub!; changed = true }
                            i = lo.body.index(after: i)
                    }
                }
                if changed || !rf.isEmpty { new = .loop(lo) }
                return rf
            default: return .init()
        }
    }
    
}
