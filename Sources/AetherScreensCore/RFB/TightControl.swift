/// Validates the compression control byte before the reader chooses a payload
/// layout. No-zlib extension values are rejected because we do not negotiate it.
struct TightControl: Equatable {
    enum Kind: Equatable {
        case basic(stream: Int, explicitFilter: Bool)
        case fill
        case jpeg
    }
    let resetMask: UInt8
    let kind: Kind

    init?(_ byte: UInt8) {
        resetMask = byte & 0x0f
        switch byte >> 4 {
        case 0...7: kind = .basic(stream: Int((byte >> 4) & 3), explicitFilter: byte & 0x40 != 0)
        case 8: kind = .fill
        case 9: kind = .jpeg
        default: return nil
        }
    }
}
