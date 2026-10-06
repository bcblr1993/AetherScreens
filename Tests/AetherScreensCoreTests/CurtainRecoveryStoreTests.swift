import XCTest
import AetherScreensSSH
@testable import AetherScreensCore

/// Pure in-memory ledger cases; no transport, credential store or UI fixture.
final class CurtainRecoveryStoreTests: XCTestCase {
    private struct Source {
        var state = RFBAppleCurtain()
        let source = RFBCurtainEventSource()
        let connection = UUID()
        let account: String?
        var revision: UInt64 = 0

        init(account: String? = "operator", recovery: Bool = false) {
            self.account = account
            state.beginConnection(connection)
            state.configureRecoveryForNewConnection(recovery)
            state.authenticated(connection: connection, apple: true)
            state.metadata(connection: connection, sessionFlags: 6)
        }

        mutating func event() -> RFBCurtainEvent {
            revision += 1
            return .init(source: source, revision: revision, account: account, transportAttached: state.hasConnection, status: state.status,
                         pendingRequestID: state.pending?.id, pendingHidden: state.pending?.hidden,
                         confirmedRestorationID: state.confirmedRestorationID)
        }
    }

    private func device() -> RemoteDevice {
        RemoteDevice(name: "Recovery test Mac", host: "recovery.invalid", authMethod: .macAccount, username: "operator")
    }

    func testClosedSourceWarningSurvivesNewReadySourceUntilFreshRestore() throws {
        let store = CurtainRecoveryStore()
        let device = device()
        var first = Source()
        _ = try XCTUnwrap(first.state.request(hidden: true))
        store.record(first.event(), device: device)
        let target = CurtainRecoveryStore.Target(device: device, account: "operator")
        XCTAssertFalse(store.hasRecoveryWarning(for: target, currentSource: first.source.id))
        first.state.disconnected(connection: first.connection)
        store.record(first.event(), device: device)
        XCTAssertEqual(store.warnings.count, 1)
        XCTAssertTrue(store.hasRecoveryWarning(for: target, currentSource: first.source.id))
        var reopened = Source(recovery: store.hasUnresolved(for: target))
        store.record(reopened.event(), device: device)
        XCTAssertTrue(reopened.state.status.recoveryUnconfirmed)
        XCTAssertEqual(store.warnings.count, 1, "A new ready connection must not clear the closed connection's warning")
        _ = try XCTUnwrap(reopened.state.request(hidden: false))
        store.record(reopened.event(), device: device)
        reopened.state.metadata(connection: reopened.connection, sessionFlags: 6)
        store.record(reopened.event(), device: device)
        XCTAssertFalse(store.hasUnresolved(for: target))
        XCTAssertTrue(store.warnings.isEmpty)
    }

    func testOlderRestoreCannotClearLaterHideFromAnotherClient() throws {
        let store = CurtainRecoveryStore()
        let device = device()
        var first = Source()
        _ = try XCTUnwrap(first.state.request(hidden: true))
        store.record(first.event(), device: device)
        first.state.metadata(connection: first.connection, sessionFlags: 2)
        store.record(first.event(), device: device)
        _ = try XCTUnwrap(first.state.request(hidden: false))
        store.record(first.event(), device: device)
        var later = Source()
        let laterHide = try XCTUnwrap(later.state.request(hidden: true))
        store.record(later.event(), device: device)
        first.state.metadata(connection: first.connection, sessionFlags: 6)
        store.record(first.event(), device: device)
        XCTAssertTrue(store.hasUnresolved(for: .init(device: device, account: "operator")))
        later.state.expire(laterHide)
        store.record(later.event(), device: device)
        XCTAssertEqual(store.warnings.count, 1)
        _ = try XCTUnwrap(later.state.request(hidden: true))
        store.record(later.event(), device: device)
        XCTAssertEqual(store.warnings.count, 1, "A later hide must preserve the unconfirmed restoration notice")
    }

    func testClearedLedgerKeepsHighWaterAndOldConfirmationScope() throws {
        let store = CurtainRecoveryStore()
        let device = device()
        var first = Source()
        _ = try XCTUnwrap(first.state.request(hidden: true))
        store.record(first.event(), device: device)
        _ = try XCTUnwrap(first.state.restorationForClose())
        store.record(first.event(), device: device)
        first.state.metadata(connection: first.connection, sessionFlags: 6)
        store.record(first.event(), device: device)
        XCTAssertFalse(store.hasUnresolved(for: .init(device: device, account: "operator")))
        var later = Source()
        _ = try XCTUnwrap(later.state.request(hidden: true))
        store.record(later.event(), device: device)
        // The old client keeps its confirmed identity on later metadata. Its
        // higher client revision must still retain the original restore scope.
        first.state.metadata(connection: first.connection, sessionFlags: 6)
        store.record(first.event(), device: device)
        XCTAssertTrue(store.hasUnresolved(for: .init(device: device, account: "operator")))
    }

    func testStaleCallbackCannotRecreateClearedObligation() throws {
        let store = CurtainRecoveryStore()
        let device = device()
        var source = Source()
        _ = try XCTUnwrap(source.state.request(hidden: true))
        let staleHide = source.event()
        store.record(staleHide, device: device)
        _ = try XCTUnwrap(source.state.restorationForClose())
        store.record(source.event(), device: device)
        source.state.metadata(connection: source.connection, sessionFlags: 6)
        store.record(source.event(), device: device)
        store.record(staleHide, device: device)
        source.state.disconnected(connection: source.connection)
        store.record(source.event(), device: device)
        store.record(staleHide, device: device)
        XCTAssertFalse(store.hasUnresolved(for: .init(device: device, account: "operator")))
        XCTAssertTrue(store.warnings.isEmpty)
    }

    func testPassiveConsoleVisibilityDoesNotLoseWarningOnClose() throws {
        let store = CurtainRecoveryStore()
        let device = device()
        var source = Source()
        _ = try XCTUnwrap(source.state.request(hidden: true))
        store.record(source.event(), device: device)
        source.state.metadata(connection: source.connection, sessionFlags: 2)
        store.record(source.event(), device: device)
        source.state.metadata(connection: source.connection, sessionFlags: 6)
        store.record(source.event(), device: device)
        XCTAssertFalse(source.state.status.needsRestoration)
        XCTAssertNil(source.state.confirmedRestorationID)
        source.state.disconnected(connection: source.connection)
        store.record(source.event(), device: device)
        XCTAssertEqual(store.warnings.count, 1, "Passive visibility is not a requested restoration confirmation")
    }

    func testActualAuthenticatedAccountAndCompleteTargetScope() throws {
        let store = CurtainRecoveryStore()
        var initial = device()
        initial.username = nil
        initial.authMethod = .vncPassword
        var source = Source(account: "actual-account")
        _ = try XCTUnwrap(source.state.request(hidden: true))
        store.record(source.event(), device: initial)
        source.state.disconnected(connection: source.connection)
        store.record(source.event(), device: initial)
        let warning = try XCTUnwrap(store.warnings.first)
        var saved = initial
        saved.username = "actual-account"
        saved.authMethod = .macAccount
        XCTAssertTrue(warning.id.matches(saved))
        XCTAssertFalse(warning.id.matches(initial))
        saved.host = "edited.invalid"
        XCTAssertFalse(warning.id.matches(saved))
        saved = warning.device
        saved.username = "other-account"
        XCTAssertFalse(warning.id.matches(saved))
        saved = warning.device
        saved.sshConfiguration = try SSHConfiguration(host: "jump.invalid", username: "jump-account")
        XCTAssertFalse(warning.id.matches(saved))
        XCTAssertFalse(store.hasUnresolved(for: .init(device: saved, account: saved.username)))
        var otherAccount = Source(account: "other-account")
        store.record(otherAccount.event(), device: warning.device)
        XCTAssertEqual(store.warnings.count, 1, "Another account's initial ready state must retain the original warning")
    }
}
