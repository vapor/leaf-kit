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
    /// Whether this AST was obtained from `LeafCache`
    var cached: Bool
    /// Absolute minimum size of a rendered document from this AST
    let underestimatedSize: UInt32
    /// The final indices that are the template's own (uninlined scope)
    let own: (scopes: Int, inlines: Int)
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
        info.touches = info.touches == Int.max ? 2 : info.touches + 1
        if values.exec > info.maximums.exec { info.maximums.exec = values.exec }
        if values.size > info.maximums.size { info.maximums.size = values.size }
        guard info.touches != 1 else { info.averages = values; return }
        info.averages.exec = info.averages.exec +
                            ((values.exec - info.averages.exec) / Double(info.touches))
        info.averages.size = info.averages.size +
                            ((values.size - info.averages.size) / UInt32(info.touches))
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
        var exec: Double
        var size: UInt32
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
        var touches: Int = 0
        var averages: Touch = .init(exec: 0, size: 0)
        var maximums: Touch = .init(exec: 0, size: 0)

        // MARK: Computed Properties
        /// Whether the AST is fully resolved
        public var resolved: Bool { requiredASTs.union(requiredRaws).isEmpty }
        /// Average and maximum duration of serialization for the AST
        public var serializeTimes: (average: Double, maximum: Double) {
            (averages.exec, maximums.exec)
        }
        /// Average and maximum size of serialized output for the AST
        public var serializeSizes: (average: Int, maximum: Int) {
            (Int(averages.size), Int(maximums.size))
        }
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
         _ underestimatedSize: UInt32,
         _ stackDepths: (overallMax: UInt16, inlineMax: UInt16)) {
        // Core properties for actual AST
        self.key = key
        self.name = key._name
        self.cached = false
        self.scopes = scopes.contiguous()
        self.defines = defines
        self.inlines = .init(inlines)
        self.stackDepths = stackDepths
        self.underestimatedSize = underestimatedSize
        self.own = (scopes: scopes.indices.last!,
                    inlines: inlines.indices.last ?? -1)
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
                          stackDepths: stackDepths)
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
                info.underestimatedSize += nonAtomic ? inAST.underestimatedSize
                                                     : inAST.scopes[0][0].underestimatedSize
            }
        }

        if nonAtomic {
            // Append remapped incoming AST define/inlines
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
        let stamp = Date()
        for (index, pointer) in inlines.enumerated() where pointer.process == false {
            let p = pointer.inline
            guard let buffer = raws[p.identifier],
                  case .raw(let r) = scopes[p.table][p.row + 1].container else { continue }
            let insert = type(of: r).instantiate(data: buffer, encoding: .utf8)
            scopes[p.table][p.row + 1] = .raw(insert)
            inlines[index].at = stamp
            info.underestimatedSize += UInt32(buffer.byteCount) - r.byteCount
        }
        raws.keys.forEach { info.requiredRaws.remove($0) }
        cached = false
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
        Inlines: [\(info.defines.joined(separator: ", "))]
        Needed - ASTS: [\(info.requiredASTs.joined(separator: ", "))]
               - Raws: [\(info.requiredRaws.joined(separator: ", "))]
        """
    }
}
