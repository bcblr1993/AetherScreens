import Foundation
import CloudKit

/// Notification invalidation is synchronous and independent of actor scheduling.
/// Cancellation is best effort; it cannot undo a write already accepted remotely.
final class CloudKitAccountOperationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var revision = UUID()
    private struct Entry {
        let operation: CKOperation
        let invalidated: (@Sendable () -> Void)?
    }
    private var operations: [ObjectIdentifier: Entry] = [:]
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    init(center: NotificationCenter = .default) {
        self.center = center
        observer = center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            self?.invalidate()
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
        invalidate()
    }

    func begin() -> UUID {
        lock.lock(); defer { lock.unlock() }
        return revision
    }

    func isCurrent(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return revision == token
    }

    @discardableResult
    func register(_ operation: CKOperation, token: UUID, invalidated: (@Sendable () -> Void)? = nil) -> Bool {
        lock.lock()
        let valid = revision == token && !operation.isCancelled
        if valid { operations[ObjectIdentifier(operation)] = Entry(operation: operation, invalidated: invalidated) }
        lock.unlock()
        if !valid { operation.cancel() }
        return valid
    }

    @discardableResult
    func finish(_ operation: CKOperation, token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        operations.removeValue(forKey: ObjectIdentifier(operation))
        return revision == token && !operation.isCancelled
    }

    func invalidate() {
        lock.lock()
        revision = UUID()
        let pending = Array(operations.values)
        operations.removeAll()
        lock.unlock()
        // cancel may call completion handlers; never hold the gate lock here.
        for entry in pending { entry.operation.cancel(); entry.invalidated?() }
    }
}
