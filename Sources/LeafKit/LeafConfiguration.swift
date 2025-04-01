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
        Self._dataLock.withLockVoid {
            if !Self.started {
                Self._tagIndicator = tagIndicator
                Self.started = true
            }
        }
        self._rootDirectory = rootDirectory
        self._ignoreUnfoundImports = ignoreUnfoundImports
    }
    
    public var rootDirectory: String {
        mutating get { accessed = true; return self._rootDirectory }
        set { _rootDirectory = newValue }
    }
    
    public var ignoreUnfoundImports: Bool {
        mutating get { accessed = true; return self._ignoreUnfoundImports }
        set { self._ignoreUnfoundImports = newValue }
    }

    public static var encoding: String.Encoding {
        get { Self._dataLock.withLock { Self._encoding } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._encoding = newValue } } }
    }
    
    public static var boolFormatter: (Bool) -> String {
        get { Self._dataLock.withLock { Self._boolFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._boolFormatter = newValue } } }
    }
    
    public static var intFormatter: (Int) -> String {
        get { Self._dataLock.withLock { Self._intFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._intFormatter = newValue } } }
    }
    
    public static var doubleFormatter: (Double) -> String {
        get { Self._dataLock.withLock { Self._doubleFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._doubleFormatter = newValue } } }
    }
    
    public static var nilFormatter: () -> String {
        get { Self._dataLock.withLock { Self._nilFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._nilFormatter = newValue } } }
    }
    
    public static var voidFormatter: () -> String {
        get { Self._dataLock.withLock { Self._voidFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._voidFormatter = newValue } } }
    }
    
    public static var stringFormatter: (String) -> String {
        get { Self._dataLock.withLock { Self._stringFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._stringFormatter = newValue } } }
    }
    
    public static var arrayFormatter: ([String]) -> String {
        get { Self._dataLock.withLock { Self._arrayFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._arrayFormatter = newValue } } }
    }
    
    public static var dictFormatter: ([String: String]) -> String {
        get { Self._dataLock.withLock { Self._dictFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._dictFormatter = newValue } } }
    }
    
    public static var dataFormatter: (Data) -> String? {
        get { Self._dataLock.withLock { Self._dataFormatter } }
        set { Self._dataLock.withLockVoid { if !Self.running { Self._dataFormatter = newValue } } }
    }

    // MARK: - Internal/Private Only
    internal static var tagIndicator: Character {
        Self._tagIndicator // The lock is expensive; because the value is write-once, it's safe (enough) to skip it here
    }

    internal var _rootDirectory: String {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }
    
    internal var _ignoreUnfoundImports: Bool {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }

    private static let _dataLock: NIOLock = .init()

    nonisolated(unsafe) private static var _tagIndicator: Character = .octothorpe
    nonisolated(unsafe) private static var _encoding: String.Encoding = .utf8
    nonisolated(unsafe) private static var _boolFormatter: (Bool) -> String = { $0.description }
    nonisolated(unsafe) private static var _intFormatter: (Int) -> String = { $0.description }
    nonisolated(unsafe) private static var _doubleFormatter: (Double) -> String = { $0.description }
    nonisolated(unsafe) private static var _nilFormatter: () -> String = { "" }
    nonisolated(unsafe) private static var _voidFormatter: () -> String = { "" }
    nonisolated(unsafe) private static var _stringFormatter: (String) -> String = { $0 }
    nonisolated(unsafe) private static var _arrayFormatter: ([String]) -> String =
        { "[\($0.map {"\"\($0)\""}.joined(separator: ", "))]" }
    nonisolated(unsafe) private static var _dictFormatter: ([String: String]) -> String =
        { "[\($0.map { "\($0): \"\($1)\"" }.joined(separator: ", "))]" }
    nonisolated(unsafe) private static var _dataFormatter: (Data) -> String? =
        { String(data: $0, encoding: Self._encoding) }

    /// Convenience flag for global write-once
    nonisolated(unsafe) private static var started = false
    /// Calls to this accessor must be guarded by the data lock; this avoids having to take the lock twice when setting values.
    private static var running: Bool {
        assert(!Self.started, "LeafKit can only be configured prior to instantiating any LeafRenderer")
        return Self.started
    }
    
    /// Convenience flag for local lock-after-access
    private var accessed = false
}
