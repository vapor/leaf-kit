import NIOCore

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct LeafAST: Hashable, Sendable {
    // MARK: - Public

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
    }

    public static func == (lhs: LeafAST, rhs: LeafAST) -> Bool {
        lhs.name == rhs.name
    }

    // MARK: - Internal/Private Only
    let name: String

    init(name: String, ast: [Syntax]) {
        self.name = name
        self.ast = ast
        self.rawAST = nil
        self.flat = false

        self.updateRefs([:])
    }

    init(from: LeafAST, referencing externals: [String: LeafAST]) {
        self.name = from.name
        self.ast = from.ast
        self.rawAST = from.rawAST
        self.externalRefs = from.externalRefs
        self.unresolvedRefs = from.unresolvedRefs
        self.flat = from.flat

        self.updateRefs(externals)
    }

    private(set) var ast: [Syntax]
    private(set) var externalRefs = Set<String>()
    private(set) var unresolvedRefs = Set<String>()
    private(set) var flat: Bool

    // MARK: - Private Only

    private var rawAST: [Syntax]?

    mutating private func updateRefs(_ externals: [String: LeafAST]) {
        var firstRun = false

        if self.rawAST == nil, self.flat == false {
            self.rawAST = self.ast
            firstRun = true
        }
        self.unresolvedRefs.removeAll()
        var pos = self.ast.startIndex

        // inline provided externals
        while pos < self.ast.endIndex {
            // get desired externals for this Syntax - if none, continue
            let wantedExts = self.ast[pos].externals()
            if wantedExts.isEmpty {
                pos = self.ast.index(after: pos)
                continue
            }
            // see if we can provide any of them - if not, continue
            let providedExts = externals.filter { wantedExts.contains($0.key) }
            if providedExts.isEmpty {
                self.unresolvedRefs.formUnion(wantedExts)
                pos = self.ast.index(after: pos)
                continue
            }

            // replace the original Syntax with the results of inlining, potentially 1...n
            let replacementSyntax = self.ast[pos].inlineRefs(providedExts, [:])
            self.ast.replaceSubrange(pos...pos, with: replacementSyntax)
            // any returned new inlined syntaxes can't be further resolved at this point
            // but we need to add their unresolvable references to the global set
            var offset = replacementSyntax.startIndex
            while offset < replacementSyntax.endIndex {
                self.unresolvedRefs.formUnion(self.ast[pos].externals())
                offset = replacementSyntax.index(after: offset)
                pos = self.ast.index(after: pos)
            }
        }

        // compress raws
        pos = self.ast.startIndex
        while pos < self.ast.index(before: ast.endIndex) {
            if case .raw(var syntax) = self.ast[pos] {
                if case .raw(var add) = self.ast[self.ast.index(after: pos)] {
                    var buffer = ByteBufferAllocator().buffer(capacity: syntax.readableBytes + add.readableBytes)
                    buffer.writeBuffer(&syntax)
                    buffer.writeBuffer(&add)
                    self.ast[pos] = .raw(buffer)
                    self.ast.remove(at: self.ast.index(after: pos))
                } else {
                    pos = self.ast.index(after: pos)
                }
            } else {
                pos = self.ast.index(after: pos)
            }
        }

        self.flat = self.unresolvedRefs.isEmpty ? true : false
        if firstRun, self.flat {
            self.rawAST = nil
        }
    }
}
