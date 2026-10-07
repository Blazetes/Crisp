import Foundation

/// Unlike the UI timeout, this lease ends only when the blocking transaction finishes.
final class DisplayConfigurationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    var isPending: Bool { lock.withLock { pending } }

    func begin() -> Bool {
        lock.withLock {
            guard !pending else { return false }
            pending = true
            return true
        }
    }

    func finish() {
        lock.withLock { pending = false }
    }
}
