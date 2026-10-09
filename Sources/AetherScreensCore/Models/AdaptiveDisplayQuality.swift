import Foundation

/// JPEG quality hints affect compression, never desktop geometry or wire color.
/// Only completed active pixel transfers qualify; an idle desktop is not a sample.
struct AdaptiveDisplayQuality {
    enum Level: Int, CaseIterable, Sendable {
        case responsive = 3, balanced = 6, high = 9
        var encodingHint: RFBConstants.EncodingType {
            .init(rawValue: Int32(-32 + rawValue))
        }
    }

    private(set) var level: Level = .high
    private var slowSamples = 0
    private var fastSamples = 0
    private var lastChange: TimeInterval?
    private var lastSample: TimeInterval?

    mutating func reset() { self = Self() }

    mutating func sample(bytes: Int, payloadDuration: TimeInterval,
                         now: TimeInterval, foreground: Bool) -> Level? {
        guard foreground, bytes >= 16_384, payloadDuration.isFinite,
              payloadDuration > 0, now.isFinite,
              lastSample.map({ now > $0 }) ?? true else { return nil }
        if let previous = lastSample, now - previous > 5 {
            slowSamples = 0
            fastSamples = 0
        }
        lastSample = now
        if payloadDuration >= 0.25 {
            slowSamples += 1
            fastSamples = 0
        } else if payloadDuration <= 0.08 {
            fastSamples += 1
            slowSamples = 0
        } else {
            slowSamples = 0
            fastSamples = 0
        }
        // Count evidence during cooldown, but require a fresh sample to change.
        guard lastChange.map({ now - $0 >= 10 }) ?? true else { return nil }
        let next: Level
        if slowSamples >= 3 {
            switch level {
            case .high: next = .balanced
            case .balanced: next = .responsive
            case .responsive: return nil
            }
        } else if fastSamples >= 8 {
            switch level {
            case .responsive: next = .balanced
            case .balanced: next = .high
            case .high: return nil
            }
        } else { return nil }
        level = next
        lastChange = now
        slowSamples = 0
        fastSamples = 0
        return next
    }
}
