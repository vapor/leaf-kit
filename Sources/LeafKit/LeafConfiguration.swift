// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// General configuration of Leaf
/// - Sets the default View directory where templates will be looked for
/// - Guards setting the global tagIndicator (default `#`).
public struct LeafConfiguration {

    /// Initialize Leaf with the default tagIndicator `#`
    /// - Parameter rootDirectory: Default directory where templates will be found
    public init(rootDirectory: String) {
        self.init(rootDirectory: rootDirectory, tagIndicator: .octothorpe)
    }

    /// Initialize Leaf with a specific tagIndicator
    /// - Parameter rootDirectory: Default directory where templates will be found
    /// - Parameter tagIndicator: Unique tagIndicator - may only be set once.
    public init(rootDirectory: String, tagIndicator: Character) {
        if !Self.started {
            Character.tagIndicator = tagIndicator
            Self.started = true
        }
        self._rootDirectory = rootDirectory
    }

    public var rootDirectory: String {
        mutating get { accessed = true; return _rootDirectory }
        set { _rootDirectory = newValue }
    }

    public static var entities: LeafEntities {
        get { _entities }
        set { if !Self.running { _entities = newValue} }
    }

    public static var timeout: Double {
        get { _timeout }
        set { if !Self.running { _timeout = newValue } }
    }

    public static var encoding: String.Encoding {
        get { _encoding }
        set { if !Self.running { _encoding = newValue } }
    }

    public static var boolFormatter: (Bool) -> String {
        get { _boolFormatter }
        set { if !Self.running { _boolFormatter = newValue } }
    }

    public static var intFormatter: (Int) -> String {
        get { _intFormatter }
        set { if !Self.running { _intFormatter = newValue } }
    }

    public static var doubleFormatter: (Double) -> String {
        get { _doubleFormatter }
        set { if !Self.running { _doubleFormatter = newValue } }
    }

    public static var nilFormatter: () -> String {
        get { _nilFormatter }
        set { if !Self.running { _nilFormatter = newValue } }
    }

    public static var voidFormatter: () -> String {
        get { _voidFormatter }
        set { if !Self.running { _voidFormatter = newValue } }
    }

    public static var stringFormatter: (String) -> String {
        get { _stringFormatter }
        set { if !Self.running { _stringFormatter = newValue } }
    }

    public static var arrayFormatter: ([String]) -> String {
        get { _arrayFormatter }
        set { if !Self.running { _arrayFormatter = newValue } }
    }

    public static var dictFormatter: ([String: String]) -> String {
        get { _dictFormatter }
        set { if !Self.running { _dictFormatter = newValue } }
    }

    public static var dataFormatter: (Data) -> String? {
        get { _dataFormatter }
        set { if !Self.running { _dataFormatter = newValue } }
    }

    // MARK: - Internal/Private Only
    static internal var isRunning: Bool { Self.started }
    /// Convenience for getting running state of LeafKit that will assert with a fault message for soft-failing things
    static internal func running(fault message: String = "Cannot complete operation") -> Bool {
        assert(!Self.started, "LeafKit is running; \(message)")
        return Self.started
    }

    internal var _rootDirectory: String {
        willSet { assert(!accessed, "Changing property after LeafConfiguration has been read has no effect") }
    }

    internal static var _entities: LeafEntities = .leaf4Core
    internal static var _encoding: String.Encoding = .utf8
    internal static var _timeout: Double = 30.0
    internal static var _boolFormatter: (Bool) -> String = { $0.description }
    internal static var _intFormatter: (Int) -> String = { $0.description }
    internal static var _doubleFormatter: (Double) -> String = { $0.description }
    internal static var _nilFormatter: () -> String = { "" }
    internal static var _voidFormatter: () -> String = { "" }
    internal static var _stringFormatter: (String) -> String = { $0 }
    internal static var _arrayFormatter: ([String]) -> String =
        { "[\($0.map {"\"\($0)\""}.joined(separator: ", "))]" }
    internal static var _dictFormatter: ([String: String]) -> String =
        { "[\($0.map { "\($0): \"\($1)\"" }.joined(separator: ", "))]" }
    internal static var _dataFormatter: (Data) -> String? =
        { String(data: $0, encoding: Self._encoding) }

    /// WARNING: Reset global "started" flag - only for testing use
    internal static func __reset() { Self.started = false }

    /// Convenience flag for global write-once
    private static var started = false
    private static var running: Bool {
        running(fault: "Cannot configure after a LeafRenderer has instantiated")
    }

    /// Convenience flag for local lock-after-access
    private var accessed = false
}
