import Foundation

/// Idempotent ownership of one consumer of a shared asset's opening download.
/// The download stops only when every consumer has released its lease.
public final class AudioCacheOpeningWarmupLease: @unchecked Sendable {
    private let lock = NSLock()
    private var release: (@Sendable () -> Void)?

    init(_ release: @escaping @Sendable () -> Void) {
        self.release = release
    }

    public func finish() {
        let action = lock.withLock {
            let action = release
            release = nil
            return action
        }
        action?()
    }

    deinit { finish() }
}
