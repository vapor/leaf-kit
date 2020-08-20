internal struct LKSyntax: LKPrintable {
    private(set) var container: Container

    enum Container {
        /// Passthrough and raw are atomic syntaxes.
        case passthrough(LKParameter.Container) // where LP.isValued
        case raw(LKRawBlock)

        /// Blocks exist as the first of a pair, followed by scope, or passthrough || raw when atomic
        case block(String, LeafBlock, LKTuple?)
        /// A scope jump reference - special case of nil for placeholders
        case scope(table: Int?) // Scopes
    }

    private init(_ container: Container) { self.container = container }

    static func raw(_ store: LKRawBlock) -> Self { .init(.raw(store)) }
    static func passthrough(_ store: LKParameter) -> Self {.init(.passthrough(store.container)) }
    static func block(_ name: String,
                      _ block: LeafBlock,
                      _ params: LKTuple?) -> Self { .init(.block(name, block, params)) }
    static func scope(_ table: Int?) -> Self { .init(.scope(table: table)) }

    var description: String {
        switch container {
            case .block(let f, let b as Inline, _): return "\(f)(\(b.file.debugDescription), process: \(b.process ? "leaf" : "raw")):"
            case .block(let f, let b as Define, _): return "\(f)(\(b.identifier)):"
            case .block(let f, let b as Evaluate, _): return "\(f)(\(b.identifier)):"
            case .block(let f, _, let t): return "\(f)\(t?.description ?? ""):"
            case .passthrough(let p): return p.description
            case .raw(let r): return "raw(\(type(of: r)): \"\(r.contents.replacingOccurrences(of: "\n", with: "\\n"))\")"
            case .scope(let table) where table != nil: return "scope(table: \(table!))"
            case .scope: return "scope(undefined)"
        }
    }

    var short: String {
        switch container {
            case .block(let f, let b as Inline, _): return "\(f)(\(b.file.debugDescription), \(b.process ? "leaf" : "raw")):"
            case .block(let f, let b as Define, _): return "\(f)(\(b.identifier)):"
            case .block(let f, let b as Evaluate, _): return "\(f)(\(b.identifier)):"
            case .block(let f, _, let t): return "\(f)\(t?.short ?? ""):"
            case .passthrough(let p): return p.short
            case .raw(let r): return "raw(\(type(of: r)): \(r.byteCount.formatBytes))"
            case .scope(let table) where table != nil: return "scope(table: \(table!))"
            case .scope: return "scope(undefined)"
        }
    }

    var underestimatedSize: UInt32 {
        switch container {
            case .passthrough : return 16
            case .raw(let r)  : return r.byteCount
            default           : return 0
        }
    }
    
    /// Return t if scope(some), 0 if scope(nil), -1 if not scope
    var table: Int { if case .scope(let t) = container { return t ?? 0 } else { return -1} }
}

extension ContiguousArray where Element == ContiguousArray<LKSyntax> {
    var formatted: String { self[0].print(0, self) }
    var terse: String { self[0].print(0, self, true) }
}

extension ContiguousArray where Element == LKSyntax {
    func print(_ depth: Int = 0, _ tables: ContiguousArray<Self>, _ terse: Bool = false) -> String {
        let rule = (!terse) ? String(repeating: " ", count: depth) + repeatElement("-", count: 60 - depth) + "\n" : ""
        var result = rule
        let maxBuffer = String(self.count - 1).count
        for index in self.indices {
            if case .raw(let b as ByteBuffer) = self[index].container,
               terse, b.contents == Character.newLine.description { continue }
            let prefix = String(repeating: " ", count: maxBuffer - String(index).count) + "\(index): "
            result += "\(indent(depth) + prefix + (terse ? self[index].short : self[index].description))\n"
            if case .scope(.some(let table)) = self[index].container {
                result += table.signum() == -1 ? "\(String(repeating: " ", count: maxBuffer + 2) + indent(depth + 1))No scope set"
                          : tables[table].print(depth + maxBuffer + 2, tables, terse)
            }
        }
        result += rule
        if depth == 0 { result.removeLast(1) }
        return result
    }
    static let indent = " "
    func indent(_ depth: Int = 0) -> String { .init(repeating: Self.indent, count: depth) }
}

extension Array where Element == [LKSyntax] {
    func contiguous() -> ContiguousArray<ContiguousArray<LKSyntax>> {
        var contig: ContiguousArray<ContiguousArray<LKSyntax>> = .init()
        contig.reserveCapacity(count)
        self.forEach { contig.append(.init($0)) }
        return contig
    }
}
