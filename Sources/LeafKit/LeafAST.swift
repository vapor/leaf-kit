// MARK: Subject to change prior to 1.0.0 release

import Foundation

// MARK: - LeafAST Definition

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct LeafAST: Hashable {
    // MARK: - Public Stored Properties
    /// Hashing key for the AST
    public let key: LeafASTKey
    /// Convenience referrent name for the AST
    public let name: String
    /// A public view of the current state of the AST
    public private(set) var info: LeafASTInfo

    // MARK: - Internal Stored Properties
    /// The AST scope tables
    var scopes: ContiguousArray<ContiguousArray<LKSyntax>>
    /// References for all `Define` identifiers used
    var defines: Set<String>
    /// Reference pointers to all `Inline` metablocks, whether they're templates, and timestamp for when they were inlined
    ///
    /// If the block has *not* been inlined, `Date` will be .distantFuture
    var inlines: ContiguousArray<(inline: Jump, process: Bool, at: Date)>
    /// Cached copies of raw inlines (where small enough to store in the AST directly)
    var raws: [String: ByteBuffer]
    /// Whether this AST was obtained from `LeafCache`
    var cached: Bool
    /// Absolute minimum size of a rendered document from this AST
    let underestimatedSize: UInt32
    /// The final indices that are the template's own (uninlined scope)
    let own: (scopes: Int, inlines: Int)
    /// Any variables needed that aren't internally defined
    let requiredVars: Set<LKVariable>
    /// List of any external templates needed to fully resolve the document.
    let requiredASTs: Set<String>
    /// List of any external unprocessed raw inlines needed to fully resolve the document
    let requiredRaws: Set<String>
    let stackDepths: (overallMax: UInt16, inlineMax: UInt16)

    // MARK: - Computed Properties And Methods

    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
    public static func ==(lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    
    
    mutating public func touch(values: Touch) {
        info.touched = Date()
        info.touch.aggregate(values: values)
    }

    // MARK: - Helper Objects

    /// An opaque object used as a key for storing `LeafAST`s in hash tables (eg, caches). Not directly readable.
    public struct Key: Hashable {
        let _key: String

        init(_ src: String, _ path: String) { self._key = "\(src):\(path)" }
        static func searchKey(_ name: String) -> Self { .init("$", name) }

        var _src: String { .init(_key.prefix(while: { $0 != ":"})) }
        var _name: String { .init(_key.split(separator: ":", maxSplits: 1)[1]) }
    }

    /// An opaque object passed to a stored `LeafAST` via `LeafCache`
    public struct Touch {
        var count: UInt32
        var sizeAvg: UInt32
        var sizeMax: UInt32
        var execAvg: Double
        var execMax: Double
    }

    /// A semi-opaque object providing information about the current state of the AST
    public struct Info {
        // MARK: Public Stored Properties
        /// Timestamp of when the AST was parsed
        public let parsed: Date
        /// Timestamp when the AST was last touched (serialized)
        public internal(set) var touched: Date = .distantPast
        /// Any identifiers for evaluable blocks defined in the AST
        public internal(set) var defines: [String] = []
        /// All external inlined files, whether processed as templates or raw contents
        public internal(set) var inlines: [String] = []
        /// Any files currently required to resolve as a flat AST
        public internal(set) var requiredASTs: Set<String> = []
        /// Any files currently required to inline as raw contents
        public internal(set) var requiredRaws: Set<String> = []

        // MARK: Internal Stored Properties
        /// Estimated minimum size of the serialized view (may be inaccurate)
        var underestimatedSize: UInt32 = 0
        var stackDepths: (overallMax: UInt16, inlineMax: UInt16) = (1,0)
        var includedASTs: Set<String> = []
        var _requiredVars: Set<LKVariable> = []
        var touch: Touch = .empty

        // MARK: Computed Properties
        /// Whether the AST is fully resolved
        public var resolved: Bool { requiredASTs.union(requiredRaws).isEmpty }
        /// Any variables required in the AST that aren't internally defined
        public var requiredVars: Set<String> { .init(_requiredVars.map {$0.terse}) }
        /// Average and maximum duration of serialization for the AST
        public var serializeTimes: (average: Double, maximum: Double) {
            (touch.execAvg, touch.execMax) }
        /// Average and maximum size of serialized output for the AST
        public var serializeSizes: (average: Int, maximum: Int) {
            (Int(touch.sizeAvg), Int(touch.sizeMax)) }
    }

    /// Internal only -
    internal struct Jump: Hashable {
        let identifier: String
        let table: Int
        let row: Int

        func hash(into hasher: inout Hasher) { hasher.combine(identifier)}

        func remap(by offset: Int = 0) -> Self {
            .init(identifier: identifier, table: table + offset, row: row) }
    }
}

// MARK: - Internal Only - Init and Resolving

internal extension LeafAST {
    init(_ key: Key,
         _ scopes: [[LKSyntax]],
         _ defines: Set<String>,
         _ inlines: [(inline: Jump, process: Bool, at: Date)],
         _ variables: Set<LKVariable>,
         _ underestimatedSize: UInt32,
         _ stackDepths: (overallMax: UInt16, inlineMax: UInt16)) {
        // Core properties for actual AST
        self.key = key
        self.name = key._name
        self.cached = false
        self.scopes = scopes.contiguous()
        self.defines = defines
        self.inlines = .init(inlines)
        self.raws = [:]
        self.stackDepths = stackDepths
        self.underestimatedSize = underestimatedSize
        self.own = (scopes: scopes.indices.last!,
                    inlines: inlines.indices.last ?? -1)
        self.requiredVars = variables
        self.requiredASTs = inlines.filter { $0.at == .distantFuture && $0.process }
                                   .reduce(into: .init(), { $0.insert($1.inline.identifier) })
        self.requiredRaws = inlines.filter { $0.at == .distantFuture && !$0.process }
                                   .reduce(into: .init(), { $0.insert($1.inline.identifier) })

        // Info properties (start same as actual AST, may modify from resolving
        self.info = .init(parsed: Date(),
                          defines: defines.sorted(),
                          inlines: Set(inlines.map {$0.inline.identifier}).sorted(),
                          requiredASTs: requiredASTs,
                          requiredRaws: requiredRaws,
                          underestimatedSize: underestimatedSize,
                          stackDepths: stackDepths,
                          _requiredVars: requiredVars)
    }

    /// Any required files, whether template or raw, required to fully resolve
    var requiredFiles: Set<String> { requiredASTs.union(requiredRaws) }

    /// Inline Leaf templates
    ///
    /// Can be improved; if inlined templates themselves have inlines (A inlines B and C, B inlines C)
    /// there will be duplicated and potentially inconsistent scopes if the inlined templates were changed
    /// and the cached version is out of date
    mutating func inline(ast toInline: LeafAST) {
        let stamp = Date()
        var inAST = toInline
        let inName = toInline.name
        let offset = scopes.count

        /// Atomic incoming AST; 1 scope, 1 element - inherently passthrough or raw
        let nonAtomic = inAST.scopes[0].count != 1
        if nonAtomic {
            /// Remap incoming AST's elements to their new table offset
            for (s, inScope) in inAST.scopes.enumerated() {
                for (r, inRow) in inScope.enumerated() {
                    /// Non-nil scopes remap by offset
                    if case .scope(.some(let t)) = inRow.container {
                        inAST.scopes[s][r] = .scope(t + offset) }
                    /// Define blocks remap their scope reference by offset
                    if case .block(let n, var b as Define, let p) = inRow.container {
                        b.remap(offset: offset)
                        inAST.scopes[s][r] = .block(n, b, p) }
                }
            }
            // Append the new scopes
            scopes.append(contentsOf: inAST.scopes)
        }

        /// Replace own AST's scope placeholders with correct offset references
        for (index, p) in inlines.enumerated() where p.process && p.at == .distantFuture {
            let t = p.inline.table
            let r = p.inline.row
            if case .block(_, let meta as Inline, _) = scopes[t][r].container,
               meta.file == inName {
                inlines[index].at = stamp
                scopes[t][r + 1] = nonAtomic ? .scope(offset)
                                             : inAST.scopes[0][0]
                info.underestimatedSize += nonAtomic ? inAST.underestimatedSize
                                                     : inAST.scopes[0][0].underestimatedSize
                /// Update required vars with any new needed ones that aren't explicitly available at this inline point
                info._requiredVars.formUnion(inAST.requiredVars.subtracting(meta.availableVars ?? []))
            }
        }

        if nonAtomic {
            /// Append remapped incoming AST define/inlines
            for i in inAST.inlines { inlines.append((inline: i.inline.remap(by: offset),
                                                     process: i.process,
                                                     at: i.at)) }

            info.stackDepths.overallMax.maxAssign(stackDepths.inlineMax +
                                                  inAST.stackDepths.overallMax)
            info.stackDepths.inlineMax.maxAssign(stackDepths.inlineMax +
                                                 inAST.stackDepths.inlineMax)
            info.defines = defines.union(inAST.info.defines).sorted()
            info.inlines = Set(info.inlines + inAST.info.inlines).sorted()
        }

        info.includedASTs.insert(info.requiredASTs.remove(inName)!)
        cached = false
    }

    /// Inline raw ByteBuffers
    mutating func inline(raws: [String: ByteBuffer]) {
        raws.forEach { inline(name: $0, raw: $1) }
    }
    
    mutating func inline(name: String, raw: ByteBuffer) {
        info.requiredRaws.remove(name)
        if raw.readableBytes <= LKConf.rawCachingLimit { cached = false }
        raws[name] = raw
    }
    
    mutating func stripOversizeRaws() {
        raws.keys.forEach {
            if raws[$0]!.readableBytes > LKConf.rawCachingLimit {
                raws[$0] = nil
                info.requiredRaws.insert($0)
            }
        }
    }

    /// Return to an unresolved state
    mutating func unresolve() {
        cached = false
        scopes.removeLast(scopes.count - own.scopes)
        inlines.removeLast(inlines.count - own.inlines)
        inlines.indices.forEach { inlines[$0].at = .distantFuture
                                  let p = inlines[$0].inline
                                  scopes[p.table][p.row + 1] = .scope(nil) }

        info.defines = defines.sorted()
        info.inlines = Set(inlines.map {$0.inline.identifier}).sorted()
        info.requiredASTs = requiredASTs
        info.requiredRaws = requiredRaws
        info.underestimatedSize = underestimatedSize
        info.stackDepths = stackDepths
    }

    var formatted: String { summary + scopes.formatted }
    var terse: String { scopes.terse }

    var summary: String {
        """
        LeafAST `\(name)`: \(scopes.count) tables (\(scopes.count) inlined), \(scopes.count - own.scopes - 1) minimum output bytes
        Template is \(info.resolved == false ? "un" : "")resolved
        Defines: [\(info.defines.joined(separator: ", "))]
        Inlines: [\(info.inlines.map {"\"\($0)\""}.joined(separator: ", "))]
        Needed - Vars: [\(Array(info._requiredVars).sorted(by: variablePrecedence).map {$0.terse}.joined(separator: ", "))]
               - ASTS: [\(info.requiredASTs.joined(separator: ", "))]
               - Raws: [\(info.requiredRaws.joined(separator: ", "))]
        """
    }
}

/// true if print lhs before rhs - only used for atomic levels, ignores paths
private func variablePrecedence(lhs: LKVariable, rhs: LKVariable) -> Bool {
    switch (lhs.scope, rhs.scope) {
        case (.none, .none): return lhs.member! < rhs.member!
        case (.some(let l), .some(let r)) where l == r: return lhs.member ?? "" < rhs.member ?? ""
        case (.some(let l), .some(let r)): return l < r
        case (.some, .none): return true
        case (.none, .some): return false
    }
}


internal extension LeafASTTouch {
    mutating func aggregate(values: Self) {
        sizeMax.maxAssign(values.sizeMax)
        execMax.maxAssign(values.execMax)
        let c = UInt64(count) + UInt64(values.count)
        let weight = (l: Double(count)/Double(c), r: Double(values.count)/Double(c))
        execAvg = (weight.l * execAvg) + (weight.r * values.execAvg)
        sizeAvg = UInt32((weight.l * Double(sizeAvg)) + (weight.r * Double(values.sizeAvg)))
        count = c > UInt32.max ? UInt32(UInt16.max) : UInt32(c)
    }
    
    static func atomic(time: Double, size: UInt32) -> Self {
        .init(count: 1, sizeAvg: size, sizeMax: size, execAvg: time, execMax: time) }
    
    static let empty: Self = .init(count: 0, sizeAvg: 0, sizeMax: 0, execAvg: 0, execMax: 0)
}
