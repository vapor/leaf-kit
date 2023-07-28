import Foundation

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
        if !Self.started.value {
            Character.tagIndicator = tagIndicator
            Self.started.value = true
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
        get { _encoding.value }
        set { if !Self.running { _encoding.value = newValue } }
    }
    
    public static var boolFormatter: (Bool) -> String {
        get { _boolFormatter.value }
        set { if !Self.running { _boolFormatter.value = newValue } }
    }
    
    public static var intFormatter: (Int) -> String {
        get { _intFormatter.value }
        set { if !Self.running { _intFormatter.value = newValue } }
    }
    
    public static var doubleFormatter: (Double) -> String {
        get { _doubleFormatter.value }
        set { if !Self.running { _doubleFormatter.value = newValue } }
    }
    
    public static var nilFormatter: () -> String {
        get { _nilFormatter.value }
        set { if !Self.running { _nilFormatter.value = newValue } }
    }
    
    public static var voidFormatter: () -> String {
        get { _voidFormatter.value }
        set { if !Self.running { _voidFormatter.value = newValue } }
    }
    
    public static var stringFormatter: (String) -> String {
        get { _stringFormatter.value }
        set { if !Self.running { _stringFormatter.value = newValue } }
    }
    
    public static var arrayFormatter: ([String]) -> String {
        get { _arrayFormatter.value }
        set { if !Self.running { _arrayFormatter.value = newValue } }
    }
    
    public static var dictFormatter: ([String: String]) -> String {
        get { _dictFormatter.value }
        set { if !Self.running { _dictFormatter.value = newValue } }
    }
    
    public static var dataFormatter: (Data) -> String? {
        get { _dataFormatter.value }
        set { if !Self.running { _dataFormatter.value = newValue } }
    }
    
    // MARK: - Internal/Private Only
    internal var _rootDirectory: String {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }
    
    internal var _ignoreUnfoundImports: Bool {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }

    internal static let _encoding = SendableBox<String.Encoding>(.utf8)
    internal static let _boolFormatter = SendableBox<(Bool) -> String>({ $0.description })
    internal static let _intFormatter = SendableBox<(Int) -> String>({ $0.description })
    internal static let _doubleFormatter = SendableBox<(Double) -> String>({ $0.description })
    internal static let _nilFormatter = SendableBox<(() -> String)>({ "" })
    internal static let _voidFormatter = SendableBox<(() -> String)>({ "" })
    internal static let _stringFormatter = SendableBox<((String) -> String)>({ $0 })
    internal static let _arrayFormatter = SendableBox<(([String]) -> String)>(
        { "[\($0.map {"\"\($0)\""}.joined(separator: ", "))]" }
    )
    internal static let _dictFormatter = SendableBox<(([String: String]) -> String)>(
        { "[\($0.map { "\($0): \"\($1)\"" }.joined(separator: ", "))]" }
    )
    internal static let _dataFormatter = SendableBox<((Data) -> String?)>(
        { String(data: $0, encoding: Self._encoding.value) }
    )
    
    /// Convenience flag for global write-once
    private static let started = SendableBox(false)
    private static var running: Bool {
        assert(!Self.started.value, "LeafKit can only be configured prior to instantiating any LeafRenderer")
        return Self.started.value
    }
    
    /// Convenience flag for local lock-after-access
    private var accessed = false
}
