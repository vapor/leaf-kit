import NIOConcurrencyHelpers

/// Uses a locking mechanism to ensure Sendability.
internal final class SendableBox<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NIOLock()

    internal var value: Value {
        get {
            lock.withLock {
                self._value
            }
        }
        set(newValue) {
            lock.withLock {
                self._value = newValue
            }
        }
    }

    internal init(_ value: Value) {
        self._value = value
    }
}
