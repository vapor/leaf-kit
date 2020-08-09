// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct Leaf4AST: Hashable {
    // MARK: - Public
    
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
    public static func ==(lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    public let key: Key
    public let name: String
    
    mutating public func touch(values: TouchValue) {
        info.touched = Date()
        info.touches = info.touches == Int.max ? 2 : info.touches + 1
        if values.exec > info.maximums.exec { info.maximums.exec = values.exec }
        if values.size > info.maximums.size { info.maximums.size = values.size }
        guard info.touches != 1 else { info.averages = values; return }
        info.averages.exec = info.averages.exec +
                            ((values.exec - info.averages.exec) / Double(info.touches))
        info.averages.size = info.averages.size +
                            ((values.size - info.averages.size) / UInt32(info.touches))
    }
    
    public struct Key: Hashable {
        internal let _key: String
        internal var _src: String {
            String(_key.prefix(while: { $0 != ":"}))
        }
        internal var _name: String {
            String(_key.split(separator: ":", maxSplits: 1)[1])
        }
        internal init(_ src: String, _ path: String) {
            self._key = "\(src):\(path)"
        }
        static func searchKey(_ name: String) -> Self { .init("$", name) }
    }
    
    public struct Info {
        // MARK: - Publicly Readable
        
        /// Timestamp of when the AST was parsed
        public internal(set) var parsed: Date = .distantPast
        /// Timestamp when the AST was last serialized
        public internal(set) var touched: Date = .distantPast
        /// Average and maximum duration of serialization for the AST
        public var serializeTimes: (average: Double, maximum: Double) {
            (averages.exec, maximums.exec)
        }
        /// Average and maximum size of serialized output for the AST
        public var serializeSizes: (average: Int, maximum: Int) {
            (Int(averages.size), Int(maximums.size))
        }
        /// Whether the AST is fully resolved
        public internal(set) var resolved: Bool = true
        /// Any evaluable blocks defined in the AST
        public internal(set) var defines: [String] = []
        /// All external inlined files, whether processed as templates or raw contents
        public internal(set) var inlines: [String] = []
        /// Any files required to resolve, if not resolved
        public internal(set) var requiredFiles: [String] = []
        /// Any files required to resolve as a flat AST
        public internal(set) var requiredASTs: Set<String> = []
        /// Any files required to inline as raw contents
        public internal(set) var requiredRaws: Set<String> = []
       
        // MARK: - Internal Only
        
        /// Estimated minimum size of the serialized view (may be inaccurate)
        internal var minSize: UInt32 = 0
        internal var stackDepths: (overallMax: UInt16, inlineMax: UInt16) = (1,0)
        internal var ownTables: Int = 0
        internal var cachedTables: Int = 0
        internal var includedASTs: Set<String> = []
        internal var touches: Int = 0
        internal var averages: TouchValue = .init(exec: 0, size: 0)
        internal var maximums: TouchValue = .init(exec: 0, size: 0)
    }
    
    public struct TouchValue {
        internal var exec: Double
        internal var size: UInt32
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
    internal var scopes: ContiguousArray<ContiguousArray<Leaf4Syntax>>
    /// Reference pointers to all `Define` metablocks
    internal var defines: ContiguousArray<ScopeReference>
    /// Reference pointers to all `Inline` metablocks, whether they're templates, and timestamp for when they were inlined
    ///
    /// If the block has *not* been inlined, `Date` will be .distantFuture
    internal var inlines: ContiguousArray<(inline: ScopeReference, process: Bool, at: Date)>
    /// Absolute minimum size of a rendered document from this AST
    internal let underestimatedSize: UInt32
    /// The final indices that are the template's own (uninlined scope)
    internal let own: (scopes: Int, defines: Int, inlines: Int)
    
    /// Any required files, whether template or raw, required to fully resolve
    internal var requiredFiles: Set<String> { requiredASTs.union(requiredRaws) }
    /// List of any external templates needed to fully resolve the document.
    internal private(set) var requiredASTs: Set<String>
    /// List of any external unprocessed raw inlines needed to fully resolve the document
    internal private(set) var requiredRaws: Set<String>
 
    internal var stackDepths: (overallMax: UInt16, inlineMax: UInt16)
    
    internal var cached: Bool
    
    
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
        
        // Atomic incoming AST; 1 scope, 1 element - inherently passthrough or raw
        let nonAtomic = inAST.scopes[0].count != 1       
        if nonAtomic {
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
        }
        
        // Replace own AST's scope placeholders with correct offset references
        for (index, p) in inlines.enumerated() where p.process && p.at == .distantFuture {
            let t = p.inline.table
            let r = p.inline.row
            if case .block(_, let meta as Inline, _) = scopes[t][r].container,
               meta.file == inName {
                inlines[index].at = stamp
                scopes[t][r + 1] = nonAtomic ? .scope(offset)
                                             : inAST.scopes[0][0]
                info.minSize += nonAtomic ? inAST.underestimatedSize
                                          : inAST.scopes[0][0].underestimatedSize
            }
        }
        
        if nonAtomic {
            // Append remapped incoming AST define/inlines
            for d in inAST.defines { defines.append(d.remap(by: offset)) }
            for i in inAST.inlines { inlines.append((inline: i.inline.remap(by: offset),
                                                     process: i.process,
                                                     at: i.at)) }
            
            info.stackDepths.inlineMax = stackDepths.inlineMax + inAST.stackDepths.inlineMax
            info.defines = Set(info.defines + inAST.info.defines).sorted()
            info.inlines = Set(info.inlines + inAST.info.inlines).sorted()
        }
        
        info.includedASTs.insert(info.requiredASTs.remove(inName)!)
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
            info.minSize += UInt32(buffer.byteCount) - r.byteCount
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
        info.stackDepths = stackDepths
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
    
    internal init(_ key: Key,
                  _ scopes: [[Leaf4Syntax]],
                  _ defines: [Leaf4AST.ScopeReference],
                  _ inlines: [(inline: Leaf4AST.ScopeReference, process: Bool, at: Date)],
                  _ underestimatedSize: UInt32,
                  _ stackDepths: (overallMax: UInt16, inlineMax: UInt16)) {
        self.key = key
        self.name = key._name
        self.cached = false
        self.scopes = scopes.contiguous()
        self.defines = .init(defines)
        self.inlines = .init(inlines)
        self.stackDepths = stackDepths
        self.requiredASTs = .init()
        self.requiredRaws = .init()
        self.underestimatedSize = underestimatedSize
        self.own = (scopes: scopes.indices.last!,
                    defines: defines.indices.last ?? -1,
                    inlines: inlines.indices.last ?? -1)
        self.requiredASTs.formUnion(_requiredASTs)
        self.requiredRaws.formUnion(_requiredRaws)
        self.info.parsed = Date()
        self.info.minSize = underestimatedSize
        self.info.stackDepths = stackDepths
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
