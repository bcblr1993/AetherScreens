import Foundation
import CloudKit

/// Bridges the actual CloudKit result callback. The supplied enqueue closure is
/// invoked only after cancellation and account gates are installed.
enum CloudKitModifyOperationRunner {
    static func runSaving(_ operation: CKModifyRecordsOperation, gate: CloudKitAccountOperationGate,
                          token: UUID, enqueue: @escaping @Sendable (CKModifyRecordsOperation) -> Void) async throws -> CloudKitComputerSyncReader.Snapshot {
        guard operation.savePolicy == .ifServerRecordUnchanged,
              operation.recordIDsToDelete?.isEmpty ?? true,
              let records = operation.recordsToSave, records.count == 1 else {
            throw CloudKitComputerSyncReader.Failure.invalidRecord
        }
        let expected = try CloudKitComputerSyncReader.decodeJournal(records[0])
        let collector = SavedRecordCollector(expectedJournal: expected)
        operation.perRecordSaveBlock = { id, result in collector.accept(id: id, result: result) }
        try await run(operation, gate: gate, token: token, enqueue: enqueue)
        return try collector.snapshot()
    }

    static func run(_ operation: CKModifyRecordsOperation, gate: CloudKitAccountOperationGate,
                    token: UUID, enqueue: @escaping @Sendable (CKModifyRecordsOperation) -> Void) async throws {
        let relay = CompletionRelay()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                relay.install(continuation)
                operation.modifyRecordsResultBlock = { [weak operation] result in
                    guard let operation else { relay.finish(.failure(CancellationError())); return }
                    guard gate.finish(operation, token: token) else {
                        relay.finish(.failure(CloudKitComputerSyncReader.Failure.accountChanged))
                        return
                    }
                    relay.finish(result)
                }
                guard !Task.isCancelled else { relay.finish(.failure(CancellationError())); return }
                guard gate.register(operation, token: token, invalidated: {
                    relay.finish(.failure(CloudKitComputerSyncReader.Failure.accountChanged))
                }) else {
                    relay.finish(.failure(CloudKitComputerSyncReader.Failure.accountChanged)); return
                }
                guard gate.isCurrent(token), !operation.isCancelled else {
                    _ = gate.finish(operation, token: token)
                    relay.finish(.failure(CloudKitComputerSyncReader.Failure.accountChanged)); return
                }
                enqueue(operation)
            }
        } onCancel: {
            relay.finish(.failure(CancellationError()))
            operation.cancel()
            _ = gate.finish(operation, token: token)
        }
    }

    private final class SavedRecordCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let expectedJournal: Data
        private var result: Result<CloudKitComputerSyncReader.Snapshot, Error>?
        init(expectedJournal: Data) { self.expectedJournal = expectedJournal }
        func accept(id: CKRecord.ID, result incoming: Result<CKRecord, Error>) {
            let validated: Result<CloudKitComputerSyncReader.Snapshot, Error> = Result {
                guard id == CloudKitComputerSyncReader.recordID else { throw CloudKitComputerSyncReader.Failure.invalidRecord }
                let record = try incoming.get()
                let data = try CloudKitComputerSyncReader.decodeJournal(record)
                guard data == expectedJournal, let tag = record.recordChangeTag, !tag.isEmpty else {
                    throw CloudKitComputerSyncReader.Failure.invalidRecord
                }
                return .init(journal: data, changeTag: tag)
            }
            lock.lock(); defer { lock.unlock() }
            if result != nil { result = .failure(CloudKitComputerSyncReader.Failure.invalidRecord) }
            else { result = validated }
        }
        func snapshot() throws -> CloudKitComputerSyncReader.Snapshot {
            lock.lock(); defer { lock.unlock() }
            guard let result else { throw CloudKitComputerSyncReader.Failure.invalidRecord }
            return try result.get()
        }
    }

    /// Cancellation can arrive before continuation installation, and CloudKit
    /// may complete after cancellation. Preserve the first terminal result.
    private final class CompletionRelay: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?
        func install(_ continuation: CheckedContinuation<Void, Error>) {
            lock.lock()
            let terminal = result
            if terminal == nil { self.continuation = continuation }
            lock.unlock()
            if let terminal { continuation.resume(with: terminal) }
        }
        func finish(_ terminal: Result<Void, Error>) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = terminal
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: terminal)
        }
    }
}
