import XCTest
@testable import AetherScreensCore

/// Pure protocol/state tests. They neither connect to a Mac nor prove privacy,
/// physical black pixels, continued control, or server recovery on disconnect.
final class AppleCurtainTests: XCTestCase {
    func testGoldenVisibilityPacketsHaveNoPrivateNote() {
        XCTAssertEqual(Array(RFBEncoder.encodeAppleCurtain(hidden: true)), [12, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(RFBEncoder.encodeAppleCurtain(hidden: false)), [12, 0, 0, 1, 0, 0])
    }

    func testConsoleVisibilityMetadataKeepsFramebufferLayout() throws {
        var visible = AppleDisplayTestPayload.body()
        visible.replaceSubrange(14..<18, with: AppleDisplayTestPayload.be32(0x06))
        var hidden = visible
        hidden.replaceSubrange(14..<18, with: AppleDisplayTestPayload.be32(0x02))
        let before = try XCTUnwrap(RFBAppleDisplayLayout.parse(visible))
        let after = try XCTUnwrap(RFBAppleDisplayLayout.parse(hidden))
        XCTAssertNotEqual(before, after, "Visibility metadata must still reach the Curtain reducer")
        XCTAssertTrue(before.hasSameFramebufferLayout(as: after), "A visibility-only report must not discard pixels or input")
    }

    func testActualDisplayAndScaleChangesStillResetFramebufferLayout() throws {
        let combined = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        let selected = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22)))
        XCTAssertFalse(combined.hasSameFramebufferLayout(as: selected))
        var screens = AppleDisplayTestPayload.screens
        screens[0].scale = 0.5
        let scaled = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens)))
        XCTAssertFalse(combined.hasSameFramebufferLayout(as: scaled))
    }

    private func ready(flags: UInt32 = 0x06, apple: Bool = true) -> (RFBAppleCurtain, UUID) {
        let connection = UUID()
        var state = RFBAppleCurtain()
        state.beginConnection(connection)
        state.authenticated(connection: connection, apple: apple)
        state.metadata(connection: connection, sessionFlags: flags)
        return (state, connection)
    }

    func testMissingMetadataAndGenericServerCannotRequest() {
        var state = RFBAppleCurtain()
        let id = UUID()
        state.beginConnection(id)
        state.authenticated(connection: id, apple: true)
        XCTAssertNil(state.request(hidden: true))
        (state, _) = ready(apple: false)
        XCTAssertNil(state.request(hidden: true))
    }

    func testCapabilityAndBothLoginBitsGateHideAndRestore() {
        for flags: UInt32 in [0, 4, 0x0E, 0x16, 0x1E, 0x06000000] {
            var (state, _) = ready(flags: flags)
            XCTAssertFalse(state.status.canRequest)
            XCTAssertNil(state.request(hidden: true))
            XCTAssertNil(state.request(hidden: false))
        }
    }

    func testUnknownMetadataVersionDoesNotGuessCapability() {
        var (state, connection) = ready()
        state.metadata(connection: connection, version: 6, sessionFlags: 6)
        XCTAssertFalse(state.status.canRequest)
        XCTAssertNil(state.request(hidden: true))
    }

    func testInitialNonConsoleReportIsNotOurHideConfirmation() {
        var (state, connection) = ready(flags: 2)
        XCTAssertEqual(state.status.phase, .unknown)
        XCTAssertFalse(state.status.isConfirmedHidden)
        XCTAssertFalse(state.status.needsRestoration)
        XCTAssertNotNil(state.request(hidden: true))
        XCTAssertEqual(state.status.phase, .hiding)
        state.metadata(connection: connection, sessionFlags: 2)
        XCTAssertTrue(state.status.isConfirmedHidden)
    }

    func testHideWaitsForNewMatchingNonLoginMetadata() throws {
        var (state, connection) = ready()
        _ = try XCTUnwrap(state.request(hidden: true))
        XCTAssertEqual(state.status.phase, .hiding)
        XCTAssertFalse(state.status.isConfirmedHidden)
        XCTAssertNil(state.request(hidden: false), "An ordinary request cannot replace an in-flight request")
        state.metadata(connection: connection, sessionFlags: 6)
        XCTAssertEqual(state.status.phase, .hiding)
        state.metadata(connection: connection, sessionFlags: 2)
        XCTAssertEqual(state.status.phase, .hidden)
        XCTAssertTrue(state.status.needsRestoration)
    }

    func testLoginOrCapabilityLossCannotConfirmPendingHide() throws {
        for flags: UInt32 in [0, 0x0A, 0x12] {
            var (state, connection) = ready()
            _ = try XCTUnwrap(state.request(hidden: true))
            state.metadata(connection: connection, sessionFlags: flags)
            XCTAssertEqual(state.status.phase, .unknown)
            XCTAssertFalse(state.status.isConfirmedHidden)
            XCTAssertTrue(state.status.needsRestoration)
            XCTAssertNil(state.restorationForClose(), "Closing cannot bypass the current login/capability gate")
        }
    }

    func testOldConnectionMetadataAndTimerCannotSettleReconnect() throws {
        var (state, oldConnection) = ready()
        let oldRequest = try XCTUnwrap(state.request(hidden: true))
        state.disconnected(connection: oldConnection)
        let newConnection = UUID()
        state.beginConnection(newConnection)
        state.authenticated(connection: newConnection, apple: true)
        state.metadata(connection: newConnection, sessionFlags: 6)
        let newRequest = try XCTUnwrap(state.request(hidden: true))
        state.metadata(connection: oldConnection, sessionFlags: 2)
        state.expire(oldRequest)
        state.writeFailed(oldRequest)
        state.disconnected(connection: oldConnection)
        XCTAssertEqual(state.pending, newRequest)
        XCTAssertEqual(state.status.phase, .hiding)
        state.metadata(connection: newConnection, sessionFlags: 2)
        XCTAssertEqual(state.status.phase, .hidden)
    }

    func testTimeoutDoesNotTurnLateNonConsoleMetadataIntoSuccess() throws {
        var (state, connection) = ready()
        let request = try XCTUnwrap(state.request(hidden: true))
        state.expire(request)
        XCTAssertEqual(state.status.phase, .timedOut)
        XCTAssertTrue(state.status.needsRestoration)
        state.metadata(connection: connection, sessionFlags: 2)
        XCTAssertEqual(state.status.phase, .timedOut)
        XCTAssertFalse(state.status.isConfirmedHidden)
    }

    func testWriteFailureKeepsRestorationObligation() throws {
        var (state, connection) = ready()
        let request = try XCTUnwrap(state.request(hidden: true))
        state.writeFailed(request)
        XCTAssertEqual(state.status.phase, .failed)
        XCTAssertTrue(state.status.needsRestoration)
        state.disconnected(connection: connection, failed: true)
        XCTAssertEqual(state.status.phase, .unknown)
        XCTAssertTrue(state.status.recoveryUnconfirmed)
    }

    func testRestoreRequiresFreshOnConsoleConfirmation() throws {
        var (state, connection) = ready()
        _ = try XCTUnwrap(state.request(hidden: true))
        state.metadata(connection: connection, sessionFlags: 2)
        let restore = try XCTUnwrap(state.request(hidden: false))
        XCTAssertFalse(restore.hidden)
        XCTAssertEqual(state.status.phase, .restoring)
        XCTAssertTrue(state.status.needsRestoration)
        state.metadata(connection: connection, sessionFlags: 2)
        XCTAssertEqual(state.status.phase, .restoring)
        state.metadata(connection: connection, sessionFlags: 6)
        XCTAssertEqual(state.status.phase, .visible)
        XCTAssertFalse(state.status.needsRestoration)
        state.disconnected(connection: connection)
        XCTAssertEqual(state.status.phase, .disconnected)
        XCTAssertFalse(state.status.recoveryUnconfirmed)
    }

    func testCloseRestoresEvenUnconfirmedHideAndCancelsItsTimerIdentity() throws {
        var (state, connection) = ready()
        let hide = try XCTUnwrap(state.request(hidden: true))
        let restore = try XCTUnwrap(state.restorationForClose())
        XCTAssertFalse(restore.hidden)
        XCTAssertEqual(restore.connectionID, connection)
        XCTAssertNotEqual(restore.id, hide.id)
        state.expire(hide)
        XCTAssertFalse(state.writeFailed(hide), "A late hide delivery failure must not cancel its close restore")
        XCTAssertEqual(state.pending, restore)
        XCTAssertEqual(state.status.phase, .restoring)
        state.expire(restore)
        state.disconnected(connection: connection)
        XCTAssertEqual(state.status.phase, .unknown)
        XCTAssertTrue(state.status.recoveryUnconfirmed)
    }

    func testReconnectRetainsRecoveryWarningUntilFreshRestoreConfirmation() throws {
        var (state, oldConnection) = ready()
        _ = try XCTUnwrap(state.request(hidden: true))
        state.disconnected(connection: oldConnection)
        let connection = UUID()
        state.beginConnection(connection)
        state.authenticated(connection: connection, apple: true)
        state.metadata(connection: connection, sessionFlags: 6)
        XCTAssertTrue(state.status.recoveryUnconfirmed)
        XCTAssertFalse(state.status.isConfirmedHidden)
        _ = try XCTUnwrap(state.request(hidden: false))
        state.metadata(connection: oldConnection, sessionFlags: 6)
        XCTAssertTrue(state.status.recoveryUnconfirmed)
        state.metadata(connection: connection, sessionFlags: 6)
        XCTAssertFalse(state.status.recoveryUnconfirmed)
        XCTAssertEqual(state.status.phase, .visible)
    }

    func testClosingUnusedConnectionSendsNoCurtainRequest() {
        var (state, connection) = ready()
        XCTAssertNil(state.restorationForClose())
        state.disconnected(connection: connection)
        XCTAssertEqual(state.status.phase, .disconnected)
        XCTAssertFalse(state.status.recoveryUnconfirmed)
    }

    func testInheritedRecoveryRestoreKeepsCloseBudgetAndConfirmationIdentity() throws {
        var (state, connection) = ready()
        state.inheritRecoveryWarning()
        let restore = try XCTUnwrap(state.request(hidden: false))
        XCTAssertTrue(state.status.needsRestoration)
        let closeRestore = try XCTUnwrap(state.restorationForClose())
        XCTAssertNotEqual(closeRestore.id, restore.id)
        state.expire(restore)
        XCTAssertEqual(state.pending, closeRestore)
        state.metadata(connection: connection, sessionFlags: 6)
        XCTAssertEqual(state.confirmedRestorationID, closeRestore.id)
        XCTAssertFalse(state.status.recoveryUnconfirmed)
        XCTAssertFalse(state.status.needsRestoration)
    }
}
