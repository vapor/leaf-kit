import Foundation
import NIOConcurrencyHelpers

/// General configuration of Leaf
/// - Sets the default View directory where templates will be looked for
/// - Guards setting the global tagIndicator (default `#`).
public struct LeafConfiguration: Sendable {
    
    /// Initialize Leaf with the default tagIndicator `#` and unfound imports throwing an exception
    /// - Parameter rootDirectory: Default directory where templates will be found
    public init(rootDirectory: String) {
        self.init(rootDirectory: rootDirectory, tagIndicator: .octothorpe, ignoreUnfoundImports: true)
    }
    
    /// Initialize Leaf with a specific tagIndicator
    /// - Parameter rootDirectory: Default directory where templates will be found
    /// - Parameter tagIndicator: Unique tagIndicator - may only be set once.
    public init(rootDirectory: String, tagIndicator: Character) {
        self.init(rootDirectory: rootDirectory, tagIndicator: tagIndicator, ignoreUnfoundImports: true)
    }
    
    /// Initialize Leaf with a specific tagIndicator and custom behaviour for unfound imports
    /// - Parameter rootDirectory: Default directory where templates will be found
    /// - Parameter tagIndicator: Unique tagIndicator - may only be set once.
    /// - Parameter ignoreUnfoundImports: Ignore unfound imports - may only be set once.
    public init(rootDirectory: String, tagIndicator: Character, ignoreUnfoundImports: Bool) {
        if !Self.started.withLockedValue({ $0 }) {
            Character.tagIndicator.withLockedValue { $0 = tagIndicator }
            Self.started.withLockedValue { $0 = true }
        }
        self._rootDirectory = rootDirectory
        self._ignoreUnfoundImports = ignoreUnfoundImports
    }
    
    public var rootDirectory: String {
        mutating get { accessed = true; return _rootDirectory }
        set { _rootDirectory = newValue }
    }
    
    public var ignoreUnfoundImports: Bool {
        mutating get { accessed = true; return _ignoreUnfoundImports }
        set { _ignoreUnfoundImports = newValue }
    }

    public static var encoding: String.Encoding {
        get { _encoding.withLockedValue { $0 } }
        set { if !Self.running { _encoding.withLockedValue { $0 = newValue } } }
    }
    
    public static var boolFormatter: (Bool) -> String {
        get { _boolFormatter.withLockedValue { $0 } }
        set { if !Self.running { _boolFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var intFormatter: (Int) -> String {
        get { _intFormatter.withLockedValue { $0 } }
        set { if !Self.running { _intFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var doubleFormatter: (Double) -> String {
        get { _doubleFormatter.withLockedValue { $0 } }
        set { if !Self.running { _doubleFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var nilFormatter: () -> String {
        get { _nilFormatter.withLockedValue { $0 } }
        set { if !Self.running { _nilFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var voidFormatter: () -> String {
        get { _voidFormatter.withLockedValue { $0 } }
        set { if !Self.running { _voidFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var stringFormatter: (String) -> String {
        get { _stringFormatter.withLockedValue { $0 } }
        set { if !Self.running { _stringFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var arrayFormatter: ([String]) -> String {
        get { _arrayFormatter.withLockedValue { $0 } }
        set { if !Self.running { _arrayFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var dictFormatter: ([String: String]) -> String {
        get { _dictFormatter.withLockedValue { $0 } }
        set { if !Self.running { _dictFormatter.withLockedValue { $0 = newValue } } }
    }
    
    public static var dataFormatter: (Data) -> String? {
        get { _dataFormatter.withLockedValue { $0 } }
        set { if !Self.running { _dataFormatter.withLockedValue { $0 = newValue } } }
    }
    
    // MARK: - Internal/Private Only
    internal var _rootDirectory: String {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }
    
    internal var _ignoreUnfoundImports: Bool {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }

    internal static let _encoding = NIOLockedValueBox<String.Encoding>(.utf8)
    internal static let _boolFormatter = NIOLockedValueBox<(Bool) -> String>({ $0.description })
    internal static let _intFormatter = NIOLockedValueBox<(Int) -> String>({ $0.description })
    internal static let _doubleFormatter = NIOLockedValueBox<(Double) -> String>({ $0.description })
    internal static let _nilFormatter = NIOLockedValueBox<(() -> String)>({ "" })
    internal static let _voidFormatter = NIOLockedValueBox<(() -> String)>({ "" })
    internal static let _stringFormatter = NIOLockedValueBox<((String) -> String)>({ $0 })
    internal static let _arrayFormatter = NIOLockedValueBox<(([String]) -> String)>(
        { "[\($0.map {"\"\($0)\""}.joined(separator: ", "))]" }
    )
    internal static let _dictFormatter = NIOLockedValueBox<(([String: String]) -> String)>(
        { "[\($0.map { "\($0): \"\($1)\"" }.joined(separator: ", "))]" }
    )
    internal static let _dataFormatter = NIOLockedValueBox<((Data) -> String?)>(
        { String(data: $0, encoding: Self._encoding.withLockedValue { $0 }) }
    )
    
    /// Convenience flag for global write-once
    private static let started = NIOLockedValueBox(false)
    private static var running: Bool {
        assert(!Self.started.withLockedValue { $0 }, "LeafKit can only be configured prior to instantiating any LeafRenderer")
        return Self.started.withLockedValue { $0 }
    }
    
    /// Convenience flag for local lock-after-access
    private var accessed = false
}
