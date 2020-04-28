public typealias ResolvedDocument = LeafAST

// Internal combination of rawAST = nil indicates no external references
// rawAST non-nil & flat = false : unresolved with external references, and public AST is not flat
// rawAST non-nil & flat = true : resolved with external references, and public AST is flat
public struct LeafAST: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: LeafAST, rhs: LeafAST) -> Bool { lhs.name == rhs.name }
    
    let name: String
    
    private var rawAST: [Syntax]?
    
    private(set) var ast: [Syntax]
    private(set) var externalRefs = Set<String>()
    private(set) var unresolvedRefs = Set<String>()
    private(set) var flat: Bool
    
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
        
    mutating private func updateRefs(_ externals: [String: LeafAST]) {
        var firstRun = false
        if rawAST == nil, flat == false { rawAST = ast; firstRun = true }
        unresolvedRefs.removeAll()
        var pos = ast.startIndex
        
        // inline provided externals
        while pos < ast.endIndex {
            switch ast[pos] {
                case .extend(let e):
                    let key = e.key
                    if let insert = externals[key] {
                        let inlined = e.extend(base: insert.ast)
                        ast.replaceSubrange(pos...pos, with: inlined)
                    } else {
                        unresolvedRefs.insert(key)
                        pos = ast.index(after: pos)
                    }
                default:
                    var new: Syntax? = nil
                    unresolvedRefs.formUnion(ast[pos].inlineRefs(externals, &new))
                    if let new = new { ast[pos] = new }
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
        if firstRun, flat { rawAST = nil }
    }
}

// struct UnresolvedDocument... *replaced by LeafAST*
//    let name... *replaced by LeafAST.name*
//    let raw... *replaced by LeafAST.rawAST? or .ast if inherently flat
//    var unresolvedDependencies... *replaced by LeafAST.externalRefs*

// public struct ResolvedDocument... *replaced by LeafAST*
//    let name... *replaced by LeafAST.name*
//    let ast... *replaced by LeafAST.ast

// internal struct ExtendResolver... *obivated*
//    init.... *replaced by LeafAST.init(from: LeafAST, referencing externals: [String: LeafAST])*
//    func resolve... *replaced by LeafRenderer resolve()
//    private func canSatisfyAllDependencies... *obviated*

//extension String {  func expand ... obviated by LeafRenderer expand()

//protocol FileAccessProtocol...  *removed - unused*
//final class FileAccessor: FileAccessProtocol...  *removed - unused*

//internal final class DocumentLoader... *removed - obviated*
