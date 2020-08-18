// MARK: Subject to change prior to 1.0.0 release
// MARK: -

@_exported import NIO


// MARK: - Public Type Shorthands

// MARK: - LeafAST
public typealias LeafASTKey = LeafAST.Key
public typealias LeafASTInfo = LeafAST.Info
public typealias LeafASTTouch = LeafAST.Touch

// MARK: - LeafFunction, *Method, *Block, *Raw
public typealias CallParameters = [LeafCallParameter]
public typealias CallValues = LeafCallValues

// MARK: - LeafBook, *Raw
public typealias ParseSignatures = [String: [LeafParseParameter]]

// MARK: - Static Conveniences

public extension Set where Element == LeafDataType {
    /// Any `LeafDataType` but `.void`
    static var any: Self { Set(LeafDataType.allCases.filter {$0 != .void}) }
    /// `LeafDataType` == `Collection`
    static var collections: Self { [.array, .dictionary] }
    /// `LeafDataType` == `SignedNumeric`
    static var numerics: Self { [.int, .double] }
}

/// Public helper identities
public extension Character {
    /// Global setting of `tagIndicator` for LeafKit - by default, `#`
    internal(set) static var tagIndicator: Character = .octothorpe
}

public extension String {
    /// Whether the string is valid as an identifier (variable part or function name) in LeafKit
    var isValidIdentifier: Bool {
        !isEmpty && allSatisfy({$0.isValidInIdentifier})
            && first?.canStartIdentifier ?? false
    }
}

extension String: Error {}

