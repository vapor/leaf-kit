public typealias ResolvedDocument = LeafAST

// Internal combination of rawAST = nil indicates no external references
// rawAST non-nil & flat = false : unresolved with external references, and public AST is not flat
// rawAST non-nil & flat = true : resolved with external references, and public AST is flat
public struct LeafAST: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: LeafAST, rhs: LeafAST) -> Bool { lhs.name == rhs.name }
    
    let name: String
    
    private var rawAST: [Syntax]?
    private var flatState: Bool?
    
    private(set) var ast: [Syntax]
    private(set) var externalRefs = Set<String>()
    private(set) var unresolvedRefs = Set<String>()
    private(set) var flat: Bool
    
    init(name: String, ast: [Syntax]) {
        self.name = name
        self.ast = ast
        self.rawAST = nil
        self.flatState = nil
        self.flat = false
        
        updateRefs()
    }
    
     init(from: LeafAST, referencing externals: [String: LeafAST]) {
        self.name = from.name
        self.ast = from.ast
        self.rawAST = from.rawAST
        self.externalRefs = from.externalRefs
        self.unresolvedRefs = from.unresolvedRefs
        self.flatState = from.flatState
        self.flat = from.flat
        
        guard self.flat == false else { return }
        
        inlineRefs(externals)
    }
    
    mutating private func updateRefs() {
        var firstRun = false
        switch (flatState, rawAST) {
            case (.some(true), _): return // known flat, no need to check for refs
            case (.none, .some): fatalError("Invalid state: rawAST shouldn't hold a value if flatness isn't known")
            case (.some(false), .none): fatalError("Invalid state: rawAST must hold a value if flatness is false")
            case (.none, .none): firstRun = true
            default: break
        }
        
        unresolvedRefs.removeAll()
        for syntax in ast {
            switch syntax {
                case .extend(let e): unresolvedRefs.insert(e.key)
                default: break
            }
        }
        flat = unresolvedRefs.count == 0
        flatState = flat
        
        if firstRun == true {
            if flat == false { rawAST = ast }
            externalRefs = unresolvedRefs
        }
    }
    
    mutating private func inlineRefs(_ externals: [String: LeafAST]) {
        guard externals.count > 0 else { return }
        unresolvedRefs.removeAll()
        var pos = ast.startIndex
        
        // inline provided externals
        while pos < ast.endIndex {
            if case .extend(let e) = ast[pos]  {
                let key = e.key
                if let insert = externals[key] {
                    let inlined = e.extend(base: insert.ast)
                    ast.remove(at: pos)
                    ast.insert(contentsOf: inlined, at: pos)
                    pos += inlined.count
                } else {
                    unresolvedRefs.insert(key)
                }
            }
            pos += 1
        }
        
        // compress raws
        pos = ast.startIndex
        while pos < ast.endIndex {
            if case .raw(var syntax) = ast[pos], pos + 1 < ast.endIndex {
                guard case .raw(var add) = ast[pos+1] else { pos += 1; break }
                var buffer = ByteBufferAllocator().buffer(capacity: 0)
                buffer.writeBuffer(&syntax)
                buffer.writeBuffer(&add)
                ast[pos] = .raw(buffer)
                ast.remove(at: pos + 1)
            } else { pos += 1 }
        }
        
        // update refs as new externals may have been introduced through extension
        updateRefs()
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
