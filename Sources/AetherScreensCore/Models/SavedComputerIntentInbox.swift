import Foundation
import Combine

/// Buffers foreground intent requests until the computer library is mounted.
@MainActor
public final class SavedComputerIntentInbox: ObservableObject {
    public static let shared = SavedComputerIntentInbox()
    @Published public private(set) var revision = 0
    private var pending: [UUID] = []
    public init() {}
    public func enqueue(_ id: UUID) {
        if !pending.contains(id) { pending.append(id) }
        revision &+= 1
    }
    public func drain() -> [UUID] {
        let result = pending
        pending.removeAll()
        return result
    }
}
