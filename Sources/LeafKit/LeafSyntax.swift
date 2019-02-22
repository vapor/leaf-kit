indirect enum Syntax {
    case raw(ByteBuffer)
    case variable(Variable)
    
    case custom(CustomTag)
    
    case conditional(Conditional)
    case loop(Loop)
    case `import`(Import)
    case extend(Extend)
    case export(Export)
}

enum ConditionalSyntax {
    case `if`([ProcessedParameter])
    case `elseif`([ProcessedParameter])
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

let block = "  "

extension Syntax {
    struct Import {
        let key: String
        init(_ params: [ProcessedParameter]) throws {
            guard params.count == 1 else { throw "import only supports single param \(params)" }
            guard case .parameter(let p) = params[0] else { throw "expected parameter" }
            guard case .stringLiteral(let s) = p else { throw "import only supports string literals" }
            self.key = s
        }
    }
    
    struct Extend {
        let key: String
        // TODO: RANDOM ORDER FAILS TEST, OK?
        let exports: [String: Export]
        
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
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
    }
    
    struct Export {
        let key: String
        let body: [Syntax]
        
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
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
            var print = ""
            
            print += "export(" + key.debugDescription + ")"
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth) } .joined(separator: "\n")
            }
            
            var buffer = ""
            for _ in 0..<depth {
                buffer += block
            }
            return print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
        }
    }
    
    final class Conditional {
        let condition: ConditionalSyntax
        let body: [Syntax]
        private(set) var next: Conditional?
        
        init(_ condition: ConditionalSyntax, body: [Syntax]) {
            self.condition = condition
            self.body = body
        }
        
        func attach(_ new: Conditional) throws {
            var tail = self
            while let next = tail.next {
                tail = next
            }
            
            // todo: verify that is valid attachment
            tail.next = new
        }
        
        func print(depth: Int) -> String {
            var print = "conditional:\n"
            print += _print(depth: depth + 1)
            return print
        }
        
        func _print(depth: Int) -> String {
            var print = ""
            switch condition {
            case .if(let params):
                print += "if(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .elseif(let params):
                print += "elseif(" + params.map { $0.description } .joined(separator: ", ") + ")"
            case .else:
                print += "else"
            }
            
            if !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth) } .joined(separator: "\n")
            }
            
            var buffer = ""
            let block = "  "
            for _ in 0..<depth {
                buffer += block
            }
            print = print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
            
            // todo: remove recursion
            if let next = self.next {
                print += "\n"
                print += next._print(depth: depth)
            }
            return print
        }
    }
    
    struct Loop: CustomStringConvertible {
        /// the key to use when accessing items
        let item: String
        /// the key to use to access the array
        let array: String
        
        /// the body of the looop
        let body: [Syntax]
        
        /// initialize a new loop
        init(_ params: [ProcessedParameter], body: [Syntax]) throws {
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
        
        var description: String {
            return print(depth: 0)
        }
        
        func print(depth: Int) -> String {
            var print = ""
            print += "for(" + item + " in " + array + "):\n"
            print += body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            
            var buffer = ""
            for _ in 0..<depth {
                buffer += block
            }
            return print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
        }
    }
    
    struct Variable {
        let name: String
        
        init(_ params: [ProcessedParameter]) throws {
            guard params.count == 1 else { throw "only single parameter variable supported currently" }
            guard case .parameter(let p) = params[0] else { throw "expected single parameter" }
            switch p {
            case .variable(let n):
                self.name = n
            default: throw "todo: implement constant and literal? maybe process earlier as not variable, but raw"
            }
        }
        
        func print(depth: Int) -> String {
            return "variable(" + name + ")"
        }
    }
    
    struct CustomTag {
        let name: String
        let params: [ProcessedParameter]
        let body: [Syntax]?
    }
}

extension Syntax: CustomStringConvertible {
    
    var description: String {
        return print(depth: 0)
    }
    
    func print(depth: Int) -> String {
        var print = ""
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            print += "raw(\(string.debugDescription))"
        case .variable(let v):
            print += v.print(depth: depth)
        case .custom(let custom):
            print += custom.name + "(" + custom.params.map { $0.description } .joined(separator: ", ") + ")"
            if let body = custom.body, !body.isEmpty {
                print += ":\n" + body.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
        case .conditional(let c):
            print += c.print(depth: depth)
        case .loop(let loop):
            print += loop.print(depth: depth)
        case .import(let imp):
            print += "import(" + imp.key.debugDescription + ")"
        case .extend(let ext):
            print += "extend(" + ext.key.debugDescription + ")"
            if !ext.exports.isEmpty {
                print += ":\n" + ext.exports.values.map { $0.print(depth: depth + 1) } .joined(separator: "\n")
            }
        case .export(let export):
            print += export.print(depth: depth)
        }
        
        var buffer = ""
        for _ in 0..<depth {
            buffer += block
        }
        print = print.split(separator: "\n").map { buffer + $0 } .joined(separator: "\n")
        
        return print
    }
}
