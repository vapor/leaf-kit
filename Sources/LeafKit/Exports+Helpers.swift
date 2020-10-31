@_exported import NIO

// MARK: Public Type Shorthands

// Can't alias until deprecated version totally removed
//public typealias LeafContext = LeafRenderer.Context
public typealias LeafOptions = LeafRenderer.Options
public typealias LeafOption = LeafRenderer.Option

public typealias ParseSignatures = [String: [LeafParseParameter]]

// MARK: - Static Conveniences

/// Public helper identities
public extension Character {
    static var tagIndicator: Self { LKConf.tagIndicator }
    static var octothorpe: Self { "#".first! }
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
