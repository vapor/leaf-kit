import NIO

/// `LeafAST` represents a "compiled," grammatically valid Leaf template (which may or may not be fully resolvable or erroring)
public struct LeafAST: Hashable {
    // MARK: - Public
    
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: LeafAST, rhs: LeafAST) -> Bool { lhs.name == rhs.name }

    // MARK: - Internal/Private Only
    let name: String

    init(name: String, ast: [Statement]) {
        self.name = name
        self.ast = ast
        self.rawAST = nil
    }

    internal private(set) var ast: [Statement]

    // MARK: - Private Only
    
    private var rawAST: [Statement]?
}
