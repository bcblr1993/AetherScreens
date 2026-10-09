import Foundation
import Darwin

/// Descriptor-based catalog restoration for platforms without Carbon.
/// The owner validates the descriptor's identity before calling this helper.
enum AppleFileCopyPortableCatalogRestore {
    enum Failure: Error { case invalidItem, cannotRestore(Int32) }

    static func restore(_ metadata: AppleFileCopyCatalogMetadata, descriptor: Int32) throws {
        var identity = stat()
        let directory = metadata.nodeFlags & 0x10 != 0
        guard fstat(descriptor, &identity) == 0,
              identity.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { throw Failure.invalidItem }
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(ATTR_CMN_SCRIPT | ATTR_CMN_CRTIME | ATTR_CMN_MODTIME
            | ATTR_CMN_CHGTIME | ATTR_CMN_BKUPTIME | ATTR_CMN_FNDRINFO)
        // Darwin packs values on four-byte boundaries in attribute order,
        // without getattrlist's leading length. Avoid Swift struct padding.
        var buffer = Data()
        var encoding = metadata.textEncodingHint
        withUnsafeBytes(of: &encoding) { buffer.append(contentsOf: $0) }
        for date in [metadata.created, metadata.contentModified, metadata.attributesModified, metadata.backedUp] {
            let seconds = Int64(date.wholeSeconds) - 2_082_844_800
            var timestamp = timespec(tv_sec: Int(seconds), tv_nsec: Int(date.fraction) * 1_000_000_000 / 65_536)
            withUnsafeBytes(of: &timestamp) { buffer.append(contentsOf: $0) }
        }
        buffer.append(metadata.finderInfoAttribute)
        let status = buffer.withUnsafeMutableBytes {
            fsetattrlist(descriptor, &attributes, $0.baseAddress, $0.count, 0)
        }
        guard status == 0 else { throw Failure.cannotRestore(errno) }
    }
}
