import XCTest
import CloudKit
@testable import AetherScreensCore

final class CloudKitModifyOperationRunnerTests: XCTestCase {
    func testOverallSuccessWithoutSavedRecordIsNotUploadSuccess() async throws {
        let operation = try CloudKitComputerSyncReader.modification(journal: ComputerSyncJournal().encoded(), base: nil, expectedChangeTag: nil)
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        do {
            _ = try await CloudKitModifyOperationRunner.runSaving(operation, gate: gate, token: gate.begin()) {
                $0.modifyRecordsResultBlock?(.success(()))
            }
            XCTFail("Missing per-record result must fail")
        } catch CloudKitComputerSyncReader.Failure.invalidRecord {}
    }

    func testPerRecordFailureIsNotHiddenByOverallSuccess() async throws {
        let operation = try CloudKitComputerSyncReader.modification(journal: ComputerSyncJournal().encoded(), base: nil, expectedChangeTag: nil)
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        do {
            _ = try await CloudKitModifyOperationRunner.runSaving(operation, gate: gate, token: gate.begin()) {
                $0.perRecordSaveBlock?(CloudKitComputerSyncReader.recordID, .failure(CKError(.serverRecordChanged)))
                $0.modifyRecordsResultBlock?(.success(()))
            }
            XCTFail("Per-record conflict must fail")
        } catch let error as CKError { XCTAssertEqual(error.code, .serverRecordChanged) }
    }

    func testSavedRecordWithoutServerVersionCannotBeAcknowledged() async throws {
        let operation = try CloudKitComputerSyncReader.modification(journal: ComputerSyncJournal().encoded(), base: nil, expectedChangeTag: nil)
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        do {
            _ = try await CloudKitModifyOperationRunner.runSaving(operation, gate: gate, token: gate.begin()) {
                let record = $0.recordsToSave![0]
                $0.perRecordSaveBlock?(record.recordID, .success(record))
                $0.modifyRecordsResultBlock?(.success(()))
            }
            XCTFail("Unsaved record has no server change tag")
        } catch CloudKitComputerSyncReader.Failure.invalidRecord {}
    }

    func testServerVersionConflictIsReturnedWithoutTreatingItAsSuccess() async throws {
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        let operation = CKModifyRecordsOperation()
        do {
            try await CloudKitModifyOperationRunner.run(operation, gate: gate, token: gate.begin()) {
                $0.modifyRecordsResultBlock?(.failure(CKError(.serverRecordChanged)))
            }
            XCTFail("Conflict must fail")
        } catch let error as CKError { XCTAssertEqual(error.code, .serverRecordChanged) }
    }

    func testAlreadyCancelledTaskNeverEnqueuesOperation() async throws {
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        let operation = CKModifyRecordsOperation()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await CloudKitModifyOperationRunner.run(operation, gate: gate, token: gate.begin()) { _ in
                XCTFail("Cancelled task must not enqueue")
            }
        }
        do { try await task.value; XCTFail("Cancellation must fail") }
        catch is CancellationError {}
        XCTAssertTrue(operation.isCancelled)
    }

    func testSuccessfulResultCompletesWithoutCloudRequest() async throws {
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        let operation = CKModifyRecordsOperation()
        try await CloudKitModifyOperationRunner.run(operation, gate: gate, token: gate.begin()) {
            $0.modifyRecordsResultBlock?(.success(()))
        }
        XCTAssertFalse(operation.isCancelled)
    }

    func testTaskCancellationCompletesAndLateSuccessCannotResumeTwice() async throws {
        let queued = expectation(description: "Operation queued")
        let gate = CloudKitAccountOperationGate(center: NotificationCenter())
        let operation = CKModifyRecordsOperation()
        let task = Task {
            try await CloudKitModifyOperationRunner.run(operation, gate: gate, token: gate.begin()) { _ in queued.fulfill() }
        }
        await fulfillment(of: [queued], timeout: 3)
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must fail") }
        catch is CancellationError {}
        XCTAssertTrue(operation.isCancelled)
        operation.modifyRecordsResultBlock?(.success(()))
    }

    func testAccountChangeCompletesEvenWhenOperationNeverCallsBack() async throws {
        let queued = expectation(description: "Operation queued")
        let center = NotificationCenter()
        let gate = CloudKitAccountOperationGate(center: center)
        let operation = CKModifyRecordsOperation()
        let task = Task {
            try await CloudKitModifyOperationRunner.run(operation, gate: gate, token: gate.begin()) { _ in queued.fulfill() }
        }
        await fulfillment(of: [queued], timeout: 3)
        center.post(name: .CKAccountChanged, object: nil)
        do { try await task.value; XCTFail("Account change must fail") }
        catch CloudKitComputerSyncReader.Failure.accountChanged {}
        XCTAssertTrue(operation.isCancelled)
        operation.modifyRecordsResultBlock?(.success(()))
    }
}
