// MARK: Subject to change prior to 1.0.0 release
// MARK: -

@_exported import NIO

// MARK: - Public Type Shorthands

// MARK: - LeafAST
public typealias LeafASTKey = LeafAST.Key
public typealias LeafASTInfo = LeafAST.Info
public typealias LeafASTTouch = LeafAST.Touch

// MARK: - LeafBlock, *Raw
public typealias ParseSignatures = [String: [LeafParseParameter]]

// MARK: - Static Conveniences

/// Public helper identities
public extension Character {
    /// Global setting of `tagIndicator` for LeafKit - by default, `#`
    internal(set) static var tagIndicator: Character = .octothorpe
}

public extension String {
    /// Whether the string is valid as an identifier (variable part or function name) in LeafKit
    var isValidLeafIdentifier: Bool {
        !isEmpty && !isLeafKeyword
            && first?.canStartIdentifier ?? false
            && allSatisfy({$0.isValidInIdentifier})
    }
    
    /// Whether the string is a (protected) Leaf keyword
    var isLeafKeyword: Bool { LeafKeyword(rawValue: self) != nil }
}
