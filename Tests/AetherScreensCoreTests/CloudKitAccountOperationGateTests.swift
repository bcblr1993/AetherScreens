import XCTest
import CloudKit
@testable import AetherScreensCore

final class CloudKitAccountOperationGateTests: XCTestCase {
    func testAccountNotificationCancelsPendingAndRejectsOldGeneration() {
        let center = NotificationCenter()
        let gate = CloudKitAccountOperationGate(center: center)
        let token = gate.begin()
        let operation = CKModifyRecordsOperation()
        XCTAssertTrue(gate.register(operation, token: token))
        center.post(name: .CKAccountChanged, object: nil)
        XCTAssertFalse(gate.isCurrent(token))
        XCTAssertTrue(operation.isCancelled)
        XCTAssertFalse(gate.finish(operation, token: token))
        let late = CKModifyRecordsOperation()
        XCTAssertFalse(gate.register(late, token: token))
        XCTAssertTrue(late.isCancelled)
        let current = gate.begin()
        let fresh = CKModifyRecordsOperation()
        XCTAssertTrue(gate.register(fresh, token: current))
        XCTAssertTrue(gate.finish(fresh, token: current))
        center.post(name: .CKAccountChanged, object: nil)
        XCTAssertFalse(fresh.isCancelled, "Finished operations are no longer retained by the gate")
    }
}
