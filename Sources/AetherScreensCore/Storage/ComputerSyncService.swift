import Foundation
import Combine
import CloudKit

@MainActor
public final class ComputerSyncService: ObservableObject {
    public enum SyncStatus: Equatable, Sendable {
        case disabled
        case idle
        case syncing
        case synced(Date)
        case error(String)

        public var localizedDescription: String {
            switch self {
            case .disabled:
                return AppLocalization.string("iCloud Sync is turned off")
            case .idle:
                return AppLocalization.string("iCloud Sync is ready")
            case .syncing:
                return AppLocalization.string("Syncing with iCloud…")
            case .synced(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return String(format: AppLocalization.string("Last synced: %@"), formatter.string(from: date))
            case .error(let message):
                return String(format: AppLocalization.string("Sync failed: %@"), message)
            }
        }
    }

    private static let enabledKey = "com.aethernative.aetherscreens.icloud-sync.enabled"
    private static let lastSyncDateKey = "com.aethernative.aetherscreens.icloud-sync.last-date"

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var status: SyncStatus = .disabled
    @Published public private(set) var lastSyncDate: Date?

    private let store: DeviceStore
    private let model: ComputerSyncLibraryModel
    private let userDefaults: UserDefaults
    private let rootDirectory: URL
    private let transportFactory: (@Sendable () async throws -> (any ComputerSyncTransport, String))?
    private var coordinator: ComputerSyncCoordinator?
    private var isSyncInProgress = false

    public convenience init(
        store: DeviceStore = .shared,
        userDefaults: UserDefaults = .standard,
        rootDirectory: URL? = nil
    ) {
        self.init(store: store, userDefaults: userDefaults, rootDirectory: rootDirectory, transportFactory: nil)
    }

    init(
        store: DeviceStore = .shared,
        userDefaults: UserDefaults = .standard,
        rootDirectory: URL? = nil,
        transportFactory: (@Sendable () async throws -> (any ComputerSyncTransport, String))? = nil
    ) {
        self.store = store
        self.model = ComputerSyncLibraryModel()
        self.userDefaults = userDefaults
        self.transportFactory = transportFactory

        let root = rootDirectory ?? (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("com.aethernative.aetherscreens/ComputerSync", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("ComputerSync", isDirectory: true)
        )
        self.rootDirectory = root

        let savedEnabled = userDefaults.bool(forKey: Self.enabledKey)
        self.isEnabled = savedEnabled
        if let timestamp = userDefaults.object(forKey: Self.lastSyncDateKey) as? Date {
            self.lastSyncDate = timestamp
            self.status = savedEnabled ? .synced(timestamp) : .disabled
        } else {
            self.status = savedEnabled ? .idle : .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.enabledKey)

        if enabled {
            status = .syncing
            await activateAndSynchronize()
        } else {
            model.deselect()
            coordinator = nil
            status = .disabled
        }
    }

    public func synchronize() async {
        guard isEnabled, !isSyncInProgress else { return }
        await activateAndSynchronize()
    }

    public func notifyLibraryChanged() async {
        guard isEnabled, let coord = coordinator else { return }
        do {
            let snapshot = try await coord.librarySnapshot()
            _ = await model.save(store.devices, basedOn: snapshot.revision)
            await synchronize()
        } catch {
            AppLogger.shared.error("Failed to commit library change for iCloud sync: \(error)", category: "Storage")
        }
    }

    private func activateAndSynchronize() async {
        guard !isSyncInProgress else { return }
        isSyncInProgress = true
        defer { isSyncInProgress = false }

        status = .syncing
        do {
            let (transport, accountID) = try await resolveTransportAndAccount()
            let coord: ComputerSyncCoordinator
            if let existing = coordinator {
                coord = existing
            } else {
                coord = try ComputerSyncCoordinator(store: store, accountIdentifier: accountID, rootDirectory: rootDirectory)
                coordinator = coord
                await model.select(coord)
            }

            let success = await model.synchronize(using: transport)
            if success {
                let now = Date()
                lastSyncDate = now
                userDefaults.set(now, forKey: Self.lastSyncDateKey)
                status = .synced(now)
                store.loadDevices()
            } else {
                let msg = AppLocalization.string("Sync failed to complete.")
                status = .error(msg)
            }
        } catch {
            let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .error(errorMsg)
        }
    }

    private func resolveTransportAndAccount() async throws -> (any ComputerSyncTransport, String) {
        if let factory = transportFactory {
            return try await factory()
        }

        let containerID = "iCloud.com.aethernative.aetherscreens"
        let reader = CloudKitComputerSyncReader(containerIdentifier: containerID)
        let container = CKContainer(identifier: containerID)
        let recordID: CKRecord.ID = try await CloudKitAccountRequestRunner.run { completion in
            container.fetchUserRecordID { record, error in
                if let error { completion(.failure(error)) }
                else if let record { completion(.success(record)) }
                else { completion(.failure(CloudKitComputerSyncReader.Failure.accountUnavailable)) }
            }
        }
        return (reader, recordID.recordName)
    }
}
