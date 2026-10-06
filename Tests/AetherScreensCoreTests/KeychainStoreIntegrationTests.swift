import XCTest
@testable import AetherScreensCore

/// System Keychain integration is an explicit gate with synthetic, unique
/// records. Ordinary tests cover the same store behavior through an injected
/// backend and never initialize this system path.
final class KeychainStoreIntegrationTests: XCTestCase {
    func testRealKeychainDurabilityMigrationAndDeletionAcrossInstances() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_REAL_KEYCHAIN"] == "1" else {
            throw XCTSkip("Set AETHERSCREENS_QA_REAL_KEYCHAIN=1 to test system Keychain migration with synthetic records")
        }
        let current = "test.aetherscreens.credentials.current." + UUID().uuidString
        let legacy = "test.aetherscreens.credentials.legacy." + UUID().uuidString
        let key = UUID().uuidString
        let oldWriter = KeychainStore(serviceName: legacy, legacyServiceName: nil)
        let newReader = KeychainStore(serviceName: current, legacyServiceName: legacy)
        defer {
            _ = KeychainStore(serviceName: current, legacyServiceName: nil).deletePassword(forKey: key)
            _ = KeychainStore(serviceName: legacy, legacyServiceName: nil).deletePassword(forKey: key)
        }
        XCTAssertTrue(oldWriter.savePassword("synthetic-migration-only", forKey: key))
        XCTAssertEqual(newReader.loadPassword(forKey: key), "synthetic-migration-only")
        XCTAssertNil(KeychainStore(serviceName: legacy, legacyServiceName: nil).loadPassword(forKey: key))
        XCTAssertEqual(KeychainStore(serviceName: current, legacyServiceName: nil).loadPassword(forKey: key),
                       "synthetic-migration-only")
        XCTAssertTrue(newReader.deletePassword(forKey: key))
        XCTAssertNil(KeychainStore(serviceName: current, legacyServiceName: nil).loadPassword(forKey: key))
    }
}
