// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct Leaf4AST: Hashable {
    // MARK: - Public
    
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func ==(lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    public let name: String
    
    public struct Info {
        let name: String
        let minSize: UInt64
        let resolved: Bool
        let ownTables: Int
        let cachedTables: Int
        let defines: [String]
        let inlines: [String]
        let required: [String]
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
    internal var underestimatedSize: UInt64
    /// The final scope table that  is the template's own (uninlined scope)
    internal let ownFinalScope: Int
    
    /// Any required files, whether template or raw, required to fully resolve
    internal var requiredFiles: Set<String> {
        inlines.filter { $0.at == .distantFuture }
               .reduce(into: .init(), { $0.insert($1.inline.identifier) })
    }
    /// List of any external templates needed to fully resolve the document.
    internal var requiredASTs: Set<String> {
        inlines.filter { $0.at == .distantFuture && $0.process }
               .reduce(into: .init(), { $0.insert($1.inline.identifier) })
    }
    /// List of any external unprocessed raw inlines needed to fully resolve the document
    internal var requiredRaws: Set<String> {
        inlines.filter { $0.at == .distantFuture && !$0.process }
               .reduce(into: .init(), { $0.insert($1.inline.identifier) })
    }
    
    /// If any inlines exist, false if any have yet to be inlined.
    internal var flat: Bool {
        guard !inlines.isEmpty else { return true }
        return inlines.first(where: { $0.at == .distantFuture })
                      .map({_ in true}) ?? false
    }
    
    /// Inline Leaf templates
    ///
    /// Can be improved; if inlined templates themselves have inlines (A inlines B and C, B inlines C)
    /// there will be duplicated and potentially inconsistent scopes if the inlined templates were changed
    /// and the cached version is out of date
    mutating func inline(asts: [String: Leaf4AST]) {
        let stamp = Date()
        var asts = asts
        var offsets: [String: Int] = [:]
        // Remap incoming asts' elements to their new table offset
        for (name, ast) in asts {
            let offset = scopes.count
            offsets[name] = offset
            for (s, scope) in ast.scopes.enumerated() {
                for (r, row) in scope.enumerated() {
                    if case .scope(let t) = row.container, let table = t {
                        asts[name]!.scopes[s][r] = .scope(table + offset)
                    }
                    if case .block(let n, var b as Define, let p) = row.container {
                        b.remap(offset: offset)
                        asts[name]!.scopes[s][r] = .block(n, b, p)
                    }
                }
            }
            for d in ast.defines { defines.append(d.remap(by: offset)) }
            for i in ast.inlines {
                inlines.append((inline: i.inline.remap(by: offset),
                                process: i.process,
                                at: i.at))
            }
            // Append the new scopes
            scopes.append(contentsOf: asts[name]!.scopes)
            // Replace own AST's scope placeholders with correct offset references
            for (index, p) in inlines.enumerated() where p.process && p.at == .distantFuture {
                if case .block(_, let block, _) = scopes[p.inline.table][p.inline.row].container,
                   let meta = block as? Inline, meta.file == name {
                    scopes[p.inline.table][p.inline.row + 1] = .scope(offset)
                    inlines[index].at = stamp
                    underestimatedSize += ast.underestimatedSize
                }
            }
        }
        
    }
    
    mutating func inline(raws: [String: ByteBuffer]) {
        let stamp = Date()
        for (index, pointer) in inlines.enumerated() where pointer.process == false {
            let p = pointer.inline
            guard let buffer = raws[p.identifier],
                  case .raw(let r) = scopes[p.table][p.row + 1].container else { continue }
            let insert = type(of: r).instantiate(data: buffer, encoding: .utf8)
            scopes[p.table][p.row + 1] = .raw(insert)
            inlines[index].at = stamp
            underestimatedSize += UInt64(buffer.readableBytes) - r.byteCount
        }
    }
    
    public var diagnostic: Info {
        .init(name: name, minSize: underestimatedSize,
              resolved: requiredFiles.isEmpty,
              ownTables: ownFinalScope + 1,
              cachedTables: scopes.count - 1 - ownFinalScope,
              defines: Set(defines.map {$0.identifier}).sorted(),
              inlines: Set(inlines.map {$0.inline.identifier}).sorted(),
              required: requiredFiles.sorted())
    }
    
    internal var summary: String {
        let d = diagnostic
        var result = "Leaf4AST `\(d.name)`: \(d.ownTables) tables, \(d.minSize) minimum output bytes\n"
        if !d.resolved { result += "Template is unresolved\n" }
        result += "Defines: [\(d.defines.joined(separator: ", "))]\n"
        result += "Inlines: [\(d.inlines.joined(separator: ", "))]\n"
        if !requiredASTs.isEmpty { result += "Missing template references: [\(requiredASTs.joined(separator: ", "))]\n"}
        if !requiredRaws.isEmpty { result += "Future raw file inlines: [\(requiredRaws.joined(separator: ", "))]\n"}
        return result
    }
    
    internal var formatted: String { summary + scopes.formatted }
    internal var terse: String { scopes.terse }
}


/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct LeafAST: Hashable {
    // MARK: - Public
    
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: LeafAST, rhs: LeafAST) -> Bool { lhs.name == rhs.name }

    // MARK: - Internal/Private Only
    let name: String

    init(name: String, ast: [Syntax]) {
        self.name = name
        self.ast = ast
        self.rawAST = nil
        self.flat = false

        updateRefs([:])
    }
    
    init(from: LeafAST, referencing externals: [String: LeafAST]) {
        self.name = from.name
        self.ast = from.ast
        self.rawAST = from.rawAST
        self.externalRefs = from.externalRefs
        self.unresolvedRefs = from.unresolvedRefs
        self.flat = from.flat

        updateRefs(externals)
    }

    internal private(set) var ast: [Syntax]
    internal private(set) var externalRefs = Set<String>()
    internal private(set) var unresolvedRefs = Set<String>()
    internal private(set) var flat: Bool
    
    // MARK: - Private Only
    
    private var rawAST: [Syntax]?

    mutating private func updateRefs(_ externals: [String: LeafAST]) {
        var firstRun = false
        if rawAST == nil, flat == false { rawAST = ast; firstRun = true }
        unresolvedRefs.removeAll()
        var pos = ast.startIndex

        // inline provided externals
        while pos < ast.endIndex {
            // get desired externals for this Syntax - if none, continue
            let wantedExts = ast[pos].externals()
            if wantedExts.isEmpty {
                pos = ast.index(after: pos)
                continue
            }
            // see if we can provide any of them - if not, continue
            let providedExts = externals.filter { wantedExts.contains($0.key) }
            if providedExts.isEmpty {
                unresolvedRefs.formUnion(wantedExts)
                pos = ast.index(after: pos)
                continue
            }
            
            // replace the original Syntax with the results of inlining, potentially 1...n
            let replacementSyntax = ast[pos].inlineRefs(providedExts, [:])
            ast.replaceSubrange(pos...pos, with: replacementSyntax)
            // any returned new inlined syntaxes can't be further resolved at this point
            // but we need to add their unresolvable references to the global set
            var offset = replacementSyntax.startIndex
            while offset < replacementSyntax.endIndex {
                unresolvedRefs.formUnion(ast[pos].externals())
                offset = replacementSyntax.index(after: offset)
                pos = ast.index(after: pos)
            }
        }

        // compress raws
        pos = ast.startIndex
        while pos < ast.index(before: ast.endIndex) {
            if case .raw(var syntax) = ast[pos] {
                if case .raw(var add) = ast[ast.index(after: pos)] {
                    var buffer = ByteBufferAllocator().buffer(capacity: syntax.readableBytes + add.readableBytes)
                    buffer.writeBuffer(&syntax)
                    buffer.writeBuffer(&add)
                    ast[pos] = .raw(buffer)
                    ast.remove(at: ast.index(after: pos) )
                } else { pos = ast.index(after: pos) }
            } else { pos = ast.index(after: pos) }
        }

        flat = unresolvedRefs.isEmpty ? true : false
        if firstRun && flat { rawAST = nil }
    }
}
