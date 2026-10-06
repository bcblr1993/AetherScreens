import Foundation
import Combine

/// Process-local recovery obligations. It never persists or looks up credentials.
/// A decoded ready/visible state is insufficient: only a fresh, matching restore
/// confirmation may retire the obligations present when that restore was sent.
public final class CurtainRecoveryStore: ObservableObject, @unchecked Sendable {
    public static let shared = CurtainRecoveryStore()
    @Published public private(set) var revision: UInt64 = 0

    struct Target: Hashable, Sendable {
        let deviceID: UUID
        let host: String
        let port: UInt16
        let account: String?
        let authentication: String
        let sshHost: String?
        let sshPort: UInt16?
        let sshAccount: String?
        let sshAuthentication: String?
        let sshDestination: String?

        init(device: RemoteDevice, account: String?) {
            deviceID = device.id
            host = device.host
            port = device.port
            self.account = account?.isEmpty == false ? account : nil
            authentication = self.account == nil ? device.authMethod.rawValue : RemoteDevice.AuthMethod.macAccount.rawValue
            sshHost = device.sshConfiguration?.host
            sshPort = device.sshConfiguration?.port
            sshAccount = device.sshConfiguration?.username
            sshAuthentication = device.sshConfiguration?.authentication.rawValue
            sshDestination = device.sshConfiguration?.destinationHost
        }

        func matches(_ device: RemoteDevice) -> Bool {
            self == Target(device: device, account: device.username)
        }
    }

    struct Warning: Identifiable, Equatable, Sendable {
        let id: Target
        let device: RemoteDevice
    }

    private struct Obligation {
        let epoch: UInt64
        let device: RemoteDevice
        let connectionID: UUID
        var showWarning: Bool
    }
    private struct RestoreScope {
        let requestID: UUID
        let target: Target
        let throughEpoch: UInt64
    }
    private struct SourceCursor {
        weak var source: RFBCurtainEventSource?
        var latestHideID: UUID?
        var restore: RestoreScope?
    }
    private let lock = NSLock()
    private var highWater: UInt64 = 0
    private var publicationRevision: UInt64 = 0
    private var obligations: [Target: [UUID: Obligation]] = [:]
    // At most the latest hide and restore scope per living source. One target
    // keeps only its newest obligation per source, never the full request history.
    private var sources: [UUID: SourceCursor] = [:]

    public init() {}

    var warnings: [Warning] {
        lock.lock(); defer { lock.unlock() }
        return obligations.compactMap { target, items in
            guard let item = items.values.filter({ $0.showWarning }).min(by: { $0.epoch < $1.epoch }) else { return nil }
            return Warning(id: target, device: item.device)
        }.sorted { $0.device.id.uuidString < $1.device.id.uuidString }
    }

    func hasUnresolved(for target: Target) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return obligations[target]?.isEmpty == false
    }

    /// An intentionally hidden, live source keeps its normal hidden-state notice.
    /// Other sources' obligations and this source's failures require recovery UI.
    func hasRecoveryWarning(for target: Target, currentSource: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return obligations[target]?.contains(where: { $0.key != currentSource || $0.value.showWarning }) == true
    }

    /// Called synchronously by the transport callback, before its UI task and
    /// before a request's bytes are sent. It works after the view model is gone.
    func record(_ event: RFBCurtainEvent, device: RemoteDevice) {
        lock.lock()
        guard event.source.accept(event.revision) else { lock.unlock(); return }
        let target = Target(device: device, account: event.account)
        var cursor = sources[event.sourceID] ?? SourceCursor()
        cursor.source = event.source
        var changed = false
        if event.status.phase == .hiding, event.pendingHidden == true,
           let request = event.pendingRequestID, let connection = event.status.connectionID,
           cursor.latestHideID != request {
            highWater &+= 1
            var snapshot = device
            snapshot.username = target.account
            if target.account != nil { snapshot.authMethod = .macAccount }
            let retainWarning = obligations[target]?[event.sourceID]?.showWarning == true
            obligations[target, default: [:]][event.sourceID] = Obligation(epoch: highWater, device: snapshot,
                                                                          connectionID: connection, showWarning: retainWarning)
            cursor.latestHideID = request
            cursor.restore = nil
            changed = true
        }
        if event.status.phase == .restoring, event.pendingHidden == false,
           let request = event.pendingRequestID, cursor.restore?.requestID != request {
            cursor.restore = RestoreScope(requestID: request, target: target, throughEpoch: highWater)
        }
        if let request = event.confirmedRestorationID, let scope = cursor.restore,
           scope.requestID == request, scope.target == target {
            let remaining = obligations[target, default: [:]].filter { $0.value.epoch > scope.throughEpoch }
            if remaining.count != (obligations[target]?.count ?? 0) {
                if remaining.isEmpty { obligations.removeValue(forKey: target) }
                else { obligations[target] = remaining }
                changed = true
            }
        }
        if !event.transportAttached || event.status.phase == .failed || event.status.recoveryUnconfirmed ||
            ((event.status.phase == .timedOut || event.status.phase == .unknown) && event.status.needsRestoration) {
            var items = obligations[target, default: [:]]
            for source in Array(items.keys) where event.status.recoveryUnconfirmed ||
                (source == event.sourceID && items[source]?.connectionID == event.status.connectionID) {
                if items[source]?.showWarning == false {
                    items[source]?.showWarning = true
                    changed = true
                }
            }
            if !items.isEmpty { obligations[target] = items }
        }
        sources[event.sourceID] = cursor
        if !event.transportAttached, !obligations.values.contains(where: { $0[event.sourceID] != nil }) {
            sources.removeValue(forKey: event.sourceID)
        }
        sources = sources.filter { $0.value.source != nil }
        if changed { publicationRevision &+= 1 }
        let nextPublication = publicationRevision
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.publicationRevision == nextPublication
            self.lock.unlock()
            if current { self.revision = nextPublication }
        }
    }
}
