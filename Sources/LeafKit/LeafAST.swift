// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct Leaf4AST: Hashable {
    // MARK: - Public
    
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
    public static func ==(lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    public let key: String
    public var name: String { String(key.split(separator: ":", maxSplits: 1)[1]) }
    
    public struct Info {
        public internal(set) var parsed: Date = .distantPast
        public internal(set) var minSize: UInt64 = 0
        public internal(set) var resolved: Bool = true
        public internal(set) var ownTables: Int = 0
        public internal(set) var cachedTables: Int = 0
        public internal(set) var defines: [String] = []
        public internal(set) var inlines: [String] = []
        public internal(set) var requiredFiles: [String] = []
        public internal(set) var requiredASTs: Set<String> = []
        public internal(set) var requiredRaws: Set<String> = []
        internal var includedASTs: Set<String> = []
    }
    
    // MARK: - Internal/Private Only
    internal struct ScopeReference: Hashable {
        let identifier: String
        let table: Int
        let row: Int
        
        func hash(into hasher: inout Hasher) { hasher.combine(identifier)}
        
        func remap(by offset: Int = 0) -> Self {
            .init(identifier: identifier, table: table + offset, row: row) }
    }
    
    /// The AST scope tables
    internal var scopes: [[Leaf4Syntax]]
    /// Reference pointers to all `Define` metablocks
    internal var defines: [ScopeReference]
    /// Reference pointers to all `Inline` metablocks, whether they're templates, and timestamp for when they were inlined
    ///
    /// If the block has *not* been inlined, `Date` will be .distantFuture
    internal var inlines: [(inline: ScopeReference, process: Bool, at: Date)]
    /// Absolute minimum size of a rendered document from this AST
    internal let underestimatedSize: UInt64
    /// The final indices that are the template's own (uninlined scope)
    internal let own: (scopes: Int, defines: Int, inlines: Int)
    
    /// Any required files, whether template or raw, required to fully resolve
    internal var requiredFiles: Set<String> { requiredASTs.union(requiredRaws) }
    /// List of any external templates needed to fully resolve the document.
    internal private(set) var requiredASTs: Set<String> = .init()
    /// List of any external unprocessed raw inlines needed to fully resolve the document
    internal private(set) var requiredRaws: Set<String> = .init()
 
    internal var cached: Bool = false
    
    
    /// Inline Leaf templates
    ///
    /// Can be improved; if inlined templates themselves have inlines (A inlines B and C, B inlines C)
    /// there will be duplicated and potentially inconsistent scopes if the inlined templates were changed
    /// and the cached version is out of date
    mutating func inline(ast toInline: Leaf4AST) {
        let stamp = Date()
        var inAST = toInline
        let inName = toInline.name
        let offset = scopes.count
        // Remap incoming AST's elements to their new table offset
        for (s, inScope) in inAST.scopes.enumerated() {
            for (r, inRow) in inScope.enumerated() {
                if case .scope(let t) = inRow.container, let table = t {
                    inAST.scopes[s][r] = .scope(table + offset) }
                if case .block(let n, var b as Define, let p) = inRow.container {
                    b.remap(offset: offset)
                    inAST.scopes[s][r] = .block(n, b, p) }
            }
        }
        // Append the new scopes
        scopes.append(contentsOf: inAST.scopes)
        // Replace own AST's scope placeholders with correct offset references
        for (index, p) in inlines.enumerated() where p.process && p.at == .distantFuture {
            if case .block(_, let meta as Inline, _) = scopes[p.inline.table][p.inline.row].container,
               meta.file == inName {
                scopes[p.inline.table][p.inline.row + 1] = .scope(offset)
                inlines[index].at = stamp
                info.minSize += inAST.underestimatedSize
            }
        }
        // Append remapped incoming AST define/inlines
        for d in inAST.defines { defines.append(d.remap(by: offset)) }
        for i in inAST.inlines { inlines.append((inline: i.inline.remap(by: offset),
                                                 process: i.process,
                                                 at: i.at)) }
        
        
        info.includedASTs.insert(info.requiredASTs.remove(inName)!)
        info.defines = Set(info.defines + inAST.info.defines).sorted()
        info.inlines = Set(info.inlines + inAST.info.inlines).sorted()
        info.requiredFiles = info.requiredASTs.union(info.requiredRaws).sorted()
        cached = false
    }
    
    
    /// Inline raw ByteBuffers
    mutating func inline(raws: [String: ByteBuffer]) {
        let stamp = Date()
        for (index, pointer) in inlines.enumerated() where pointer.process == false {
            let p = pointer.inline
            guard let buffer = raws[p.identifier],
                  case .raw(let r) = scopes[p.table][p.row + 1].container else { continue }
            let insert = type(of: r).instantiate(data: buffer, encoding: .utf8)
            scopes[p.table][p.row + 1] = .raw(insert)
            inlines[index].at = stamp
            info.minSize += UInt64(buffer.readableBytes) - r.byteCount
        }
        raws.keys.forEach { info.requiredRaws.remove($0) }
        info.requiredFiles = info.requiredRaws.union(info.requiredASTs).sorted()
        cached = false
    }
    
    /// Return to an unresolved state
    internal mutating func unresolve() {
        scopes.removeLast(scopes.count - own.scopes)
        inlines.removeLast(inlines.count - own.inlines)
        defines.removeLast(defines.count - own.defines)
        inlines.indices.forEach { inlines[$0].at = .distantFuture
                                  let p = inlines[$0].inline
                                  scopes[p.table][p.row + 1] = .scope(nil) }
        info.requiredASTs = requiredASTs
        info.requiredRaws = requiredRaws
        info.minSize = underestimatedSize
        info.resolved = requiredFiles.isEmpty
        info.cachedTables = scopes.count - 1 - own.scopes
        info.defines = Set(defines.map {$0.identifier}).sorted()
        info.inlines = Set(inlines.map {$0.inline.identifier}).sorted()
        info.requiredFiles = requiredASTs.union(requiredRaws).sorted()
        cached = false
    }
    
    /// A public view of the current state of the AST
    public private(set) var info: Info = .init()
    
    internal var summary: String {
        let d = info
        var result = "Leaf4AST `\(name)`: \(scopes.count) tables (\(d.cachedTables) inlined), \(d.minSize) minimum output bytes\n"
        if !d.resolved { result += "Template is unresolved\n" }
        result += "Defines: [\(d.defines.joined(separator: ", "))]\n"
        result += "Inlines: [\(d.inlines.joined(separator: ", "))]\n"
        if !d.requiredASTs.isEmpty { result += "Missing template references: [\(d.requiredASTs.joined(separator: ", "))]\n"}
        if !d.requiredRaws.isEmpty { result += "Future raw file inlines: [\(d.requiredRaws.joined(separator: ", "))]\n"}
        return result
    }
    
    internal var formatted: String { summary + scopes.formatted }
    internal var terse: String { scopes.terse }
    
    internal init(_ key: String,
                  _ scopes: [[Leaf4Syntax]],
                  _ defines: [Leaf4AST.ScopeReference],
                  _ inlines: [(inline: Leaf4AST.ScopeReference, process: Bool, at: Date)],
                  _ underestimatedSize: UInt64) {
        self.key = key.first != "$" ? "$:\(key)" : key
        self.scopes = scopes
        self.defines = defines
        self.inlines = inlines
        self.underestimatedSize = underestimatedSize
        self.own = (scopes: scopes.indices.last!,
                    defines: defines.indices.last ?? -1,
                    inlines: inlines.indices.last ?? -1)
        self.requiredASTs = _requiredASTs
        self.requiredRaws = _requiredRaws
        self.info.parsed = Date()
        self.info.minSize = underestimatedSize
        self.info.resolved = requiredFiles.isEmpty
        self.info.cachedTables = scopes.count - 1 - own.scopes
        self.info.defines = Set(defines.map {$0.identifier}).sorted()
        self.info.inlines = Set(inlines.map {$0.inline.identifier}).sorted()
        self.info.requiredASTs = requiredASTs
        self.info.requiredRaws = requiredRaws
        self.info.requiredFiles = requiredASTs.union(requiredRaws).sorted()
    }
    
    /// Expensive - should only be used at init time
    private var _requiredASTs: Set<String> {
        inlines.filter { $0.at == .distantFuture && $0.process }
               .reduce(into: .init(), { $0.insert($1.inline.identifier) })
    }
    /// Expensive - should only be used at init time
    private var _requiredRaws: Set<String> {
        inlines.filter { $0.at == .distantFuture && !$0.process }
               .reduce(into: .init(), { $0.insert($1.inline.identifier) })
    }
}
