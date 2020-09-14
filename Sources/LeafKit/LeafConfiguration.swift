// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// General configuration of Leaf
/// - Sets the default View directory where templates will be looked for
/// - Guards setting the global tagIndicator (default `#`).
public struct LeafConfiguration {
    /// Initialize Leaf with a specific tagIndicator
    /// - Parameter rootDirectory: Default directory where templates will be found
    /// - Parameter tagIndicator: Unique tagIndicator - may only be set once.
    public init(rootDirectory: String,
                tagIndicator: Character = Self.tagIndicator) {
        if !Self.started {
            Character.tagIndicator = tagIndicator
            Self.rootDirectory = rootDirectory
            Self.started = true
        }
    }

    @LeafRuntimeGuard public static var rootDirectory: String = "/"

    @LeafRuntimeGuard public static var tagIndicator: Character = .octothorpe
    
    @LeafRuntimeGuard public static var entities: LeafEntities = .leaf4Core
    
    @LeafRuntimeGuard public static var timeout: Double = 30.0
    
    @LeafRuntimeGuard public static var encoding: String.Encoding = .utf8
    
    @LeafRuntimeGuard public static var boolFormatter: (Bool) -> String = { $0.description }
    @LeafRuntimeGuard public static var intFormatter: (Int) -> String = { $0.description }
    @LeafRuntimeGuard public static var doubleFormatter: (Double) -> String = { $0.description }
    @LeafRuntimeGuard public static var nilFormatter: () -> String = { "" }
    @LeafRuntimeGuard public static var stringFormatter: (String) -> String = { $0 }
    @LeafRuntimeGuard public static var dataFormatter: (Data) -> String? =
        { String(data: $0, encoding: encoding) }

    static var isRunning: Bool { started }
    
    /// Convenience for getting running state of LeafKit that will assert with a fault message for soft-failing things
    static func running(fault message: String) -> Bool {
        assert(!started, "LeafKit is running; \(message)")
        return started
    }

    // MARK: - Internal/Private Only
    
    /// WARNING: Reset global "started" flag - only for testing use
    static func __reset() { started = false }

    /// Convenience flag for global write-once
    private static var started = false

    static func accessed() { _accessed = true }
    /// Convenience flag for local lock-after-access
    private static var _accessed = false
}


@propertyWrapper
public struct LeafRuntimeGuard<T> {
    public var wrappedValue: T {
        get { _unsafeValue }
        set { if !LKConf.running(fault: fault) { _unsafeValue = newValue } }
    }
    
    public init(wrappedValue: T, local: Bool = false) { self._unsafeValue = wrappedValue }
    
    internal var _unsafeValue: T
    internal var fault: String = "Cannot configure after a LeafRenderer has instantiated"
}
