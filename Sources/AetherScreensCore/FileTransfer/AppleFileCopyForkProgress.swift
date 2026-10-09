import Foundation

/// Accounting for an ordinary file's native data/resource fork sequence.
/// Bytes must be acknowledged only after the corresponding write succeeds.
struct AppleFileCopyForkProgress: Equatable, Sendable {
    enum Fork: Equatable, Sendable { case data, resource }
    enum Failure: Error, Equatable { case invalidByteCount }
    private(set) var dataRemaining: UInt64
    private(set) var resourceRemaining: UInt64

    init(dataBytes: UInt64, resourceBytes: UInt64) {
        dataRemaining = dataBytes
        resourceRemaining = resourceBytes
    }

    var activeFork: Fork? {
        if dataRemaining > 0 { return .data }
        if resourceRemaining > 0 { return .resource }
        return nil
    }
    var remainingInActiveFork: UInt64 {
        activeFork == .data ? dataRemaining : resourceRemaining
    }
    var isComplete: Bool { activeFork == nil }

    mutating func acknowledgeWrittenBytes(_ count: UInt64) throws {
        guard count > 0, let fork = activeFork, count <= remainingInActiveFork else {
            throw Failure.invalidByteCount
        }
        switch fork {
        case .data: dataRemaining -= count
        case .resource: resourceRemaining -= count
        }
    }
}
