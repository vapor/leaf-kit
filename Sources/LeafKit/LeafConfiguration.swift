// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation
import NIOConcurrencyHelpers

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
    
    @LeafRuntimeGuard(condition: {$0>0})
    public static var timeout: Double = 30.0
    
    @LeafRuntimeGuard public static var rawCachingLimit: UInt32 = 1024
    
    @LeafRuntimeGuard public static var encoding: String.Encoding = .utf8

    static var isRunning: Bool { started }
    
    /// Convenience for getting running state of LeafKit that will assert with a fault message for soft-failing things
    static func running(fault message: String) -> Bool {
        assert(!started, "\(message) after LeafRenderer has instantiated")
        return started
    }

    // MARK: - Internal/Private Only
    
    /// WARNING: Reset global "started" flag - only for testing use
    static func __reset() { started = false }

    /// Convenience flag for global write-once
    private static var started = false
}


/// `LeafRuntimeGuard` secures a value against being changed once a `LeafRenderer` is active
///
/// Attempts to change the value secured by the runtime guard will assert in debug to warn against
/// programmatic changes to a value that needs to be consistent across the running state of LeafKit.
/// Such attempts to change will silently fail in production builds.
@propertyWrapper public struct LeafRuntimeGuard<T> {
    public var wrappedValue: T {
        get { _unsafeValue }
        set {
            assert(condition(newValue), "\(object) failed conditional check")
            if !LKConf.running(fault: "Cannot configure \(object)")
               { _unsafeValue = newValue }
        }
    }
    
    public init(wrappedValue: T,
                module: String = #fileID,
                component: String = #function,
                condition: @escaping (T) -> Bool = {_ in true}) {
        self._unsafeValue = wrappedValue
        let module = String(module.split(separator: "/").first ?? "")
        self.object = module.isEmpty ? component : "\(module).\(component)"
        self.condition = condition
    }
    
    internal var _unsafeValue: T
    private let condition: (T) -> Bool
    private let object: String
    
    internal var fault: String { "Cannot configure \(object)" }
}
