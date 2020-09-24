//===----------------------------------------------------------------------===//
//
// Derived from SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#else
import Glibc
#endif

/// A threading lock based on `libpthread` instead of `libdispatch`.
///
/// This object provides a lock on top of a single `pthread_mutex_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO.
public final class RWLock {
    fileprivate let rwlock: UnsafeMutablePointer<pthread_rwlock_t> =
        UnsafeMutablePointer.allocate(capacity: 1)

    /// Create a new lock.
    public init() {
        var attr = pthread_rwlockattr_t()
        pthread_rwlockattr_init(&attr)
        let err = pthread_rwlock_init(self.rwlock, &attr)
        precondition(err == 0, "\(#function) failed in pthread_rwlock with error \(err)")
    }

    deinit {
        let err = pthread_rwlock_destroy(self.rwlock)
        precondition(err == 0, "\(#function) failed in pthread_rwlock with error \(err)")
        rwlock.deallocate()
    }

    public func lock(forWrite: Bool = false) {
        let err = forWrite ? pthread_rwlock_wrlock(self.rwlock)
                           : pthread_rwlock_rdlock(self.rwlock)
        precondition(err == 0, "\(#function) failed in pthread_rwlock with error \(err)")
    }

    public func unlock() {
        let err = pthread_rwlock_unlock(self.rwlock)
        precondition(err == 0, "\(#function) failed in pthread_rwlock with error \(err)")
    }
}

extension RWLock {
    /// Acquire the lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    public func readWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(forWrite: false)
        defer { unlock() }
        return try body()
    }
    
    @inlinable
    public func writeWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(forWrite: true)
        defer { unlock() }
        return try body()
    }

    @inlinable
    public func writeWithLock(_ body: () throws -> Void) rethrows -> Void {
        lock(forWrite: true)
        defer { unlock() }
        try body()
    }
}
