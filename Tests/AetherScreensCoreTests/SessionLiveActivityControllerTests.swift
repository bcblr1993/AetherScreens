import XCTest
import AetherScreensWidgetSupport
@testable import AetherScreensCore

@MainActor
final class SessionLiveActivityControllerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000)

    func testStartsOnlyConnectedForegroundSessionsAndBalancesRepeatedEnd() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        controller.sessionConnected(sessionID: session)
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 1)
        XCTAssertEqual(driver.starts.first?.sessionID, session)
        XCTAssertEqual(driver.starts.first?.state.phase, .connected)
        XCTAssertEqual(driver.starts.first?.staleDate, date.addingTimeInterval(90))
        await controller.sessionEnded(sessionID: session)?.value
        XCTAssertNil(controller.sessionEnded(sessionID: session))
        XCTAssertEqual(driver.ends.map(\.id), ["activity-1"])
        XCTAssertEqual(driver.ends.first?.state.phase, .ended)
        XCTAssertEqual(driver.ends.first?.dismissAt, date.addingTimeInterval(60))
    }

    func testDisabledSystemDoesNotRequestOrPreventLaterExplicitStart() {
        let driver = Driver()
        driver.canStart = false
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        controller.sessionConnected(sessionID: session)
        XCTAssertTrue(driver.starts.isEmpty)
        driver.canStart = true
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 1)
    }

    func testRequestFailureDoesNotKeepOwnershipOrRetryUntilANewConnection() {
        let driver = Driver()
        driver.rejectStart = true
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        controller.sessionConnected(sessionID: session)
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 1)
        XCTAssertNil(controller.sessionEnded(sessionID: session, reason: .failed))
        driver.rejectStart = false
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 2)
        XCTAssertEqual(driver.existing.count, 1)
    }

    func testFailureEndsWithGenericFailedStateAndNoDiagnosticPayload() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        controller.sessionConnected(sessionID: session)
        await controller.sessionEnded(sessionID: session, reason: .failed)?.value
        XCTAssertEqual(driver.ends.first?.state.phase, .failed)
        XCTAssertTrue(driver.existing.isEmpty)
    }

    func testBackgroundEndsEveryActivityAsPausedAndForegroundDoesNotRestart() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let first = UUID(), second = UUID()
        controller.sessionConnected(sessionID: first)
        controller.sessionConnected(sessionID: second)
        let closing = controller.applicationDidEnterBackground()
        controller.sessionConnected(sessionID: UUID())
        await controller.refreshConnectedActivities()
        XCTAssertEqual(driver.starts.count, 2)
        XCTAssertTrue(driver.updates.isEmpty)
        await closing?.value
        XCTAssertEqual(Set(driver.ends.map(\.id)), ["activity-1", "activity-2"])
        XCTAssertTrue(driver.ends.allSatisfy { $0.state.phase == .paused })
        XCTAssertNil(controller.applicationDidEnterBackground())
        controller.applicationWillEnterForeground()
        XCTAssertEqual(driver.starts.count, 2)
        controller.sessionConnected(sessionID: first)
        XCTAssertEqual(driver.starts.count, 3)
    }

    func testLateEndCannotRetireReplacementActivityForSameSession() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        let entered = expectation(description: "old activity end entered")
        var finish: CheckedContinuation<Void, Never>?
        driver.beforeEnd = { id in
            guard id == "activity-1" else { return }
            await withCheckedContinuation { continuation in
                finish = continuation
                entered.fulfill()
            }
        }
        controller.sessionConnected(sessionID: session)
        let end = controller.sessionEnded(sessionID: session)
        await fulfillment(of: [entered], timeout: 2)
        controller.sessionConnected(sessionID: session)
        finish?.resume()
        await end?.value
        await controller.refreshConnectedActivities()
        XCTAssertEqual(driver.starts.count, 2)
        XCTAssertEqual(driver.ends.map(\.id), ["activity-1"])
        XCTAssertEqual(driver.updates.map(\.id), ["activity-2"])
    }

    func testSynchronousBackgroundDuringRequestRetiresReturnedActivity() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let ended = expectation(description: "reentrant request balanced")
        driver.onStart = { controller.applicationDidEnterBackground() }
        driver.onEnd = { ended.fulfill() }
        controller.sessionConnected(sessionID: UUID())
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(driver.ends.map(\.id), ["activity-1"])
        XCTAssertEqual(driver.ends.first?.state.phase, .paused)
        XCTAssertNil(controller.applicationDidEnterBackground())
    }

    func testDismissedActivityIsNotRecreatedByDuplicateConnectedEvent() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        let session = UUID()
        controller.sessionConnected(sessionID: session)
        driver.existing.removeAll() // Models a person removing the system activity.
        await controller.refreshConnectedActivities()
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 1)
        XCTAssertNil(controller.sessionEnded(sessionID: session))
        controller.sessionConnected(sessionID: session)
        XCTAssertEqual(driver.starts.count, 2)
    }

    func testLaunchReconciliationEndsOnlyOrphansImmediately() async {
        let driver = Driver()
        driver.existing = [.init(id: "previous-process", sessionID: UUID())]
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        controller.sessionConnected(sessionID: UUID())
        await controller.reconcileAfterLaunch()?.value
        XCTAssertEqual(driver.ends.map(\.id), ["previous-process"])
        XCTAssertNil(driver.ends.first?.dismissAt)
        await controller.refreshConnectedActivities()
        XCTAssertEqual(driver.updates.map(\.id), ["activity-1"])
    }

    func testInFlightRefreshFinishesBeforeTerminalBackgroundState() async {
        let driver = Driver()
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        controller.sessionConnected(sessionID: UUID())
        let entered = expectation(description: "foreground refresh entered")
        var finish: CheckedContinuation<Void, Never>?
        driver.beforeUpdate = {
            await withCheckedContinuation { continuation in
                finish = continuation
                entered.fulfill()
            }
        }
        let refresh = Task { await controller.refreshConnectedActivities() }
        await fulfillment(of: [entered], timeout: 2)
        let closing = controller.applicationDidEnterBackground()
        XCTAssertTrue(driver.ends.isEmpty)
        finish?.resume()
        await refresh.value
        await closing?.value
        XCTAssertEqual(driver.operationOrder, ["update:activity-1", "end:activity-1"])
        XCTAssertEqual(driver.ends.first?.state.phase, .paused)
    }

    func testReconciliationCannotOverwritePendingPausedEndAndCleanupLeaseIsBalanced() async {
        let driver = Driver()
        let lease = Lease()
        driver.lease = lease
        let controller = SessionLiveActivityController(driver: driver, now: { self.date })
        controller.sessionConnected(sessionID: UUID())
        let entered = expectation(description: "background terminal update entered")
        var finish: CheckedContinuation<Void, Never>?
        driver.beforeEnd = { _ in
            await withCheckedContinuation { continuation in
                finish = continuation
                entered.fulfill()
            }
        }
        let closing = controller.applicationDidEnterBackground()
        await fulfillment(of: [entered], timeout: 2)
        controller.applicationWillEnterForeground()
        XCTAssertNil(controller.reconcileAfterLaunch())
        XCTAssertEqual(lease.endCalls, 0)
        finish?.resume()
        await closing?.value
        XCTAssertEqual(driver.ends.count, 1)
        XCTAssertEqual(driver.ends.first?.state.phase, .paused)
        XCTAssertEqual(lease.endCalls, 1)
    }

    func testSerializedPayloadContainsOnlyOpaqueIdentityAndPresentationState() throws {
        let attributes = SessionActivityAttributes(sessionID: UUID())
        let state = SessionActivityContentState(phase: .paused, updatedAt: date)
        let encodedAttributes = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any])
        let encodedState = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertEqual(Set(encodedAttributes.keys), ["sessionID"])
        XCTAssertEqual(Set(encodedState.keys), ["phase", "updatedAt"])
    }

    @MainActor
    private final class Lease: SessionActivityCleanupLease {
        var endCalls = 0
        func end() { endCalls += 1 }
    }

    @MainActor
    private final class Driver: SessionActivityDriver {
        struct Start {
            let sessionID: UUID
            let state: SessionActivityContentState
            let staleDate: Date
        }
        struct Update {
            let id: String
            let state: SessionActivityContentState
        }
        struct End {
            let id: String
            let state: SessionActivityContentState
            let dismissAt: Date?
        }
        var canStart = true
        var rejectStart = false
        var existing: [SessionActivityReference] = []
        var starts: [Start] = []
        var updates: [Update] = []
        var ends: [End] = []
        var operationOrder: [String] = []
        var lease: Lease?
        var onStart: (() -> Void)?
        var onEnd: (() -> Void)?
        var beforeEnd: ((String) async -> Void)?
        var beforeUpdate: (() async -> Void)?

        func existingActivities() -> [SessionActivityReference] { existing }
        func beginTerminalTask() -> (any SessionActivityCleanupLease)? { lease }
        func start(sessionID: UUID, state: SessionActivityContentState, staleDate: Date) throws -> String? {
            starts.append(.init(sessionID: sessionID, state: state, staleDate: staleDate))
            if rejectStart { throw NSError(domain: "SyntheticActivityFailure", code: 1) }
            let id = "activity-\(starts.count)"
            existing.append(.init(id: id, sessionID: sessionID))
            onStart?()
            return id
        }
        func update(id: String, state: SessionActivityContentState, staleDate: Date) async {
            await beforeUpdate?()
            updates.append(.init(id: id, state: state))
            operationOrder.append("update:" + id)
        }
        func end(id: String, state: SessionActivityContentState, dismissAt: Date?) async {
            await beforeEnd?(id)
            ends.append(.init(id: id, state: state, dismissAt: dismissAt))
            operationOrder.append("end:" + id)
            existing.removeAll { $0.id == id }
            onEnd?()
        }
    }
}
