import Foundation
import Combine

/// Live sessions are kept in memory; credentials and temporary connections are
/// never serialized as part of window/session selection.
@MainActor
public final class SessionRegistry: ObservableObject {
    public struct Entry: Identifiable {
        public let id: UUID
        public let viewModel: SessionViewModel
        public let number: Int
        public var title: String { "\(viewModel.device.name) · \(number)" }
    }

    public static let shared = SessionRegistry()
    @Published public private(set) var sessions: [Entry] = []
    @Published public private(set) var activeSessionID: UUID?
    private var nextNumber = 1

    public init() {}

    @discardableResult
    public func register(_ session: SessionViewModel, reuseExisting: Bool = true) -> UUID {
        if reuseExisting, let id = reusableSessionID(for: session.device) {
            return id
        }
        let id = UUID()
        sessions.append(Entry(id: id, viewModel: session, number: nextNumber))
        nextNumber += 1
        return id
    }

    /// Metadata-only lookup; callers can focus an existing session before
    /// reading credentials or constructing a replacement SessionViewModel.
    public func reusableSessionID(for device: RemoteDevice) -> UUID? {
        sessions.first(where: {
            let old = $0.viewModel.device, new = device
            return old.id == new.id && old.host == new.host && old.port == new.port &&
                old.username == new.username && old.authMethod == new.authMethod &&
                old.sshConfiguration == new.sshConfiguration
        })?.id
    }

    public func session(for id: UUID) -> SessionViewModel? {
        sessions.first(where: { $0.id == id })?.viewModel
    }

    /// Select one foreground session without reconnecting or discarding another viewport.
    @discardableResult
    public func activate(_ id: UUID) -> SessionViewModel? {
        guard let selected = session(for: id) else { return nil }
        for entry in sessions { entry.viewModel.setForegroundSession(entry.id == id) }
        activeSessionID = id
        return selected
    }

    public func returnToLibrary() {
        for entry in sessions { entry.viewModel.setForegroundSession(false) }
        activeSessionID = nil
    }

    public func close(_ id: UUID) {
        guard let session = remove(id) else { return }
        session.endSession()
    }

    @discardableResult
    public func remove(_ id: UUID) -> SessionViewModel? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        if activeSessionID == id { activeSessionID = nil }
        return sessions.remove(at: index).viewModel
    }
}
