import Foundation
import CryptoKit
import NIO
import NIOSSH

/// Public host-key information safe to display during explicit trust review.
public struct SSHHostKeyIdentity: Equatable, Sendable {
    public let openSSHKey: String
    public let fingerprint: String
    public init(key: NIOSSHPublicKey) {
        openSSHKey = String(openSSHPublicKey: key)
        var encoded = ByteBuffer()
        key.write(to: &encoded)
        let digest = SHA256.hash(data: Data(encoded.readableBytesView))
        fingerprint = "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}
